// Copyright 2024 - 2026 Longbridge <https://longbridge.com>
// SPDX-License-Identifier: Apache-2.0
// Adapted from GPUI Kit: the controlled pagination state and page-window
// algorithm (crates/base/src/pagination.rs); the progress size presets and
// both indeterminate curves (crates/component/src/progress/progress.rs and
// progress_circle.rs); and the shimmer spread clamping, band center and
// padding (crates/component/src/shimmer.rs). The rest is new UI2 code. See
// third_party/gpui-kit.
module ui2

import math

// Pure logic of the display and feedback controls: progress values and
// curves, size presets, shimmer bands, badge and avatar text, pagination.
// The looping keyframes a feedback part plays are built here too, from keys
// or spans sampled over one cycle.

// ── Progress ────────────────────────────────────────────────────────

// progress_percent clamps a percentage to 0...100. NaN counts as no progress.
pub fn progress_percent(value f64) f64 {
	if math.is_nan(value) {
		return 0
	}
	return math.clamp(value, 0, 100)
}

// progress_value_text is how a percentage is announced: whole percents, and a
// tenth only when the value has one.
pub fn progress_value_text(percent f64) string {
	rounded := math.round(percent * 10) / 10
	if rounded == math.round(rounded) {
		return '${i64(rounded)}%'
	}
	return '${rounded:.1f}%'
}

// linear_progress_thickness is GPUI's bar height for a size.
pub fn linear_progress_thickness(size ControlSize) f64 {
	return match size {
		.small { 6 }
		.medium { 8 }
		.large { 10 }
	}
}

// linear_progress_loading_span is the indeterminate indicator at a fraction t of
// its cycle, as (left, right) fractions of the track: the right edge eases out
// to the end over the whole cycle while the left edge follows in the second
// half, so the bar grows from the start and then drains away at the end.
pub fn linear_progress_loading_span(t f64) (f64, f64) {
	return feedback_ease(math.clamp((t - 0.5) * 2, 0, 1)), feedback_ease(t)
}

// progress_circle_diameter is GPUI's ring size for a size.
pub fn progress_circle_diameter(size ControlSize) f64 {
	return match size {
		.small { 12 }
		.medium { 16 }
		.large { 20 }
	}
}

// progress_circle_thickness is GPUI's stroke for a ring of a given diameter.
pub fn progress_circle_thickness(diameter f64) f64 {
	return math.min(diameter * 0.15, 5)
}

// progress_circle_loading_arc is the indeterminate arc at a fraction t of its
// cycle, as (start, end) fractions of a turn from twelve o'clock: the end eases
// around the ring over the cycle and the start follows in the second half.
pub fn progress_circle_loading_arc(t f64) (f64, f64) {
	return feedback_ease(math.clamp((t - 0.5) * 2, 0, 1)), feedback_ease(t)
}

// loading_spinner_diameter is GPUI's spinner size for a size.
pub fn loading_spinner_diameter(size ControlSize) f64 {
	return match size {
		.small { 14 }
		.medium { 16 }
		.large { 24 }
	}
}

// loading_spinner_head is where the spinner's head is, in turns from twelve
// o'clock, at a fraction t of a revolution.
pub fn loading_spinner_head(t f64) f64 {
	return feedback_ease(t)
}

// ── Feedback curves and loops ───────────────────────────────────────

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

// feedback_times merges evenly spaced samples with the instants at which a
// level changes slope, sorted and without near duplicates, all within [0, 1].
fn feedback_times(samples int, critical []f64) []f64 {
	mut times := []f64{cap: samples + 1 + critical.len}
	for k in 0 .. samples + 1 {
		times << f64(k) / f64(samples)
	}
	for t in critical {
		if math.is_finite(t) && t > 0 && t < 1 {
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

// ── Shimmer ─────────────────────────────────────────────────────────

// ShimmerShape is one skeleton placeholder of a shimmer: a rectangle, or a
// circle the size of the frame's shorter side centered in it.
pub struct ShimmerShape {
pub:
	frame  Rect
	circle bool
	radius f64 = 6 // Corner radius of a rectangular shape, limited to a pill.
}

// shimmer_paragraph returns line shapes for a placeholder paragraph: lines
// rows line_height tall with gap between them, the last one shorter.
pub fn shimmer_paragraph(x f64, y f64, width f64, lines int, line_height f64, gap f64) []ShimmerShape {
	mut shapes := []ShimmerShape{cap: lines}
	for i in 0 .. lines {
		line_width := if i == lines - 1 && lines > 1 { width * 0.6 } else { width }
		shapes << ShimmerShape{
			frame:  rect(x, y + f64(i) * (line_height + gap), line_width, line_height)
			radius: line_height / 2
		}
	}
	return shapes
}

// shimmer_half_width resolves a sweep's spread to the band's half-width in a
// frame width wide, following GPUI's rules: an absolute spread_pixels (at
// least 1) wins, else spread is a fraction clamped to 0.05...1, and a
// non-finite spread keeps the default 0.3.
pub fn shimmer_half_width(width f64, spread f64, spread_pixels f64) f64 {
	if math.is_finite(spread_pixels) && spread_pixels > 0 {
		return math.max(spread_pixels, 1)
	}
	fraction := if math.is_finite(spread) { math.clamp(spread, 0.05, 1) } else { 0.3 }
	return width * fraction
}

// shimmer_band_center is where the band's center is at a fraction t of a
// sweep across width. The sweep starts and ends with the whole band outside the
// frame, five percent of the width beyond its edge.
pub fn shimmer_band_center(t f64, width f64, half f64, reverse bool) f64 {
	if width <= 0 {
		return 0
	}
	padding := half / width + 0.05
	phase := if reverse { 1 - t } else { t }
	return (phase * (1 + 2 * padding) - padding) * width
}

// shimmer_band_time is the inverse of shimmer_band_center.
fn shimmer_band_time(center f64, width f64, half f64, reverse bool) f64 {
	if width <= 0 {
		return 0
	}
	padding := half / width + 0.05
	phase := (center / width + padding) / (1 + 2 * padding)
	return if reverse { 1 - phase } else { phase }
}

// shimmer_band_span is the part of the band of half-width half centered at
// center that lies over [start, start + extent], as an offset from start and a
// width. It is empty while the band is elsewhere.
pub fn shimmer_band_span(center f64, half f64, start f64, extent f64) (f64, f64) {
	left := math.clamp(center - half, start, start + extent)
	right := math.clamp(center + half, start, start + extent)
	return left - start, right - left
}

// ── Badge and avatar ────────────────────────────────────────────────

// badge_text is a counter's text: the count, or `<max_count>+` past it (99 when
// max_count is not positive). A negative count has no counter.
pub fn badge_text(count int, max_count int) string {
	if count < 0 {
		return ''
	}
	limit := if max_count > 0 { max_count } else { 99 }
	return if count > limit { '${limit}+' } else { count.str() }
}

// avatar_initials takes whole characters, never individual UTF-8 bytes.
// A single word contributes one initial; multiple words use first and last.
pub fn avatar_initials(name string) string {
	words := name.fields()
	if words.len == 0 {
		return '?'
	}
	first := avatar_initial(words[0])
	if words.len == 1 {
		return first.to_upper()
	}
	return (first + avatar_initial(words[words.len - 1])).to_upper()
}

// avatar_initial is a word's first Unicode scalar plus the combining marks after
// it, so a decomposed accent stays on its letter instead of being dropped.
fn avatar_initial(word string) string {
	runes := word.runes()
	mut end := 1
	for end < runes.len && avatar_is_combining_mark(runes[end]) {
		end++
	}
	return runes[..end].string()
}

fn avatar_is_combining_mark(r rune) bool {
	return (r >= 0x0300 && r <= 0x036f) || (r >= 0x1ab0 && r <= 0x1aff)
		|| (r >= 0x1dc0 && r <= 0x1dff) || (r >= 0x20d0 && r <= 0x20ff)
		|| (r >= 0xfe20 && r <= 0xfe2f)
}

// ── Pagination ──────────────────────────────────────────────────────

pub const pagination_max_visible_pages = 100

pub enum PaginationItemKind {
	page
	ellipsis
}

// Ellipses describe a half-open range [start, end) of hidden page numbers.
pub struct PaginationItem {
pub:
	kind  PaginationItemKind
	page  int
	start int
	end   int
}

// Private fields ensure every state is normalized, including its zero value.
pub struct PaginationState {
	page     int = 1
	pages    int = 1
	visible  int = 5
	disabled bool
}

pub fn pagination_state(current_page int, total_pages int) PaginationState {
	pages := if total_pages > 0 { total_pages } else { 1 }
	page := if current_page < 1 {
		1
	} else if current_page > pages {
		pages
	} else {
		current_page
	}
	return PaginationState{
		page:  page
		pages: pages
	}
}

pub fn (state PaginationState) current_page() int {
	return state.page
}

pub fn (state PaginationState) total_pages() int {
	return state.pages
}

pub fn (state PaginationState) is_disabled() bool {
	return state.disabled
}

pub fn (state PaginationState) with_disabled(disabled bool) PaginationState {
	return PaginationState{
		...state
		disabled: disabled
	}
}

// Bound rendering work even if the dataset has billions of pages. The cap
// applies to requested visible pages, not to total_pages or navigation.
pub fn (state PaginationState) with_visible_pages(visible int) PaginationState {
	return PaginationState{
		...state
		visible: if visible < 5 {
			5
		} else if visible > pagination_max_visible_pages {
			pagination_max_visible_pages
		} else {
			visible
		}
	}
}

// request_page returns a proposed new value; it never mutates application state.
pub fn (state PaginationState) request_page(page int) ?int {
	if state.disabled || page == state.page || page < 1 || page > state.pages {
		return none
	}
	return page
}

pub fn (state PaginationState) previous_page() ?int {
	if state.disabled || state.page <= 1 {
		return none
	}
	return state.page - 1
}

pub fn (state PaginationState) next_page() ?int {
	if state.disabled || state.page >= state.pages {
		return none
	}
	return state.page + 1
}

pub fn (state PaginationState) items() []PaginationItem {
	if state.pages <= 1 {
		return []PaginationItem{}
	}
	mut items := []PaginationItem{}
	if state.pages <= state.visible {
		for page in 1 .. state.pages + 1 {
			items << PaginationItem{
				page: page
			}
		}
		return items
	}
	items << PaginationItem{
		page: 1
	}
	side := (state.visible - 3) / 2
	start := if state.page <= side + 1 {
		2
	} else if state.page > state.pages - side - 1 {
		state.pages - side - 1
	} else {
		state.page - side
	}
	if start > 2 {
		items << PaginationItem{
			kind:  .ellipsis
			start: 2
			end:   start
		}
	}
	end := if state.page >= state.pages - side {
		state.pages - 1
	} else if state.page <= side + 1 {
		side + 2
	} else {
		state.page + side
	}
	for page in start .. end + 1 {
		items << PaginationItem{
			page: page
		}
	}
	if end < state.pages - 1 {
		items << PaginationItem{
			kind:  .ellipsis
			start: end + 1
			end:   state.pages
		}
	}
	items << PaginationItem{
		page: state.pages
	}
	return items
}
