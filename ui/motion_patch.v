module ui2

// MotionPatch is one sparse piece of a MotionConfig, composed left to right by
// compose_motion, as StylePatch pieces compose by compose_styles. Each
// motion_<name> helper returns one piece, so a VML property such as
// `motion: [fade(0.2), slide_y(12), spring(170, 26)]` lowers to
// `ui2.compose_motion([ui2.motion_fade(0.2), ui2.motion_slide_y(12),
// ui2.motion_spring(170, 26)])`. An absent field keeps the value composed
// before it; enter and exit merge channel by channel.
pub struct MotionPatch {
pub:
	enter            MotionStyle
	exit             MotionStyle
	enter_transition MotionTransitionPatch
	exit_transition  MotionTransitionPatch
	transition       MotionTransitionPatch
	layout           ?MotionLayoutMode
	timeline         ?MotionTimeline
	targets          []MotionTarget
	on_motion        MotionEventFn = unsafe { nil }
	handle           &MotionHandle = unsafe { nil }
	clock            MotionClock   = unsafe { nil }
	reduced_motion   ?bool
}

// MotionTransitionPatch is a sparse MotionTransition.
pub struct MotionTransitionPatch {
pub:
	duration  ?f64
	easing    ?MotionEasing
	easing_fn MotionEasingFn = unsafe { nil }
	spring    ?MotionSpring
}

// compose_motion combines pieces into the configuration a `motion` property
// takes. It starts with no enter or exit effect, so a list without fade, slide,
// scale or rotate pieces only animates what its other pieces name.
pub fn compose_motion(patches []MotionPatch) MotionConfig {
	mut config := MotionConfig{
		enter: MotionStyle{}
		exit:  MotionStyle{}
	}
	for patch in patches {
		config = MotionConfig{
			...config
			enter:            merge_style_fields(config.enter, patch.enter)
			exit:             merge_style_fields(config.exit, patch.exit)
			enter_transition: patch.enter_transition.over(config.enter_transition)
			exit_transition:  patch.exit_transition.over(config.exit_transition)
			transition:       patch.transition.over(config.transition)
			layout:           patch.layout or { config.layout }
			timeline:         patch.timeline or { config.timeline }
			targets:          if patch.targets.len > 0 {
				mut targets := config.targets.clone()
				targets << patch.targets
				targets
			} else {
				config.targets
			}
			on_motion:        if patch.on_motion != unsafe { nil } {
				patch.on_motion
			} else {
				config.on_motion
			}
			handle:           if patch.handle != unsafe { nil } {
				patch.handle
			} else {
				config.handle
			}
			clock:            if patch.clock != unsafe { nil } { patch.clock } else { config.clock }
			reduced_motion:   patch.reduced_motion or { config.reduced_motion }
		}
	}
	return config
}

// over returns base with every field the patch sets replaced. A spring
// without a duration takes the spring's settle time.
pub fn (patch MotionTransitionPatch) over(base MotionTransition) MotionTransition {
	spring := if spring := patch.spring { ?MotionSpring(spring) } else { base.spring }
	mut duration := patch.duration or { base.duration }
	if patch.duration == none && patch.spring != none {
		if value := spring {
			duration = value.settle_time()
		}
	}
	return MotionTransition{
		duration:  duration
		easing:    patch.easing or { base.easing }
		easing_fn: if patch.easing_fn != unsafe { nil } { patch.easing_fn } else { base.easing_fn }
		spring:    spring
	}
}

fn motion_all_transitions(transition MotionTransitionPatch) MotionPatch {
	return MotionPatch{
		enter_transition: transition
		exit_transition:  transition
		transition:       transition
	}
}

// motion_fade fades in on enter and out on exit over duration seconds.
pub fn motion_fade(duration f64) MotionPatch {
	return MotionPatch{
		enter:            MotionStyle{
			opacity: 0
		}
		exit:             MotionStyle{
			opacity: 0
		}
		enter_transition: MotionTransitionPatch{
			duration: duration
		}
		exit_transition:  MotionTransitionPatch{
			duration: duration
		}
	}
}

// motion_slide_x enters from distance logical units along x and exits there.
pub fn motion_slide_x(distance f64) MotionPatch {
	return MotionPatch{
		enter: MotionStyle{
			translate_x: distance
		}
		exit:  MotionStyle{
			translate_x: distance
		}
	}
}

// motion_slide_y enters from distance logical units along y and exits there.
pub fn motion_slide_y(distance f64) MotionPatch {
	return MotionPatch{
		enter: MotionStyle{
			translate_y: distance
		}
		exit:  MotionStyle{
			translate_y: distance
		}
	}
}

// motion_scale enters from scale and exits to it, about the element's origin.
pub fn motion_scale(scale f64) MotionPatch {
	return MotionPatch{
		enter: MotionStyle{
			scale_x: scale
			scale_y: scale
		}
		exit:  MotionStyle{
			scale_x: scale
			scale_y: scale
		}
	}
}

// motion_rotate enters from degrees and exits to them, about the origin.
pub fn motion_rotate(degrees f64) MotionPatch {
	return MotionPatch{
		enter: MotionStyle{
			rotation: degrees
		}
		exit:  MotionStyle{
			rotation: degrees
		}
	}
}

// motion_enter sets the channels the element enters from.
pub fn motion_enter(style MotionStyle) MotionPatch {
	return MotionPatch{
		enter: style
	}
}

// motion_exit sets the channels the element exits to.
pub fn motion_exit(style MotionStyle) MotionPatch {
	return MotionPatch{
		exit: style
	}
}

// motion_duration sets the seconds of entering, exiting and transitions.
pub fn motion_duration(seconds f64) MotionPatch {
	return motion_all_transitions(MotionTransitionPatch{ duration: seconds })
}

// motion_enter_duration sets the seconds of entering.
pub fn motion_enter_duration(seconds f64) MotionPatch {
	return MotionPatch{
		enter_transition: MotionTransitionPatch{
			duration: seconds
		}
	}
}

// motion_exit_duration sets the seconds of exiting.
pub fn motion_exit_duration(seconds f64) MotionPatch {
	return MotionPatch{
		exit_transition: MotionTransitionPatch{
			duration: seconds
		}
	}
}

// motion_transition sets the seconds a declared value or, with motion_layout,
// a laid-out frame takes to change while the element is shown.
pub fn motion_transition(seconds f64) MotionPatch {
	return MotionPatch{
		transition: MotionTransitionPatch{
			duration: seconds
		}
	}
}

// motion_easing sets the curve of entering, exiting and transitions.
pub fn motion_easing(curve MotionEasing) MotionPatch {
	return motion_all_transitions(MotionTransitionPatch{ easing: curve })
}

// motion_spring eases entering, exiting and transitions with a damped spring
// and sets their duration to its settle time. Put a duration piece after it
// to override that.
pub fn motion_spring(stiffness f64, damping f64) MotionPatch {
	return motion_all_transitions(MotionTransitionPatch{
		spring: MotionSpring{
			stiffness: stiffness
			damping:   damping
		}
	})
}

// motion_layout animates changes of the element's laid-out frame.
pub fn motion_layout(mode MotionLayoutMode) MotionPatch {
	return MotionPatch{
		layout: mode
	}
}

// motion_timeline plays timeline over the element while it is mounted.
pub fn motion_timeline(timeline MotionTimeline) MotionPatch {
	return MotionPatch{
		timeline: timeline
	}
}

// motion_target plays timeline on the descendant with the public id.
pub fn motion_target(id string, timeline MotionTimeline) MotionPatch {
	return MotionPatch{
		targets: [MotionTarget{
			id:       id
			timeline: timeline
		}]
	}
}

// motion_reduced shows every motion of the element at its end at once.
pub fn motion_reduced(reduced bool) MotionPatch {
	return MotionPatch{
		reduced_motion: reduced
	}
}

// motion_on hears the element's motion events.
pub fn motion_on(handler MotionEventFn) MotionPatch {
	return MotionPatch{
		on_motion: handler
	}
}

// motion_handle attaches a handle that controls the element's motion.
pub fn motion_handle(handle &MotionHandle) MotionPatch {
	return MotionPatch{
		handle: handle
	}
}

// motion_clock drives the element's motion from clock instead of the
// monotonic system clock.
pub fn motion_clock(clock MotionClock) MotionPatch {
	return MotionPatch{
		clock: clock
	}
}
