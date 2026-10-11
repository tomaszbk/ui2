module ui2

import math
import time

// MotionStyle changes presentation without changing an element's layout.
// Opacity includes the whole subtree. Transform uses logical units and degrees.
pub struct MotionStyle {
pub:
	opacity   f64 = 1
	transform VisualTransform
}

// MotionTransition uses the same easing curves as animation(). Duration is in
// seconds. Opacity and scales clamp easing overshoot to stay valid; translation,
// rotation and origin retain the easing curve's overshoot.
pub struct MotionTransition {
pub:
	duration  f64                   = 0.2
	easing    AnimationTransition   = .linear
	easing_fn AnimationTransitionFn = unsafe { nil }
}

// MotionClock returns finite, monotonic seconds. Supply a controlled clock to
// drive motion deterministically without a timer or sleeping.
pub type MotionClock = fn () f64

pub enum PresencePhase {
	absent
	entering
	present
	exiting
}

pub struct MotionSample {
pub:
	style    MotionStyle
	phase    PresencePhase
	running  bool
	progress f64
}

pub struct MotionControllerConfig {
pub:
	initial        MotionStyle
	present        bool
	clock          MotionClock = unsafe { nil }
	reduced_motion bool
}

// MotionController owns one presentation timeline. It has no event loop and
// performs no tree rebuilds. The host retains exiting content until sample()
// reports absent and requests frames while running is true.
pub struct MotionController {
mut:
	clock          MotionClock = unsafe { nil }
	reduced_motion bool
	current        MotionStyle
	start          MotionStyle
	target         MotionStyle
	transition     MotionTransition
	phase          PresencePhase
	desired        bool
	running        bool
	progress       f64 = 1
	started_at     f64
	last_at        f64
}

// motion_monotonic_seconds is the default clock shared by motion timelines.
pub fn motion_monotonic_seconds() f64 {
	return f64(time.sys_mono_now()) / f64(time.second)
}

// new_motion_controller begins at initial. For an entering element, pass its enter
// style with present: false, then set_present(true, present_style, transition).
pub fn new_motion_controller(config MotionControllerConfig) !MotionController {
	config.initial.validate()!
	clock := if voidptr(config.clock) == unsafe { nil } {
		MotionClock(motion_monotonic_seconds)
	} else {
		config.clock
	}
	now := clock()
	validate_motion_time(now)!
	return MotionController{
		clock:          clock
		reduced_motion: config.reduced_motion
		current:        config.initial
		start:          config.initial
		target:         config.initial
		phase:          if config.present { .present } else { .absent }
		desired:        config.present
		started_at:     now
		last_at:        now
	}
}

// validate rejects invalid opacity and nonfinite or singular transforms.
pub fn (style MotionStyle) validate() ! {
	if !finite_number(style.opacity) || style.opacity < 0 || style.opacity > 1 {
		return error('motion opacity must be finite and between 0 and 1')
	}
	style.transform.matrix(Rect{})!
}

pub fn (transition MotionTransition) validate() ! {
	if !finite_number(transition.duration) || transition.duration < 0 {
		return error('motion duration must be finite and nonnegative')
	}
}

// set_present enters or exits toward an explicit presentation target. Reentry
// and retargeting begin at the currently sampled style. Repeating the same
// desired presence and target does not restart the timeline.
pub fn (mut controller MotionController) set_present(present bool, target MotionStyle, transition MotionTransition) ! {
	controller.set_present_at(present, target, transition, controller.clock())!
}

// set_present_at lets a host synchronize many controllers to one clock sample.
pub fn (mut controller MotionController) set_present_at(present bool, target MotionStyle, transition MotionTransition, now f64) ! {
	target.validate()!
	transition.validate()!
	controller.sample_at(now)!
	if present == controller.desired && target == controller.target {
		return
	}
	// An absent node has no exit presentation to retain.
	if !present && controller.phase == .absent {
		controller.current = target
		controller.start = target
		controller.target = target
		return
	}
	if !controller.reduced_motion && transition.duration > 0 {
		if !finite_number(now + transition.duration) {
			return error('motion deadline must be finite')
		}
		validate_motion_path(controller.current, target)!
	}
	previous_phase := controller.phase
	controller.desired = present
	controller.begin(target, transition, now)
	controller.phase = if present {
		if previous_phase in [.absent, .exiting, .entering] { .entering } else { .present }
	} else {
		.exiting
	}
	controller.finish_if_immediate()
}

// transition_to animates a mounted element's target presentation, independent
// of enter/exit. Changing a target during entry preserves the entering phase.
pub fn (mut controller MotionController) transition_to(target MotionStyle, transition MotionTransition) ! {
	controller.transition_to_at(target, transition, controller.clock())!
}

pub fn (mut controller MotionController) transition_to_at(target MotionStyle, transition MotionTransition, now f64) ! {
	if !controller.desired {
		return error('motion target transitions require a present element')
	}
	controller.set_present_at(true, target, transition, now)!
}

pub fn (mut controller MotionController) sample() !MotionSample {
	return controller.sample_at(controller.clock())
}

// sample_at updates only presentation. Completion sets the exact target and
// terminal phase once, including after a suspension past the deadline.
pub fn (mut controller MotionController) sample_at(now f64) !MotionSample {
	validate_motion_time(now)!
	if now < controller.last_at {
		return error('motion clock must be monotonic')
	}
	if !controller.running {
		controller.last_at = now
		return controller.snapshot()
	}
	progress := math.min(1.0, (now - controller.started_at) / controller.transition.duration)
	if now >= controller.started_at + controller.transition.duration || progress >= 1 {
		controller.finish()
	} else {
		eased := apply_animation_transition(Animation{
			transition:    controller.transition.easing
			transition_fn: controller.transition.easing_fn
		}, progress)
		if !finite_number(eased) {
			return error('motion easing must return a finite value')
		}
		style := interpolate_motion_style(controller.start, controller.target, eased)
		style.validate()!
		controller.current = style
		controller.progress = progress
	}
	controller.last_at = now
	return controller.snapshot()
}

// set_reduced_motion immediately finishes active motion. Later targets also
// snap while enabled; disabling it never restarts an already finished timeline.
pub fn (mut controller MotionController) set_reduced_motion(reduced bool) {
	controller.reduced_motion = reduced
	if reduced && controller.running {
		controller.finish()
	}
}

// cancel freezes the currently sampled presentation and cancels removal. A
// mounted element settles to present; an absent element remains absent.
pub fn (mut controller MotionController) cancel() ! {
	controller.cancel_at(controller.clock())!
}

pub fn (mut controller MotionController) cancel_at(now f64) ! {
	controller.sample_at(now)!
	controller.running = false
	controller.start = controller.current
	controller.target = controller.current
	if controller.phase != .absent {
		controller.phase = .present
		controller.desired = true
	}
}

fn (controller MotionController) snapshot() MotionSample {
	return MotionSample{
		style:    controller.current
		phase:    controller.phase
		running:  controller.running
		progress: controller.progress
	}
}

fn (mut controller MotionController) begin(target MotionStyle, transition MotionTransition, now f64) {
	controller.start = controller.current
	controller.target = target
	controller.transition = transition
	controller.started_at = now
	controller.progress = 0
	controller.running = true
}

fn (mut controller MotionController) finish_if_immediate() {
	if controller.reduced_motion || controller.transition.duration == 0 || controller.start == controller.target {
		controller.finish()
	}
}

fn (mut controller MotionController) finish() {
	controller.current = controller.target
	controller.progress = 1
	controller.running = false
	controller.phase = if controller.desired { .present } else { .absent }
}

fn validate_motion_time(now f64) ! {
	if !finite_number(now) {
		return error('motion clock must return finite seconds')
	}
}

fn validate_motion_path(start MotionStyle, target MotionStyle) ! {
	if (start.transform.scale_x < 0) != (target.transform.scale_x < 0)
		|| (start.transform.scale_y < 0) != (target.transform.scale_y < 0) {
		return error('motion scales must not cross zero during a transition')
	}
}

fn interpolate_motion_style(start MotionStyle, target MotionStyle, eased f64) MotionStyle {
	bounded := math.max(0.0, math.min(1.0, eased))
	return MotionStyle{
		opacity:   motion_lerp(start.opacity, target.opacity, bounded)
		transform: VisualTransform{
			translate_x: motion_lerp(start.transform.translate_x, target.transform.translate_x, eased)
			translate_y: motion_lerp(start.transform.translate_y, target.transform.translate_y, eased)
			scale_x:     motion_lerp(start.transform.scale_x, target.transform.scale_x, bounded)
			scale_y:     motion_lerp(start.transform.scale_y, target.transform.scale_y, bounded)
			rotation:    motion_lerp(start.transform.rotation, target.transform.rotation, eased)
			origin_x:    motion_lerp(start.transform.origin_x, target.transform.origin_x, eased)
			origin_y:    motion_lerp(start.transform.origin_y, target.transform.origin_y, eased)
		}
	}
}

fn motion_lerp(start f64, target f64, progress f64) f64 {
	return start * (1 - progress) + target * progress
}
