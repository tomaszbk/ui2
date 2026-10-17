// SPDX-License-Identifier: Apache-2.0
// Includes shimmer spread and band tests and pagination behavior tests adapted
// from GPUI Kit (Longbridge, copyright 2024 - 2026); the other tests are new.
// See third_party/gpui-kit.
module ui2

import math

// kit_loop_values is what a part playing timeline presents ms milliseconds in.
fn kit_loop_values(part Element, timeline MotionTimeline, ms f64) MotionValues {
	program := compile_motion_timeline(timeline) or { panic(err) }
	position := program.locate(ms / 1000)
	mut channels := motion_channels(element_motion_values(part))
	program.apply(mut channels, position.time)
	return channels.values()
}

// kit_key_level is the level keys give at t, linear between them.
fn kit_key_level(keys []FeedbackKey, t f64) f64 {
	for i in 1 .. keys.len {
		if t <= keys[i].at {
			span := keys[i].at - keys[i - 1].at
			ratio := if span <= 0 { 1.0 } else { (t - keys[i - 1].at) / span }
			return keys[i - 1].level + (keys[i].level - keys[i - 1].level) * ratio
		}
	}
	return keys[keys.len - 1].level
}

// ── Progress ────────────────────────────────────────────────────────

fn test_progress_percent_and_value_text() {
	assert progress_percent(-5) == 0
	assert progress_percent(140) == 100
	assert progress_percent(math.nan()) == 0
	assert progress_percent(math.inf(1)) == 100
	assert progress_percent(42.5) == 42.5
	assert progress_value_text(40) == '40%'
	assert progress_value_text(33.33) == '33.3%'
	assert progress_value_text(99.96) == '100%'
}

fn test_progress_sizes_follow_gpui() {
	assert linear_progress_thickness(.small) == 6
	assert linear_progress_thickness(.large) == 10
	assert progress_circle_diameter(.medium) == 16
	assert progress_circle_thickness(16) == 2.4
	assert progress_circle_thickness(40) == 5
	assert loading_spinner_diameter(.large) == 24
}

fn test_feedback_ease_eases_in_and_out() {
	assert feedback_ease(0) == 0
	assert feedback_ease(0.25) == 0.125
	assert feedback_ease(0.5) == 0.5
	assert feedback_ease(0.75) == 0.875
	assert feedback_ease(1) == 1
}

fn test_progress_loading_curve_follows_gpui() {
	left0, right0 := linear_progress_loading_span(0)
	assert left0 == 0 && right0 == 0
	left_half, right_half := linear_progress_loading_span(0.5)
	assert left_half == 0 && right_half == 0.5
	left1, right1 := linear_progress_loading_span(1)
	assert left1 == 1 && right1 == 1
	// The left edge waits for the second half: one key holds it at zero.
	left, right := linear_progress_loading_keys()
	assert left[0] == FeedbackKey{0, 0}
	assert left[1] == FeedbackKey{0.5, 0}
	assert left[left.len - 1] == FeedbackKey{1, 1}
	assert right.len > 2 && right[right.len - 1] == FeedbackKey{1, 1}
	for key in right {
		_, end := linear_progress_loading_span(key.at)
		assert key.level == end
	}
}

// ── Feedback loops ──────────────────────────────────────────────────

fn test_feedback_scale_and_pulse_loops() {
	keys := feedback_compact_keys([FeedbackKey{0, 0}, FeedbackKey{0.25, 0.5}, FeedbackKey{0.5, 1},
		FeedbackKey{0.75, 1}, FeedbackKey{1, 1}])
	assert keys == [FeedbackKey{0, 0}, FeedbackKey{0.5, 1}, FeedbackKey{1, 1}]
	assert feedback_times(4, [0.3, 0.3, 2.0, math.nan()]) == [0.0, 0.25, 0.3, 0.5, 0.75, 1.0]
	// A scaled part is declared transparent and shown by the loop.
	bar := Element{
		...view('bar', rect(10, 0, 100, 4), BoxStyle{}, []Element{})
		opacity: 0
	}
	scale := feedback_scale_loop(1, keys)
	assert scale.repeat == motion_forever
	quarter := kit_loop_values(bar, scale, 250)
	assert quarter.opacity == 1
	assert math.abs(quarter.box_scale_x - 0.5) < 1e-9
	assert kit_loop_values(bar, scale, 750).box_scale_x == 1
	pulse := feedback_pulse_loop(2, 0.5)
	assert pulse.repeat == motion_forever
	assert kit_loop_values(bar, pulse, 1000).opacity == 0.5
	assert kit_loop_values(bar, pulse, 2000).opacity == 1
}

// ── Shimmer ─────────────────────────────────────────────────────────

fn test_shimmer_spread_and_band_follow_gpui() {
	// Relative spreads clamp to 5%...100% of the width; a non-finite one keeps
	// the default and an absolute one has a one-pixel minimum.
	assert shimmer_half_width(100, 0, 0) == 5
	assert shimmer_half_width(100, 2, 0) == 100
	assert shimmer_half_width(100, math.nan(), 0) == 30
	assert shimmer_half_width(100, 0.45, 0) == 45
	assert shimmer_half_width(100, 0.3, 0.5) == 1
	assert shimmer_half_width(100, 0.3, 48) == 48
	assert shimmer_half_width(100, 0.3, math.inf(1)) == 30
	half := shimmer_half_width(100, 0.3, 0)
	// The band starts and ends outside the text and moves left to right.
	_, before := shimmer_band_span(shimmer_band_center(0, 100, half, false), half, 0, 100)
	_, after := shimmer_band_span(shimmer_band_center(1, 100, half, false), half, 0, 100)
	assert before == 0 && after == 0
	early, _ := shimmer_band_span(shimmer_band_center(0.35, 100, half, false), half, 0, 100)
	late, _ := shimmer_band_span(shimmer_band_center(0.65, 100, half, false), half, 0, 100)
	assert early < late
	assert shimmer_band_center(0.35, 100, half, true) == shimmer_band_center(0.65, 100, half,
		false)
	// Inner layers are narrower than outer ones.
	outer_x, outer_w := shimmer_band_span(50, half, 0, 100)
	inner_x, inner_w := shimmer_band_span(50, half / 6, 0, 100)
	assert inner_x > outer_x && inner_w < outer_w
	// An absolute spread keeps the band the same width across text widths.
	_, narrow := shimmer_band_span(50, 20, 0, 100)
	_, wide := shimmer_band_span(100, 20, 0, 200)
	assert narrow == 40 && wide == 40
	assert math.abs(shimmer_band_time(shimmer_band_center(0.4, 100, half, true), 100, half,
		true) - 0.4) < 1e-9
}

fn test_shimmer_band_keys_sweep_across_the_line() {
	left, right := shimmer_band_keys(0.3, false)
	// The band starts before the line and ends past it.
	assert left[0].level == 0 && right[0].level == 0
	assert left[left.len - 1].level == 1 && right[right.len - 1].level == 1
	// Between the keys both edges move in straight lines, so the keys hold
	// the band wherever it is sampled.
	half := shimmer_half_width(1, 0.3, 0)
	for i in 0 .. 11 {
		t := f64(i) / 10
		offset, width := shimmer_band_span(shimmer_band_center(t, 1, half, false), half,
			0, 1)
		assert math.abs(kit_key_level(left, t) - offset) < 1e-6
		assert math.abs(kit_key_level(right, t) - (offset + width)) < 1e-6
	}
	reversed_left, _ := shimmer_band_keys(0.3, true)
	assert reversed_left[0].level == 1
}

// ── Badge and avatar ────────────────────────────────────────────────

fn test_badge_text_caps_its_count() {
	assert badge_text(101, 99) == '99+'
	assert badge_text(3, 0) == '3'
	assert badge_text(-1, 99) == ''
}

fn test_avatar_initials_take_whole_characters() {
	assert avatar_initials('  Ada  Lovelace ') == 'AL'
	assert avatar_initials('Ada') == 'A'
	assert avatar_initials('张 三') == '张三'
	assert avatar_initials(' \t\n ') == '?'
	assert avatar_initials('émile zola') == 'ÉZ'
}

// ── Pagination ──────────────────────────────────────────────────────

fn test_pagination_normalization_and_navigation_guards() {
	first := pagination_state(0, 0)
	assert first.current_page() == 1
	assert first.total_pages() == 1
	assert (first.previous_page() or { -1 }) == -1
	assert (first.next_page() or { -1 }) == -1
	last := pagination_state(20, 10)
	assert last.current_page() == 10
	assert (last.previous_page() or { -1 }) == 9
	assert (last.next_page() or { -1 }) == -1
	disabled := last.with_disabled(true)
	assert (disabled.previous_page() or { -1 }) == -1
	assert (disabled.request_page(1) or { -1 }) == -1
	assert (last.request_page(10) or { -1 }) == -1
	assert (last.request_page(11) or { -1 }) == -1
	assert PaginationState{}.current_page() == 1
}

fn test_pagination_upstream_page_window() {
	items := pagination_state(5, 10).with_visible_pages(7).items()
	assert items == [PaginationItem{
		page: 1
	}, PaginationItem{
		kind:  .ellipsis
		start: 2
		end:   3
	}, PaginationItem{
		page: 3
	}, PaginationItem{
		page: 4
	}, PaginationItem{
		page: 5
	}, PaginationItem{
		page: 6
	}, PaginationItem{
		page: 7
	}, PaginationItem{
		kind:  .ellipsis
		start: 8
		end:   10
	}, PaginationItem{
		page: 10
	}]
}

fn test_pagination_windows_cover_every_page_without_hiding_current() {
	for total in 2 .. 80 {
		for current in 1 .. total + 1 {
			for visible in 0 .. 16 {
				state := pagination_state(current, total).with_visible_pages(visible)
				items := state.items()
				assert items.len <= state.visible + 2
				mut next := 1
				mut found := false
				for item in items {
					if item.kind == .page {
						assert item.page == next
						found = found || item.page == current
						next++
					} else {
						assert item.start == next
						assert item.end > item.start
						next = item.end
					}
				}
				assert next == total + 1
				assert found
			}
		}
	}
}

fn test_pagination_large_datasets() {
	state := pagination_state(1, 2147483647).with_visible_pages(2147483647)
	assert state.items().len <= pagination_max_visible_pages + 2
	assert (state.request_page(2147483647) or { -1 }) == 2147483647
	last := pagination_state(2147483647, 2147483647)
	assert (last.next_page() or { -1 }) == -1
}
