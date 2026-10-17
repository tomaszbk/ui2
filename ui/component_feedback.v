module ui2

import math

// Shared machinery for the feedback components: linear_progress, progress_circle,
// loading_spinner, shimmer and shimmer_text.
//
// Every moving part is an ordinary view whose MotionConfig plays a looping
// timeline over it: keyframes from the start of the cycle to its end, so every
// cycle starts from the same values whatever was on screen before. Colors fade
// through keyframes; the cells of a ring jump in and out of sight instead, so a
// moving arc costs one animated element per cell and none of them has to be
// recolored. A timeline plays while its part is mounted and stops when the part
// leaves the tree; building the same configuration again keeps it running, and
// a new color, size or speed restarts it. Renderers without motion draw the
// parts at rest, as reduce_motion does.

// FeedbackKey is one keyframe of a looping part: at is the fraction of the cycle,
// level how far the part is between its resting and its lit color.
struct FeedbackKey {
	at    f64
	level f64
}

// FeedbackSpan is one keyframe of a part that moves: its x and width at a
// fraction of the cycle.
struct FeedbackSpan {
	at    f64
	x     f64
	width f64
}

enum FeedbackChannel {
	background
	text_color
}

// feedback_animates reports whether a feedback component can move: the
// renderer presents motion and neither the component nor the application
// (set_reduced_motion) asks for less.
fn feedback_animates(reduce_motion bool) bool {
	return backend_supports_motion && !reduce_motion && !reduced_motion()
}

// feedback_motion plays timeline on part. Declared values change at once, as
// they do on a part without motion.
fn feedback_motion(part Element, timeline MotionTimeline) Element {
	return with_motion(part, MotionConfig{
		enter:            MotionStyle{}
		exit:             MotionStyle{}
		enter_transition: MotionTransition{
			duration: 0
		}
		exit_transition:  MotionTransition{
			duration: 0
		}
		transition:       MotionTransition{
			duration: 0
		}
		timeline:         timeline
	})
}

// progress_percent clamps a percentage to 0...100. NaN counts as no progress.
pub fn progress_percent(value f64) f64 {
	if math.is_nan(value) {
		return 0
	}
	return math.clamp(value, 0, 100)
}

// feedback_ease is GPUI's ease_in_out, a quadratic ease in and out.
fn feedback_ease(t f64) f64 {
	x := math.clamp(t, 0, 1)
	if x < 0.5 {
		return 2 * x * x
	}
	y := 2 - 2 * x
	return 1 - y * y / 2
}

// feedback_ease_inverse returns the time at which feedback_ease reaches y.
fn feedback_ease_inverse(y f64) f64 {
	v := math.clamp(y, 0, 1)
	if v < 0.5 {
		return math.sqrt(v / 2)
	}
	return 1 - math.sqrt(2 * (1 - v)) / 2
}

// feedback_fraction wraps a number of turns into [0, 1).
fn feedback_fraction(turns f64) f64 {
	wrapped := turns - math.floor(turns)
	return if wrapped >= 1 { 0.0 } else { wrapped }
}

fn feedback_luminance(color u32) f64 {
	r := f64((color >> 16) & 0xff) / 255
	g := f64((color >> 8) & 0xff) / 255
	b := f64(color & 0xff) / 255
	return 0.2126 * r + 0.7152 * g + 0.0722 * b
}

// feedback_is_dark tells a dark theme from a light one by its background, since
// ComponentTheme carries colors rather than a mode.
fn feedback_is_dark(theme ComponentTheme) bool {
	return feedback_luminance(theme.background) < 0.5
}

// feedback_tone_color is the indicator color of a tone. The neutral tone's fill
// is a near-background gray, so its indicator uses the muted text color.
fn feedback_tone_color(theme ComponentTheme, tone ComponentTone) u32 {
	if tone == .neutral {
		return theme.muted_foreground
	}
	fill, _ := theme.colors(tone)
	return fill
}

// feedback_track_color is color drawn at 20% over background: the translucent
// track GPUI draws, flattened because ui2 colors are opaque.
fn feedback_track_color(color u32, background u32) u32 {
	return interpolate_color(color, background, 0.8)
}

fn feedback_validate_length(name string, value f64) ! {
	if !component_finite(value) || value < 0 {
		return error('${name} must be finite and non-negative')
	}
}

// feedback_compact_keys drops keyframes that lie on the line through their
// neighbors: flat stretches and straight ramps need only their ends.
fn feedback_compact_keys(keys []FeedbackKey) []FeedbackKey {
	if keys.len <= 2 {
		return keys
	}
	mut compact := [keys[0]]
	for i in 1 .. keys.len - 1 {
		previous := compact[compact.len - 1]
		next := keys[i + 1]
		span := next.at - previous.at
		expected := if span <= 0 {
			previous.level
		} else {
			previous.level + (next.level - previous.level) * (keys[i].at - previous.at) / span
		}
		if math.abs(expected - keys[i].level) > 1e-4 {
			compact << keys[i]
		}
	}
	compact << keys[keys.len - 1]
	return compact
}

// feedback_times merges evenly spaced samples with the instants at which a
// level changes slope, sorted and without near duplicates, all within [0, 1].
fn feedback_times(samples int, critical []f64) []f64 {
	mut times := []f64{cap: samples + 1 + critical.len}
	for k in 0 .. samples + 1 {
		times << f64(k) / f64(samples)
	}
	for t in critical {
		if component_finite(t) && t > 0 && t < 1 {
			times << t
		}
	}
	times.sort()
	mut unique := []f64{cap: times.len}
	for t in times {
		if unique.len == 0 || t - unique[unique.len - 1] > 1e-6 {
			unique << t
		}
	}
	return unique
}

// feedback_level_loop animates a color channel between off and on through keys,
// which run from at = 0 to at = 1 over period seconds.
fn feedback_level_loop(period f64, keys []FeedbackKey, off u32, on u32, channel FeedbackChannel, repeat bool) MotionTimeline {
	mut keyframes := []MotionKeyframe{cap: keys.len}
	for key in keys {
		color := interpolate_color(off, on, math.clamp(key.level, 0, 1))
		keyframes << MotionKeyframe{
			at:    key.at
			style: match channel {
				.background {
					MotionStyle{
						background: color
					}
				}
				.text_color {
					MotionStyle{
						text_color: color
					}
				}
			}
		}
	}
	return feedback_cycle(motion_keyframes(period, ...keyframes), repeat)
}

// feedback_cycle loops a timeline, or plays it once and keeps where it ends.
fn feedback_cycle(timeline MotionTimeline, repeat bool) MotionTimeline {
	return if repeat {
		timeline.looped()
	} else {
		MotionTimeline{
			...timeline
			hold: true
		}
	}
}

// feedback_span_loop moves and sizes a part through spans over period seconds.
// The part is declared at x and width; each span translates it and scales its
// box, so the part is laid out once.
fn feedback_span_loop(period f64, spans []FeedbackSpan, x f64, width f64, repeat bool) MotionTimeline {
	mut keyframes := []MotionKeyframe{cap: spans.len}
	for span in spans {
		keyframes << MotionKeyframe{
			at:    span.at
			style: MotionStyle{
				translate_x: span.x - x
				box_scale_x: if width > 0 { math.max(span.width, 0) / width } else { 0.0 }
			}
		}
	}
	return feedback_cycle(motion_keyframes(period, ...keyframes), repeat)
}

// feedback_compact_spans drops spans that lie on the line through their
// neighbors in both x and width.
fn feedback_compact_spans(spans []FeedbackSpan) []FeedbackSpan {
	if spans.len <= 2 {
		return spans
	}
	mut compact := [spans[0]]
	for i in 1 .. spans.len - 1 {
		previous := compact[compact.len - 1]
		next := spans[i + 1]
		span := next.at - previous.at
		ratio := if span <= 0 { 0.0 } else { (spans[i].at - previous.at) / span }
		x := previous.x + (next.x - previous.x) * ratio
		width := previous.width + (next.width - previous.width) * ratio
		if math.abs(x - spans[i].x) > 1e-3 || math.abs(width - spans[i].width) > 1e-3 {
			compact << spans[i]
		}
	}
	compact << spans[spans.len - 1]
	return compact
}

// feedback_toggle_loop shows a part from on to off of every cycle and hides it
// for the rest. The window may wrap past the cycle's end. Showing and hiding
// are jumps: a part is either drawn in full or not at all.
fn feedback_toggle_loop(period f64, on f64, off f64) MotionTimeline {
	mut times := [0.0, 1.0]
	for t in [feedback_fraction(on), feedback_fraction(off)] {
		if t > 0 {
			times << t
		}
	}
	times.sort()
	mut keyframes := []MotionKeyframe{}
	for i in 0 .. times.len - 1 {
		length := times[i + 1] - times[i]
		if length <= 1e-9 {
			continue
		}
		middle := (times[i] + times[i + 1]) / 2
		shown := if feedback_window_contains(on, off, middle) { 1.0 } else { 0.0 }
		// Keys sharing an instant jump: the later one wins from that instant.
		keyframes << MotionKeyframe{
			at:    times[i]
			style: MotionStyle{
				opacity: shown
			}
		}
		keyframes << MotionKeyframe{
			at:    times[i + 1]
			style: MotionStyle{
				opacity: shown
			}
		}
	}
	return motion_keyframes(period, ...keyframes).looped()
}

// feedback_window_contains reports whether t lies in the cyclic window that
// opens at on and closes at off.
fn feedback_window_contains(on f64, off f64, t f64) bool {
	return feedback_fraction(t - on) < feedback_fraction(off - on)
}

// FeedbackPiece is one shape of a ring: its frame in the ring's square box and
// the sector of the ring it lies in.
struct FeedbackPiece {
	frame  Rect
	radius f64
	sector int
}

// The custom renderer spends some 370 sokol-gl vertices on every rounded rect
// and has 65,536 a frame, so rings of round cells would blank a busy window
// there. It gets scan-converted strips instead, which cost six vertices each;
// the other renderers draw round cells, which they antialias.
fn feedback_draws_strips() bool {
	return backend_feedback_strips
}

// feedback_parent_clips reports whether the renderer clips a view's children to
// its rounded corners, as AppKit does by masking a layer with a corner radius.
fn feedback_parent_clips() bool {
	return backend_clips_rounded_children
}

// feedback_ring_pieces covers the stretch of a ring from turn `from` to turn
// `to` (clockwise from twelve o'clock; a whole turn or more is the full ring)
// with pieces split into `sectors` equal sectors. A single sector draws round
// ends half the stroke beyond from and to.
fn feedback_ring_pieces(diameter f64, stroke f64, from f64, to f64, sectors int) []FeedbackPiece {
	if feedback_draws_strips() {
		return feedback_ring_strips(diameter, stroke, from, to, sectors, feedback_strip_row(diameter))
	}
	return feedback_ring_cells(diameter, stroke, from, to, sectors, 0.5)
}

// feedback_strip_row is the height of a ring's scan lines: one device pixel on
// a 2x display for small rings, a point for large ones.
fn feedback_strip_row(diameter f64) f64 {
	return if diameter <= 200 { 0.5 } else { 1.0 }
}

fn feedback_sector(turn f64, sectors int) int {
	if sectors <= 1 {
		return 0
	}
	index := int(feedback_fraction(turn) * f64(sectors))
	return if index >= sectors { sectors - 1 } else { index }
}

// feedback_ring_cells places round cells of the stroke's diameter along the
// ring's centerline, spacing strokes apart, so they overlap into a smooth band
// whose ends are round.
fn feedback_ring_cells(diameter f64, stroke f64, from f64, to f64, sectors int, spacing f64) []FeedbackPiece {
	ring := (diameter - stroke) / 2
	center := diameter / 2
	span := math.min(to - from, 1.0)
	if ring <= 0 || stroke <= 0 || span < 0 {
		return []FeedbackPiece{}
	}
	full := span >= 1
	steps := math.max(1, int(math.ceil(2 * math.pi * ring * span / (stroke * spacing))))
	count := if full { steps } else { steps + 1 }
	mut pieces := []FeedbackPiece{cap: count}
	for i in 0 .. count {
		turn := from + span * f64(i) / f64(steps)
		pieces << FeedbackPiece{
			frame:  feedback_ring_cell(center, center, ring, stroke, turn)
			radius: stroke / 2
			sector: feedback_sector(turn, sectors)
		}
	}
	return pieces
}

struct FeedbackInterval {
	start  f64
	end    f64
	sector int
}

// feedback_ring_strips scan-converts the same band into horizontal strips row
// tall, the way chart.v draws doughnut slices: each row of the ring is split
// where a sector boundary crosses it, and kept where it lies between from and
// to. A single sector also takes in the round end caps and merges each row
// into as few strips as possible.
fn feedback_ring_strips(diameter f64, stroke f64, from f64, to f64, sectors int, row f64) []FeedbackPiece {
	outer := diameter / 2
	inner := outer - stroke
	center := diameter / 2
	span := math.min(to - from, 1.0)
	if outer <= 0 || stroke <= 0 || row <= 0 || span < 0 {
		return []FeedbackPiece{}
	}
	full := span >= 1
	mut boundaries := []f64{}
	if sectors > 1 {
		for k in 0 .. sectors {
			boundaries << f64(k) / f64(sectors)
		}
	}
	if !full {
		boundaries << from
		boundaries << to
	}
	middle := (outer + inner) / 2
	caps := sectors <= 1 && !full
	mut cap_centers := []f64{}
	if caps {
		for turn in [from, to] {
			angle := turn * 2 * math.pi
			cap_centers << middle * math.sin(angle)
			cap_centers << -middle * math.cos(angle)
		}
	}
	rows := int(math.ceil(diameter / row))
	mut pieces := []FeedbackPiece{}
	for r in 0 .. rows {
		y0 := -outer + f64(r) * row
		y1 := math.min(outer, y0 + row)
		y := (y0 + y1) / 2
		mut segments := [][]f64{}
		if math.abs(y) < outer {
			half := math.sqrt(outer * outer - y * y)
			if math.abs(y) < inner {
				hole := math.sqrt(inner * inner - y * y)
				segments << [-half, -hole]
				segments << [hole, half]
			} else {
				segments << [-half, half]
			}
		}
		mut kept := []FeedbackInterval{}
		for segment in segments {
			mut edges := [segment[0], segment[1]]
			for turn in boundaries {
				angle := turn * 2 * math.pi
				dy := -math.cos(angle)
				if math.abs(dy) > 1e-10 && y / dy >= 0 {
					x := y * math.sin(angle) / dy
					if x > segment[0] && x < segment[1] {
						edges << x
					}
				}
			}
			edges.sort()
			for j in 0 .. edges.len - 1 {
				if edges[j + 1] - edges[j] <= 1e-9 {
					continue
				}
				x := (edges[j] + edges[j + 1]) / 2
				turn := feedback_fraction(math.atan2(x, -y) / (2 * math.pi))
				if !full && feedback_fraction(turn - from) > span {
					continue
				}
				kept << FeedbackInterval{edges[j], edges[j + 1], feedback_sector(turn, sectors)}
			}
		}
		if caps {
			for c in 0 .. 2 {
				cx := cap_centers[c * 2]
				cy := cap_centers[c * 2 + 1]
				dy := y - cy
				if math.abs(dy) < stroke / 2 {
					chord := math.sqrt(stroke * stroke / 4 - dy * dy)
					kept << FeedbackInterval{cx - chord, cx + chord, 0}
				}
			}
			kept.sort(a.start < b.start)
			mut merged := []FeedbackInterval{}
			for interval in kept {
				if merged.len > 0 && interval.start <= merged[merged.len - 1].end + 1e-9 {
					last := merged[merged.len - 1]
					merged[merged.len - 1] = FeedbackInterval{last.start, math.max(last.end,
						interval.end), 0}
				} else {
					merged << interval
				}
			}
			kept = merged.clone()
		}
		for interval in kept {
			pieces << FeedbackPiece{
				frame:  rect(center + interval.start, center + y0, interval.end - interval.start,
					y1 - y0)
				sector: interval.sector
			}
		}
	}
	return pieces
}

// feedback_ring_track is the ring's track: a disc in the track color with a
// disc of the background over its middle. ui2 colors are opaque, so the hole
// shows the background color rather than whatever lies behind the ring.
fn feedback_ring_track(diameter f64, stroke f64, track u32, background u32) []Element {
	hole := math.max(diameter - 2 * stroke, 0)
	return [
		view('', rect(0, 0, diameter, diameter), BoxStyle{
			bg:     track
			radius: diameter / 2
		}, []Element{}),
		view('', rect(stroke, stroke, hole, hole), BoxStyle{
			bg:     background
			radius: hole / 2
		}, []Element{}),
	]
}

// FeedbackArcMotion is how the arc of an animated ring moves.
enum FeedbackArcMotion {
	spinner  // A three-quarter arc eased once round the ring per cycle.
	progress // GPUI's indeterminate arc: it grows round the ring, then its tail chases it off.
}

// window is the part of the cycle during which the arc covers turn.
fn (motion FeedbackArcMotion) window(turn f64) (f64, f64) {
	return match motion {
		.spinner { spinner_ring_window(turn) }
		.progress { progress_circle_sector_window(turn) }
	}
}

// Strips are shown and hidden this many sectors at a time.
const feedback_ring_sectors = 24

// feedback_ring_loop draws the arc of an animated ring. Each round cell, or each
// of feedback_ring_sectors sectors of strips, is a part under group that a
// looping timeline shows while the arc covers it, so the arc moves without
// any element changing color. Cells overlap, and each one shown on top of the
// track gives the arc round ends.
fn feedback_ring_loop(id string, group string, diameter f64, stroke f64, color u32, period f64, motion FeedbackArcMotion) []Element {
	mut parts := []Element{}
	if feedback_draws_strips() {
		sectors := feedback_ring_sectors
		mut groups := [][]Element{len: sectors}
		for piece in feedback_ring_strips(diameter, stroke, 0, 1, sectors, feedback_strip_row(diameter)) {
			groups[piece.sector] << view('', piece.frame, BoxStyle{ bg: color }, []Element{})
		}
		for i in 0 .. sectors {
			on, off := motion.window((f64(i) + 0.5) / f64(sectors))
			parts << feedback_motion(view(component_part_id(id, '${group}:${i}'), rect(0,
				0, diameter, diameter), BoxStyle{ transparent: true }, groups[i]),
				feedback_toggle_loop(period, on, off))
		}
		return parts
	}
	cells := feedback_ring_cells(diameter, stroke, 0, 1, 1, 0.6)
	for i, cell in cells {
		on, off := motion.window(f64(i) / f64(cells.len))
		parts << feedback_motion(view(component_part_id(id, '${group}:${i}'), cell.frame,
			BoxStyle{
				bg:     color
				radius: cell.radius
			}, []Element{}), feedback_toggle_loop(period, on, off))
	}
	return parts
}

// feedback_ring_cell is the frame of a round cell of diameter cell whose center
// lies on a circle of radius ring around (cx, cy), turn of a revolution
// clockwise from twelve o'clock.
fn feedback_ring_cell(cx f64, cy f64, ring f64, cell f64, turn f64) Rect {
	angle := turn * 2 * math.pi
	x := cx + ring * math.sin(angle)
	y := cy - ring * math.cos(angle)
	return rect(x - cell / 2, y - cell / 2, cell, cell)
}
