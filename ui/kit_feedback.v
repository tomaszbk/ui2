module ui2

import math

// The kit's feedback components: Progress and ProgressCircle, the loading
// Spinner, Skeleton and Shimmer placeholders, and Clipboard. Their motion is
// a looping timeline built once per build (kit_logic_display.v); reduced
// motion plays none, and each shows a still, complete presentation instead.

// ── Progress ────────────────────────────────────────────────────────

// ProgressProps is the `Progress` tag: a bar filled to value / max, in the
// tone's color over the track. `loading` sweeps an indeterminate segment
// along it instead; under reduced motion that is a full bar.
pub struct ProgressProps {
	CommonProps
pub mut:
	value   f64
	max     f64         = 100
	size    ControlSize = .medium
	tone    Tone        = .primary
	loading bool
}

pub fn (p ProgressProps) vml_structure() VmlStructure {
	return .generated
}

pub fn (p ProgressProps) vml_themed() {}

pub fn (p ProgressProps) validate() ! {
	p.CommonProps.validate()!
	kit_validate_progress('Progress', p.value, p.max)!
}

pub fn (p ProgressProps) build(ctx VmlBuildContext) !Element {
	t := ctx.tokens()
	height := p.height or { linear_progress_thickness(p.size) }
	color := kit_progress_color(t, p.tone)
	radius := height / 2
	frame := rect(ctx.frame.x, ctx.frame.y, ctx.frame.width, height)
	fill := view(ctx.part_id('fill'), Rect{}, BoxStyle{
		bg:     color
		radius: radius
	}, [])
	track := BoxStyle{
		bg:     t.track
		radius: radius
	}
	if p.loading {
		left, right := linear_progress_loading_keys()
		// The fill shows up to the segment's right edge and the mask, in the
		// track color, hides it up to the left edge.
		mask := Element{
			...view(ctx.part_id('mask'), Rect{}, track, [])
			opacity: 0
		}
		root := stack_with_rules(StackConfig{
			id:      ctx.id
			frame:   frame
			box:     track
			align_x: .stretch
			align_y: .stretch
		}, [
			with_motion(fill, motion_compose(motion_timeline(feedback_scale_loop(kit_progress_period,
				right)))),
			with_motion(mask, motion_compose(motion_timeline(feedback_scale_loop(kit_progress_period,
				left)))),
		], [StackRule{}, StackRule{}])!
		return vml_handled(Element{
			...root
			accessibility_role:  'progressbar'
			accessibility_label: 'Loading'
		}, ctx, p.element_callback())
	}
	percent := progress_percent(p.value / p.max * 100)
	fraction := percent / 100
	root := flex_with_rules(FlexConfig{
		id:          ctx.id
		frame:       frame
		orientation: .horizontal
		box:         track
	}, [
		with_motion(fill, motion_compose(motion_layout(.box), motion_transition(0.3), motion_easing(.out_cubic))),
		view(ctx.part_id('rest'), Rect{}, BoxStyle{ transparent: true }, []),
	], [FlexRule{
		grow: fraction
	}, FlexRule{
		grow: 1 - fraction
	}])!
	return vml_handled(Element{
		...root
		accessibility_role:  'progressbar'
		accessibility_value: progress_value_text(percent)
	}, ctx, p.element_callback())
}

// kit_progress_period is how long one sweep of an indeterminate indicator
// takes, in seconds.
const kit_progress_period = 2.0

// kit_progress_color is the color of a progress value in a tone. Neutral is
// the secondary text color, which reads on the track.
fn kit_progress_color(t KitTokens, tone Tone) u32 {
	if tone == .neutral {
		return t.muted
	}
	color, _ := t.tone_colors(tone)
	return color
}

fn kit_validate_progress(tag string, value f64, max f64) ! {
	if !math.is_finite(max) || max <= 0 {
		return error('${tag} `max` must be finite and positive')
	}
	if math.is_inf(value, 0) {
		return error('${tag} `value` must be finite')
	}
}

// ── ProgressCircle ──────────────────────────────────────────────────

// ProgressCircleProps is the `ProgressCircle` tag: a ring filled clockwise
// from twelve o'clock to value / max. `loading` turns a quarter arc around
// it instead. An authored width or height sets the diameter.
pub struct ProgressCircleProps {
	CommonProps
pub mut:
	value   f64
	max     f64         = 100
	size    ControlSize = .medium
	tone    Tone        = .primary
	loading bool
}

pub fn (p ProgressCircleProps) vml_structure() VmlStructure {
	return .generated
}

pub fn (p ProgressCircleProps) vml_themed() {}

pub fn (p ProgressCircleProps) validate() ! {
	p.CommonProps.validate()!
	kit_validate_progress('ProgressCircle', p.value, p.max)!
}

pub fn (p ProgressCircleProps) build(ctx VmlBuildContext) !Element {
	t := ctx.tokens()
	preset := progress_circle_diameter(p.size)
	side := math.min(p.width or { preset }, p.height or { preset })
	stroke := progress_circle_thickness(side)
	radius := math.max(0.0, (side - stroke) / 2)
	percent := progress_percent(p.value / p.max * 100)
	sweep := if p.loading { 0.25 } else { percent / 100 }
	mut shapes := []VectorShape{cap: 2}
	shapes << prepare_vector_shape(kit_arc_path(side / 2, side / 2, radius, 0, 1), VectorStyle{
		stroke:       t.track
		stroke_width: stroke
	})!
	if sweep > 0 {
		shapes << prepare_vector_shape(kit_arc_path(side / 2, side / 2, radius, 0, sweep),
			VectorStyle{
				stroke:       kit_progress_color(t, p.tone)
				stroke_width: stroke
				cap:          .round
			})!
	}
	canvas := vector_canvas(
		id:     ctx.id
		frame:  rect(ctx.frame.x, ctx.frame.y, side, side)
		shapes: shapes
	)!
	ring := Element{
		...canvas
		origin_x:            side / 2
		origin_y:            side / 2
		accessibility_role:  'progressbar'
		accessibility_label: if p.loading { 'Loading' } else { '' }
		accessibility_value: if p.loading { '' } else { progress_value_text(percent) }
	}
	if !p.loading {
		return vml_handled(ring, ctx, p.element_callback())
	}
	turn := motion_keyframes(1, MotionKeyframe{
		at:    0
		style: MotionStyle{
			rotation: 0
		}
	}, MotionKeyframe{
		at:    1
		style: MotionStyle{
			rotation: 360
		}
	}).looped()
	return vml_handled(with_motion(ring, motion_compose(motion_timeline(turn))), ctx,
		p.element_callback())
}

// ── Spinner ─────────────────────────────────────────────────────────

// SpinnerProps is the `Spinner` tag: a turning three-quarter ring, in the
// secondary text color unless `color` is set. Reduced motion stills it.
pub struct SpinnerProps {
	CommonProps
pub mut:
	size  ControlSize = .medium
	color ?u32
}

pub fn (p SpinnerProps) vml_structure() VmlStructure {
	return .generated
}

pub fn (p SpinnerProps) vml_themed() {}

pub fn (p SpinnerProps) build(ctx VmlBuildContext) !Element {
	side := loading_spinner_diameter(p.size)
	spinner := kit_spinner_element(ctx.id, side, p.color or { ctx.tokens().muted })
	return vml_handled(Element{
		...spinner
		frame: rect(ctx.frame.x, ctx.frame.y, side, side)
	}, ctx, p.element_callback())
}

// ── Skeleton ────────────────────────────────────────────────────────

// SkeletonProps is the `Skeleton` tag: a pulsing placeholder box, 16 units
// tall and as wide as its parent gives it, or a 40-unit circle with
// `circle`. An authored width or height sets its size.
pub struct SkeletonProps {
	CommonProps
pub mut:
	circle bool
}

pub fn (p SkeletonProps) vml_themed() {}

pub fn (p SkeletonProps) build(ctx VmlBuildContext) !Element {
	t := ctx.tokens()
	height := p.height or { if p.circle { 40.0 } else { 16.0 } }
	width := p.width or { if p.circle { height } else { ctx.frame.width } }
	el := view(ctx.id, rect(ctx.frame.x, ctx.frame.y, width, height), BoxStyle{
		bg:     t.track
		radius: if p.circle { height / 2 } else { t.radius_medium }
	}, [])
	return vml_handled(with_motion(Element{
		...el
		accessibility_role:  'progressbar'
		accessibility_label: 'Loading'
	}, motion_compose(motion_timeline(feedback_pulse_loop(2, 0.5)))), ctx, p.element_callback())
}

// ── Shimmer ─────────────────────────────────────────────────────────

// ShimmerProps is the `Shimmer` tag: a placeholder paragraph of `lines`
// lines, the last one shorter, with a light band sweeping across each.
// `spread` is the band's half-width as a fraction of a line (GPUI's rules,
// shimmer_half_width); `reverse` sweeps right to left.
pub struct ShimmerProps {
	CommonProps
pub mut:
	lines   int = 3
	spread  f64 = 0.3
	reverse bool
}

pub fn (p ShimmerProps) vml_structure() VmlStructure {
	return .generated
}

pub fn (p ShimmerProps) vml_themed() {}

pub fn (p ShimmerProps) validate() ! {
	p.CommonProps.validate()!
	if p.lines < 1 || p.lines > 32 {
		return error('Shimmer `lines` must be between 1 and 32')
	}
}

pub fn (p ShimmerProps) build(ctx VmlBuildContext) !Element {
	t := ctx.tokens()
	height := t.font_caption
	left, right := shimmer_band_keys(p.spread, p.reverse)
	// Every line plays the same two loops: the band shows up to its right
	// edge and a cover, in the line's color, hides it up to its left edge.
	band := motion_compose(motion_timeline(feedback_scale_loop(kit_progress_period * 0.8,
		right)))
	cover := motion_compose(motion_timeline(feedback_scale_loop(kit_progress_period * 0.8,
		left)))
	line_box := BoxStyle{
		bg:     t.track
		radius: height / 2
	}
	band_box := BoxStyle{
		bg:     kit_mix(t.track, t.surface, 0.7)
		radius: height / 2
	}
	mut lines := []Element{cap: p.lines}
	for index in 0 .. p.lines {
		line := stack_with_rules(StackConfig{
			id:      ctx.part_id('line_${index}')
			frame:   rect(0, 0, 0, height)
			box:     line_box
			align_x: .stretch
			align_y: .stretch
		}, [
			with_motion(Element{
				...view('', Rect{}, band_box, [])
				key:     'band'
				opacity: 0
			}, band),
			with_motion(Element{
				...view('', Rect{}, line_box, [])
				key:     'cover'
				opacity: 0
			}, cover),
		], [StackRule{}, StackRule{}])!
		lines << if index == p.lines - 1 && p.lines > 1 {
			// The last line is three fifths of the width.
			flex_with_rules(FlexConfig{
				id:          ctx.part_id('last')
				orientation: .horizontal
			}, [line, view('', Rect{}, BoxStyle{ transparent: true }, [])], [
				FlexRule{
					grow: 3
				},
				FlexRule{
					grow: 2
				},
			])!
		} else {
			line
		}
	}
	root := flex_with_rules(FlexConfig{
		id:          ctx.id
		frame:       ctx.frame
		orientation: .vertical
		gap:         t.space_small
	}, lines, []FlexRule{len: lines.len})!
	return vml_handled(Element{
		...root
		accessibility_role:  'progressbar'
		accessibility_label: 'Loading'
	}, ctx, p.element_callback())
}

// ── Clipboard ───────────────────────────────────────────────────────

// ClipboardProps is the `Clipboard` tag: a button that copies `value` to the
// system clipboard. After a copy its icon is a check and `copied` is true
// for two seconds. `text` is an optional caption.
pub struct ClipboardProps {
	CommonProps
pub mut:
	value   string
	copied  bool
	text    DisplayText   = ''
	variant ButtonVariant = .ghost
	size    ControlSize   = .small
}

pub fn (p ClipboardProps) vml_structure() VmlStructure {
	return .generated
}

pub fn (p ClipboardProps) vml_themed() {}

pub fn (p ClipboardProps) control_size() ControlSize {
	return p.size
}

// A clipboard button is focusable, which needs an id.
pub fn (p ClipboardProps) control_id_required() bool {
	return true
}

pub fn (mut p ClipboardProps) apply_event(event ElementEvent) {
	if event.kind == .change {
		p.copied = event.checked
	}
}

pub fn (p ClipboardProps) build(ctx VmlBuildContext) !Element {
	el := kit_button_element(ctx.tokens(), ctx.id, ctx.frame, ButtonProps{
		text:    p.text
		variant: p.variant
		size:    p.size
		icon:    if p.copied { IconName.check } else { .copy }
		enabled: p.enabled
	}, [], [])!
	emitter := ctx.emitter(p.element_callback())
	handler := p.element_callback()
	value := p.value
	copied := p.copied
	// A copy sets `copied`, and the first one in a row clears it two seconds
	// later. The handlers see the click, then the changes.
	on_event := fn [emitter, handler, value, copied] (event ElementEvent) {
		if handler != unsafe { nil } {
			handler(event)
		}
		if event.kind == .click && set_clipboard_text(value) {
			emitter.emit(ElementEvent{
				kind:    .change
				id:      event.id
				checked: true
			})
			if !copied {
				kit_after(2, fn [emitter] () {
					emitter.emit(ElementEvent{
						kind:    .change
						checked: false
					})
				})
			}
		}
	}
	caption := p.text.str()
	return vml_handled(Element{
		...el
		accessibility_label: if caption.len > 0 { caption } else { 'Copy' }
		accessibility_value: if p.copied { 'Copied' } else { '' }
	}, ctx, on_event)
}
