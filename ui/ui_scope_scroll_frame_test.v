// vtest vflags: -d ui2_custom_rendering -d darwin_sokol_glcore33
// vfmt off
@[has_globals]
module ui2

$if macos && ui2_custom_rendering ? && darwin_sokol_glcore33 ? && !ui2_headless ? {
import gg
import os
import sokol.gfx

__global scope_frame_mode int
__global scope_frame_builds int
__global scope_frame_phase int
__global scope_frame_setup_posted bool
__global scope_frame_verify_posted bool
__global scope_frame_events = []string{}
__global scope_frame_scheduler = &FrameCoordinator(unsafe { nil })
__global scope_frame_draws u64
__global scope_frame_verified bool

fn scope_frame_old_scroll(event ElementEvent) {
	scope_frame_events << 'old:${event.value}'
}

fn scope_frame_current_scroll(event ElementEvent) {
	scope_frame_events << 'current:${event.value}'
	// Scroll's established range includes its 16 logical unit bottom inset:
	// 250 + 30 + 16 - 100 = 196 after the post-begin content shrink.
	expected := if scope_frame_mode >= 10 { 196 } else { 430 }
	eprintln('scope callback frame mode=${scope_frame_mode} event=${event.kind} id=${event.id} value=${event.value}')
	assert event.kind == .scroll && event.id == 'pane' && event.value == expected
	scope_frame_scheduler = g_gg_app.scheduler
	scope_frame_draws = render_stats().draws
	match scope_frame_mode {
		1 { on_event(&gg.Event{typ: .unfocused}, g_gg_app) }
		2 { on_event(&gg.Event{typ: .suspended}, g_gg_app) }
		3 {
			previous := activate_custom_window_state(new_custom_window_state())
			activate_custom_window_state(previous)
		}
		4 { on_event(&gg.Event{typ: .key_down, key_code: .n}, g_gg_app) }
		5 { on_event(&gg.Event{typ: .mouse_down, mouse_x: 240, mouse_y: 140}, g_gg_app) }
		6 { update_custom_focus_tree(screen(0xffffff, [Element{kind: .button, id: 'replacement'}])) }
		7 { focus('fresh') }
		8 {
			g_gg_app.scheduler = new_frame_coordinator()
			assert ui_dispatcher().post(scope_frame_verify)
		}
		9, 10 { quit() }
		11 {
			previous := activate_custom_window_state(new_custom_window_state())
			activate_custom_window_state(previous)
		}
		else {}
	}
}

fn scope_frame_verify() {
	defer { quit() }
	scope_frame_assert_restoration()
	assert scope_frame_verified
	eprintln('scope callback frame mode=${scope_frame_mode} passed')
}

fn scope_frame_assert_restoration() {
	expected := if scope_frame_mode >= 10 { 196.0 } else { 430.0 }
	assert scope_frame_events == ['current:${expected}'], 'the current mounted callback must run exactly once'
	assert scope_frame_scheduler.stats().draws == scope_frame_draws
	assert !scope_frame_scheduler.stats().in_flight, 'the captured scheduler must finish an aborted frame'
	if scope_frame_mode >= 10 {
		// cancel commits an empty command frame rather than opening a GPU pass.
		assert gfx.query_frame_stats().num_passes == 0
		assert gfx.query_frame_stats().num_draw == 0
	}
	if scope_frame_mode == 6 {
		assert semantic_tree().filter(it.id == 'restore').len == 0
	} else if scope_frame_mode in [5, 7] {
		assert focused_id() == 'fresh'
	} else {
		assert active_focus_scope() == '' && focused_id() == 'restore'
		assert scroll_offset('pane') == expected
		assert text('restore') == 'café ñ'
		assert text_area_caret('restore') == 3 && text_area_selection_length('restore') == 2
	}
	if scope_frame_mode == 5 {
		assert g_touch.down && g_touch.pointer_captured && g_touch.pointer_target.id == 'fresh'
		on_event(&gg.Event{typ: .mouse_up, mouse_x: 240, mouse_y: 140}, g_gg_app)
	}
	scope_frame_verified = true
}

fn scope_frame_cleanup(app &GgApp) {
	if scope_frame_mode in [9, 10] {
		scope_frame_assert_restoration()
		assert scope_frame_verified
		assert scope_frame_scheduler.stats().closed
		eprintln('scope callback frame mode=${scope_frame_mode} passed')
	}
	on_cleanup(app)
}

fn scope_frame_pointer(_event ElementEvent) {}

fn scope_frame_setup() {
	focus('restore')
	assert focused_id() == 'restore' && scroll_offset('pane') == 430
	assert scope_frame_events == ['old:430.0']
	text_area_set_selection('restore', 1, 2)
	if scope_frame_mode < 10 {
		assert enter_focus_scope('scope')
		scroll_to_offset('pane', 0)
		assert scope_frame_events == ['old:430.0', 'old:0.0']
	}
	scope_frame_events.clear()
	scope_frame_phase = 1
	refresh()
}

fn scope_frame_root() Element {
	scope_frame_builds++
	// The initial preload build precedes mounting. Setup belongs to build #2.
	if scope_frame_builds >= 2 && !scope_frame_setup_posted {
		gfx.enable_frame_stats()
		g_gg_app.ctx.inner.config = gg.Config{...g_gg_app.ctx.inner.config, cleanup_fn: scope_frame_cleanup}
		scope_frame_setup_posted = true
		assert ui_dispatcher().post(scope_frame_setup)
	}
	if scope_frame_phase == 1 && !scope_frame_verify_posted {
		scope_frame_verify_posted = true
		assert ui_dispatcher().post(scope_frame_verify)
	}
	pane := Element{kind: .scroll, id: 'pane', frame: rect(0, 0, 160, 100),
		on_event: if scope_frame_phase == 0 { scope_frame_old_scroll } else { scope_frame_current_scroll },
		children: [Element{kind: .text_area, id: 'restore', text: 'café ñ', disable_scroll: true,
			frame: rect(0, if scope_frame_phase == 1 && scope_frame_mode >= 10 { 250 } else { 500 }, 150, 30)}]}
	mut children := [pane, Element{kind: .view, id: 'fresh', focus_policy: .focusable, clickable: true,
		draggable: true, on_event: scope_frame_pointer, frame: rect(200, 120, 100, 50)}]
	if scope_frame_phase == 0 {
		children << Element{kind: .view, id: 'scope', focus_scope: true, frame: rect(180, 0, 100, 100),
			children: [Element{kind: .button, id: 'inside', frame: rect(0, 0, 90, 30)}]}
	}
	return screen(0xffffff, children)
}

fn test_scope_removal_notifies_current_scroll_and_aborts_stale_frames_on_real_gl_host() {
	mode_arg := os.args.filter(it.starts_with('--scope-frame-mode='))
	if mode_arg.len == 0 {
		// NSApplication terminates the Sokol process when its window closes.
		// Run each case in a child and require its assertion-completion receipt.
		for mode in 0 .. 12 {
			result := os.execute('${os.quoted_path(os.executable())} --scope-frame-mode=${mode}')
			eprintln(result.output)
			assert result.exit_code == 0
			assert result.output.contains('scope callback frame mode=${mode} passed')
			assert !result.output.contains(' failed ')
		}
		return
	}
	previous_app := g_gg_app
	previous := activate_custom_window_state(new_custom_window_state())
	defer { activate_custom_window_state(previous); g_gg_app = previous_app }
	// Actual Mac GL windows; synthetic API/input calls do not certify physical
	// OS keyboard/pointer input or Metal host acceptance.
	scope_frame_mode = mode_arg[0].all_after('=').int()
	scope_frame_builds = 0
	scope_frame_phase = 0
	scope_frame_setup_posted = false
	scope_frame_verify_posted = false
	scope_frame_verified = false
	scope_frame_events = []string{}
	g_gg_app = &GgApp{}
	activate_custom_window_state(new_custom_window_state())
	run_window('Scope callback frame ownership', 320, 180, scope_frame_root)
	expected := if scope_frame_mode >= 10 { 196.0 } else { 430.0 }
	assert scope_frame_events == ['current:${expected}']
	assert scope_frame_verified
}
}
