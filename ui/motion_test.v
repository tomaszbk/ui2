@[has_globals]
module ui2

import math

fn test_native_profile_diagnoses_motion_and_opacity() {
	if !backend_supports_motion {
		for element in [Element{ opacity: 0.5 }, Element{ motion: MotionConfig{} }] {
			if _ := validate_element_tree(element) {
				assert false, 'unsupported motion must be diagnosed'
			} else {
				assert err.msg().contains('opacity and motion require the desktop custom renderer')
			}
		}
	}
}

fn test_motion_rejects_overflowing_deadlines_without_starting_a_timeline() ! {
	mut controller := new_motion_controller(MotionControllerConfig{
		initial: MotionValues{ opacity: 0 }
		clock:   fn () f64 { return 1e308 }
	})!
	controller.set_present(true, MotionValues{}, MotionTransition{ duration: 1e308 }) or {
		assert err.msg().contains('deadline must be finite')
		assert controller.sample()! == MotionSample{ values: MotionValues{ opacity: 0 }, phase: .absent, progress: 1 }
		return
	}
	assert false, 'unrepresentable deadlines must reject'
}

__global motion_test_now = f64(0)

fn motion_test_clock() f64 {
	return motion_test_now
}

fn motion_test_controller(initial MotionValues, present bool) MotionController {
	motion_test_now = 0
	return new_motion_controller(MotionControllerConfig{
		initial: initial
		present: present
		clock:   motion_test_clock
	}) or { panic(err) }
}

fn test_motion_fractional_deadline_finishes_without_an_extra_frame() ! {
	motion_test_now = 10
	mut controller := new_motion_controller(MotionControllerConfig{
		initial: MotionValues{ opacity: 0 }
		clock:   motion_test_clock
	})!
	controller.set_present(true, MotionValues{}, MotionTransition{ duration: 0.2 })!
	motion_test_now = 10.2
	sample := controller.sample()!
	assert sample.phase == .present && !sample.running && sample.progress == 1
	assert sample.values == MotionValues{}
}

fn test_motion_injected_clock_fade_transform_and_exact_completion() {
	enter := MotionValues{
		opacity:   0
		transform: VisualTransform{
			translate_x: -20
			translate_y: 10
			scale_x:     0.5
			scale_y:     0.75
			rotation:    -30
			origin_x:    40
			origin_y:    20
		}
	}
	target := MotionValues{
		transform: VisualTransform{
			translate_x: 20
			translate_y: -10
			scale_x:     1.5
			scale_y:     1.25
			rotation:    30
			origin_x:    60
			origin_y:    40
		}
	}
	mut controller := motion_test_controller(enter, false)
	controller.set_present(true, target, MotionTransition{ duration: 2 })!
	begin := controller.sample()!
	assert begin.phase == .entering
	assert begin.running
	assert begin.progress == 0
	assert begin.values == enter
	motion_test_now = 1
	half := controller.sample()!
	assert half.progress == 0.5
	assert half.values.opacity == 0.5
	assert half.values.transform == VisualTransform{
		scale_x:  1
		scale_y:  1
		origin_x: 50
		origin_y: 30
	}
	assert half.phase == .entering
	motion_test_now = 2
	end := controller.sample()!
	assert !end.running
	assert end.phase == .present
	assert end.progress == 1
	assert end.values == target
	motion_test_now = 100
	assert controller.sample()! == end
}

fn test_motion_exit_remains_mounted_until_terminal_sample_after_suspension() {
	mut controller := motion_test_controller(MotionValues{}, true)
	controller.set_present_at(false, MotionValues{ opacity: 0 }, MotionTransition{
		duration: 1
	}, 10)!
	exiting := controller.sample_at(10.5)!
	assert exiting.phase == .exiting
	assert exiting.running
	assert exiting.values.opacity == 0.5
	end := controller.sample_at(1_000)!
	assert end.phase == .absent
	assert !end.running
	assert end.values.opacity == 0
	assert end.progress == 1
	assert controller.sample_at(1_001)! == end
}

fn test_motion_reentry_and_retarget_begin_at_current_style_without_restarting_unchanged_targets() {
	mut controller := motion_test_controller(MotionValues{}, true)
	transition := MotionTransition{ duration: 2 }
	controller.set_present_at(false, MotionValues{
		opacity:   0
		transform: VisualTransform{ translate_x: 100 }
	}, transition, 0)!
	controller.set_present_at(true, MotionValues{}, transition, 1)!
	reentered := controller.sample_at(1)!
	assert reentered.phase == .entering
	assert reentered.values.opacity == 0.5
	assert reentered.values.transform.translate_x == 50
	assert reentered.progress == 0
	controller.set_present_at(true, MotionValues{}, transition, 1.5)!
	unchanged := controller.sample_at(2)!
	assert unchanged.progress == 0.5
	assert unchanged.values.opacity == 0.75
	assert unchanged.values.transform.translate_x == 25
	controller.transition_to_at(MotionValues{
		transform: VisualTransform{ translate_x: -75 }
	}, transition, 2)!
	redirected := controller.sample_at(3)!
	assert redirected.phase == .entering
	assert redirected.values.opacity == 0.875
	assert redirected.values.transform.translate_x == -25
	assert controller.sample_at(4)!.phase == .present
	controller.transition_to_at(MotionValues{
		transform: VisualTransform{ rotation: 90 }
	}, transition, 4)!
	assert controller.sample_at(5)!.phase == .present
	assert controller.sample_at(6)!.values.transform.rotation == 90
}

fn test_motion_reduced_motion_snaps_active_and_future_transitions() {
	mut controller := motion_test_controller(MotionValues{ opacity: 0 }, false)
	controller.set_present_at(true, MotionValues{}, MotionTransition{ duration: 5 }, 0)!
	controller.sample_at(1)!
	controller.set_reduced_motion(true)
	entered := controller.sample_at(1)!
	assert entered.phase == .present
	assert entered.values == MotionValues{}
	assert !entered.running
	controller.set_present_at(false, MotionValues{ opacity: 0 }, MotionTransition{
		duration: 5
	}, 1)!
	exited := controller.sample_at(1)!
	assert exited.phase == .absent
	assert exited.values.opacity == 0
	assert !exited.running
	controller.set_reduced_motion(false)
	assert controller.sample_at(2)! == exited
	controller.set_present_at(true, MotionValues{}, MotionTransition{ duration: 0 }, 2)!
	assert controller.sample_at(2)!.phase == .present
	assert !controller.sample_at(2)!.running
}

fn test_motion_initial_reduced_preference_and_unchanged_style_need_no_frames() {
	motion_test_now = 0
	mut controller := new_motion_controller(MotionControllerConfig{
		initial:        MotionValues{ opacity: 0 }
		clock:          motion_test_clock
		reduced_motion: true
	})!
	controller.set_present(true, MotionValues{}, MotionTransition{ duration: 10 })!
	assert !controller.sample()!.running
	controller.set_reduced_motion(false)
	controller.set_present(false, MotionValues{}, MotionTransition{ duration: 10 })!
	assert controller.sample()!.phase == .absent
	assert !controller.sample()!.running
}

fn test_motion_easing_curves_and_custom_callback() {
	mut controller := motion_test_controller(MotionValues{ opacity: 0 }, false)
	controller.set_present_at(true, MotionValues{}, MotionTransition{
		duration: 1
		easing:   .in_quad
	}, 0)!
	assert controller.sample_at(0.5)!.values.opacity == 0.25
	controller.sample_at(1)!
	controller.transition_to_at(MotionValues{ opacity: 0 }, MotionTransition{
		duration:  1
		easing_fn: fn (progress f64) f64 {
			return progress * progress * progress
		}
	}, 1)!
	assert controller.sample_at(1.5)!.values.opacity == 0.875
	assert controller.sample_at(2)!.values.opacity == 0
}

fn test_motion_overshoot_is_preserved_for_translation_and_bounded_for_opacity_and_scale() {
	mut controller := motion_test_controller(MotionValues{}, true)
	controller.transition_to_at(MotionValues{
		opacity:   0
		transform: VisualTransform{ translate_x: 100, scale_x: 0.1, rotation: 90 }
	}, MotionTransition{ duration: 1, easing: .out_back }, 0)!
	sample := controller.sample_at(0.5)!
	assert sample.values.transform.translate_x > 100
	assert sample.values.transform.rotation > 90
	assert sample.values.opacity == 0
	assert sample.values.transform.scale_x == 0.1
	sample.values.validate()!
	assert controller.sample_at(1)!.values.transform.translate_x == 100
}

fn test_motion_cancel_freezes_current_values_and_prevents_exit() {
	mut controller := motion_test_controller(MotionValues{}, true)
	controller.set_present_at(false, MotionValues{ opacity: 0 }, MotionTransition{
		duration: 2
	}, 0)!
	controller.cancel_at(1)!
	frozen := controller.sample_at(1)!
	assert frozen.values.opacity == 0.5
	assert frozen.phase == .present
	assert !frozen.running
	assert controller.sample_at(100)! == frozen
	controller.set_present_at(false, MotionValues{ opacity: 0 }, MotionTransition{
		duration: 1
	}, 100)!
	assert controller.sample_at(101)!.phase == .absent
	controller.cancel_at(102)!
	assert controller.sample_at(102)!.phase == .absent
}

fn test_motion_invalid_style_duration_and_clock_values_reject() {
	for style in [MotionValues{ opacity: -0.1 }, MotionValues{ opacity: 1.1 },
		MotionValues{ opacity: math.nan() }, MotionValues{
			transform: VisualTransform{ scale_x: 0 }
		}, MotionValues{ transform: VisualTransform{ translate_x: math.inf(1) } }] {
		if _ := new_motion_controller(MotionControllerConfig{ initial: style }) {
			assert false, 'invalid initial style must fail'
		}
	}
	mut controller := motion_test_controller(MotionValues{}, true)
	for duration in [-1.0, math.nan(), math.inf(1)] {
		if _ := controller.transition_to_at(MotionValues{ opacity: 0 }, MotionTransition{
			duration: duration
		}, 0) {
			assert false, 'invalid duration must fail'
		}
	}
	for now in [math.nan(), math.inf(1), -1.0] {
		if _ := controller.sample_at(now) {
			assert false, 'invalid or backward time must fail'
		}
	}
	assert controller.sample_at(0)!.values == MotionValues{}
	controller.sample_at(10)!
	if _ := controller.sample_at(9) {
		assert false, 'clock rewind must fail'
	}
	assert controller.sample_at(10)!.values == MotionValues{}
	motion_test_now = math.nan()
	if _ := new_motion_controller(MotionControllerConfig{ clock: motion_test_clock }) {
		assert false, 'invalid clock must fail at construction'
	}
}

fn test_motion_scale_sign_crossing_rejects_but_reflection_and_snapping_are_valid() {
	mut controller := motion_test_controller(MotionValues{}, true)
	reflected := MotionValues{ transform: VisualTransform{ scale_x: -1 } }
	if _ := controller.transition_to_at(reflected, MotionTransition{ duration: 1 }, 0) {
		assert false, 'animated scale cannot cross zero'
	}
	assert controller.sample_at(0)!.values == MotionValues{}
	controller.transition_to_at(reflected, MotionTransition{ duration: 0 }, 0)!
	controller.transition_to_at(MotionValues{ transform: VisualTransform{ scale_x: -2 } },
		MotionTransition{ duration: 1 }, 0)!
	assert controller.sample_at(0.5)!.values.transform.scale_x == -1.5
	controller.set_reduced_motion(true)
	controller.transition_to_at(MotionValues{}, MotionTransition{ duration: 1 }, 0.5)!
	assert controller.sample_at(0.5)!.values == MotionValues{}
}

fn test_motion_invalid_easing_does_not_corrupt_state_and_completion_is_exact() {
	mut controller := motion_test_controller(MotionValues{ opacity: 0 }, false)
	controller.set_present_at(true, MotionValues{}, MotionTransition{
		duration:  1
		easing_fn: fn (_ f64) f64 {
			return math.nan()
		}
	}, 0)!
	if _ := controller.sample_at(0.5) {
		assert false, 'nonfinite easing must fail'
	}
	// The terminal sample bypasses the curve and applies exactly the target.
	end := controller.sample_at(1)!
	assert end.values == MotionValues{}
	assert end.phase == .present
	assert !end.running
}

fn test_motion_absent_target_transition_rejects() {
	mut controller := motion_test_controller(MotionValues{ opacity: 0 }, false)
	if _ := controller.transition_to_at(MotionValues{}, MotionTransition{}, 0) {
		assert false, 'absent property motion has no retained presentation'
	}
	assert controller.sample_at(0)!.phase == .absent
}
