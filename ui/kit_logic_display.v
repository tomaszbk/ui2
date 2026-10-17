// Copyright 2024 - 2026 Longbridge <https://longbridge.com>
// SPDX-License-Identifier: Apache-2.0
// Adapted from GPUI Kit: the controlled pagination state and page-window
// algorithm (crates/base/src/pagination.rs); the progress size presets and
// the indeterminate bar's curve (crates/component/src/progress/progress.rs
// and progress_circle.rs); and the shimmer spread clamping, band center and
// padding (crates/component/src/shimmer.rs). The rest is new UI2 code. See
// third_party/gpui-kit.
module ui2

import math

// Pure logic of the display, feedback and navigation controls: progress
// values and curves, size presets, shimmer bands, badge and avatar text,
// pagination and carousel indexes. The looping keyframes a feedback part
// plays are built here too, from keys sampled over one cycle.

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

// loading_spinner_diameter is GPUI's spinner size for a size.
pub fn loading_spinner_diameter(size ControlSize) f64 {
	return match size {
		.small { 14 }
		.medium { 16 }
		.large { 24 }
	}
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

// FeedbackKey is one keyframe of a looping part: at is the fraction of the
// cycle, level the fraction of its width the part covers.
struct FeedbackKey {
	at    f64
	level f64
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

// feedback_scale_loop shows a part from its left edge to the fraction of its
// width each key's level gives (box_scale_x), over period seconds, until the
// part leaves. Every keyframe makes the part opaque, so a part declared
// transparent stays out of sight under reduced motion, which plays no
// timeline.
fn feedback_scale_loop(period f64, keys []FeedbackKey) MotionTimeline {
	mut keyframes := []MotionKeyframe{cap: keys.len}
	for key in keys {
		keyframes << MotionKeyframe{
			at:    key.at
			style: MotionStyle{
				opacity:     1
				box_scale_x: math.clamp(key.level, 0, 1)
			}
		}
	}
	return motion_keyframes(period, ...keyframes).looped()
}

// feedback_pulse_loop fades a part to opacity low and back over period
// seconds, easing in and out, until the part leaves.
fn feedback_pulse_loop(period f64, low f64) MotionTimeline {
	return motion_keyframes(period, MotionKeyframe{
		at:    0
		style: MotionStyle{
			opacity: 1
		}
	}, MotionKeyframe{
		at:     0.5
		style:  MotionStyle{
			opacity: low
		}
		easing: .in_out_sine
	}, MotionKeyframe{
		at:     1
		style:  MotionStyle{
			opacity: 1
		}
		easing: .in_out_sine
	}).looped()
}

// linear_progress_loading_keys are the indeterminate indicator's edges over
// one cycle (linear_progress_loading_span) as keyframe levels: its left edge,
// then its right edge.
fn linear_progress_loading_keys() ([]FeedbackKey, []FeedbackKey) {
	times := feedback_times(24, [0.5])
	mut left := []FeedbackKey{cap: times.len}
	mut right := []FeedbackKey{cap: times.len}
	for t in times {
		start, end := linear_progress_loading_span(t)
		left << FeedbackKey{t, start}
		right << FeedbackKey{t, end}
	}
	return feedback_compact_keys(left), feedback_compact_keys(right)
}

// ── Shimmer ─────────────────────────────────────────────────────────

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

// shimmer_band_keys are one sweep of a band over a line as keyframe levels,
// in fractions of the line: the band's left edge, then its right edge. The
// band moves at a constant speed, so keys where an edge enters or leaves the
// line are exact; spread is the band's half-width (shimmer_half_width).
fn shimmer_band_keys(spread f64, reverse bool) ([]FeedbackKey, []FeedbackKey) {
	half := shimmer_half_width(1, spread, 0)
	mut critical := []f64{cap: 4}
	for edge in [-half, half, 1 - half, 1 + half] {
		critical << shimmer_band_time(edge, 1, half, reverse)
	}
	times := feedback_times(1, critical)
	mut left := []FeedbackKey{cap: times.len}
	mut right := []FeedbackKey{cap: times.len}
	for t in times {
		offset, width := shimmer_band_span(shimmer_band_center(t, 1, half, reverse), half,
			0, 1)
		left << FeedbackKey{t, offset}
		right << FeedbackKey{t, offset + width}
	}
	return feedback_compact_keys(left), feedback_compact_keys(right)
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

// ── Keyboard selection ──────────────────────────────────────────────

// roving_index is where a navigation key moves a selection among items, of
// which only the enabled ones can be selected: left or up to the previous
// enabled item, right or down to the next, home and end to the first and
// last. At either end it wraps with `wrap` and stays otherwise. From no
// selection (current out of range) the keys start at the first or last
// item. It is none for another key, or when no item is enabled or the
// selection does not move.
pub fn roving_index(enabled []bool, current int, key string, wrap bool) ?int {
	count := enabled.len
	if count == 0 || !enabled.any(it) {
		return none
	}
	step := match key {
		'left', 'up' { -1 }
		'right', 'down' { 1 }
		'home', 'end' { 0 }
		else { return none }
	}
	outside := current < 0 || current >= count
	mut index := if key == 'home' || (outside && step > 0) {
		-1
	} else if key == 'end' || (outside && step < 0) {
		count
	} else {
		current
	}
	direction := if step == 0 {
		if key == 'home' { 1 } else { -1 }
	} else {
		step
	}
	for _ in 0 .. count {
		index += direction
		if index < 0 || index >= count {
			if !wrap || step == 0 {
				return none
			}
			index = (index + count) % count
		}
		if enabled[index] {
			if index == current {
				return none
			}
			return index
		}
	}
	return none
}

// ── Tree ────────────────────────────────────────────────────────────

// TreeRow is a shown row of a tree: an item, its depth, and the row of its
// parent, -1 at the top level.
pub struct TreeRow {
pub:
	item   TreeItemRecord
	depth  int
	parent int = -1
}

// tree_rows flattens the shown part of a tree: each item, followed by the
// rows of its children while it is expanded.
pub fn tree_rows(items []TreeItemRecord) []TreeRow {
	mut rows := []TreeRow{}
	tree_append_rows(items, 0, -1, mut rows)
	return rows
}

fn tree_append_rows(items []TreeItemRecord, depth int, parent int, mut rows []TreeRow) {
	for item in items {
		index := rows.len
		rows << TreeRow{
			item:   item
			depth:  depth
			parent: parent
		}
		if item.expanded {
			tree_append_rows(item.children, depth + 1, index, mut rows)
		}
	}
}

// TreeKeyMove is what a key does in a tree: select another row, or expand
// or collapse the selected one.
pub struct TreeKeyMove {
pub:
	row    int = -1 // the row to select; -1 keeps the selection
	toggle bool // expand or collapse the selected row
}

// tree_key_move is what a key does while row `current` is selected. Up,
// Down, Home and End select among the enabled rows. Right expands a
// collapsed parent and enters an expanded one; Left collapses an expanded
// parent and otherwise selects the parent row. Enter and Space expand or
// collapse a parent.
pub fn tree_key_move(rows []TreeRow, current int, key string) TreeKeyMove {
	if key in ['up', 'down', 'home', 'end'] {
		return TreeKeyMove{
			row: roving_index(rows.map(it.item.enabled), current, key, false) or { -1 }
		}
	}
	if current < 0 || current >= rows.len {
		return TreeKeyMove{}
	}
	row := rows[current]
	parent := row.item.children.len > 0
	match key {
		'right' {
			if parent && !row.item.expanded {
				return TreeKeyMove{
					toggle: true
				}
			}
			if parent && current + 1 < rows.len && rows[current + 1].item.enabled {
				return TreeKeyMove{
					row: current + 1
				}
			}
		}
		'left' {
			if parent && row.item.expanded {
				return TreeKeyMove{
					toggle: true
				}
			}
			if row.parent >= 0 {
				return TreeKeyMove{
					row: row.parent
				}
			}
		}
		'enter', 'space' {
			if parent {
				return TreeKeyMove{
					toggle: true
				}
			}
		}
		else {}
	}
	return TreeKeyMove{}
}
