// SPDX-License-Identifier: Apache-2.0
// Includes shimmer spread, band and highlight tests adapted from GPUI Kit
// (Longbridge, copyright 2024 - 2026); other tests are new. See third_party/gpui-kit.
module ui2

import math

fn feedback_test_find(el Element, id string) ?Element {
	if el.id == id {
		return el
	}
	for child in el.children {
		if found := feedback_test_find(child, id) {
			return found
		}
	}
	return none
}

fn feedback_test_ids(el Element, prefix string) []string {
	mut ids := []string{}
	if el.id.starts_with(prefix) {
		ids << el.id
	}
	for child in el.children {
		ids << feedback_test_ids(child, prefix)
	}
	return ids
}

fn feedback_test_has_color(el Element, color u32) bool {
	if el.kind == .view && !el.box.transparent && el.box.bg == color {
		return true
	}
	for child in el.children {
		if feedback_test_has_color(child, color) {
			return true
		}
	}
	return false
}

// feedback_test_timeline is the timeline an animated part plays.
fn feedback_test_timeline(part Element) MotionTimeline {
	config := part.motion or { panic('${part.id} has no motion') }
	assert !config.timeline.is_empty(), part.id
	return config.timeline
}

// feedback_test_values is what part presents ms milliseconds into its timeline.
fn feedback_test_values(part Element, ms f64) MotionValues {
	program := compile_motion_timeline(feedback_test_timeline(part)) or { panic(err) }
	position := program.locate(ms / 1000)
	mut channels := motion_channels(element_motion_values(part))
	program.apply(mut channels, position.time)
	return channels.values()
}

// feedback_test_span is the x and width of the box part presents ms
// milliseconds into its timeline.
fn feedback_test_span(part Element, ms f64) (f64, f64) {
	values := feedback_test_values(part, ms)
	return part.frame.x + values.transform.translate_x, part.frame.width * values.box_scale_x
}

fn feedback_test_part(root Element, id string) Element {
	return feedback_test_find(root, id) or { panic('missing part ${id}') }
}

@[heap]
struct FeedbackTestClock {
mut:
	now f64
}

// feedback_test_clocked drives part's motion from clock, so a test can mount
// it on an ElementMotionState and step its time.
fn feedback_test_clocked(part Element, clock MotionClock) Element {
	config := part.motion or { panic('${part.id} has no motion') }
	return Element{
		...part
		motion: MotionConfig{
			...config
			clock: clock
		}
	}
}

fn feedback_test_mount(part Element) &ElementMotionState {
	mut state := new_element_motion_state(part) or { panic(err) }
	state.mount() or { panic(err) }
	return state
}

// Children stay inside their parent and every motion is valid.
fn feedback_assert_local_geometry(el Element) {
	component_validate_frame(el.frame) or { panic(err) }
	if config := el.motion {
		config.validate() or { panic('${el.id}: ${err}') }
	}
	for child in el.children {
		assert child.frame.x >= -1e-6 && child.frame.y >= -1e-6, '${child.id} ${child.frame}'
		assert child.frame.x + child.frame.width <= el.frame.width + 1e-6, '${child.id} ${child.frame} in ${el.frame}'
		assert child.frame.y + child.frame.height <= el.frame.height + 1e-6, '${child.id} ${child.frame} in ${el.frame}'
		feedback_assert_local_geometry(child)
	}
}

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

fn test_feedback_ease_and_inverse_round_trip() {
	assert feedback_ease(0) == 0
	assert feedback_ease(0.5) == 0.5
	assert feedback_ease(1) == 1
	for i in 0 .. 21 {
		t := f64(i) / 20
		assert math.abs(feedback_ease_inverse(feedback_ease(t)) - t) < 1e-9
	}
	assert feedback_fraction(1.25) == 0.25
	assert feedback_fraction(-0.25) == 0.75
	assert feedback_window_contains(0.9, 0.2, 0.95)
	assert feedback_window_contains(0.9, 0.2, 0.1)
	assert !feedback_window_contains(0.9, 0.2, 0.5)
}

fn test_linear_progress_geometry_and_accessibility() {
	theme := component_theme(false)
	el := linear_progress(id: 'upload', frame: rect(10, 20, 200, 20), value: 40, theme: theme) or {
		panic(err)
	}
	assert el.accessibility_role == 'progressbar'
	assert el.accessibility_label == 'Progress'
	assert el.accessibility_value == '40%'
	track := el.children[0]
	assert track.frame == rect(0, 6, 200, 8)
	assert track.box.radius == 4
	assert track.box.bg == feedback_track_color(theme.primary, theme.background)
	indicator := track.children[0]
	assert indicator.frame.width == 80
	assert indicator.box.bg == theme.primary
	small := linear_progress(id: 'small', frame: rect(0, 0, 100, 4), size: .large, value: 120) or {
		panic(err)
	}
	// The preset is limited to the frame, and the value to 100%.
	assert small.children[0].frame.height == 4
	assert small.children[0].children[0].frame.width == 100
	assert small.accessibility_value == '100%'
	square := linear_progress(
		id:          'square'
		frame:       rect(0, 0, 100, 16)
		thickness:   16
		radius:      2
		tone:        .success
		track_color: 0x123456
		theme:       theme
	) or { panic(err) }
	assert square.children[0].box.radius == 2
	assert square.children[0].box.bg == 0x123456
	assert square.children[0].children[0].box.bg == theme.success
	for config in [LinearProgressConfig{}, LinearProgressConfig{
		id:        'a'
		thickness: -1
	}, LinearProgressConfig{
		id:         'a'
		transition: math.nan()
	}, LinearProgressConfig{
		id:     'a'
		radius: -2
	}] {
		if _ := linear_progress(config) {
			assert false, 'invalid linear progress accepted'
		}
	}
}

fn test_linear_progress_value_change_eases_from_the_shown_width() {
	part := component_part_id('upload', 'indicator')
	first := feedback_test_part(linear_progress(id: 'upload', frame: rect(0, 0, 200, 8), value: 40) or {
		panic(err)
	}, part)
	assert first.frame.width == 80
	if !backend_supports_motion {
		assert first.motion == none
		return
	}
	config := first.motion or { panic('the indicator has no motion') }
	assert config.layout == .box
	assert config.transition.duration == 0.25
	assert config.transition.easing == .out_cubic
	assert config.timeline.is_empty()
	// Layout gives the indicator its new width at once; its box grows from the
	// width on screen.
	mut clock := &FeedbackTestClock{}
	tick := fn [clock] () f64 {
		return clock.now
	}
	mut state := feedback_test_mount(feedback_test_clocked(first, tick))
	state.observe_layout(first.frame, true)
	second := feedback_test_part(linear_progress(id: 'upload', frame: rect(0, 0, 200, 8), value: 90) or {
		panic(err)
	}, part)
	assert second.frame.width == 180
	state.update(feedback_test_clocked(second, tick)) or { panic(err) }
	state.observe_layout(second.frame, true)
	assert math.abs(second.frame.width + state.current.layout_offset.width - 80) < 1e-6
	clock.now = 0.125
	state.sample() or { panic(err) }
	middle := second.frame.width + state.current.layout_offset.width
	assert middle > 80 && middle < 180
	clock.now = 1
	state.sample() or { panic(err) }
	assert state.current.layout_offset == Rect{}
	assert !state.current.running
	// The same value again leaves the indicator where it is.
	state.update(feedback_test_clocked(second, tick)) or { panic(err) }
	state.observe_layout(second.frame, true)
	assert !state.current.running
	// Without a transition the width changes at once.
	for settings in [LinearProgressConfig{
		id:         'upload'
		frame:      rect(0, 0, 200, 8)
		value:      10
		transition: 0
	}, LinearProgressConfig{
		id:            'upload'
		frame:         rect(0, 0, 200, 8)
		value:         10
		reduce_motion: true
	}] {
		plain := feedback_test_part(linear_progress(settings) or { panic(err) }, part)
		assert plain.frame.width == 20
		assert plain.motion == none
	}
}

fn test_linear_progress_loading_follows_gpui_curve() {
	left0, right0 := linear_progress_loading_span(0)
	assert left0 == 0 && right0 == 0
	left_half, right_half := linear_progress_loading_span(0.5)
	assert left_half == 0 && right_half == 0.5
	left1, right1 := linear_progress_loading_span(1)
	assert left1 == 1 && right1 == 1
	still := linear_progress(
		id:            'busy'
		frame:         rect(0, 0, 200, 8)
		loading:       true
		reduce_motion: true
	) or {
		panic(err)
	}
	assert still.children[0].children[0].frame == rect(65, 0, 70, 8)
	assert still.children[0].children[0].id == ''
	assert still.children[0].children[0].motion == none
	if !backend_supports_motion {
		return
	}
	el := linear_progress(id: 'busy', frame: rect(0, 0, 200, 8), loading: true) or { panic(err) }
	assert el.accessibility_value == ''
	parts := feedback_test_ids(el, component_part_id('busy', 'loading'))
	assert parts.len == 1
	bar := feedback_test_part(el, parts[0])
	// The bar is laid out across the track once; its loop moves and sizes its box.
	assert bar.frame == rect(0, 0, 200, 8)
	timeline := feedback_test_timeline(bar)
	assert timeline.repeat == motion_forever
	assert math.abs(timeline.duration - 1.0) < 1e-9
	for ms in [250, 500, 750] {
		x, width := feedback_test_span(bar, ms)
		left, right := linear_progress_loading_span(f64(ms) / 1000)
		assert math.abs(x - left * 200) < 2, '${ms}: ${x} ${width}'
		assert math.abs(width - (right - left) * 200) < 2, '${ms}: ${x} ${width}'
	}
	// Leaving the loading state removes the loop, so nothing keeps redrawing.
	done := linear_progress(id: 'busy', frame: rect(0, 0, 200, 8), value: 20) or { panic(err) }
	assert feedback_test_ids(done, parts[0]).len == 0
	// The application's reduced motion preference stills it too.
	set_reduced_motion(true)
	reduced := linear_progress(id: 'busy', frame: rect(0, 0, 200, 8), loading: true) or {
		panic(err)
	}
	set_reduced_motion(false)
	assert reduced.children[0].children[0].frame == rect(65, 0, 70, 8)
	assert reduced.children[0].children[0].motion == none
}

fn test_ring_cells_and_strips_cover_the_ring() {
	if backend_name == 'custom' {
		assert feedback_draws_strips()
		assert !feedback_parent_clips()
	} else if backend_name == 'appkit' {
		assert !feedback_draws_strips()
		assert feedback_parent_clips()
	}
	diameter, stroke := 40.0, 6.0
	ring := (diameter - stroke) / 2
	cells := feedback_ring_cells(diameter, stroke, 0, 1, 4, 0.5)
	assert cells.len == int(math.ceil(2 * math.pi * ring / (stroke * 0.5)))
	for cell in cells {
		cx := cell.frame.x + cell.frame.width / 2
		cy := cell.frame.y + cell.frame.height / 2
		assert math.abs(math.hypot(cx - 20, cy - 20) - ring) < 1e-9
		assert cell.radius == stroke / 2
		turn := feedback_fraction(math.atan2(cx - 20, 20 - cy) / (2 * math.pi))
		assert cell.sector == feedback_sector(turn, 4)
	}
	partial := feedback_ring_cells(diameter, stroke, 0.1, 0.4, 1, 0.5)
	first := partial[0].frame
	last := partial[partial.len - 1].frame
	assert math.abs(first.x + stroke / 2 - (20 + ring * math.sin(0.2 * math.pi))) < 1e-9
	assert math.abs(last.y + stroke / 2 - (20 - ring * math.cos(0.8 * math.pi))) < 1e-9
	strips := feedback_ring_strips(diameter, stroke, 0, 1, 8, 0.5)
	mut area := 0.0
	mut sectors := []bool{len: 8}
	for strip in strips {
		assert strip.radius == 0
		assert strip.frame.x >= -1e-9 && strip.frame.x + strip.frame.width <= diameter + 1e-9
		assert strip.frame.y >= -1e-9 && strip.frame.y + strip.frame.height <= diameter + 1e-9
		area += strip.frame.width * strip.frame.height
		sectors[strip.sector] = true
		middle := strip.frame.x + strip.frame.width / 2 - 20
		y := strip.frame.y + strip.frame.height / 2 - 20
		assert strip.sector == feedback_sector(math.atan2(middle, -y) / (2 * math.pi), 8)
	}
	annulus := math.pi * (20 * 20 - 14 * 14)
	assert math.abs(area - annulus) / annulus < 0.02
	assert !sectors.contains(false)
	// A half ring with round ends covers half the annulus plus one stroke disc.
	half := feedback_ring_strips(diameter, stroke, 0.1, 0.6, 1, 0.25)
	mut half_area := 0.0
	for strip in half {
		half_area += strip.frame.width * strip.frame.height
	}
	expected := annulus / 2 + math.pi * stroke * stroke / 4
	assert math.abs(half_area - expected) / expected < 0.03
	assert feedback_ring_strips(0, 0, 0, 1, 1, 0.5).len == 0
	assert feedback_ring_cells(diameter, stroke, 0.5, 0.2, 1, 0.5).len == 0
}

fn test_progress_circle_geometry_and_accessibility() {
	theme := component_theme(false)
	assert progress_circle_diameter(.small) == 12
	assert progress_circle_diameter(.large) == 20
	assert progress_circle_thickness(16) == 16 * 0.15
	assert progress_circle_thickness(80) == 5
	el := progress_circle(id: 'c', frame: rect(0, 0, 40, 30), value: 50, theme: theme) or {
		panic(err)
	}
	assert el.accessibility_role == 'progressbar'
	assert el.accessibility_value == '50%'
	box := el.children[0]
	assert box.frame == rect(12, 7, 16, 16)
	// Track disc, background hole, then the arc.
	assert box.children[0].box.bg == feedback_track_color(theme.primary, theme.background)
	assert box.children[0].box.radius == 8
	assert box.children[1].box.bg == theme.background
	assert box.children[1].frame == rect(2.4, 2.4, 11.2, 11.2)
	arc := box.children[2..]
	assert arc.len > 0
	for piece in arc {
		assert piece.box.bg == theme.primary
		assert piece.frame.x + piece.frame.width / 2 >= 8 - 1e-9
	}
	full := progress_circle(id: 'c', frame: rect(0, 0, 16, 16), value: 100, theme: theme) or {
		panic(err)
	}
	assert full.children[0].children.len == 2
	assert full.children[0].children[0].box.bg == theme.primary
	empty := progress_circle(id: 'c', frame: rect(0, 0, 16, 16), value: 0, background: 0x101010) or {
		panic(err)
	}
	assert empty.children[0].children.len == 2
	assert empty.children[0].children[1].box.bg == 0x101010
	labelled := progress_circle(
		id:       'c'
		frame:    rect(0, 0, 100, 100)
		diameter: 80
		value:    75
		label:    '75%'
		caption:  'Uploaded'
		size:     .large
		children: [label('extra', 'x', rect(0, 0, 10, 10), TextStyle{})]
	) or { panic(err) }
	texts := labelled.children[0].children.filter(it.kind == .label)
	assert texts.len == 3
	assert texts[0].text == '75%'
	assert texts[1].text == 'Uploaded'
	assert texts[1].frame.y >= texts[0].frame.y + texts[0].frame.height - 1e-9
	assert texts[2].id == 'extra'
	turns_first, turns_last := progress_circle_lit_turns(50, 7, 2)
	cap := 1.0 / (2 * math.pi * 7)
	assert math.abs(turns_first - cap) < 1e-12
	assert math.abs(turns_last - (0.5 - cap)) < 1e-12
	tiny_first, tiny_last := progress_circle_lit_turns(1, 7, 2)
	assert tiny_first == tiny_last
	if _ := progress_circle(id: 'c', thickness: -1) {
		assert false, 'negative thickness accepted'
	}
	if _ := progress_circle(frame: rect(0, 0, 16, 16)) {
		assert false, 'progress circle accepted without identity'
	}
}

fn test_progress_circle_loading_runs_the_gpui_arc() {
	start0, end0 := progress_circle_loading_arc(0)
	assert start0 == 0 && end0 == 0
	start_half, end_half := progress_circle_loading_arc(0.5)
	assert start_half == 0 && end_half == 0.5
	on, off := progress_circle_sector_window(0.5)
	assert math.abs(on - 0.5) < 1e-9
	assert math.abs(off - 0.75) < 1e-9
	still := progress_circle(
		id:            'spin'
		frame:         rect(0, 0, 32, 32)
		diameter:      32
		loading:       true
		reduce_motion: true
	) or {
		panic(err)
	}
	assert feedback_test_ids(still, component_part_id('spin', '')).len == 0
	assert still.children[0].children.len > 2
	if !backend_supports_motion {
		return
	}
	el := progress_circle(id: 'spin', frame: rect(0, 0, 32, 32), diameter: 32, loading: true) or {
		panic(err)
	}
	assert el.accessibility_value == ''
	parts := feedback_test_ids(el, component_part_id('spin', 'loading:'))
	assert parts.len > 12
	// Halfway through the cycle the arc covers the first half of the ring.
	mut visible := 0
	for id in parts {
		part := feedback_test_part(el, id)
		assert feedback_test_timeline(part).repeat == motion_forever
		opacity := feedback_test_values(part, 500).opacity
		assert opacity == 0 || opacity == 1
		if opacity == 1 {
			visible++
		}
	}
	assert visible > 0 && visible < parts.len
}

fn test_loading_spinner_kinds_sizes_and_colors() {
	theme := component_theme(false)
	assert loading_spinner_diameter(.small) == 14
	assert loading_spinner_diameter(.large) == 24
	dots := loading_spinner(id: 'dots', frame: rect(0, 0, 30, 20), theme: theme) or { panic(err) }
	assert dots.accessibility_role == 'progressbar'
	assert dots.accessibility_label == 'Loading'
	box := dots.children[0]
	assert box.frame == rect(7, 2, 16, 16)
	assert box.children.len == spinner_dot_count
	// At rest the head is the first dot, at twelve o'clock, in full color.
	assert box.children[0].box.bg == theme.muted_foreground
	assert math.abs(box.children[0].frame.y) < 1e-9
	assert box.children[1].box.bg != theme.muted_foreground
	if backend_supports_motion {
		for dot in box.children {
			assert feedback_test_timeline(dot).repeat == motion_forever
		}
		// Halfway round, the dot opposite twelve o'clock is the head.
		assert feedback_test_values(box.children[4], 400).paint.background == theme.muted_foreground
		assert feedback_test_values(box.children[0], 400).paint.background != theme.muted_foreground
	}
	ring := loading_spinner(
		id:         'ring'
		frame:      rect(0, 0, 24, 24)
		kind:       .ring
		size:       .large
		tone:       .primary
		background: 0x000000
		theme:      theme
	) or { panic(err) }
	ring_box := ring.children[0]
	assert ring_box.frame.width == 24
	assert ring_box.children[0].box.bg == feedback_track_color(theme.primary, 0x000000)
	assert ring_box.children[1].box.bg == 0x000000
	if backend_supports_motion {
		ring_parts := feedback_test_ids(ring, component_part_id('ring', 'spin:'))
		assert ring_parts.len > 0
		for part in ring_parts {
			assert feedback_test_timeline(feedback_test_part(ring, part)).repeat == motion_forever
		}
	}
	for config in [LoadingSpinnerConfig{}, LoadingSpinnerConfig{
		id:       's'
		diameter: -1
	}, LoadingSpinnerConfig{
		id:       's'
		duration: math.inf(1)
	}] {
		if _ := loading_spinner(config) {
			assert false, 'invalid spinner accepted'
		}
	}
}

fn test_spinner_windows_follow_the_eased_head() {
	assert spinner_dot_level(0) == 1
	assert math.abs(spinner_dot_level(0.375) - 0.5) < 1e-9
	assert spinner_dot_level(0.8) == 0
	assert spinner_dot_level(-0.03125) == 0.5
	for i in 0 .. 12 {
		turn := f64(i) / 12
		on, off := spinner_ring_window(turn)
		for k in 1 .. 40 {
			t := f64(k) / 40
			behind := feedback_fraction(loading_spinner_head(t) - turn)
			if math.abs(behind) < 1e-6 || math.abs(behind - spinner_ring_arc) < 1e-6 {
				continue
			}
			assert feedback_window_contains(on, off, t) == (behind < spinner_ring_arc), '${turn} ${t}'
		}
	}
}

fn test_feedback_loops_restart_on_new_settings() {
	still := loading_spinner(id: 'busy', frame: rect(0, 0, 16, 16), reduce_motion: true) or {
		panic(err)
	}
	assert feedback_test_ids(still, component_part_id('busy', '')).len == 0
	if !backend_supports_motion {
		return
	}
	first := loading_spinner(id: 'busy', frame: rect(0, 0, 16, 16)) or { panic(err) }
	parts := feedback_test_ids(first, component_part_id('busy', 'spin:'))
	assert parts.len == spinner_dot_count
	recolored := loading_spinner(id: 'busy', frame: rect(0, 0, 16, 16), color: 0xff0000) or {
		panic(err)
	}
	again := loading_spinner(id: 'busy', frame: rect(0, 0, 16, 16), color: 0xff0000) or {
		panic(err)
	}
	// Parts keep their ids; a new color is a new timeline, which starts over.
	assert feedback_test_ids(recolored, component_part_id('busy', 'spin:')) == parts
	mut clock := &FeedbackTestClock{}
	tick := fn [clock] () f64 {
		return clock.now
	}
	mut state := feedback_test_mount(feedback_test_clocked(feedback_test_part(first, parts[0]),
		tick))
	assert state.timeline_on && state.timeline_start == 0
	clock.now = 0.3
	state.update(feedback_test_clocked(feedback_test_part(recolored, parts[0]), tick)) or {
		panic(err)
	}
	assert state.timeline_on && state.timeline_start == 0.3
	// Rebuilding with the same settings keeps the running loop.
	clock.now = 0.5
	state.update(feedback_test_clocked(feedback_test_part(again, parts[0]), tick)) or {
		panic(err)
	}
	assert state.timeline_on && state.timeline_start == 0.3
	// A ring only shows and hides its cells, so a new color keeps its loops.
	ring := loading_spinner(id: 'arc', kind: .ring, frame: rect(0, 0, 16, 16)) or { panic(err) }
	ring_parts := feedback_test_ids(ring, component_part_id('arc', 'spin:'))
	red_ring := loading_spinner(id: 'arc', kind: .ring, frame: rect(0, 0, 16, 16), color: 0xff0000) or {
		panic(err)
	}
	assert feedback_test_ids(red_ring, component_part_id('arc', 'spin:')) == ring_parts
	for id in ring_parts {
		assert feedback_test_timeline(feedback_test_part(red_ring, id)) == feedback_test_timeline(feedback_test_part(ring,
			id))
	}
	assert feedback_test_has_color(red_ring, 0xff0000)
	// Moving a shimmer shape restarts its sweep.
	sheen := shimmer(
		id:     'sheen'
		frame:  rect(0, 0, 100, 10)
		shapes: shimmer_paragraph(0, 0,
			100, 1, 10, 0)
	) or { panic(err) }
	moved := shimmer(
		id:     'sheen'
		frame:  rect(0, 0, 100, 10)
		shapes: shimmer_paragraph(10, 0,
			80, 1, 10, 0)
	) or { panic(err) }
	band := sheen.children[0].children[0]
	moved_band := moved.children[0].children[0]
	assert band.id == moved_band.id
	assert feedback_test_timeline(band) != feedback_test_timeline(moved_band)
	// The application's reduced motion preference stills every loop.
	set_reduced_motion(true)
	reduced := loading_spinner(id: 'busy', frame: rect(0, 0, 16, 16)) or { panic(err) }
	set_reduced_motion(false)
	assert feedback_test_ids(reduced, component_part_id('busy', '')).len == 0
}

fn test_feedback_toggle_and_level_loops() {
	toggle := feedback_toggle_loop(2, 0.25, 0.5)
	assert math.abs(toggle.duration - 2) < 1e-9
	assert toggle.repeat == motion_forever
	start := view('part', rect(0, 0, 4, 4), BoxStyle{}, []Element{})
	shown := feedback_motion(start, toggle)
	assert feedback_test_values(shown, 100).opacity == 0
	assert feedback_test_values(shown, 750).opacity == 1
	assert feedback_test_values(shown, 1500).opacity == 0
	wrapped := feedback_motion(start, feedback_toggle_loop(1, 0.75, 0.25))
	assert feedback_test_values(wrapped, 100).opacity == 1
	assert feedback_test_values(wrapped, 500).opacity == 0
	assert feedback_test_values(wrapped, 900).opacity == 1
	keys := feedback_compact_keys([FeedbackKey{0, 0}, FeedbackKey{0.25, 0.5}, FeedbackKey{0.5, 1},
		FeedbackKey{0.75, 1}, FeedbackKey{1, 1}])
	assert keys == [FeedbackKey{0, 0}, FeedbackKey{0.5, 1}, FeedbackKey{1, 1}]
	level := feedback_motion(start, feedback_level_loop(1, keys, 0x000000, 0xffffff, .background,
		true))
	assert feedback_test_values(level, 250).paint.background == 0x808080
	assert feedback_test_values(level, 750).paint.background == 0xffffff
	text_loop := feedback_level_loop(1, keys, 0x000000, 0xffffff, .text_color, false)
	// A loop played once keeps its final values.
	assert text_loop.repeat == 0 && text_loop.hold
	text := feedback_motion(start, text_loop)
	assert feedback_test_values(text, 250).paint.text_color == 0x808080
	assert feedback_times(4, [0.3, 0.3, 2.0, math.nan()]) == [0.0, 0.25, 0.3, 0.5, 0.75, 1.0]
	// Spans move and scale a box laid out once.
	span := feedback_motion(view('bar', rect(10, 0, 100, 4), BoxStyle{}, []Element{}),
		feedback_span_loop(1, [FeedbackSpan{0, 10, 0}, FeedbackSpan{1, 60, 50}], 10, 100, true))
	x, width := feedback_test_span(span, 500)
	assert math.abs(x - 35) < 1e-9 && math.abs(width - 25) < 1e-9
}

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
	inner_x, inner_w := shimmer_band_span(50, half / shimmer_layer_count, 0, 100)
	assert inner_x > outer_x && inner_w < outer_w
	// An absolute spread keeps the band the same width across text widths.
	_, narrow := shimmer_band_span(50, 20, 0, 100)
	_, wide := shimmer_band_span(100, 20, 0, 200)
	assert narrow == 40 && wide == 40
	assert math.abs(shimmer_band_time(shimmer_band_center(0.4, 100, half, true), 100, half,
		true) - 0.4) < 1e-9
	// Keyframes for a shape cover the whole sweep and are empty at both ends.
	spans := shimmer_band_spans(400, 120, false, 100, 200, 6)
	assert spans[0].at == 0 && spans[0].width == 0
	assert spans[spans.len - 1].at == 1 && spans[spans.len - 1].width == 0
	for span in spans {
		assert span.x >= 6 - 1e-9 && span.x + span.width <= 206 + 1e-9
	}
}

fn test_shimmer_shapes_bands_and_once() {
	theme := component_theme(false)
	mut shapes := [ShimmerShape{
		frame:  rect(0, 0, 40, 40)
		circle: true
	}]
	shapes << shimmer_paragraph(50, 0, 200, 3, 12, 8)
	assert shapes.len == 4
	assert shapes[3].frame == rect(50, 40, 120, 12)
	assert shapes[1].radius == 6
	el := shimmer(id: 'card', frame: rect(0, 0, 260, 60), shapes: shapes, theme: theme) or {
		panic(err)
	}
	assert el.accessibility_role == 'status'
	assert el.accessibility_label == 'Loading'
	base := shimmer_base_color(theme)
	assert el.children[0].children[0].box.bg == base
	assert el.children[0].children[0].id.starts_with(component_part_id('card', 'sheen:'))
	still := shimmer(id: 'card', frame: rect(0, 0, 260, 60), shapes: shapes, reduce_motion: true) or {
		panic(err)
	}
	assert still.children[1].children.len == 0
	feedback_assert_local_geometry(el)
	if !backend_supports_motion {
		return
	}
	for line in el.children[1..] {
		assert line.box.bg == base
		assert line.children.len == shimmer_layer_count
		for band in line.children {
			// A band is laid out across its shape and starts out of sight.
			_, width := feedback_test_span(band, 0)
			assert width == 0
			assert feedback_test_timeline(band).repeat == motion_forever
		}
	}
	_, mid := feedback_test_span(el.children[1].children[0], 1000)
	assert mid > 0
	once := shimmer(
		id:       'once'
		frame:    rect(0, 0, 100, 10)
		shapes:   shimmer_paragraph(0, 0, 100,
			1, 10, 0)
		once:     true
		duration: 0.5
	) or { panic(err) }
	first := once.children[0].children[0]
	timeline := feedback_test_timeline(first)
	assert timeline.repeat == 0 && timeline.hold
	// After its sweep the band stays out of sight.
	_, rest := feedback_test_span(first, 600)
	assert rest == 0
	// Building it again keeps the sweep that already played.
	again := shimmer(
		id:       'once'
		frame:    rect(0, 0, 100, 10)
		shapes:   shimmer_paragraph(0, 0, 100, 1,
			10, 0)
		once:     true
		duration: 0.5
	) or { panic(err) }
	assert feedback_test_timeline(again.children[0].children[0]) == timeline
	if _ := shimmer(id: 'x', duration: math.nan()) {
		assert false, 'non-finite duration accepted'
	}
	if _ := shimmer(
		id:     'x'
		shapes: [ShimmerShape{
			frame:  rect(0, 0, 10, 10)
			radius: -1
		}]
	) {
		assert false, 'negative radius accepted'
	}
}

fn test_shimmer_colors_follow_the_theme() {
	light := component_theme(false)
	dark := component_theme(true)
	assert !feedback_is_dark(light)
	assert feedback_is_dark(dark)
	light_base := shimmer_base_color(light)
	assert feedback_luminance(shimmer_highlight_default(light, light_base)) > feedback_luminance(light_base)
	dark_base := shimmer_base_color(dark)
	assert dark_base == dark.muted
	assert feedback_luminance(shimmer_highlight_default(dark, dark_base)) > feedback_luminance(dark_base)
	// Text moves toward the background in a light theme and the foreground in
	// a dark one, or to the other end when it already has that lightness.
	assert feedback_luminance(shimmer_text_highlight(light.foreground, light)) > feedback_luminance(light.foreground)
	assert feedback_luminance(shimmer_text_highlight(dark.muted_foreground, dark)) > feedback_luminance(dark.muted_foreground)
	assert feedback_luminance(shimmer_text_highlight(0xffffff, dark)) < 0.75
	assert feedback_luminance(shimmer_text_highlight(0xffffff, light)) < 0.75
}

fn test_shimmer_text_pulses_its_label() {
	theme := component_theme(false)
	el := shimmer_text(
		id:    'thinking'
		frame: rect(0, 0, 120, 20)
		text:  'Thinking…'
		theme: theme
	) or {
		panic(err)
	}
	text_label := el.children[0]
	assert text_label.kind == .label
	assert text_label.text == 'Thinking…'
	assert text_label.accessibility_label == 'Thinking…'
	assert text_label.text_style.color == theme.foreground
	assert text_label.text_style.size == 14
	if backend_supports_motion {
		assert feedback_test_timeline(text_label).repeat == motion_forever
		peak := feedback_test_values(text_label, 1000)
		assert peak.paint.text_color == shimmer_text_highlight(theme.foreground, theme)
	}
	plain := shimmer_text(
		id:            'thinking'
		frame:         rect(0, 0, 120, 20)
		text:          'Done'
		reduce_motion: true
	) or {
		panic(err)
	}
	assert plain.children[0].id == ''
	assert plain.children[0].motion == none
	if _ := shimmer_text(id: 'x', font_size: -1) {
		assert false, 'negative font size accepted'
	}
}

fn test_icon_names_map_to_portable_symbols() {
	names := icon_names()
	assert names.len == int(IconName.users) + 1
	mut seen := map[string]bool{}
	for name in names {
		symbol := name.symbol()
		assert symbol_known(symbol), '${name}: ${symbol}'
		seen[name.str()] = true
	}
	assert seen.len == names.len
	assert IconName.eye_off.title() == 'Eye off'
	assert IconName.search.symbol() == 'magnifyingglass'
	assert IconName.padlock.symbol() == 'lock'
}

fn test_named_icon_geometry_tint_and_accessibility() {
	theme := component_theme(true)
	el := named_icon(id: 'find', frame: rect(10, 10, 40, 20), name: .search, theme: theme) or {
		panic(err)
	}
	assert el.kind == .image
	assert el.image_path == 'symbol:magnifyingglass'
	assert el.frame == rect(22, 12, 16, 16)
	assert el.text_style.color == theme.foreground
	assert el.accessibility_role == 'img'
	assert el.accessibility_label == 'Search'
	big := named_icon(
		name:                .star
		pixel_size:          64
		color:               0xff0000
		rotation:            90
		frame:               rect(0, 0,
			32, 48)
		accessibility_label: 'Favorite'
	) or { panic(err) }
	assert big.frame == rect(0, 8, 32, 32)
	assert big.text_style.color == 0xff0000
	assert big.rotation == 90
	assert big.accessibility_label == 'Favorite'
	assert icon_pixel_size(.small) == 14
	assert icon_pixel_size(.large) == 24
	custom := named_icon(symbol: 'tag', frame: rect(0, 0, 16, 16)) or { panic(err) }
	assert custom.image_path == 'symbol:tag'
	assert custom.accessibility_label == 'tag'
	if _ := named_icon(symbol: 'no.such.glyph') {
		assert false, 'symbol without a glyph on every backend accepted'
	}
	if _ := named_icon(pixel_size: math.nan()) {
		assert false, 'non-finite icon size accepted'
	}
	if _ := named_icon(rotation: math.inf(-1)) {
		assert false, 'non-finite rotation accepted'
	}
}

fn test_feedback_components_handle_tiny_frames() {
	for extent in [0.0, 0.5, 1.0, 8.0, 32.0, 200.0] {
		frame := rect(10, 20, extent, extent / 2)
		elements := [
			linear_progress(id: 'bar', frame: frame, value: 50) or { panic(err) },
			linear_progress(id: 'busy', frame: frame, loading: true) or { panic(err) },
			progress_circle(id: 'ring', frame: frame, value: 60, label: '60%', caption: 'x') or {
				panic(err)
			},
			progress_circle(id: 'wait', frame: frame, loading: true) or { panic(err) },
			loading_spinner(id: 'dots', frame: frame) or { panic(err) },
			loading_spinner(id: 'arc', frame: frame, kind: .ring) or { panic(err) },
			shimmer(
				id:     'sheen'
				frame:  frame
				shapes: [ShimmerShape{
					frame: rect(0, 0, extent, extent / 2)
				}, ShimmerShape{
					frame:  rect(0, 0, extent / 2, extent / 2)
					circle: true
				}]
			) or { panic(err) },
			shimmer_text(id: 'text', frame: frame, text: 'Loading') or { panic(err) },
		]
		for el in elements {
			feedback_assert_local_geometry(el)
		}
		named_icon(frame: frame, name: .plus) or { panic(err) }
	}
}
