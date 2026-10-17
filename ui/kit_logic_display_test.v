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

fn test_feedback_ease_and_inverse_round_trip() {
	assert feedback_ease(0) == 0
	assert feedback_ease(0.5) == 0.5
	assert feedback_ease(1) == 1
	for i in 0 .. 21 {
		t := f64(i) / 20
		assert math.abs(feedback_ease_inverse(feedback_ease(t)) - t) < 1e-9
	}
}

fn test_progress_loading_curves_follow_gpui() {
	left0, right0 := linear_progress_loading_span(0)
	assert left0 == 0 && right0 == 0
	left_half, right_half := linear_progress_loading_span(0.5)
	assert left_half == 0 && right_half == 0.5
	left1, right1 := linear_progress_loading_span(1)
	assert left1 == 1 && right1 == 1
	start, end := progress_circle_loading_arc(0.75)
	assert start == 0.5 && end == feedback_ease(0.75)
	assert loading_spinner_head(0.25) == 0.125
}

// ── Feedback loops ──────────────────────────────────────────────────

fn test_feedback_level_and_span_loops() {
	keys := feedback_compact_keys([FeedbackKey{0, 0}, FeedbackKey{0.25, 0.5}, FeedbackKey{0.5, 1},
		FeedbackKey{0.75, 1}, FeedbackKey{1, 1}])
	assert keys == [FeedbackKey{0, 0}, FeedbackKey{0.5, 1}, FeedbackKey{1, 1}]
	start := view('part', rect(0, 0, 4, 4), BoxStyle{}, []Element{})
	level := feedback_level_loop(1, keys, 0x000000, 0xffffff, .background, true)
	assert level.repeat == motion_forever
	assert kit_loop_values(start, level, 250).paint.background == 0x808080
	assert kit_loop_values(start, level, 750).paint.background == 0xffffff
	text := feedback_level_loop(1, keys, 0x000000, 0xffffff, .text_color, false)
	// A loop played once keeps its final values.
	assert text.repeat == 0 && text.hold
	assert kit_loop_values(start, text, 250).paint.text_color == 0x808080
	assert feedback_times(4, [0.3, 0.3, 2.0, math.nan()]) == [0.0, 0.25, 0.3, 0.5, 0.75, 1.0]
	// Spans move and scale a box laid out once.
	bar := view('bar', rect(10, 0, 100, 4), BoxStyle{}, []Element{})
	spans := feedback_compact_spans([FeedbackSpan{0, 10, 0}, FeedbackSpan{0.5, 35, 25},
		FeedbackSpan{1, 60, 50}])
	assert spans == [FeedbackSpan{0, 10, 0}, FeedbackSpan{1, 60, 50}]
	values := kit_loop_values(bar, feedback_span_loop(1, spans, 10, 100, true), 500)
	assert math.abs(bar.frame.x + values.transform.translate_x - 35) < 1e-9
	assert math.abs(bar.frame.width * values.box_scale_x - 25) < 1e-9
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

fn test_shimmer_paragraph_shortens_its_last_line() {
	lines := shimmer_paragraph(4, 8, 200, 3, 10, 6)
	assert lines.len == 3
	assert lines[1].frame == rect(4, 24, 200, 10)
	assert lines[2].frame.width == 120
	assert lines[2].radius == 5
	assert shimmer_paragraph(0, 0, 200, 1, 10, 6)[0].frame.width == 200
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
