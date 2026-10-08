// vtest vflags: -d ui2_custom_rendering
// vfmt off
@[has_globals]
module ui2

$if (android || linux || ((macos || windows) && ui2_custom_rendering ?)) && !ui2_headless ? {
	import gg

	struct PointerCaptureRecord {
	callback string
	event ElementEvent
}

__global pointer_capture_events = []PointerCaptureRecord{}

fn pointer_capture_expected(callback string, event ElementEvent) PointerCaptureRecord {
	return PointerCaptureRecord{ callback: callback, event: event }
}

fn pointer_capture_callback(callback string, remove_on_up bool) ElementCallback {
	return fn [callback, remove_on_up] (event ElementEvent) {
		pointer_capture_events << PointerCaptureRecord{ callback: callback, event: event }
		if remove_on_up && event.kind == .pointer_up { g_hit_targets = []HitTarget{} }
	}
}

	fn reset_pointer_capture_test() {
		g_touch = TouchState{}
		g_hit_targets = []HitTarget{}

		pointer_capture_events = []PointerCaptureRecord{}
		reset_scroll_frame()
		close_dropdown()
	}

	fn test_drag_keeps_original_target_after_resize_handle_moves_and_is_covered() {
		reset_pointer_capture_test()
		// The IDE's 9px resize handles move outside the original press almost
		// immediately. Their callbacks do not require an element id.
		g_hit_targets = [HitTarget{identity: 'resize_widget', on_event: pointer_capture_callback('resize_widget', false), w: 9, h: 9, draggable: true}]
		handle_touch_down(4, 4)
		handle_touch_move(20, 20)
		// Simulate the next frame rebuilding the hit targets at new coordinates.
		g_hit_targets = [
			HitTarget{identity: 'resize_widget', on_event: pointer_capture_callback('resize_widget', false), x: 20, y: 20, w: 9, h: 9, draggable: true},
			HitTarget{identity: 'unrelated', on_event: pointer_capture_callback('unrelated', false), w: 9, h: 9, slider: true},
		]
		handle_touch_move(50, 60)
		handle_touch_up(70, 80)
		assert pointer_capture_events == [
			pointer_capture_expected('resize_widget', ElementEvent{ kind: .pointer_down, x: 4, y: 4 }),
			pointer_capture_expected('resize_widget', ElementEvent{ kind: .pointer_drag, x: 20, y: 20 }),
			pointer_capture_expected('resize_widget', ElementEvent{ kind: .pointer_drag, x: 50, y: 60 }),
			pointer_capture_expected('resize_widget', ElementEvent{ kind: .pointer_up, x: 70, y: 80 }),
		]
		assert !g_touch.down
		handle_touch_move(90, 90)
		handle_touch_up(90, 90)
		assert pointer_capture_events.len == 4
	}

	fn test_capture_is_released_and_the_next_press_uses_the_new_target() {
		reset_pointer_capture_test()
		g_hit_targets = [HitTarget{identity: 'first', on_event: pointer_capture_callback('first', false), w: 20, h: 20, clickable: true}]
		handle_touch_down(5, 5)
		g_hit_targets = [HitTarget{identity: 'second', on_event: pointer_capture_callback('second', false), w: 20, h: 20, clickable: true}]
		handle_touch_up(5, 5)
		handle_touch_down(5, 5)
		handle_touch_up(5, 5)
		assert pointer_capture_events == [
			pointer_capture_expected('first', ElementEvent{ kind: .pointer_down, x: 5, y: 5 }),
			pointer_capture_expected('first', ElementEvent{ kind: .pointer_up, x: 5, y: 5 }),
			pointer_capture_expected('second', ElementEvent{ kind: .pointer_down, x: 5, y: 5 }),
			pointer_capture_expected('second', ElementEvent{ kind: .pointer_up, x: 5, y: 5 }),
		]
	}

	fn test_capture_survives_a_frame_with_no_hit_targets_and_cancels_on_focus_loss() {
		reset_pointer_capture_test()
		g_hit_targets = [HitTarget{identity: 'drag', on_event: pointer_capture_callback('drag', false), w: 20, h: 20, draggable: true}]
		handle_touch_down(5, 5)
		g_hit_targets = []HitTarget{}
		on_event(&gg.Event{typ: .mouse_move, mouse_x: 40, mouse_y: 50}, &GgApp{})
		on_event(&gg.Event{typ: .unfocused}, &GgApp{})
		assert pointer_capture_events == [
			pointer_capture_expected('drag', ElementEvent{ kind: .pointer_down, x: 5, y: 5 }),
			pointer_capture_expected('drag', ElementEvent{ kind: .pointer_drag, x: 40, y: 50 }),
			pointer_capture_expected('drag', ElementEvent{ kind: .pointer_up, x: 40, y: 50 }),
		]
		assert !g_touch.down
		on_event(&gg.Event{typ: .mouse_up, mouse_x: 40, mouse_y: 50}, &GgApp{})
		assert pointer_capture_events.len == 3
	}

	fn test_cancelling_an_ordinary_button_does_not_activate_it() {
		reset_pointer_capture_test()
		g_hit_targets = [HitTarget{identity: 'button', on_event: pointer_capture_callback('button', false), w: 20, h: 20}]
		handle_touch_down(5, 5)
		on_event(&gg.Event{typ: .touches_cancelled}, &GgApp{})
		handle_touch_up(5, 5)
		assert pointer_capture_events.len == 0
		assert !g_touch.down
	}

	fn test_button_behavior_emits_one_tap_on_release_inside() {
		reset_pointer_capture_test()
		g_hit_targets = [HitTarget{
			identity: 'save_card', on_event: pointer_capture_callback('save_card', false)
			w:              120
			h:              56
			button_behavior: true
		}]
		handle_touch_down(20, 20)
		handle_touch_up(20, 20)
		assert pointer_capture_events == [pointer_capture_expected('save_card', ElementEvent{ kind: .tap })]
	}

	fn test_button_behavior_keeps_the_pressed_target_across_a_rebuild() {
		reset_pointer_capture_test()
		g_hit_targets = [HitTarget{
			id:             'card'
			identity: 'original', on_event: pointer_capture_callback('original', false)
			w:              120
			h:              56
			button_behavior: true
		}]
		handle_touch_down(20, 20)
		g_hit_targets = [HitTarget{
			id:             'card'
			identity: 'replacement', on_event: pointer_capture_callback('replacement', false)
			w:              120
			h:              56
			button_behavior: true
		}]
		handle_touch_up(20, 20)
		assert pointer_capture_events == [pointer_capture_expected('original', ElementEvent{ kind: .tap, id: 'card' })]
	}

	fn test_button_behavior_revalidates_current_geometry_and_registration() {
		reset_pointer_capture_test()
		g_hit_targets = [HitTarget{
			id:             'card'
			identity: 'save', on_event: pointer_capture_callback('save', false)
			w:              40
			h:              20
			button_behavior: true
		}]
		handle_touch_down(10, 10)
		// Releasing in the old frame must not activate after the view moves.
		g_hit_targets = [HitTarget{
			id:             'card'
			identity: 'save', on_event: pointer_capture_callback('save', false)
			x:              100
			w:              40
			h:              20
			button_behavior: true
		}]
		handle_touch_up(10, 10)
		assert pointer_capture_events.len == 0

		// A resize that excludes the unchanged pointer also cancels activation.
		reset_pointer_capture_test()
		g_hit_targets = [HitTarget{
			id:             'card'
			identity: 'save', on_event: pointer_capture_callback('save', false)
			w:              40
			h:              20
			button_behavior: true
		}]
		handle_touch_down(30, 10)
		g_hit_targets = [HitTarget{
			id:             'card'
			identity: 'save', on_event: pointer_capture_callback('save', false)
			w:              20
			h:              20
			button_behavior: true
		}]
		handle_touch_up(30, 10)
		assert pointer_capture_events.len == 0

		// The current frame is authoritative while the captured action stays fixed.
		reset_pointer_capture_test()
		g_hit_targets = [HitTarget{
			id:             'card'
			identity: 'save', on_event: pointer_capture_callback('save', false)
			w:              5
			h:              20
			button_behavior: true
		}]
		handle_touch_down(2, 10)
		g_hit_targets = [HitTarget{
			id:             'card'
			identity: 'replacement', on_event: pointer_capture_callback('replacement', false)
			x:              6
			w:              5
			h:              20
			button_behavior: true
		}]
		handle_touch_up(7, 10)
		assert pointer_capture_events == [pointer_capture_expected('save', ElementEvent{ kind: .tap, id: 'card' })]

		// Disabled and removed views are absent from the current hit-target frame.
		reset_pointer_capture_test()
		g_hit_targets = [HitTarget{
			id:             'card'
			identity: 'save', on_event: pointer_capture_callback('save', false)
			w:              40
			h:              20
			button_behavior: true
		}]
		handle_touch_down(10, 10)
		g_hit_targets = []HitTarget{}
		handle_touch_up(10, 10)
		assert pointer_capture_events.len == 0

		// Another element occupying the old rectangle is not the pressed target.
		reset_pointer_capture_test()
		g_hit_targets = [HitTarget{
			id:             'card'
			identity: 'save', on_event: pointer_capture_callback('save', false)
			w:              40
			h:              20
			button_behavior: true
		}]
		handle_touch_down(10, 10)
		g_hit_targets = [HitTarget{
			id:             'replacement'
			identity: 'save', on_event: pointer_capture_callback('save', false)
			w:              40
			h:              20
			button_behavior: true
		}]
		handle_touch_up(10, 10)
		assert pointer_capture_events.len == 0

		// Keeping the view but removing semantic behavior also cancels activation.
		reset_pointer_capture_test()
		g_hit_targets = [HitTarget{
			id:             'card'
			identity: 'save', on_event: pointer_capture_callback('save', false)
			w:              40
			h:              20
			button_behavior: true
		}]
		handle_touch_down(10, 10)
		g_hit_targets = [HitTarget{
			id:        'card'
			identity: 'save', on_event: pointer_capture_callback('save', false)
			w:         40
			h:         20
			clickable: true
		}]
		handle_touch_up(10, 10)
		assert pointer_capture_events.len == 0

		// Anonymous overlaid surfaces use structural identity and attached callbacks.
		reset_pointer_capture_test()
		g_hit_targets = [
			HitTarget{identity: 'lower', on_event: pointer_capture_callback('lower', false), w: 40, h: 20, button_behavior: true},
			HitTarget{identity: 'upper', on_event: pointer_capture_callback('upper', false), w: 40, h: 20, button_behavior: true},
		]
		handle_touch_down(10, 10)
		handle_touch_up(10, 10)
		assert pointer_capture_events == [pointer_capture_expected('upper', ElementEvent{ kind: .tap })]
	}

	fn test_button_behavior_cancels_outside_and_nested_button_wins() {
		reset_pointer_capture_test()
		g_hit_targets = [HitTarget{
			identity: 'card', on_event: pointer_capture_callback('card', false)
			w:              120
			h:              56
			button_behavior: true
		}]
		handle_touch_down(20, 20)
		handle_touch_up(160, 20)
		assert pointer_capture_events.len == 0

		// Children are registered after their parent and reverse hit testing
		// gives a nested control ownership of the tap.
		g_hit_targets = [
			HitTarget{identity: 'card', on_event: pointer_capture_callback('card', false), w: 120, h: 56, button_behavior: true},
			HitTarget{identity: 'child', on_event: pointer_capture_callback('child', false), x: 10, y: 10, w: 40, h: 30},
		]
		handle_touch_down(20, 20)
		handle_touch_up(20, 20)
		assert pointer_capture_events == [pointer_capture_expected('child', ElementEvent{ kind: .tap })]
	}

	fn test_button_behavior_cancels_after_drag_or_focus_loss() {
		reset_pointer_capture_test()
		g_hit_targets = [HitTarget{
			identity: 'card', on_event: pointer_capture_callback('card', false)
			w:              120
			h:              56
			button_behavior: true
		}]
		handle_touch_down(20, 20)
		handle_touch_move(50, 20)
		handle_touch_up(20, 20)
		assert pointer_capture_events.len == 0

		handle_touch_down(20, 20)
		cancel_touch()
		assert pointer_capture_events.len == 0
	}

	fn test_raw_clickable_and_button_behavior_emit_both_contracts() {
		reset_pointer_capture_test()
		g_hit_targets = [HitTarget{
			identity: 'surface', on_event: pointer_capture_callback('surface', false)
			w:              120
			h:              56
			clickable:      true
			button_behavior: true
		}]
		handle_touch_down(20, 20)
		handle_touch_up(20, 20)
		assert pointer_capture_events == [
			pointer_capture_expected('surface', ElementEvent{ kind: .pointer_down, x: 20, y: 20 }),
			pointer_capture_expected('surface', ElementEvent{ kind: .pointer_up, x: 20, y: 20 }),
			pointer_capture_expected('surface', ElementEvent{ kind: .tap }),
		]
	}

	fn test_raw_pointer_up_rebuild_does_not_change_an_already_validated_tap() {
		reset_pointer_capture_test()
		g_hit_targets = [HitTarget{
			id:             'surface'
			identity: 'surface', on_event: pointer_capture_callback('surface', true)
			w:              120
			h:              56
			clickable:      true
			button_behavior: true
		}]
		handle_touch_down(20, 20)
		handle_touch_up(20, 20)
		assert pointer_capture_events == [
			pointer_capture_expected('surface', ElementEvent{ kind: .pointer_down, id: 'surface', x: 20, y: 20 }),
			pointer_capture_expected('surface', ElementEvent{ kind: .pointer_up, id: 'surface', x: 20, y: 20 }),
			pointer_capture_expected('surface', ElementEvent{ kind: .tap, id: 'surface' }),
		]
	}

	fn test_ordinary_controls_cancel_when_kind_or_callback_is_removed_during_press() {
		for kind in [Kind.button, .checkbox, .slider, .switch_control, .toggle_button, .dropdown] {
			for withdraw_callback in [false, true] {
				reset_pointer_capture_test()
				original := HitTarget{
					identity: 'control'
					id: 'control'
					kind: kind
					on_event: pointer_capture_callback('original', false)
					w: 100
					h: 40
					slider: kind == .slider
					slider_frame: rect(0, 0, 100, 40)
					slider_spec: SliderSpec{ min: 0, max: 100 }
					switch_control: kind == .switch_control
					checkbox: kind == .checkbox
					toggle_button: kind == .toggle_button
					dropdown: kind == .dropdown
					options: ['one', 'two']
				}
				g_hit_targets = [original]
				handle_touch_down(20, 20)
				pointer_capture_events = []PointerCaptureRecord{}
				g_hit_targets = if withdraw_callback {
					[HitTarget{ ...original, on_event: ElementCallback(unsafe { nil }) }]
				} else {
					[HitTarget{ identity: 'control', id: 'control', kind: .text_field,
						on_event: pointer_capture_callback('replacement', false), w: 100, h: 40, text_field: true }]
				}
				handle_touch_move(25, 20)
				handle_touch_up(25, 20)
				assert pointer_capture_events.len == 0, '${kind}/${withdraw_callback}'
				assert g_open_dropdown.len == 0
			}
		}
	}

	fn test_long_press_and_swipe_require_the_current_gesture_declaration() {
		reset_pointer_capture_test()
		original := HitTarget{ id: 'gesture', identity: 'gesture', kind: .button,
			on_event: pointer_capture_callback('original', false), w: 200, h: 40,
			long_press: true, swipe_left: true }
		g_hit_targets = [original]
		handle_touch_down(150, 20)
		g_hit_targets = [HitTarget{ ...original, long_press: false, swipe_left: false }]
		g_touch.start_time = renderer_now_ms() - 500
		check_long_press()
		handle_touch_move(20, 20)
		handle_touch_up(20, 20)
		assert pointer_capture_events.len == 0
	}

	fn test_scrollbar_drag_takes_precedence_over_view_capture() {
		reset_pointer_capture_test()
		frame := rect(0, 0, 100, 100)
		register_scroll_view(named_scroll_state_id('pane'), frame, frame, 400, true, true, true, HitTarget{})
		g_hit_targets = [HitTarget{identity: 'view', on_event: pointer_capture_callback('view', false), w: 100, h: 100, draggable: true}]
		bar := scrollbar_geometry(frame, 400, 0, true)
		handle_touch_down(bar.thumb.x + 1, bar.thumb.y + 1)
		assert g_touch.scrollbar_drag
		handle_touch_move(bar.thumb.x + 1, 60)
		handle_touch_up(bar.thumb.x + 1, 60)
		assert pointer_capture_events.len == 0
	}
}
