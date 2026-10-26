module ui2

// Motion parts: Timeline and its Keyframe rows. A Timeline under an element
// plays on that element, or on the descendants its keyframes name by target:
//
//     View(id: card) {
//         Image(id: logo, ...)
//         Timeline(duration: 1.2, repeat: true) {
//             Keyframe(target: "logo", at: 0.5, opacity: 0.4, scale: 1.1, easing: in_out_sine)
//             Keyframe(target: "logo", at: 1, opacity: 1, scale: 1)
//         }
//     }
//
// A keyframe without a target animates the element holding the Timeline.

// VmlKeyframe is a Keyframe part. target is the public id it animates, empty
// for the element that holds its Timeline.
pub struct VmlKeyframe {
pub:
	target   string
	keyframe MotionKeyframe
}

// VmlTimeline is a Timeline part: one timeline for each element it animates.
// An empty id is the element that holds it.
pub struct VmlTimeline {
pub:
	targets []MotionTarget
}

// KeyframeProps is one keyframe: the channels it sets at `at`, a fraction of
// its Timeline's duration. scale sets scale_x and scale_y together. easing
// shapes the segment that ends here.
pub struct KeyframeProps {
pub mut:
	target       string
	at           f64
	opacity      ?f64
	translate_x  ?f64
	translate_y  ?f64
	scale        ?f64
	scale_x      ?f64
	scale_y      ?f64
	rotation     ?f64
	origin_x     ?f64
	origin_y     ?f64
	background   ?u32
	border_color ?u32
	text_color   ?u32
	radius       ?f64
	box_scale_x  ?f64
	box_scale_y  ?f64
	easing       MotionEasing
}

pub fn (p KeyframeProps) style() MotionStyle {
	return MotionStyle{
		opacity:      p.opacity
		translate_x:  p.translate_x
		translate_y:  p.translate_y
		scale_x:      if value := p.scale_x { ?f64(value) } else { p.scale }
		scale_y:      if value := p.scale_y { ?f64(value) } else { p.scale }
		rotation:     p.rotation
		origin_x:     p.origin_x
		origin_y:     p.origin_y
		background:   p.background
		border_color: p.border_color
		text_color:   p.text_color
		radius:       p.radius
		box_scale_x:  p.box_scale_x
		box_scale_y:  p.box_scale_y
	}
}

pub fn (p KeyframeProps) part(ctx VmlBuildContext) !VmlPart {
	keyframe := MotionKeyframe{
		at:     p.at
		style:  p.style()
		easing: p.easing
	}
	MotionTimeline{
		duration:  1
		keyframes: [keyframe]
	}.validate()!
	return VmlKeyframe{
		target:   ctx.resolve_id(p.target)
		keyframe: keyframe
	}
}

// TimelineProps plays its Keyframe rows over duration seconds. repeat loops
// it while the element is mounted; otherwise it plays `times` times.
// alternate plays every other cycle backwards, step samples it every step
// seconds and hold keeps its final values once it ends.
pub struct TimelineProps {
pub mut:
	duration  f64 = 1
	delay     f64
	repeat    bool
	times     int = 1
	alternate bool
	step      f64
	hold      bool
}

pub fn (p TimelineProps) part(ctx VmlBuildContext) !VmlPart {
	if !p.repeat && p.times < 1 {
		return error('a Timeline plays at least once: `times` must be positive')
	}
	mut order := []string{}
	mut groups := map[string][]MotionKeyframe{}
	for part in ctx.parts {
		if part is VmlKeyframe {
			if part.target !in groups {
				order << part.target
			}
			groups[part.target] << part.keyframe
		}
	}
	mut targets := []MotionTarget{cap: order.len}
	for target in order {
		timeline := MotionTimeline{
			duration:  p.duration
			keyframes: groups[target]
			delay:     p.delay
			repeat:    if p.repeat { motion_forever } else { p.times - 1 }
			alternate: p.alternate
			step:      p.step
			hold:      p.hold
		}
		timeline.validate()!
		targets << MotionTarget{
			id:       target
			timeline: timeline
		}
	}
	return VmlTimeline{
		targets: targets
	}
}

// vml_project_motion is the motion of an element built with its Timeline
// parts: a timeline on the element itself plays with the configured one, and
// timelines on descendants become its targets.
fn vml_project_motion(authored ?MotionConfig, el Element, ctx VmlBuildContext) ?MotionConfig {
	declared := if config := authored { ?MotionConfig(config) } else { el.motion }
	mut own := []MotionTimeline{}
	mut targets := []MotionTarget{}
	for part in ctx.parts {
		if part is VmlTimeline {
			for target in part.targets {
				if target.id.len == 0 || target.id == el.id {
					own << target.timeline
				} else {
					targets << target
				}
			}
		}
	}
	if own.len == 0 && targets.len == 0 {
		return declared
	}
	base := declared or { compose_motion([]) }
	if !base.timeline.is_empty() {
		own.prepend(base.timeline)
	}
	mut all_targets := base.targets.clone()
	all_targets << targets
	return MotionConfig{
		...base
		timeline: match own.len {
			0 { MotionTimeline{} }
			1 { own[0] }
			else { motion_parallel(...own) }
		}
		targets:  all_targets
	}
}
