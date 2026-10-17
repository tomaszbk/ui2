@[has_globals]
module ui2

import math

enum SlotComposite {
	screen_manager
}

__global slot_events = []ElementEvent{}

fn slot_event(event ElementEvent) {
	slot_events << event
}

fn slot_content(kind LayoutKind) !Element {
	// Both levels have authored inputs before any composite receives them.
	// The nested Stack's preferred 24x18 must survive its parent's allocation.
	nested := stack(StackConfig{
		id:       'nested'
		frame:    rect(3, 5, 24, 18)
		padding:  LayoutPadding{ left: 2, top: 3, right: 4, bottom: 5 }
		align_x:  .center
		align_y:  .end
		children: [StackChild{
			element: Element{
				...view('', rect(11, 13, 10, 6), BoxStyle{}, [])
				key: 'leaf/key'
			}
		}]
	})!
	marker := view('marker', rect(17, 19, 30, 12), BoxStyle{}, [])
	authored := rect(7, 9, 40, 30)
	content := match kind {
		.flex {
			flex(FlexConfig{
				id:       'content'
				frame:    authored
				padding:  LayoutPadding{ left: 4, top: 6, right: 8, bottom: 10 }
				gap:      8
				children: [FlexChild{ element: nested, grow: 1, shrink: 0 },
					FlexChild{ element: marker, shrink: 0, align_self: .end }]
			})!
		}
		.grid {
			grid(GridConfig{
				id:       'content'
				frame:    authored
				columns:  2
				padding:  GridPadding{ left: 4, top: 6, right: 8, bottom: 10 }
				spacing:  GridSpacing{ horizontal: 8 }
				children: [nested, marker]
			})!
		}
		.stack {
			stack(StackConfig{
				id:       'content'
				frame:    authored
				padding:  LayoutPadding{ left: 4, top: 6, right: 8, bottom: 10 }
				children: [
					StackChild{ element: nested, align_x: .stretch, align_y: .stretch },
					StackChild{ element: marker, align_x: .center, align_y: .end },
				]
			})!
		}
		else { return error('fixture requires Flex, Grid or Stack') }
	}
	return Element{
		...content
		key:                'content-key'
		on_event:           slot_event
		accessibility_name: 'slot content'
		cursor:             cursor_pointing_hand
	}
}

fn slot_composite(kind SlotComposite, frame Rect, content Element) !Element {
	return match kind {
		.screen_manager {
			screen_manager(
				id:      'composite'
				frame:   frame
				screens: [ManagedScreen{ name: 'first', content: content }]
			)!
		}
	}
}

fn slot_find(root Element, id string) ?Element {
	if root.id == id { return root }
	for child in root.children {
		if found := slot_find(child, id) { return found }
	}
	return none
}

fn slot_rect(actual Rect, expected Rect) {
	assert math.abs(actual.x - expected.x) < 0.000001, 'x: ${actual} != ${expected}'
	assert math.abs(actual.y - expected.y) < 0.000001, 'y: ${actual} != ${expected}'
	assert math.abs(actual.width - expected.width) < 0.000001, 'width: ${actual} != ${expected}'
	assert math.abs(actual.height - expected.height) < 0.000001, 'height: ${actual} != ${expected}'
}

fn slot_assert_same_output(actual Element, expected Element) {
	slot_rect(actual.frame, expected.frame)
	slot_rect(actual.layout_input or { panic('missing resolved input') }, expected.layout_input or {
		panic('missing expected input')
	})
	assert actual.id == expected.id && actual.key == expected.key
	assert actual.kind == expected.kind && actual.layout.kind == expected.layout.kind
	assert actual.on_event == expected.on_event
	assert actual.hidden == expected.hidden && actual.enabled == expected.enabled
	assert actual.accessibility_name == expected.accessibility_name && actual.cursor == expected.cursor
	assert actual.text == expected.text && actual.box == expected.box
	assert actual.children.len == expected.children.len
	for index, child in actual.children { slot_assert_same_output(child, expected.children[index]) }
}

fn slot_measure(text string, _style TextStyle, width f64) !LayoutSize {
	return LayoutSize{ width: if width < 0 { f64(text.runes().len * 8) } else { width }, height: 20 }
}

fn slot_resolve(mut tree LayoutTree) !Element {
	return tree.resolve(LayoutConstraints{}, slot_measure, LayoutEnvironment{})!
}

fn slot_expected(kind SlotComposite, width f64, height f64) Rect {
	// Public contracts, without calling any composite geometry helper.
	return match kind {
		.screen_manager { rect(0, 0, width, height) }
	}
}

fn slot_assert_descendants(content Element, kind LayoutKind, slot Rect) {
	// Hand arithmetic: padding subtracts 12x16. Flex reserves the 30-wide
	// marker plus gap 8; Grid divides the remaining width after gap equally;
	// Stack stretches only nested, leaving the marker's authored preference.
	nested_width := match kind {
		.flex { slot.width - 50 }
		.grid { (slot.width - 20) / 2 }
		else { slot.width - 12 }
	}
	nested_height := slot.height - 16
	nested := content.children[0]
	slot_rect(nested.frame, rect(4, 6, nested_width, nested_height))
	slot_rect((nested.layout_input or { panic('missing authored input') }), rect(3, 5, 24, 18))
	slot_rect(nested.children[0].frame, rect(nested_width / 2 - 6, nested_height - 11, 10, 6))
	slot_rect((nested.children[0].layout_input or { panic('missing authored input') }), rect(11, 13, 10, 6))
	marker := match kind {
		.flex { rect(slot.width - 38, slot.height - 22, 30, 12) }
		.grid { rect(12 + nested_width, 6, nested_width, nested_height) }
		else { rect(slot.width / 2 - 17, slot.height - 22, 30, 12) }
	}
	slot_rect(content.children[1].frame, marker)
	slot_rect((content.children[1].layout_input or { panic('missing authored input') }), rect(17, 19, 30, 12))
}

fn slot_resize_fixture(composite SlotComposite, layout LayoutKind) ! {
	authored := slot_content(layout)!
	slot_rect((authored.layout_input or { panic('missing authored input') }), rect(7, 9, 40, 30))
	mut tree := LayoutTree{}
	mut generations := []u64{}
	mut first := Element{}
	for index, size in [rect(11, 13, 320, 200), rect(11, 13, 500, 300), rect(11, 13, 320, 200)] {
		declaration := slot_composite(composite, size, authored)!
		expected := slot_expected(composite, size.width, size.height)
		// The constructor contract already assigns this slot before resolve.
		slot_rect((slot_find(declaration, 'content') or { panic('missing content') }).frame, expected)
		tree.replace(declaration)!
		resolved := slot_resolve(mut tree)!
		content := (slot_find(resolved, 'content') or { panic('missing content') })
		slot_rect(resolved.frame, size)
		slot_rect(content.frame, expected)
		slot_rect((content.layout_input or { panic('missing authored input') }), expected)
		slot_assert_descendants(content, layout, expected)
		assert content.layout.kind == layout
		assert content.id == 'content' && content.key == 'content-key'
		assert content.on_event == authored.on_event
		assert content.accessibility_name == 'slot content' && content.cursor == cursor_pointing_hand
		slot_events = []ElementEvent{}
		content.on_event(ElementEvent{ kind: .click, id: content.id })
		assert slot_events.len == 1 && slot_events[0].id == 'content'
		leaf_identity := 'id:' + 'nested'.bytes().hex() + '/key:' + 'leaf/key'.bytes().hex()
		current := [
			(tree.identity('content') or { panic('missing identity') }).generation,
			(tree.identity('nested') or { panic('missing identity') }).generation,
			(tree.nodes[leaf_identity] or { panic('missing keyed leaf') }).generation,
		]
		if index == 0 {
			assert tree.stats().measure_visits > 0
			generations = current.clone()
			first = content
		} else {
			assert current == generations
		}
		if index == 2 { slot_assert_same_output(content, first) }
		tree.reset_stats()
		slot_assert_same_output(slot_resolve(mut tree)!, resolved)
		assert tree.stats().measure_visits == 0 && tree.stats().text_measurements == 0
		assert tree.stats().layout_visits == 0
		// Feeding resolved output back must not promote nested solver frames.
		tree.replace(resolved)!
		tree.reset_stats()
		slot_assert_same_output(slot_resolve(mut tree)!, resolved)
		assert tree.stats().measure_visits == 0 && tree.stats().text_measurements == 0
		assert tree.stats().layout_visits == 0
	}
	// Neither the caller's content nor its descendant preferences are rewritten.
	slot_rect(authored.frame, rect(7, 9, 40, 30))
	slot_rect((authored.children[0].layout_input or { panic('missing authored input') }), rect(3, 5, 24, 18))
}

fn test_screen_manager_flex_slot_resize() { slot_resize_fixture(.screen_manager, .flex)! }

fn test_screen_manager_grid_slot_resize() { slot_resize_fixture(.screen_manager, .grid)! }

fn test_screen_manager_stack_slot_resize() { slot_resize_fixture(.screen_manager, .stack)! }

fn test_screen_manager_selected_content_fills_its_slot() {
	content := slot_content(.flex)!
	other := stack(StackConfig{ id: 'other', frame: rect(7, 9, 40, 30) })!
	mut tree := LayoutTree{}
	for current in [0, 1] {
		screens := screen_manager(
			id:      'screens'
			frame:   rect(0, 0, 320, 200)
			current: if current == 0 { 'one' } else { 'two' }
			screens: [ManagedScreen{ name: 'one', content: content },
				ManagedScreen{ name: 'two', content: other }]
		)!
		tree.replace(screens)!
		slot_rect(slot_resolve(mut tree)!.children[0].frame, rect(0, 0, 320, 200))
	}
}

$if linux || macos || windows || ui2_headless ?|| ui2_document_library ? {
	fn test_overlay_content_reflows_and_reopens_without_promoting_authored_descendant_frames() ! {
		for kind in [OverlayKind.dialog, .popover] {
			for layout in [LayoutKind.flex, .grid, .stack] {
				authored := slot_content(layout)!
				mut raw := LayoutTree{}
				mut portals := OverlayTree{ measure: slot_measure }
				mut generations := []u64{}
				// Resize in both directions, then close and reopen the same surface.
				for index, surface in [rect(33, 41, 240, 120), rect(33, 41, 300, 180),
					rect(33, 41, 240, 120), rect(33, 41, 240, 120), rect(33, 41, 240, 120)] {
					open := index != 3
					content_slot := stack(StackConfig{
						id:       'surface'
						frame:    surface
						children: [StackChild{ element: authored, align_x: .stretch, align_y: .stretch }]
					})!
					overlay := with_overlay(content_slot, OverlayConfig{
						kind:   kind
						open:   open
						anchor: if kind == .popover { 'anchor' } else { '' }
					})!
					root := screen(0xffffff, [
						button('anchor', 'Open', rect(20, 20, 80, 30), BoxStyle{}, TextStyle{}),
						overlay,
					])
					raw.replace(root)!
					projected := portals.resolve(slot_resolve(mut raw)!, map[string]f64{}, rect(0, 0, 400, 300), 0)!
					presented := slot_find(projected, 'surface') or { panic('missing surface') }
					assert presented.hidden == !open
					content := slot_find(presented, 'content') or { panic('missing retained content') }
					expected := rect(0, 0, surface.width, surface.height)
					if open {
						slot_rect(content.frame, expected)
						slot_assert_descendants(content, layout, expected)
					}
					assert content.key == 'content-key' && content.on_event == authored.on_event
					assert content.accessibility_name == authored.accessibility_name
						&& content.cursor == authored.cursor
					current := [
						(raw.identity('content') or { panic('missing content identity') }).generation,
						(raw.identity('nested') or { panic('missing nested identity') }).generation,
						(portals.layers[0].layout.identity('content') or { panic('missing portal identity') }).generation,
					]
					if index == 0 {
						generations = current.clone()
					} else {
						assert current == generations
					}
					assert portals.resolve(slot_resolve(mut raw)!, map[string]f64{}, rect(0, 0, 400, 300), 0)! == projected
				}
				slot_rect(authored.frame, rect(7, 9, 40, 30))
				slot_rect(authored.children[0].layout_input or { panic('missing authored input') }, rect(3, 5, 24, 18))
			}
		}
	}
} $else {
	fn test_mobile_rejects_overlay_surfaces() ! {
		surface := with_overlay(view('dialog', rect(0, 0, 240, 120), BoxStyle{}, []Element{}), OverlayConfig{ kind: .dialog, open: true })!
		if _ := validate_element_tree(surface) {
			assert false, 'mobile builds must reject unsupported overlay presentation'
		} else {
			assert err.msg().contains('overlays require the desktop custom renderer')
		}
	}
}

fn slot_runtime_content(layout LayoutKind) !Element {
	editor := text_area(TextAreaConfig{ id: 'editor', text: 'declarado', disable_scroll: true, frame: rect(0, 0, 100, 30) })!
	pane := scroll('pane', rect(15, 17, 100, 80), 0xffffff, [editor,
		view('tail', rect(0, 400, 100, 30), BoxStyle{}, [])])
	return match layout {
		.flex {
			flex(FlexConfig{ id: 'content', frame: rect(7, 9, 40, 30), children: [FlexChild{ element: pane, grow: 1 }] })!
		}
		.grid {
			grid(GridConfig{ id: 'content', frame: rect(7, 9, 40, 30), columns: 1, children: [pane] })!
		}
		.stack {
			stack(StackConfig{ id: 'content', frame: rect(7, 9, 40, 30), align_x: .stretch, align_y: .stretch, children: [StackChild{ element: pane }] })!
		}
		else { return error('fixture requires Flex, Grid or Stack') }
	}
}

$if macos && !ui2_headless ? {
	fn test_custom_composite_resize_preserves_local_edit_selection_focus_scroll_and_ime() {
		for composite in [SlotComposite.screen_manager] {
			for layout in [LayoutKind.flex, .grid, .stack] {
				mut w := &Window{}
				content := slot_runtime_content(layout)!
				w.declared_root = slot_composite(composite, rect(0, 0, 320, 200), content)!
				initial := w.scheduler.begin_frame(0) or { panic('no initial frame') }
				_ = w.resolve_custom_layout(initial, slot_measure, w.take_custom_layout_patches())!
				w.scheduler.finish_frame(initial)
				w.replace_text_prop('editor', 'declarado')
				w.replace_text_value('editor', 'ñ café🙂')
				w.replace_text_editor('editor', TextEditor{ text: 'ñ café🙂'.clone(), selection: TextSelection{ anchor: 1, caret: 4 } })
				w.focused_field = 'editor'
				w.scroll_offsets[named_scroll_state_id('pane')] = 42
				w.composition = TextComposition{ field_id: 'editor', text: 'á' }
				generation := (w.layout_tree.identity('editor') or { panic('missing identity') }).generation
				for index, size in [rect(0, 0, 500, 300), rect(0, 0, 320, 200)] {
					w.declared_root = slot_composite(composite, size, content)!
					w.scheduler.invalidate(.build)
					work := w.scheduler.begin_frame(i64(index + 1)) or { panic('missing rebuild') }
					resolved := w.resolve_custom_layout(work, slot_measure, w.take_custom_layout_patches())!
					w.scheduler.finish_frame(work)
					slot_rect((slot_find(resolved, 'content') or { panic('missing content') }).frame, slot_expected(composite, size.width, size.height))
					assert (w.layout_tree.identity('editor') or { panic('missing identity') }).generation == generation
					assert w.text('editor') == 'ñ café🙂'
					assert w.text_editors['editor'].selection == TextSelection{ anchor: 1, caret: 4 }
					assert w.focused_id() == 'editor' && w.scroll_offset('pane') == 42
					assert w.composition.field_id == 'editor' && w.composition.text == 'á'
				}
			}
		}
	}
}
