// vtest vflags: -d ui2_custom_rendering
@[has_globals]
module ui2

struct VmlFragmentItem {
	id   string
	text string
}

@[heap]
struct VmlFragmentFixture {
mut:
	lists        map[string]&VmlKeyedList[VmlFragmentItem]
	fragments    map[string]&CompiledVmlNode
	mounts       []string
	cleanups     []string
	patches      []Element
	outer_builds int
	inner_builds int
}

fn vml_fragment_rows(mut parent CompiledVmlNode, mut fixture VmlFragmentFixture) !&VmlKeyedList[VmlFragmentItem] {
	return new_vml_keyed_list(mut parent, 'outer', fn (item VmlFragmentItem) string {
		return item.id
	},
		fn [mut fixture] (mut row CompiledVmlComponent, source &Signal[VmlFragmentItem]) ![]&CompiledVmlNode {
			fixture.outer_builds++
			mut item := source
			id := item.get()!.id
			row.on_mount('mounted', fn [mut fixture, id] () ! { fixture.mounts << id })!
			row.on_cleanup('released', fn [mut fixture, id] () { fixture.cleanups << id })!
			mut fragment := row.fragment('body')!
			fragment.set_child_layout(VmlChildLayout{ flex: FlexChild{ basis: 20, shrink: 0 }, grid: GridSpan{ column_span: 2 } })!
			fixture.fragments[id] = fragment
			// An empty branch owns only this fragment, with no mounted controls.
			if id == 'empty' {
				fixture.lists[id] = new_vml_keyed_list(mut fragment, 'inner', vml_fragment_key, vml_fragment_inner)!
				return [fragment]
			}
			mut lead := row.element(Element{ kind: .label, id: 'lead', key: 'lead', text: id + ':before', frame: rect(0, 0, 20, 20) })!
			fragment.set_segment('before', [lead])!
			mut inner := new_vml_keyed_list(mut fragment, 'inner', vml_fragment_key,
				fn [mut fixture] (mut owner CompiledVmlComponent, inner_item &Signal[VmlFragmentItem]) ![]&CompiledVmlNode {
					fixture.inner_builds++
					return vml_fragment_inner(mut owner, inner_item)
				})!
			fixture.lists[id] = inner
			inner.update([VmlFragmentItem{ id: 'x', text: id + ':x' }])!
			mut tail := row.element(Element{ kind: .label, id: 'tail', key: 'tail', text: id + ':after', frame: rect(0, 0, 20, 20) })!
			fragment.set_segment('after', [tail])!
			return [fragment]
		})!
}

fn vml_fragment_key(item VmlFragmentItem) string { return item.id }

fn vml_fragment_inner(mut owner CompiledVmlComponent, source &Signal[VmlFragmentItem]) ![]&CompiledVmlNode {
	mut item := source
	mut edit := owner.element(text_area(TextAreaConfig{ id: 'edit', text: 'declarado', frame: rect(0, 0, 20, 40) })!)!
	edit.set_child_layout(VmlChildLayout{ flex: FlexChild{ basis: 25, shrink: 0 }, grid: GridSpan{ column_span: 1 } })!
	mut label := owner.element(Element{ kind: .label, id: 'label', frame: rect(0, 0, 20, 20) })!
	label.effect('text', fn [mut item] (element Element) !Element {
		return Element{ ...element, text: item.get()!.text }
	})!
	return [edit, label]
}

fn test_nested_fragment_lists_flatten_keys_layout_rules_and_source_order() ! {
	mut owner := new_vml_document('nested fragments')!
	mut fixture := &VmlFragmentFixture{}
	owner.publish = fn [mut fixture] (_ string, element Element) { fixture.patches << element }
	mut parent := owner.element(flex(FlexConfig{ id: 'root', frame: rect(0, 0, 600, 100) })!)!
	mut prefix := owner.element(Element{ kind: .label, id: 'prefix', key: 'prefix', frame: rect(0, 0, 30, 20) })!
	prefix.set_child_layout(VmlChildLayout{ flex: FlexChild{ basis: 30, shrink: 0 } })!
	parent.set_segment('before', [prefix])!
	mut rows := vml_fragment_rows(mut parent, mut fixture)!
	mut suffix := owner.element(Element{ kind: .label, id: 'suffix', key: 'suffix', frame: rect(0, 0, 50, 20) })!
	suffix.set_child_layout(VmlChildLayout{ flex: FlexChild{ basis: 50, shrink: 0 } })!
	parent.set_segment('after', [suffix])!
	rows.update([VmlFragmentItem{ id: 'a' }, VmlFragmentItem{ id: 'b' }])!
	parent.mount()!
	assert fixture.mounts == ['a', 'b']
	assert parent.children.len == 4 // two logical fragments and the neighbours
	assert parent.element().children.len == 10
	assert parent.element().children.all(it.kind != .view)
	assert parent.element().layout.flex.children.map(it.basis) == [30.0, 20.0, 25.0, 20.0, 20.0,
		20.0, 25.0, 20.0, 20.0, 50.0]
	keys := parent.element().children.map(it.key)
	mut seen := map[string]bool{}
	for key in keys {
		assert key !in seen
		seen[key] = true
	}
	assert keys.all(!it.contains('/compiled:') && !it.contains('vml:'))
	assert keys[2] != keys[6] // `x` belongs to independent outer branches
	mut layout := &LayoutTree{}
	layout.replace(parent.element())!
	resolved := layout.resolve(LayoutConstraints{}, measure_layout_text, LayoutEnvironment{})!
	assert resolved.children.len == 10
	for _, fragment in fixture.fragments {
		assert fragment.identity() !in layout.nodes
		assert fragment.frame()! == Rect{}
	}
	mut inner := fixture.lists['a'] or { panic('missing a list') }
	edit := inner.nodes()[0]
	identity := layout.identity(edit.element().id) or { panic('missing visible edit') }
	assert edit.frame()!.width == 25
	fixture.patches.clear()
	inner.update([VmlFragmentItem{ id: 'y', text: 'a:y' }, VmlFragmentItem{ id: 'x', text: 'a:x!' }])!
	assert fixture.inner_builds == 3
	assert inner.nodes()[2] == edit
	assert parent.element().children.len == 12
	assert parent.element().children[5].text == 'a:x!'
	assert fixture.patches.len == 2 // changed label + one structural root patch
	assert fixture.patches.last().id == 'root'
	rows.update([VmlFragmentItem{ id: 'b' }, VmlFragmentItem{ id: 'a' }])!
	assert fixture.outer_builds == 2
	assert parent.element().children[1].text == 'b:before'
	assert parent.element().children.last().id == 'suffix'
	layout.patch('root', parent.element())!
	assert layout.identity(edit.element().id) or { panic('retired edit') } == identity
	before := parent.element()
	mut retained := inner.nodes()[0]
	retained.set_child_layout(VmlChildLayout{ flex: FlexChild{ grow: -1 } }) or {
		assert err.msg().contains('negative') || err.msg().contains('non-negative')
		assert vml_declaration_equal(parent.element(), before)
	}
	rows.update([VmlFragmentItem{ id: 'a' }])!
	assert fixture.cleanups == ['b']
	removed := fixture.fragments['b'] or { panic('missing b fragment') }
	assert removed.component.is_disposed()
	rows.update([VmlFragmentItem{ id: 'b' }, VmlFragmentItem{ id: 'a' }])!
	assert fixture.outer_builds == 3
	assert fixture.mounts == ['a', 'b', 'b']
	owner.dispose()!
	assert owner.runtime.stats() == SignalStats{}
}

fn test_empty_fragments_mount_only_visible_descendants_and_dispose_once() ! {
	mut owner := new_vml_document('empty fragments')!
	mut fixture := &VmlFragmentFixture{}
	owner.publish = fn [mut fixture] (_ string, element Element) { fixture.patches << element }
	mut parent := owner.element(grid(GridConfig{ id: 'grid', frame: rect(0, 0, 400, 100), columns: 4 })!)!
	mut rows := vml_fragment_rows(mut parent, mut fixture)!
	rows.update([VmlFragmentItem{ id: 'empty' }])!
	parent.mount()!
	assert fixture.mounts.len == 0
	assert parent.element().children.len == 0
	before := parent.element()
	fragment := rows.nodes()[0]
	mut rejected := false
	parent.set_children([fragment, fragment]) or {
		rejected = true
		assert err.msg().contains('more than once')
		assert parent.children == [fragment]
		assert vml_declaration_equal(parent.element(), before)
	}
	assert rejected
	mut inner := fixture.lists['empty'] or { panic('missing empty list') }
	inner.update([VmlFragmentItem{ id: 'x', text: 'inside' }])!
	assert fixture.mounts == ['empty']
	assert parent.element().children.len == 2
	assert parent.element().layout.grid.child_spans.map(it.column_span) == [1, 2]
	first := inner.nodes()[0]
	inner.update([])!
	assert parent.element().children.len == 0
	assert first.component.is_disposed()
	inner.update([VmlFragmentItem{ id: 'x', text: 'new' }])!
	assert fixture.mounts == ['empty']
	assert inner.nodes()[0] != first
	rows.update([])!
	assert fixture.cleanups == ['empty']
	assert parent.element().children.len == 0
	owner.dispose()!
	owner.dispose()!
	assert fixture.cleanups == ['empty']
	assert owner.runtime.stats() == SignalStats{}
}

fn test_fragment_slot_keeps_author_captures_and_receiver_lifetime() ! {
	mut author := new_vml_document('fragment slots')!
	author.publish = fn (_ string, _ Element) {}
	mut value := author.state('title', 'author')!
	mut ref := author.ref[VmlButton]('slot button')!
	mut host := author.child('receiver')!
	mut content := author.slot_child(mut host, 'content')!
	mut group := content.fragment('slot roots')!
	mut button := content.element(Element{ kind: .button, id: 'button' })!
	button.effect('text', fn [mut value] (element Element) !Element {
		return Element{ ...element, text: value.get()! }
	})!
	callback := content.callback(fn [mut value] (_ ElementEvent) ! { value.set('clicked')! })
	ref.bind(button)!
	group.set_segment('button', [button])!
	mut root := author.element(Element{ kind: .view, id: 'root' })!
	root.set_children([group])!
	root.mount()!
	assert root.element().children.len == 1 && root.element().children[0].kind == .button
	assert ref.is_available()
	callback(ElementEvent{})
	assert root.element().children[0].text == 'clicked'
	root.set_children([])!
	host.dispose()!
	assert !ref.is_available() && content.is_disposed()
	value.set('surviving author')!
	callback(ElementEvent{})
	assert value.get()! == 'surviving author'
	author.dispose()!
	assert author.runtime.stats() == SignalStats{}
}

fn test_late_nested_fragment_mount_runs_parent_before_child() ! {
	mut owner := new_vml_document('late nested mount')!
	owner.publish = fn (_ string, _ Element) {}
	mut fixture := &VmlFragmentFixture{}
	mut outer := owner.child('outer')!
	mut inner := outer.child('inner')!
	outer.on_mount('outer', fn [mut fixture] () ! { fixture.mounts << 'outer' })!
	inner.on_mount('inner', fn [mut fixture] () ! { fixture.mounts << 'inner' })!
	mut outer_fragment := outer.fragment('outer roots')!
	mut inner_fragment := inner.fragment('inner roots')!
	outer_fragment.set_children([inner_fragment])!
	mut root := owner.element(Element{ kind: .view, id: 'root' })!
	root.set_children([outer_fragment])!
	root.mount()!
	assert fixture.mounts.len == 0
	mut node := inner.element(Element{ kind: .button, id: 'late' })!
	inner_fragment.set_children([node])!
	assert fixture.mounts == ['outer', 'inner']
	assert root.element().children.len == 1 && root.element().children[0].kind == .button
	owner.dispose()!
	assert owner.runtime.stats() == SignalStats{}
}

$if (android || linux || ((macos || windows) && ui2_custom_rendering ?)) && !ui2_headless ? {
	fn vml_fragment_measure(text string, _style TextStyle, width f64) !LayoutSize {
		return LayoutSize{ width: if width < 0 { f64(text.runes().len * 8) } else { width }, height: 30 }
	}

	fn test_nested_fragment_reorder_preserves_live_editor_and_retained_layout() ! {
		previous_app := g_gg_app
		previous_window := capture_custom_window_state()
		defer {
			g_gg_app = previous_app
			previous_window.restore()
		}
		mut app := &GgApp{ scheduler: new_frame_coordinator() }
		g_gg_app = app
		mut component := new_vml_document('live nested fragments')!
		defer { component.dispose() or { panic(err) } }
		mut fixture := &VmlFragmentFixture{}
		mut root := component.element(flex(FlexConfig{ id: 'root', frame: rect(0, 0, 600, 100) })!)!
		mut rows := vml_fragment_rows(mut root, mut fixture)!
		rows.update([VmlFragmentItem{ id: 'a' }, VmlFragmentItem{ id: 'b' }])!
		app.declared_root = root.element()
		initial := app.scheduler.begin_frame(0) or { panic('missing initial frame') }
		_ = resolve_custom_layout(mut app, initial, vml_fragment_measure, take_custom_layout_patches(mut app))!
		app.scheduler.finish_frame(initial)
		root.mount()!
		mut inner := fixture.lists['a'] or { panic('missing a') }
		editor_node := inner.nodes()[0]
		editor := editor_node.element().id
		identity := app.layout_tree.identity(editor) or { panic('missing editor') }
		replace_text_prop(editor, 'declarado')
		replace_text_value(editor, 'ñ café🙂')
		replace_text_editor(editor, TextEditor{ text: 'ñ café🙂'.clone(), selection: TextSelection{ anchor: 1, caret: 4 } })
		g_focused_field = editor
		g_scroll_offsets[named_scroll_state_id(editor)] = 42
		app.composition = TextComposition{ field_id: editor, text: 'á' }
		app.layout_tree.reset_stats()
		inner.update([VmlFragmentItem{ id: 'y', text: 'a:y' },
			VmlFragmentItem{ id: 'x', text: 'a:x!' }])!
		rows.update([VmlFragmentItem{ id: 'b' }, VmlFragmentItem{ id: 'a' }])!
		work := app.scheduler.begin_frame(1) or { panic('missing retained frame') }
		assert !work.build && work.reasons == [.layout]
		resolved := resolve_custom_layout(mut app, work, vml_fragment_measure, take_custom_layout_patches(mut app))!
		app.scheduler.finish_frame(work)
		assert resolved.children.len == 10
		assert resolved.children[7].id == editor
		assert resolved.children.all(it.kind != .view)
		assert app.layout_tree.identity(editor) or { panic('retired editor') } == identity
		assert text(editor) == 'ñ café🙂'
		assert g_text_editors[editor].selection == TextSelection{ anchor: 1, caret: 4 }
		assert g_focused_field == editor
		assert scroll_offset(editor) == 42
		assert app.composition == TextComposition{ field_id: editor, text: 'á' }
		assert app.layout_tree.stats().builds == 0
		assert !app.scheduler.stats().pending
		for _, fragment in fixture.fragments {
			assert fragment.frame()! == Rect{}
			assert fragment.identity() !in app.layout_tree.nodes
		}
	}
}
