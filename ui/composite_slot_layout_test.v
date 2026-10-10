@[has_globals]
module ui2

import math

$if macos && !ui2_custom_rendering ?&& !ui2_headless ? {
	import macos
}

enum SlotComposite {
	screen_manager
	tabbed_panel
	modal_view
	carousel
	accordion
	popup
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
		key:            'content-key'
		on_event:       slot_event
		focused:        true
		text_selection: TextSelection{ anchor: 1, caret: 4 }
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
		.tabbed_panel {
			tabbed_panel(
				id:    'composite'
				frame: frame
				tabs:  [TabbedPanelTab{ id: 'tab', title: 'Tab', content: content }]
			)!
		}
		.modal_view { modal_view(id: 'composite', frame: frame, open: true, content: content)! }
		.carousel { carousel(id: 'composite', frame: frame, slides: [content])! }
		.accordion {
			accordion(
				id:    'composite'
				frame: frame
				items: [AccordionItem{ id: 'header', title: 'Header', content: content }]
			)!
		}
		.popup {
			popup(id: 'composite', frame: frame, open: true, title: 'Popup', content: content)!
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
	assert actual.focused == expected.focused && actual.text_selection == expected.text_selection
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
	// Public contracts, without calling any composite geometry helper:
	// tabs reserve 40 at top; modal takes centered 80%; horizontal accordion
	// reserves its one 44-wide header; popup removes 48+1 from the surface.
	return match kind {
		.screen_manager, .carousel { rect(0, 0, width, height) }
		.tabbed_panel { rect(0, 40, width, height - 40) }
		.modal_view { rect(width / 10, height / 10, width * 0.8, height * 0.8) }
		.accordion { rect(44, 0, width - 44, height) }
		.popup { rect(0, 49, width * 0.8, height * 0.8 - 49) }
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
		assert content.focused && content.text_selection == TextSelection{ anchor: 1, caret: 4 }
		slot_events = []ElementEvent{}
		content.on_event(ElementEvent{ kind: .tap, id: content.id })
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

fn test_tabbed_panel_flex_slot_resize() { slot_resize_fixture(.tabbed_panel, .flex)! }

fn test_tabbed_panel_grid_slot_resize() { slot_resize_fixture(.tabbed_panel, .grid)! }

fn test_tabbed_panel_stack_slot_resize() { slot_resize_fixture(.tabbed_panel, .stack)! }

fn test_modal_view_flex_slot_resize() { slot_resize_fixture(.modal_view, .flex)! }

fn test_modal_view_grid_slot_resize() { slot_resize_fixture(.modal_view, .grid)! }

fn test_modal_view_stack_slot_resize() { slot_resize_fixture(.modal_view, .stack)! }

fn test_carousel_flex_slot_resize() { slot_resize_fixture(.carousel, .flex)! }

fn test_carousel_grid_slot_resize() { slot_resize_fixture(.carousel, .grid)! }

fn test_carousel_stack_slot_resize() { slot_resize_fixture(.carousel, .stack)! }

fn test_accordion_flex_slot_resize() { slot_resize_fixture(.accordion, .flex)! }

fn test_accordion_grid_slot_resize() { slot_resize_fixture(.accordion, .grid)! }

fn test_accordion_stack_slot_resize() { slot_resize_fixture(.accordion, .stack)! }

fn test_popup_flex_slot_resize() { slot_resize_fixture(.popup, .flex)! }

fn test_popup_grid_slot_resize() { slot_resize_fixture(.popup, .grid)! }

fn test_popup_stack_slot_resize() { slot_resize_fixture(.popup, .stack)! }

fn test_selected_content_slots_follow_headers_and_carousel_keeps_slide_generation() {
	content := slot_content(.flex)!
	other := stack(StackConfig{ id: 'other', frame: rect(7, 9, 40, 30) })!
	mut tree := LayoutTree{}
	for current in [0, 1, 0] {
		tree.replace(carousel(
			id:     'gallery'
			frame:  rect(0, 0, 320, 200)
			index:  current
			slides: [content, other]
		)!)!
		resolved := slot_resolve(mut tree)!
		slot_rect(resolved.children[current].frame, rect(0, 0, 320, 200))
		assert !resolved.children[current].hidden && resolved.children[1 - current].hidden
		assert resolved.accessibility_value == 'Slide ${current + 1} of 2'
		generation := (tree.identity('content') or { panic('missing identity') }).generation
		tree.replace(carousel(
			id:     'gallery'
			frame:  rect(0, 0, 320, 200)
			index:  1 - current
			slides: [content, other]
		)!)!
		_ = slot_resolve(mut tree)!
		assert (tree.identity('content') or { panic('missing identity') }).generation == generation
	}
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
		tabs := tabbed_panel(
			id:           'tabs'
			frame:        rect(0, 0, 320, 200)
			current:      current
			tab_position: .left_top
			tabs:         [TabbedPanelTab{ id: 'one', content: content },
				TabbedPanelTab{ id: 'two', content: other }]
		)!
		tree.replace(tabs)!
		selected := slot_resolve(mut tree)!
		slot_rect(selected.children[0].frame, rect(40, 0, 280, 200))
		assert selected.children[current + 1].accessibility_value == 'selected'
		sections := accordion(
			id:          'sections'
			frame:       rect(0, 0, 320, 200)
			orientation: .vertical
			current:     current
			items:       [AccordionItem{ id: 'one', content: content },
				AccordionItem{ id: 'two', content: other }]
		)!
		tree.replace(sections)!
		expanded := slot_resolve(mut tree)!
		slot_rect(expanded.children[0].frame, rect(0, f64((current + 1) * 44), 320, 112))
		assert expanded.children[current + 1].accessibility_value == 'expanded'
		assert expanded.children[0].id == if current == 0 { 'content' } else { 'other' }
	}
}

fn test_modal_and_popup_reopen_same_content_without_promoting_descendant_frames() {
	for composite in [SlotComposite.modal_view, .popup] {
		content := slot_content(.grid)!
		mut tree := LayoutTree{}
		mut generation := u64(0)
		for index, open in [true, false, true] {
			declaration := if composite == .modal_view {
				modal_view(
					id:      'composite'
					frame:   rect(0, 0, 320, 200)
					open:    open
					content: content
				)!
			} else {
				popup(
					id:      'composite'
					frame:   rect(0, 0, 320, 200)
					open:    open
					title:   'Popup'
					content: content
				)!
			}
			tree.replace(declaration)!
			resolved := slot_resolve(mut tree)!
			assert resolved.hidden == !open
			if index == 0 {
				generation = (tree.identity('content') or { panic('missing identity') }).generation
			}
			assert (tree.identity('content') or { panic('missing identity') }).generation == generation
			if open {
				allocated := (slot_find(resolved, 'content') or { panic('missing content') })
				slot_rect(allocated.frame, slot_expected(composite, 320, 200))
				slot_assert_descendants(allocated, .grid, slot_expected(composite, 320, 200))
			}
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

$if macos && !ui2_custom_rendering ?&& !ui2_headless ? {
	fn slot_native_runtime_fixture(composite SlotComposite, layout LayoutKind) ! {
		mut st := state()
		previous := *st
		st.layout_tree = &LayoutTree{}
		st.root_view = native_new_flipped_view(native_rect(0, 0, 500, 300), BoxStyle{})
		defer {
			remove_stale_nodes(map[string]bool{})
			macos.release(st.root_view)
			unsafe { *st = previous }
		}
		content := slot_runtime_content(layout)!
		render_root(screen(0xffffff, [slot_composite(composite, rect(0, 0, 320, 200), content)!]))
		editor := st.views['editor'] or { panic('missing editor') }
		pane := st.views['pane'] or { panic('missing scroll') }
		macos.msg_void1(editor, 'setString:', macos.nsstring('ñ café🙂'))
		macos.msg_void_range(editor, 'setSelectedRange:', macos.range(1, 4))
		macos.msg_void_id_range(editor, 'setMarkedText:selectedRange:', macos.nsstring('á'), macos.range(1, 0))
		assert macos.msg_bool(editor, 'hasMarkedText')
		live_text := macos.utf8_string(macos.msg_id(editor, 'string'))
		selection := macos.msg_range(editor, 'selectedRange')
		composition := macos.msg_range(editor, 'markedRange')
		scroll_to_offset('pane', 42)
		assert scroll_offset('pane') == 42
		generation := (st.layout_tree.identity('editor') or { panic('missing identity') }).generation
		for size in [rect(0, 0, 500, 300), rect(0, 0, 320, 200)] {
			render_root(screen(0xffffff, [slot_composite(composite, size, content)!]))
			resolved := slot_resolve(mut st.layout_tree)!
			slot_rect((slot_find(resolved, 'content') or { panic('missing content') }).frame, slot_expected(composite, size.width, size.height))
			native_content := st.views['content'] or { panic('missing native content') }
			native_frame := macos.msg_rect(native_content, 'frame')
			slot_rect(rect(native_frame.x, native_frame.y, native_frame.width, native_frame.height), slot_expected(composite, size.width, size.height))
			assert (st.views['editor'] or { panic('lost editor') }) == editor && (st.views['pane'] or { panic('lost scroll') }) == pane
			assert (st.layout_tree.identity('editor') or { panic('missing identity') }).generation == generation
			assert macos.utf8_string(macos.msg_id(editor, 'string')) == live_text
			assert macos.msg_range(editor, 'selectedRange') == selection
			assert macos.msg_bool(editor, 'hasMarkedText')
			assert macos.msg_range(editor, 'markedRange') == composition
			assert scroll_offset('pane') == 42
		}
	}

	fn test_native_composite_resize_preserves_editor_selection_ime_and_scroll() {
		pool := macos.autorelease_pool_new()
		defer { macos.release(pool) }
		ensure_runtime_classes()
		for composite in [SlotComposite.screen_manager, .tabbed_panel, .modal_view, .carousel,
			.accordion, .popup] {
			for layout in [LayoutKind.flex, .grid, .stack] {
				slot_native_runtime_fixture(composite, layout)!
			}
		}
	}
}

$if macos && ui2_custom_rendering ?&& !ui2_headless ? {
	fn test_custom_composite_resize_preserves_local_edit_selection_focus_scroll_and_ime() {
		previous_app := g_gg_app
		previous_window := capture_custom_window_state()
		defer {
			g_gg_app = previous_app
			previous_window.restore()
		}
		for composite in [SlotComposite.screen_manager, .tabbed_panel, .modal_view, .carousel,
			.accordion, .popup] {
			for layout in [LayoutKind.flex, .grid, .stack] {
				mut app := &GgApp{ scheduler: new_frame_coordinator() }
				g_gg_app = app
				content := slot_runtime_content(layout)!
				app.declared_root = slot_composite(composite, rect(0, 0, 320, 200), content)!
				initial := app.scheduler.begin_frame(0) or { panic('no initial frame') }
				_ = resolve_custom_layout(mut app, initial, slot_measure, take_custom_layout_patches(mut app))!
				app.scheduler.finish_frame(initial)
				replace_text_prop('editor', 'declarado')
				replace_text_value('editor', 'ñ café🙂')
				replace_text_editor('editor', TextEditor{ text: 'ñ café🙂'.clone(), selection: TextSelection{ anchor: 1, caret: 4 } })
				g_focused_field = 'editor'
				g_scroll_offsets[named_scroll_state_id('pane')] = 42
				app.composition = TextComposition{ field_id: 'editor', text: 'á' }
				generation := (app.layout_tree.identity('editor') or { panic('missing identity') }).generation
				for index, size in [rect(0, 0, 500, 300), rect(0, 0, 320, 200)] {
					app.declared_root = slot_composite(composite, size, content)!
					app.scheduler.invalidate(.build)
					work := app.scheduler.begin_frame(i64(index + 1)) or { panic('missing rebuild') }
					resolved := resolve_custom_layout(mut app, work, slot_measure, take_custom_layout_patches(mut app))!
					app.scheduler.finish_frame(work)
					slot_rect((slot_find(resolved, 'content') or { panic('missing content') }).frame, slot_expected(composite, size.width, size.height))
					assert (app.layout_tree.identity('editor') or { panic('missing identity') }).generation == generation
					assert text('editor') == 'ñ café🙂'
					assert g_text_editors['editor'].selection == TextSelection{ anchor: 1, caret: 4 }
					assert focused_id() == 'editor' && scroll_offset('pane') == 42
					assert app.composition.field_id == 'editor' && app.composition.text == 'á'
				}
			}
		}
	}
}
