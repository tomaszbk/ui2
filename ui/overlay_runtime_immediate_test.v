@[has_globals]
module ui2

import gg
import math

@[heap]
struct OverlayRuntimeClock {
mut:
	now f64
}

$if (linux || macos || windows) && !ui2_headless ? {
	__global overlay_requests = []ElementEvent{}
	__global overlay_clicks int

	fn overlay_motion_style(clock &OverlayRuntimeClock) MotionConfig {
		return MotionConfig{
			clock:            fn [clock] () f64 { return clock.now }
			enter:            MotionStyle{ opacity: 0, translate_x: -40 }
			enter_transition: MotionTransition{ duration: 0.2 }
			exit_transition:  MotionTransition{ duration: 0.4 }
		}
	}
	fn overlay_motion_frame(mut w Window, now i64) !(Element, FrameWork) {
		work := w.scheduler.begin_frame(now) or { return error('expected motion frame') }
		root := w.resolve_custom_layout(work, measure_layout_text, w.take_custom_layout_patches())!
		w.reconcile_mounted_focus_controls(root)
		w.update_custom_focus_tree(root)
		w.scheduler.set_motion_active(motion_tree_needs_frame(w.declared_root))
		w.scheduler.finish_frame(work)
		return root, work
	}
	fn overlay_record(event ElementEvent) { overlay_requests << event }
	fn overlay_record_quit(event ElementEvent) {
		mut w := event.window
		overlay_requests << event
		w.quit()
	}
	fn overlay_click(_event ElementEvent) { overlay_clicks++ }

	fn overlay_mount(mut w Window, root Element) !Element {
		w.declared_root = root
		w.has_root = true
		w.declaration_pending = true
		projected := w.resolve_custom_layout_snapshot(FrameWork{}, measure_layout_text, [], true)!
		w.reconcile_mounted_focus_controls(projected)
		w.update_custom_focus_tree(projected)
		return projected
	}

	fn overlay_runtime_root(children []Element) Element {
		return Element{ kind: .screen, id: 'root', frame: rect(0, 0, 400, 300), children: children }
	}

	fn test_overlay_outside_veto_escape_repeat_and_callback_quit_are_consumed() ! {
		mut w := &Window{ ctx: &DrawContext{ width: 400, height: 300 } }
		overlay_requests.clear()
		overlay_clicks = 0
		dialog := with_overlay(view('dialog', rect(0, 0, 180, 100), BoxStyle{}, [
			Element{ kind: .button, id: 'inside', frame: rect(8, 8, 100, 28), on_event: overlay_click },
		]), OverlayConfig{ kind: .dialog, open: true, on_dismiss: overlay_record })!
		overlay_mount(mut w, overlay_runtime_root([
			Element{ kind: .button, id: 'outside', frame: rect(0, 0, 100, 28), on_event: overlay_click },
			dialog,
		]))!
		assert w.overlay_pointer_down(10, 10)
		assert overlay_clicks == 0 && overlay_requests.last().dismiss_reason == .outside_pointer
		assert w.overlay_tree.top_active() != none // controlled veto retains modal
		assert !w.navigation.can_focus('outside')
		assert !w.overlay_pointer_down(120, 110)
		assert w.overlay_key(KeyEvent{ code: .escape }, false)
		assert w.overlay_key(KeyEvent{ code: .escape }, true)
		assert overlay_requests.len == 2 && overlay_requests.last().dismiss_reason == .escape
		quitting := with_overlay(view('dialog', dialog.frame, BoxStyle{}, dialog.children), OverlayConfig{
			kind:       .dialog
			open:       true
			on_dismiss: overlay_record_quit
		})!
		overlay_mount(mut w, overlay_runtime_root([quitting]))!
		assert w.overlay_pointer_down(10, 10)
		assert w.scheduler.is_closed() && overlay_clicks == 0
	}

	fn test_overlay_menu_keyboard_selection_and_secondary_context_request() ! {
		mut w := &Window{ ctx: &DrawContext{ width: 400, height: 300 } }
		overlay_requests.clear()
		overlay_clicks = 0
		anchor := Element{ kind: .button, id: 'anchor', frame: rect(20, 20, 100, 30), on_event: overlay_click }
		menu := with_overlay(view('menu', rect(0, 0, 140, 90), BoxStyle{}, [
			Element{ kind: .button, id: 'first', frame: rect(4, 4, 130, 28), on_event: overlay_click },
			Element{ kind: .button, id: 'last', frame: rect(4, 36, 130, 28), on_event: overlay_click },
		]), OverlayConfig{ kind: .menu, open: true, anchor: 'anchor', on_dismiss: overlay_record })!
		overlay_mount(mut w, overlay_runtime_root([anchor, menu]))!
		assert w.focused_id() == 'first'
		assert w.overlay_key(KeyEvent{ code: .up }, false) && w.focused_id() == 'last'
		assert w.overlay_key(KeyEvent{ code: .home }, false) && w.focused_id() == 'first'
		assert w.activate_semantic_control('first', .activate)
		assert overlay_clicks == 1 && overlay_requests.last().dismiss_reason == .selection
		context := with_overlay(view('context', rect(0, 0, 140, 90), BoxStyle{}, []), OverlayConfig{
			kind:    .context_menu
			anchor:  'anchor'
			on_open: overlay_record
		})!
		overlay_mount(mut w, overlay_runtime_root([anchor, context]))!
		on_event(&gg.Event{ typ: .mouse_down, mouse_button: .right, mouse_x: 50, mouse_y: 30 }, mut w)
		on_event(&gg.Event{ typ: .mouse_up, mouse_button: .right, mouse_x: 50, mouse_y: 30 }, mut w)
		assert overlay_clicks == 1
		assert overlay_requests.last().kind == .open
		assert overlay_requests.last().x == 50 && overlay_requests.last().y == 30
		assert !w.touch.down
		opened := with_overlay(view('context', context.frame, context.box, []), OverlayConfig{
			kind:    .context_menu
			anchor:  'anchor'
			open:    true
			point:   OverlayPoint{ x: 160, y: 100 }
			on_open: overlay_record
		})!
		overlay_mount(mut w, overlay_runtime_root([anchor, opened]))!
		on_event(&gg.Event{ typ: .mouse_down, mouse_button: .right, mouse_x: 40, mouse_y: 30 }, mut w)
		assert overlay_requests.last().kind == .open && overlay_requests.last().x == 40
		assert overlay_clicks == 1
	}

	fn test_overlay_tooltip_deadlines_focus_and_owner_retirement() ! {
		mut w := &Window{ ctx: &DrawContext{ width: 400, height: 300 } }
		overlay_requests.clear()
		anchor := Element{ kind: .button, id: 'anchor', frame: rect(20, 20, 100, 30) }
		tip := with_overlay(view('tip', rect(0, 0, 140, 50), BoxStyle{}, []), OverlayConfig{
			kind:          .tooltip
			anchor:        'anchor'
			tooltip_delay: 0.5
			on_open:       overlay_record
			on_dismiss:    overlay_record
		})!
		overlay_mount(mut w, overlay_runtime_root([anchor, tip]))!
		w.tooltip.pointer_in = true
		w.tooltip.pointer_x = 30
		w.tooltip.pointer_y = 30
		w.update_overlay_triggers(0)
		assert w.overlay_deadline() == 500 && overlay_requests.len == 0
		w.update_overlay_triggers(499)
		assert overlay_requests.len == 0
		w.update_overlay_triggers(500)
		assert overlay_requests.len == 1 && overlay_requests.last().kind == .open
		assert w.overlay_deadline() == -1
		w.update_overlay_triggers(700)
		assert overlay_requests.len == 1 // one request while controlled owner vetoes
		w.tooltip.pointer_in = false
		w.update_overlay_triggers(710)
		w.focus('anchor')
		w.update_overlay_triggers(711)
		assert overlay_requests.len == 2 && w.overlay_deadline() == -1
		opened := with_overlay(view('tip', tip.frame, tip.box, []), OverlayConfig{
			kind:       .tooltip
			open:       true
			anchor:     'anchor'
			on_open:    overlay_record
			on_dismiss: overlay_record
		})!
		overlay_mount(mut w, overlay_runtime_root([anchor, opened]))!
		assert !w.navigation.can_focus('tip')
		overlay_mount(mut w, overlay_runtime_root([opened]))!
		w.update_overlay_triggers(720)
		w.update_overlay_triggers(721)
		assert overlay_requests.filter(it.dismiss_reason == .owner_unavailable && it.kind == .dismiss).len == 1
		overlay_mount(mut w, overlay_runtime_root([]))!
		w.update_overlay_triggers(730)
		assert w.overlay_triggers.len == 0 && w.overlay_deadline() == -1
		w.focused_field = ''
		w.tooltip.pointer_in = true
		overlay_mount(mut w, overlay_runtime_root([anchor, tip]))!
		w.update_overlay_triggers(1000)
		assert w.overlay_deadline() == 1500
		overlay_mount(mut w, overlay_runtime_root([tip]))!
		w.update_overlay_triggers(1010)
		assert w.overlay_deadline() == -1 && w.overlay_triggers.len == 0
	}

	fn test_overlay_motion_backdrop_exit_and_editor_reopen_keep_retained_state() ! {
		mut clock := &OverlayRuntimeClock{}
		config := OverlayConfig{ kind: .dialog, open: true, backdrop_opacity: 0.4 }
		base := view('dialog', rect(0, 0, 180, 100), BoxStyle{}, [
			Element{ kind: .text_field, id: 'draft', text: 'España ñ', frame: rect(8, 8, 160, 28) },
		])
		motion := overlay_motion_style(clock)
		dialog := with_motion(with_overlay(base, config)!, motion)
		mut w := &Window{ ctx: &DrawContext{ width: 400, height: 300 }, has_root: true, declared_root: overlay_runtime_root([dialog]) }
		defer {
			w.motion_tree.dispose()
		}
		overlay_motion_frame(mut w, 0)!
		clock.now = 0.1
		mid, _ := overlay_motion_frame(mut w, 100)!
		assert math.abs(mid.children[1].presented_opacity() - 0.2) < 0.00001
		clock.now = 0.21
		overlay_motion_frame(mut w, 210)!
		assert w.scheduler.begin_frame(211) == none
		w.set_text('draft', 'borrador café ñ')
		mut editor := w.text_editors['draft'] or { panic('editor') }
		editor.selection = TextSelection{ anchor: 1, caret: 6 }
		w.replace_text_editor('draft', editor)
		closed := with_motion(with_overlay(base, OverlayConfig{ ...config, open: false })!, motion)
		w.declared_root = overlay_runtime_root([closed])
		w.declaration_pending = true
		w.scheduler.invalidate(.layout)
		leaving, _ := overlay_motion_frame(mut w, 220)!
		assert leaving.children.len == 3 && !w.navigation.can_focus('draft')
		assert w.text('draft') == 'borrador café ñ'
		clock.now = 0.31
		overlay_motion_frame(mut w, 310)!
		w.declared_root = overlay_runtime_root([dialog])
		w.declaration_pending = true
		w.scheduler.invalidate(.layout)
		overlay_motion_frame(mut w, 320)!
		assert w.text('draft') == 'borrador café ñ'
		assert w.text_editors['draft'].selection == editor.selection
		clock.now = 0.6
		overlay_motion_frame(mut w, 600)!
		assert w.scheduler.begin_frame(601) == none
	}
}
