// vtest build: macos && !ui2_custom_rendering?
// vfmt off
@[has_globals]
module ui2

$if !ui2_custom_rendering ? {
import macos
import os

__global native_reveal_mode int
__global native_reveal_armed bool
__global native_reveal_events = []string{}
__global native_reveal_after_callback f64

fn native_reveal_root(replaced bool) Element {
	return screen(0xffffff, [Element{kind: .scroll, id: 'outer', frame: rect(10, 10, 240, 100), on_event: native_reveal_scroll,
		children: [
			Element{kind: .button, id: 'redirect', text: 'Redirect', frame: rect(0, 0, 120, 30)},
			Element{kind: .scroll, id: 'inner', frame: rect(0, if replaced { 40 } else { 400 }, 180, 100), on_event: native_reveal_scroll,
				children: [Element{kind: if replaced && native_reveal_mode == 3 { Kind.text_field } else { Kind.button }, id: 'target',
					text: 'Target ñ', frame: rect(0, if replaced { 0 } else { 400 }, 120, 30)}]},
			Element{kind: .label, id: 'tail', text: 'extent', frame: rect(0, 900, 120, 30)},
		]}])
}

fn native_reveal_scroll(event ElementEvent) {
	if event.kind != .scroll { return }
	native_reveal_events << '${event.id}:${event.value}'
	if !native_reveal_armed || event.id != 'inner' { return }
	mut st := event.window
	native_reveal_armed = false
	if native_reveal_mode == 1 {
		st.focus('redirect')
	} else if native_reveal_mode in [2, 3] {
		st.render_root(native_reveal_root(true))
		st.focus('target')
	}
	native_reveal_after_callback = st.scroll_offset('outer')
}

fn test_appkit_nested_reveal_stops_after_actual_scroll_callback_redirect_or_replacement() {
	args := os.args.filter(it.starts_with('--native-reveal-mode='))
	if args.len == 0 {
		mut failures := []int{}
		for mode in 0 .. 4 {
			result := os.exec([os.executable(), '--native-reveal-mode=${mode}'])
			eprintln(result.output)
			if result.exit_code != 0 || !result.output.contains('native reveal mode=${mode} passed') { failures << mode }
		}
		assert failures.len == 0, 'native reveal failures: ${failures}'
		return
	}
	native_reveal_mode = args[0].all_after('=').int()
	pool := macos.autorelease_pool_new()
	defer { macos.release(pool) }
	mut st := scroll_semantic_window()
	defer { close_scroll_semantic_window(mut st) }
	st.render_root(native_reveal_root(false))
	st.focus('redirect')
	native_reveal_events.clear()
	native_reveal_armed = true
	before_target := st.views['target'] or { panic('missing original target') }
	st.focus('target')
	eprintln('native reveal mode=${native_reveal_mode} focused=${st.focused_id()} inner=${st.scroll_offset('inner')} outer=${st.scroll_offset('outer')} after_callback=${native_reveal_after_callback} events=${native_reveal_events}')
	assert !native_reveal_armed && native_reveal_events.len > 0, 'actual AppKit scrolling must synchronously call the registered Scroll handler'
	if native_reveal_mode == 0 {
		assert st.focused_id() == 'target' && st.scroll_offset('inner') > 0 && st.scroll_offset('outer') > 0
	} else {
		assert st.focused_id() == if native_reveal_mode == 1 { 'redirect' } else { 'target' }
		assert st.scroll_offset('outer') == native_reveal_after_callback, 'stale outer requests must stop after the inner callback'
		assert st.scroll_offset('outer') == 0, 'the new target is already visible in the outer viewport'
		after_target := st.views['target'] or { panic('missing replacement target') }
		if native_reveal_mode == 2 { assert after_target == before_target }
		if native_reveal_mode == 3 { assert after_target != before_target }
	}
	eprintln('native reveal mode=${native_reveal_mode} passed callbacks=${native_reveal_events.len}')
}

fn scroll_semantic_window() &Window {
	return appkit_fixture_window('Scroll and window semantics', 400, 300)
}

fn close_scroll_semantic_window(mut st Window) {
	st.render_root(screen(0xffffff, []))
	st.close_fixture()
}

fn test_appkit_explicit_scroll_focus_retains_identity_and_child_editor_ownership() {
	pool := macos.autorelease_pool_new()
	defer { macos.release(pool) }
	mut st := scroll_semantic_window()
	defer { close_scroll_semantic_window(mut st) }
	pane := Element{kind: .scroll, id: 'pane', focus_policy: .focusable,
		frame: rect(10, 50, 240, 180), children: [
			Element{kind: .text_field, id: 'field', text: 'declarado ñ', tab_index: -1, frame: rect(0, 0, 180, 30)},
			Element{kind: .text_area, id: 'area', text: 'área declarada', tab_index: -1, frame: rect(0, 40, 180, 60)},
			Element{kind: .button, id: 'child', text: 'Child', tab_index: -1, frame: rect(0, 110, 100, 30)},
		]}
	root := screen(0xffffff, [
		Element{kind: .button, id: 'a', text: 'A', frame: rect(10, 10, 100, 30)}, pane,
		Element{kind: .button, id: 'b', text: 'B', frame: rect(10, 250, 100, 30)},
	])
	st.render_root(root)
	st.focus('a')
	assert st.focused_id() == 'a'
	forward := st.focus_next()
	eprintln('scroll forward=${forward} id=${st.focused_id()}')
	assert forward && st.focused_id() == 'pane'
	native := st.views['pane'] or { panic('missing Scroll') }
	assert macos.msg_id(st.window, 'firstResponder') == macos.msg_id(native, 'documentView')
	assert (st.semantic_node('pane') or { panic('missing Scroll semantics') }).state.focused
	assert st.focus_next() && st.focused_id() == 'b'
	assert st.focus_previous() && st.focused_id() == 'pane'
	assert st.focus_previous() && st.focused_id() == 'a'
	st.focus('pane')
	assert st.focused_id() == 'pane'
	st.focus('b')
	assert st.perform_semantic_action('pane', .focus) && st.focused_id() == 'pane'
	for id in ['field', 'area', 'child'] {
		st.focus(id)
		assert st.focused_id() == id, 'Scroll must not claim its child responder'
	}
	st.focus('field')
	field := st.views['field'] or { panic('missing child field') }
	native_set_text(field, 'borrador café ñ')
	native_restore_control_selection(field, 2, 3)
	st.focus('pane')
	st.focus('field')
	assert st.text('field') == 'borrador café ñ'
	assert native_control_selected_range(field) == macos.range(2, 3)
	st.focus('area')
	area := st.text_area_document_view('area') or { panic('missing child text view') }
	macos.msg_void1(area, 'setString:', macos.nsstring('área local ñ'))
	st.text_area_set_selection('area', 1, 4)
	st.focus('pane')
	st.render_root(Element{...root, box: BoxStyle{bg: 0xeeeeee}})
	assert st.focused_id() == 'pane'
	st.focus('area')
	assert st.focused_id() == 'area' && st.text('area') == 'área local ñ'
	assert native_text_view_selected_range(area) == macos.range(1, 4)

	// The explicit Scroll is also the scope's first target; leaving restores
	// the real child editor and its selection, rather than the Scroll ancestor.
	scoped := screen(0xffffff, [Element{kind: .view, id: 'scope', focus_scope: true,
		frame: rect(0, 0, 400, 300), children: [pane, root.children[2]]}, root.children[0]])
	st.render_root(scoped)
	st.focus('a')
	assert st.enter_focus_scope('scope') && st.focused_id() == 'pane'
	assert st.focus_next() && st.focused_id() == 'b'
	assert st.focus_next() && st.focused_id() == 'pane'
	assert st.focus_previous() && st.focused_id() == 'b'
	assert st.perform_semantic_action('pane', .focus)
	assert st.leave_focus_scope() && st.focused_id() == 'a'
	st.focus('area')
	st.text_area_set_selection('area', 1, 3)
	assert st.enter_focus_scope('scope') && st.focused_id() == 'pane'
	assert st.leave_focus_scope() && st.focused_id() == 'area'
	assert st.text_area_selection_length('area') == 3
	assert !st.perform_semantic_action('scope', .focus)

	st.focus('pane')
	st.render_root(screen(0xffffff, [root.children[0], Element{...pane, enabled: false}, root.children[2]]))
	assert st.focused_id() != 'pane'
	st.focus('a')
	assert !st.perform_semantic_action('pane', .focus)
	st.focus('pane')
	assert st.focused_id() == 'a'
	assert st.focus_next() && st.focused_id() == 'b'
	st.render_root(root)
	st.focus('pane')
	st.render_root(screen(0xffffff, [root.children[0], root.children[2]]))
	assert st.focused_id() != 'pane' && !st.perform_semantic_action('pane', .focus)
	assert st.semantic_tree().filter(it.id == 'pane').len == 0
}

fn test_appkit_mounted_screen_semantics_use_current_logical_viewport_without_rebuild() {
	pool := macos.autorelease_pool_new()
	defer { macos.release(pool) }
	mut st := scroll_semantic_window()
	defer { close_scroll_semantic_window(mut st) }
	st.build = fn (mut _ Window) Element { panic('semantic read must not rebuild') }
	root := screen(0xffffff, [Element{kind: .view, id: 'panel', frame: rect(12.5, 9.25, 175, 80),
		children: [Element{kind: .label, id: 'caption', frame: rect(3.25, 4.5, 87.5, 10.25)}]}])
	st.render_root(root)
	stats := st.layout_tree.stats()
	resolved_frame := st.navigation.root.frame
	snapshot := st.semantic_tree()
	eprintln('mounted root=${snapshot[0].frame}')
	assert snapshot[0].role == 'window' && snapshot[0].frame == rect(0, 0, 400, 300)
	assert (st.semantic_node('panel') or { panic('missing panel') }).frame == rect(12.5, 9.25, 175, 80)
	assert (st.semantic_node('caption') or { panic('missing caption') }).frame == rect(15.75, 13.75, 87.5, 10.25)
	assert st.navigation.root.frame == resolved_frame && st.layout_tree.stats() == stats
	macos.msg_void_point(st.window, 'setContentSize:', macos.point(520, 360))
	assert st.semantic_tree()[0].frame == rect(0, 0, 520, 360)
	assert st.navigation.root.frame == resolved_frame && st.layout_tree.stats() == stats
	// A declared subtree is not a mounted screen viewport.
	st.navigation.set_root(root.children[0])
	assert st.semantic_tree()[0].frame == root.children[0].frame
	assert (st.semantic_node('caption') or { panic('missing subtree caption') }).frame == rect(15.75, 13.75, 87.5, 10.25)
}
}

$if !ui2_custom_rendering ? {
fn test_appkit_retained_patch_updates_focus_geometry_and_preserves_live_editor_and_scroll() {
	pool := macos.autorelease_pool_new()
	defer { macos.release(pool) }
	mut st := scroll_semantic_window()
	defer { close_scroll_semantic_window(mut st) }
	st.build = fn (mut _ Window) Element { panic('retained patch must not invoke BuildFn') }
	caption := label('caption', 'breve', Rect{}, TextStyle{size: 18, lines: 20})
	area := Element{kind: .text_area, id: 'area', key: 'stable-editor', text: 'declarado', disable_scroll: true, frame: rect(0, 0, 0, 60)}
	column := flex(FlexConfig{id: 'column', frame: rect(0, 0, 180, 600), orientation: .vertical, align: .stretch,
		children: [FlexChild{element: caption, shrink: 0}, FlexChild{element: area, shrink: 0}]})!
	pane := Element{kind: .scroll, id: 'pane', frame: rect(10.5, 20.25, 200, 100), children: [Element{...column, focus_scope: true}]}
	st.render_root(screen(0xffffff, [pane, Element{kind: .button, id: 'outside', text: 'Outside', frame: rect(240, 20, 100, 30)}]))
	st.focus('area')
	assert st.focused_id() == 'area'
	editor := st.text_area_document_view('area') or { panic('missing editor') }
	macos.msg_void1(editor, 'setString:', macos.nsstring('ñ café🙂'))
	macos.msg_void_range(editor, 'setSelectedRange:', macos.range(1, 4))
	macos.msg_void_id_range(editor, 'setMarkedText:selectedRange:', macos.nsstring('á'), macos.range(1, 0))
	assert macos.msg_bool(editor, 'hasMarkedText')
	live := st.text('area')
	selection := macos.msg_range(editor, 'selectedRange')
	marked := macos.msg_range(editor, 'markedRange')
	st.scroll_to_offset('pane', 12)
	offset := st.scroll_offset('pane')
	before := macos.msg_rect(editor, 'frame')
	geometry := (st.semantic_node('area') or { panic('missing semantics') }).frame
	st.layout_tree.reset_stats()
	st.refresh_element('caption', Element{...caption, text_style: TextStyle{...caption.text_style, color: 0xff0000}})
	assert st.layout_stats().builds == 0 && st.layout_stats().measure_visits == 0 && st.layout_stats().layout_visits == 0
	st.refresh_element('caption', Element{...caption, text: 'palabra palabra palabra palabra palabra palabra palabra palabra'})
	assert st.text_area_document_view('area') or { panic('lost editor') } == editor
	assert st.focused_id() == 'area' && st.text('area') == live
	assert macos.msg_range(editor, 'selectedRange') == selection
	assert macos.msg_bool(editor, 'hasMarkedText') && macos.msg_range(editor, 'markedRange') == marked
	assert st.scroll_offset('pane') == offset
	after := macos.msg_rect(editor, 'frame')
	resolved := (st.semantic_node('area') or { panic('lost semantics') }).frame
	assert after.y > before.y && resolved.y > geometry.y
	assert resolved.y - geometry.y == after.y - before.y
	assert st.layout_stats().builds == 0
	// An environment render shares the same focus snapshot/reconciliation path.
	st.invalidate_layout_environment(LayoutEnvironment{version: 1})
	assert st.focused_id() == 'area' && st.text('area') == live
	assert macos.msg_range(editor, 'selectedRange') == selection && macos.msg_bool(editor, 'hasMarkedText')
	assert st.scroll_offset('pane') == offset && st.layout_stats().builds == 0
	st.focus('outside')
	assert st.enter_focus_scope('column') && st.focused_id() == 'area'
	// Use the current retained declaration so the size patch remains applied.
	st.refresh_element('column', Element{...st.layout_tree.declaration().children[0].children[0], enabled: false})
	assert st.active_focus_scope() == '' && st.focused_id() == 'outside'
	assert (st.semantic_node('area') or { panic('missing disabled editor') }).state.disabled
	assert !st.perform_semantic_action('area', .focus)
	assert st.layout_stats().builds == 0
	eprintln('native retained focus/selection/composition/scroll combination passed')
}
}
