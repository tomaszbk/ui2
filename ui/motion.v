module ui2

import math
import time

// MotionStyle is a partial presentation: every field it leaves unset keeps the
// value beneath it. Under an element's enter and exit styles that is the
// element's declared presentation; under a timeline keyframe it is the value
// the timeline reached before, or the element's presentation where nothing
// keyed the channel yet. Opacity includes the whole subtree. Translation and
// origins are logical units, rotation is in degrees. Paint channels change the
// element's own box and text color without relayout. box_scale_x and
// box_scale_y size the element's own fill, border and shadow from its top-left
// corner without scaling its content.
pub struct MotionStyle {
pub:
	opacity      ?f64
	translate_x  ?f64
	translate_y  ?f64
	scale_x      ?f64
	scale_y      ?f64
	rotation     ?f64
	origin_x     ?f64
	origin_y     ?f64
	background   ?u32
	border_color ?u32
	text_color   ?u32
	radius       ?f64
	shadow       ?BoxShadow
	box_scale_x  ?f64
	box_scale_y  ?f64
}

// MotionPaint is the part of a box and its text that motion animates.
pub struct MotionPaint {
pub:
	background   u32
	border_color u32
	text_color   u32
	radius       f64
	shadow       BoxShadow
}

// MotionValues is a complete presentation: the values a sample presents.
pub struct MotionValues {
pub:
	opacity     f64 = 1
	transform   VisualTransform
	paint       MotionPaint
	box_scale_x f64 = 1
	box_scale_y f64 = 1
}

// MotionTransition is a duration in seconds and an easing curve: a named
// curve, a custom easing_fn, or a spring, which takes precedence. Opacity,
// scales and colors clamp easing overshoot to stay valid; translation,
// rotation, origins and lengths retain the curve's overshoot.
pub struct MotionTransition {
pub:
	duration  f64            = 0.2
	easing    MotionEasing   = .linear
	easing_fn MotionEasingFn = unsafe { nil }
	spring    ?MotionSpring
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

// MotionSample is what one element presents at one frame. layout_offset is a
// running layout transition's offset from the laid-out frame: x and y move the
// element, width and height resize it (see MotionLayoutMode).
pub struct MotionSample {
pub:
	values        MotionValues
	phase         PresencePhase
	running       bool
	progress      f64
	layout_offset Rect
}

pub struct MotionControllerConfig {
pub:
	initial        MotionValues
	present        bool
	clock          MotionClock = unsafe { nil }
	reduced_motion bool
}

// MotionController owns one presentation transition. It has no event loop and
// performs no tree rebuilds. The host retains exiting content until sample()
// reports absent and requests frames while running is true.
pub struct MotionController {
mut:
	clock          MotionClock = unsafe { nil }
	reduced_motion bool
	current        MotionValues
	start          MotionValues
	target         MotionValues
	transition     MotionTransition
	phase          PresencePhase
	desired        bool
	running        bool
	progress       f64 = 1
	started_at     f64
	last_at        f64
	// serial counts the transitions begun; run_phase is the phase each began in.
	serial    u64
	run_phase PresencePhase
}

// motion_monotonic_seconds is the default clock shared by motion timelines.
pub fn motion_monotonic_seconds() f64 {
	return f64(time.sys_mono_now()) / f64(time.second)
}

// new_motion_controller begins at initial. For an entering element, pass its enter
// values with present: false, then set_present(true, present_values, transition).
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

// over returns base with every channel the style sets replaced.
pub fn (style MotionStyle) over(base MotionValues) MotionValues {
	t := base.transform
	p := base.paint
	return MotionValues{
		opacity:     style.opacity or { base.opacity }
		transform:   VisualTransform{
			translate_x: style.translate_x or { t.translate_x }
			translate_y: style.translate_y or { t.translate_y }
			scale_x:     style.scale_x or { t.scale_x }
			scale_y:     style.scale_y or { t.scale_y }
			rotation:    style.rotation or { t.rotation }
			origin_x:    style.origin_x or { t.origin_x }
			origin_y:    style.origin_y or { t.origin_y }
		}
		paint:       MotionPaint{
			background:   style.background or { p.background }
			border_color: style.border_color or { p.border_color }
			text_color:   style.text_color or { p.text_color }
			radius:       style.radius or { p.radius }
			shadow:       style.shadow or { p.shadow }
		}
		box_scale_x: style.box_scale_x or { base.box_scale_x }
		box_scale_y: style.box_scale_y or { base.box_scale_y }
	}
}

// validate rejects the channels a style sets to invalid values.
pub fn (style MotionStyle) validate() ! {
	style.over(MotionValues{}).validate()!
}

// validate rejects invalid opacity, nonfinite or singular transforms, negative
// radii and blur, and negative box scales.
pub fn (values MotionValues) validate() ! {
	if !finite_number(values.opacity) || values.opacity < 0 || values.opacity > 1 {
		return error('motion opacity must be finite and between 0 and 1')
	}
	values.transform.matrix(Rect{})!
	paint := values.paint
	if !finite_number(paint.radius) || paint.radius < 0 {
		return error('motion corner radius must be finite and nonnegative')
	}
	shadow := paint.shadow
	if !finite_number(shadow.opacity) || shadow.opacity < 0 || shadow.opacity > 1 {
		return error('motion shadow opacity must be finite and between 0 and 1')
	}
	if !finite_number(shadow.blur) || shadow.blur < 0 || !finite_number(shadow.x)
		|| !finite_number(shadow.y) || !finite_number(shadow.spread) {
		return error('motion shadow offsets must be finite and its blur nonnegative')
	}
	if !finite_number(values.box_scale_x) || values.box_scale_x < 0
		|| !finite_number(values.box_scale_y) || values.box_scale_y < 0 {
		return error('motion box scales must be finite and nonnegative')
	}
}

pub fn (transition MotionTransition) validate() ! {
	if !finite_number(transition.duration) || transition.duration < 0 {
		return error('motion duration must be finite and nonnegative')
	}
	if spring := transition.spring {
		spring.validate()!
	}
}

fn (transition MotionTransition) ease(progress f64) f64 {
	if spring := transition.spring {
		return if progress >= 1 { 1.0 } else { spring.position(progress * transition.duration) }
	}
	return motion_ease(transition.easing, transition.easing_fn, progress)
}

// set_present enters or exits toward an explicit presentation target. Reentry
// and retargeting begin at the currently sampled values. Repeating the same
// desired presence and target does not restart the transition.
pub fn (mut controller MotionController) set_present(present bool, target MotionValues, transition MotionTransition) ! {
	controller.set_present_at(present, target, transition, controller.clock())!
}

// set_present_at lets a host synchronize many controllers to one clock sample.
pub fn (mut controller MotionController) set_present_at(present bool, target MotionValues, transition MotionTransition, now f64) ! {
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
	controller.run_phase = controller.phase
	controller.finish_if_immediate()
}

// transition_to animates a mounted element's target presentation, independent
// of enter/exit. Changing a target during entry preserves the entering phase.
pub fn (mut controller MotionController) transition_to(target MotionValues, transition MotionTransition) ! {
	controller.transition_to_at(target, transition, controller.clock())!
}

pub fn (mut controller MotionController) transition_to_at(target MotionValues, transition MotionTransition, now f64) ! {
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
		eased := controller.transition.ease(progress)
		if !finite_number(eased) {
			return error('motion easing must return a finite value')
		}
		values := interpolate_motion_values(controller.start, controller.target, eased)
		values.validate()!
		controller.current = values
		controller.progress = progress
	}
	controller.last_at = now
	return controller.snapshot()
}

// set_reduced_motion immediately finishes active motion. Later targets also
// snap while enabled; disabling it never restarts an already finished transition.
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

// rebase_at continues from values instead of the sampled presentation, then
// transitions back to the current target. A timeline releasing its channels
// hands its last values to the controller this way. Reduced motion, a zero
// duration or an absent element snap instead.
fn (mut controller MotionController) rebase_at(values MotionValues, transition MotionTransition, now f64) ! {
	controller.sample_at(now)!
	if values == controller.current || !controller.desired || controller.reduced_motion
		|| transition.duration <= 0 || controller.phase == .absent {
		return
	}
	values.validate()!
	validate_motion_path(values, controller.target) or { return }
	// A full turn is the same orientation: unwind it instead of spinning back.
	turns := math.round((values.transform.rotation - controller.target.transform.rotation) / 360)
	controller.current = if turns == 0 {
		values
	} else {
		MotionValues{
			...values
			transform: VisualTransform{
				...values.transform
				rotation: values.transform.rotation - turns * 360
			}
		}
	}
	phase := controller.phase
	controller.begin(controller.target, transition, now)
	controller.phase = phase
	controller.run_phase = phase
	controller.finish_if_immediate()
}

// freeze_at stops at values: they become the current presentation and the
// target until the next target arrives. A mounted element settles to present.
fn (mut controller MotionController) freeze_at(values MotionValues, now f64) ! {
	controller.sample_at(now)!
	values.validate()!
	controller.running = false
	controller.current = values
	controller.start = values
	controller.target = values
	if controller.phase != .absent {
		controller.phase = .present
		controller.desired = true
	}
}

// finish_at completes a running transition at once.
fn (mut controller MotionController) finish_at(now f64) ! {
	controller.sample_at(now)!
	if controller.running {
		controller.finish()
	}
}

fn (controller MotionController) snapshot() MotionSample {
	return MotionSample{
		values:   controller.current
		phase:    controller.phase
		running:  controller.running
		progress: controller.progress
	}
}

fn (mut controller MotionController) begin(target MotionValues, transition MotionTransition, now f64) {
	controller.start = controller.current
	controller.target = target
	controller.transition = transition
	controller.started_at = now
	controller.progress = 0
	controller.running = true
	controller.serial++
}

fn (mut controller MotionController) finish_if_immediate() {
	if controller.reduced_motion || controller.transition.duration == 0
		|| controller.start == controller.target {
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

fn validate_motion_path(start MotionValues, target MotionValues) ! {
	if (start.transform.scale_x < 0) != (target.transform.scale_x < 0)
		|| (start.transform.scale_y < 0) != (target.transform.scale_y < 0) {
		return error('motion scales must not cross zero during a transition')
	}
}

fn interpolate_motion_values(start MotionValues, target MotionValues, eased f64) MotionValues {
	bounded := motion_unit(eased)
	return MotionValues{
		opacity:     motion_lerp(start.opacity, target.opacity, bounded)
		transform:   VisualTransform{
			translate_x: motion_lerp(start.transform.translate_x, target.transform.translate_x,
				eased)
			translate_y: motion_lerp(start.transform.translate_y, target.transform.translate_y,
				eased)
			scale_x:     motion_lerp(start.transform.scale_x, target.transform.scale_x, bounded)
			scale_y:     motion_lerp(start.transform.scale_y, target.transform.scale_y, bounded)
			rotation:    motion_lerp(start.transform.rotation, target.transform.rotation, eased)
			origin_x:    motion_lerp(start.transform.origin_x, target.transform.origin_x, eased)
			origin_y:    motion_lerp(start.transform.origin_y, target.transform.origin_y, eased)
		}
		paint:       interpolate_motion_paint(start.paint, target.paint, eased)
		box_scale_x: math.max(0.0, motion_lerp(start.box_scale_x, target.box_scale_x,
			eased))
		box_scale_y: math.max(0.0, motion_lerp(start.box_scale_y, target.box_scale_y,
			eased))
	}
}

fn interpolate_motion_paint(start MotionPaint, target MotionPaint, eased f64) MotionPaint {
	if start == target {
		return target
	}
	bounded := motion_unit(eased)
	return MotionPaint{
		background:   interpolate_color(start.background, target.background, bounded)
		border_color: interpolate_color(start.border_color, target.border_color, bounded)
		text_color:   interpolate_color(start.text_color, target.text_color, bounded)
		radius:       math.max(0.0, motion_lerp(start.radius, target.radius, eased))
		shadow:       BoxShadow{
			color:   interpolate_color(start.shadow.color, target.shadow.color, bounded)
			opacity: motion_lerp(start.shadow.opacity, target.shadow.opacity, bounded)
			blur:    math.max(0.0, motion_lerp(start.shadow.blur, target.shadow.blur, eased))
			x:       motion_lerp(start.shadow.x, target.shadow.x, eased)
			y:       motion_lerp(start.shadow.y, target.shadow.y, eased)
			spread:  motion_lerp(start.shadow.spread, target.shadow.spread, eased)
		}
	}
}
