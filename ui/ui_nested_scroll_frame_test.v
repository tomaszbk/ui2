// vtest vflags: -d ui2_custom_rendering -d darwin_sokol_glcore33
// vfmt off
@[has_globals]
module ui2

$if macos && ui2_custom_rendering ? && (darwin_sokol_glcore33 ? || ui2_embedder ?) && !ui2_headless ? {
import os
__global nested_scroll_mode int
__global nested_scroll_removed = false
__global nested_scroll_build_count = 0
__global nested_scroll_setup_posted = false
__global nested_scroll_verify_posted = false
__global nested_scroll_scroll_events = []f64{}
__global nested_scroll_b_old_events = []f64{}
__global nested_scroll_b_new_events = []f64{}
__global nested_scroll_nested_events = []string{}
__global nested_scroll_setup_draws u64
fn nested_scroll_scrolled(event ElementEvent) {
	if event.kind == .scroll {
		assert event.id == 'pane'
		nested_scroll_scroll_events << event.value
		eprintln('A SCROLL callback offset=${event.value}')
		if nested_scroll_removed {
			nested_scroll_nested_events << 'A:${event.value}'
			// Public API reentry while automatic scope restoration is notifying A.
			// The default case keeps B visible with a changed mounted handler.
			if nested_scroll_mode == 5 {
				scroll_to_rect('pane_b', 0, 250, 10, 30)
			} else {
				scroll_to_offset('pane_b', if nested_scroll_mode == 1 { 10_000 } else { 42 })
			}
		}
	}
}
fn nested_scroll_b_old_scrolled(event ElementEvent) {
	if event.kind == .scroll {
		assert event.id == 'pane_b'
		nested_scroll_b_old_events << event.value
		eprintln('B OLD SCROLL callback offset=${event.value}')
		if nested_scroll_removed { nested_scroll_nested_events << 'B_OLD:${event.value}' }
	}
}
fn nested_scroll_b_new_scrolled(event ElementEvent) {
	if event.kind == .scroll {
		assert event.id == 'pane_b'
		nested_scroll_b_new_events << event.value
		eprintln('B NEW SCROLL callback offset=${event.value}')
		if nested_scroll_removed { nested_scroll_nested_events << 'B_NEW:${event.value}' }
	}
}
fn nested_scroll_setup() {
	focus('restore')
	assert focused_id() == 'restore'
	assert scroll_offset('pane') == 430
	assert nested_scroll_scroll_events == [f64(430)], 'ordinary focus reveal callback control'
	text_area_set_selection('restore', 1, 2)
	assert text_area_caret('restore') == 3 && text_area_selection_length('restore') == 2
	if nested_scroll_mode != 8 {
		assert enter_focus_scope('scope')
		scroll_to_offset('pane', 0)
		assert nested_scroll_scroll_events == [f64(430), f64(0)], 'public scroll callback control'
		assert scroll_offset('pane') == 0
	}
	// Prove B was actually mounted and its old typed handler receives changes.
	scroll_to_offset('pane_b', 17)
	assert scroll_offset('pane_b') == 17
	assert nested_scroll_b_old_events == [f64(17)] && nested_scroll_b_new_events.len == 0
	scroll_to_offset('pane_b', 0)
	assert scroll_offset('pane_b') == 0
	assert nested_scroll_b_old_events == [f64(17), f64(0)] && nested_scroll_b_new_events.len == 0
	eprintln('CONTROLS PASSED mode=${nested_scroll_mode} A=${nested_scroll_scroll_events} B_OLD=${nested_scroll_b_old_events} build_count=${nested_scroll_build_count}')
	nested_scroll_scroll_events.clear()
	nested_scroll_b_old_events.clear()
	nested_scroll_b_new_events.clear()
	nested_scroll_nested_events.clear()
	nested_scroll_setup_draws = render_stats().draws
	nested_scroll_removed = true
	refresh()
}
fn nested_scroll_verify() {
	defer { quit() }
	eprintln('ACTUAL focus=${focused_id()} scope=${active_focus_scope()} offset=${scroll_offset('pane')} callbacks=${nested_scroll_scroll_events} text=${text('restore')} caret=${text_area_caret('restore')} selection_length=${text_area_selection_length('restore')} B_offset=${scroll_offset('pane_b')} B_old=${nested_scroll_b_old_events} B_new=${nested_scroll_b_new_events} nested=${nested_scroll_nested_events}')
	assert active_focus_scope() == '' && focused_id() == 'restore'
	expected_a := if nested_scroll_mode == 8 { f64(196) } else { f64(430) }
	assert scroll_offset('pane') == expected_a
	assert text('restore') == 'café ñ'
	assert text_area_caret('restore') == 3 && text_area_selection_length('restore') == 2
	assert nested_scroll_scroll_events == [expected_a], 'restoration or paint-time clamping must notify the current mounted Scroll callback'
	if nested_scroll_mode in [2, 3, 6] {
		assert nested_scroll_b_old_events.len == 0 && nested_scroll_b_new_events.len == 0
		assert named_scroll_state_id('pane_b') !in g_scroll_viewports
		assert g_pending_scroll[named_scroll_state_id('pane_b')] == 42
		eprintln('nested current scroll mode=${nested_scroll_mode} passed')
		return
	}
	expected := if nested_scroll_mode == 1 { f64(86) } else if nested_scroll_mode == 5 { f64(80) } else { f64(42) }
	assert scroll_offset('pane_b') == expected, 'nested public scroll uses the current mounted logical range'
	assert nested_scroll_b_old_events.len == 0, 'nested public scroll must not dispatch B previous painted handler'
	assert nested_scroll_b_new_events == [expected], 'nested public scroll must notify B current declared handler exactly once'
	assert nested_scroll_nested_events == ['A:${expected_a}', 'B_NEW:${expected}']
	if nested_scroll_mode == 8 {
		assert render_stats().draws == nested_scroll_setup_draws, 'paint-time notification must abort its stale draw'
	}
	if nested_scroll_mode in [4, 7] {
		assert render_stats().draws > nested_scroll_setup_draws, 'a normal retained frame must complete after restoration'
		assert named_scroll_state_id('pane_b') in g_scroll_viewports, 'culled mounted panes keep their current logical range after painting'
	}
	eprintln('nested current scroll mode=${nested_scroll_mode} passed')
}
fn nested_scroll_build() Element {
	nested_scroll_build_count++
	$if ui2_embedder ? {
		// The owned host has no preload build. Request a second mounted build
		// before running the same public API controls used by the GL host.
		if nested_scroll_build_count == 1 { assert ui_dispatcher().post(refresh) }
	}
	// Retain the root-corrected timing: on_init preload build #1 is unmounted.
	if nested_scroll_build_count >= 2 && !nested_scroll_setup_posted { nested_scroll_setup_posted = true; assert ui_dispatcher().post(nested_scroll_setup) }
	if nested_scroll_removed && !nested_scroll_verify_posted
		&& (nested_scroll_mode !in [4, 7] || nested_scroll_build_count >= 4) {
		nested_scroll_verify_posted = true
		assert ui_dispatcher().post(nested_scroll_verify)
	}
	pane := Element{kind: .scroll, id: 'pane', frame: rect(0, 0, 160, 100), on_event: nested_scroll_scrolled,
		children: [Element{kind: .text_area, id: 'restore', text: 'café ñ', disable_scroll: true,
			frame: rect(0, if nested_scroll_removed && nested_scroll_mode == 8 { 250 } else { 500 }, 150, 30)}]}
	pane_b := Element{kind: .scroll, id: 'pane_b', frame: rect(180, if nested_scroll_removed && nested_scroll_mode == 4 { 500 } else { 0 }, 130, if nested_scroll_removed && nested_scroll_mode == 1 { 120 } else if nested_scroll_removed && nested_scroll_mode == 5 { 200 } else { 100 }),
		on_event: if nested_scroll_removed { nested_scroll_b_new_scrolled } else { nested_scroll_b_old_scrolled },
		children: [Element{kind: .label, id: 'b_bottom', text: 'B content', frame: rect(0, if nested_scroll_removed && nested_scroll_mode == 1 { 160 } else { 300 }, 110, 30)}]}
	mut children := [pane]
	if !nested_scroll_removed || nested_scroll_mode !in [2, 3, 6] {
		if nested_scroll_removed && nested_scroll_mode == 4 {
			children << Element{kind: .scroll, id: 'outer_b', frame: rect(180, 0, 130, 100), children: [pane_b]}
		} else { children << pane_b }
	} else if nested_scroll_mode in [3, 6] {
		children << Element{kind: if nested_scroll_mode == 6 { Kind.text_area } else { Kind.view }, id: 'pane_b', frame: rect(180, 0, 130, 100), on_event: nested_scroll_b_new_scrolled}
	}
	// Scope moves below B to keep B visibly mounted; no physical input is used.
	if !nested_scroll_removed { children << Element{kind: .view, id: 'scope', focus_scope: true, frame: rect(180, 110, 130, 60),
		children: [Element{kind: .button, id: 'inside', text: 'Inside', frame: rect(0, 0, 90, 30)}]} }
	return screen(0xffffff, children)
}
fn test_nested_public_scroll_from_scope_restoration_uses_current_mounted_handler_and_range() {
	mode_arg := os.args.filter(it.starts_with('--nested-scroll-mode='))
	if mode_arg.len == 0 {
		// Closing a Sokol window exits its process. Require every child's business marker.
		// The paint-time empty-frame case uses GL. Owned Metal cancellation
		// already fails in Sokol commit without a command buffer, independently
		// of nested notifications; that resource defect is tracked separately.
		case_count := $if ui2_embedder ? { 8 } $else { 9 }
		for mode in 0 .. case_count {
			result := os.execute('${os.quoted_path(os.executable())} --nested-scroll-mode=${mode}')
			eprintln(result.output)
			assert result.exit_code == 0
			assert result.output.contains('nested current scroll mode=${mode} passed')
			assert !result.output.contains('FAIL:')
		}
		return
	}
	nested_scroll_mode = mode_arg[0].all_after('=').int()
	run_window('Nested current Scroll callback regression', 320, 180, nested_scroll_build)
}
}
