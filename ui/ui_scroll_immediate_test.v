// vtest vflags: -d vml_fixtures
// vfmt off
@[has_globals]
module ui2

// vml: fixtures/ui_scroll_immediate_0.vml
// vml: fixtures/ui_scroll_immediate_1.vml
// vml: fixtures/ui_scroll_immediate_2.vml
// vml: fixtures/ui_scroll_immediate_3.vml

$if (android || linux || ((ios || macos || windows) && ui2_custom_rendering ?)) && !ui2_headless ? {
	__global scroll_test_events = []string{}
	__global scroll_test_payloads = []ElementEvent{}
	__global scroll_test_measurements = 0

	fn reset_scroll_test_state(mut w Window) {
		w.reset_scroll_frame()
		w.scroll_offsets = map[string]f64{}
		w.pending_scroll = map[string]f64{}
		w.scroll_content_h = map[string]f64{}
		w.scroll_offsets_x = map[string]f64{}
		w.pending_scroll_x = map[string]f64{}
		w.scroll_content_w = map[string]f64{}
		w.active_scrolls = map[string]bool{}
		w.active_fields = map[string]bool{}
		w.text_values = map[string]string{}
		w.text_props = map[string]string{}
		w.text_kinds = map[string]Kind{}
		w.text_editors = map[string]TextEditor{}
		w.clear_text_area_layouts()
		w.hit_targets = []HitTarget{}
		w.touch = TouchState{}
		w.focused_field = ''

		scroll_test_events = []string{}
		scroll_test_payloads = []ElementEvent{}
		scroll_test_measurements = 0
		w.close_dropdown()
	}

	fn scroll_test_width(line string) f64 {
		scroll_test_measurements++
		return f64(line.runes().len) * 10
	}

	fn scroll_test_changed(event ElementEvent) {
		assert event.kind == .scroll
		scroll_test_events << event.id
		scroll_test_payloads << event
	}

	fn scroll_test_target(id string) HitTarget {
		return HitTarget{ id: id, on_event: scroll_test_changed }
	}

	$if android || ios {
		fn test_text_area_wraps_words_and_preserves_explicit_blank_lines() {
			mut w := &Window{}
			reset_scroll_test_state(mut w)
			assert wrap_text_area_lines('one two three', 70, scroll_test_width) == ['one two', 'three']
			assert wrap_text_area_lines('one\r\n\r\ntwo\n', 100, scroll_test_width) == ['one', '', 'two', '']
			assert wrap_text_area_lines('', 100, scroll_test_width) == ['']
			assert wrap_text_area_lines('one\ttwo', 30, scroll_test_width) == ['one', 'two']
		}
	}

	fn test_page_navigation_scrolls_the_focused_text_area() {
		mut w := &Window{}
		reset_scroll_test_state(mut w)
		frame := rect(0, 0, 100, 80)
		w.register_scroll_view_in_parent(named_scroll_state_id('notes'), '', frame, frame, 400, true, true, false, scroll_test_target('notes'))
		w.focused_field = 'notes'
		w.page_focused_text_area(1)
		assert w.scroll_offset('notes') == 80
		w.page_focused_text_area(10)
		assert w.scroll_offset('notes') == 320
		w.page_focused_text_area(-1)
		assert w.scroll_offset('notes') == 240
	}

	$if android || ios {
		fn test_text_area_wraps_long_words_without_splitting_utf8_bytes() {
			mut w := &Window{}
			reset_scroll_test_state(mut w)
			assert wrap_text_area_lines('é界🙂abcd', 30, scroll_test_width) == ['é界🙂', 'abc', 'd']
			assert wrap_text_area_lines('é界', 1, scroll_test_width) == ['é', '界']
			assert wrap_text_area_lines('abc', 0, scroll_test_width).len == 0
			assert wrap_text_area_lines('abc', -1, scroll_test_width).len == 0
		}
	}

	$if android || ios {
		fn test_text_area_does_not_limit_content_to_one_thousand_lines() {
			mut w := &Window{}
			reset_scroll_test_state(mut w)
			mut lines := []string{}
			for index in 0 .. 1105 {
				lines << 'line ${index}'
			}
			assert wrap_text_area_lines(lines.join('\n'), 500, scroll_test_width) == lines
		}
	}

	$if android || ios {
		fn test_text_area_wrap_cache_tracks_text_width_and_font_changes() {
			mut w := &Window{}
			reset_scroll_test_state(mut w)
			style := TextStyle{}
			assert w.text_area_lines('text', 'abcdef', 30, style, 15, scroll_test_width) == ['abc', 'def']
			measured := scroll_test_measurements
			assert w.text_area_lines('text', 'abcdef', 30, style, 15, scroll_test_width) == ['abc', 'def']
			assert scroll_test_measurements == measured
			assert w.text_area_lines('text', 'abcdef', 60, style, 15, scroll_test_width) == ['abcdef']
			assert w.text_area_lines('text', 'new', 60, style, 15, scroll_test_width) == ['new']
			before_font := scroll_test_measurements
			w.text_area_lines('text', 'new', 60, TextStyle{size: 20}, 20, scroll_test_width)
			assert scroll_test_measurements > before_font
		}
	}

	fn test_text_area_content_is_top_aligned_and_clipped_inside_its_pane() {
		content := text_area_content_rect(rect(20, 100, 200, 216), 12, true)
		assert content == rect(32, 108, 176, 200)
		$if android || ios {
			first, last := visible_text_area_rows(100, content.y, 20, 0, content)
			assert first == 0
			assert last == 10
			bottom_first, bottom_last := visible_text_area_rows(100, content.y, 20, 1800, content)
			assert bottom_first == 90
			assert bottom_last == 100
			parent_clip := intersect_rect(content, rect(0, 138, 150, 70))
			assert parent_clip == rect(32, 138, 118, 70)
			clipped_first, clipped_last := visible_text_area_rows(100, content.y, 20, 0, parent_clip)
			assert clipped_first == 1
			assert clipped_last == 5
			empty_first, empty_last := visible_text_area_rows(100, content.y, 20, 0, Rect{})
			assert empty_first == 0
			assert empty_last == 0
		}

		small := text_area_content_rect(rect(0, 0, 10, 10), 12, true)
		assert small.width == 0
		assert small.height == 0
	}

	fn scroll_test_panes(mut w Window) {
		clip := rect(0, 0, 300, 200)
		// Read-only text areas register exactly like editable areas: registration
		// is outside the editable hit-target branch in render_element.
		w.register_scroll_view_in_parent(named_scroll_state_id('info'), '', rect(0, 0, 100, 100), clip, 400, true, true, false, scroll_test_target('info'))
		w.register_scroll_view_in_parent(named_scroll_state_id('text'), '', rect(120, 0, 100, 100), clip, 1000, true, true, false, scroll_test_target('text'))
	}

	fn test_readonly_panes_scroll_independently_with_wheel_and_drag() {
		mut w := &Window{}
		reset_scroll_test_state(mut w)
		scroll_test_panes(mut w)
		scroll_test_events = []string{}
		scroll_test_payloads = []ElementEvent{}
		w.handle_mouse_scroll_vector(150, 50, 0, -2)
		assert w.scroll_offset('text') == 96
		assert w.scroll_offset('info') == 0
		w.handle_mouse_scroll_vector(50, 50, 0, -1)
		assert w.scroll_offset('info') == 48
		w.handle_mouse_scroll_vector(110, 50, 0, -1)
		assert w.scroll_offset('info') == 48
		assert w.scroll_offset('text') == 96
		w.handle_touch_down(150, 80)
		w.handle_touch_move(150, 30)
		w.handle_touch_up(150, 30)
		assert w.scroll_offset('text') == 146
		assert w.scroll_offset('info') == 48
		assert w.focused_field == ''
		assert scroll_test_events == ['text', 'info', 'text']
	}

	fn test_text_area_scroll_clamps_at_both_ends() {
		mut w := &Window{}
		reset_scroll_test_state(mut w)
		scroll_test_panes(mut w)
		scroll_test_events = []string{}
		scroll_test_payloads = []ElementEvent{}
		w.handle_mouse_scroll_vector(150, 50, 0, -1000)
		assert w.scroll_offset('text') == 900
		w.handle_mouse_scroll_vector(150, 50, 0, -1000)
		assert scroll_test_events.len == 1
		w.handle_mouse_scroll_vector(150, 50, 0, 1000)
		assert w.scroll_offset('text') == 0
		w.handle_mouse_scroll_vector(150, 50, 0, 1000)
		assert scroll_test_events == ['text', 'text']
	}

	fn test_text_area_scroll_survives_rebuild_and_clamps_after_resize_or_edit() {
		mut w := &Window{}
		reset_scroll_test_state(mut w)
		scroll_test_panes(mut w)
		w.handle_mouse_scroll_vector(150, 50, 0, -2)
		w.reset_scroll_frame()
		clip := rect(0, 0, 500, 500)
		assert w.register_scroll_view_in_parent(named_scroll_state_id('text'), '', rect(120, 0, 200, 200), clip, 1000, true, true, false, scroll_test_target('text')) == 96
		scroll_test_events = []string{}
		scroll_test_payloads = []ElementEvent{}
		w.reset_scroll_frame()
		assert w.register_scroll_view_in_parent(named_scroll_state_id('text'), '', rect(120, 0, 200, 950), clip, 1000, true, true, false, scroll_test_target('text')) == 50
		w.reset_scroll_frame()
		assert w.register_scroll_view_in_parent(named_scroll_state_id('text'), '', rect(120, 0, 200, 950), clip, 30, true, true, false, scroll_test_target('text')) == 0
		assert scroll_test_events == ['text', 'text']
	}

	fn test_text_area_scroll_hit_testing_uses_visible_clip_and_inner_first_order() {
		mut w := &Window{}
		reset_scroll_test_state(mut w)
		clip := rect(0, 0, 300, 300)
		w.register_scroll_view_in_parent(named_scroll_state_id('outer'), '', clip, clip, 1000, true, true, false, scroll_test_target('outer'))
		w.register_scroll_view_in_parent(named_scroll_state_id('inner'), '', rect(20, 20, 100, 200), rect(0, 0, 300, 100), 1000,
			true, true, false, scroll_test_target('inner'))
		assert w.scroll_maximum(named_scroll_state_id('inner')) == 800
		assert w.scroll_areas[named_scroll_state_id('inner')] == rect(20, 20, 100, 80)
		w.handle_mouse_scroll_vector(50, 50, 0, -1)
		assert w.scroll_offset('inner') == 48
		assert w.scroll_offset('outer') == 0
		w.handle_mouse_scroll_vector(50, 150, 0, -1)
		assert w.scroll_offset('outer') == 48
		assert w.scroll_offset('inner') == 48
	}

	fn test_scroll_hit_testing_falls_through_a_fitted_child_to_its_parent() {
		mut w := &Window{}
		reset_scroll_test_state(mut w)
		clip := rect(0, 0, 300, 300)
		w.register_scroll_view_in_parent(named_scroll_state_id('outer'), '', clip, clip, 1000, true, true, false, scroll_test_target('outer'))
		w.register_scroll_view_in_parent(named_scroll_state_id('inner'), '', rect(20, 20, 100, 100), clip, 100, true, true,
			false, scroll_test_target('inner'))
		assert w.scroll_maximum(named_scroll_state_id('inner')) == 0
		assert w.scroll_hit_test(50, 50) == named_scroll_state_id('outer')
		w.handle_mouse_scroll_vector(50, 50, 0, -1)
		assert w.scroll_offset('inner') == 0
		assert w.scroll_offset('outer') == 48
	}

	fn nested_scroll_test_panes(mut w Window) {
		clip := rect(0, 0, 300, 300)
		w.register_scroll_view_in_parent(named_scroll_state_id('outer'), '', clip, clip, 1200, true, true, false, scroll_test_target('outer'))
		w.register_scroll_view_in_parent(named_scroll_state_id('inner'), named_scroll_state_id('outer'), rect(20, 20, 100, 100), clip,
			200, true, true, false, scroll_test_target('inner'))
	}

	fn test_mouse_wheel_chains_remaining_delta_to_a_parent_at_child_boundary() {
		mut w := &Window{}
		reset_scroll_test_state(mut w)
		nested_scroll_test_panes(mut w)
		w.set_scroll_offset(named_scroll_state_id('inner'), 80, w.scroll_maximum(named_scroll_state_id('inner')))
		scroll_test_events = []string{}
		scroll_test_payloads = []ElementEvent{}

		w.handle_mouse_scroll_vector(50, 50, 0, -1)
		assert w.scroll_offset('inner') == 100
		assert w.scroll_offset('outer') == 28
		w.handle_mouse_scroll_vector(50, 50, 0, -1)
		assert w.scroll_offset('inner') == 100
		assert w.scroll_offset('outer') == 76
		assert scroll_test_events == ['inner', 'outer', 'outer']

		w.set_scroll_offset(named_scroll_state_id('inner'), 0, w.scroll_maximum(named_scroll_state_id('inner')))
		scroll_test_events = []string{}
		w.handle_mouse_scroll_vector(50, 50, 0, 1)
		assert w.scroll_offset('inner') == 0
		assert w.scroll_offset('outer') == 28
		assert scroll_test_events == ['outer']
	}

	fn test_touch_drag_chains_remaining_delta_and_reverses_into_the_child() {
		mut w := &Window{}
		reset_scroll_test_state(mut w)
		nested_scroll_test_panes(mut w)
		w.set_scroll_offset(named_scroll_state_id('inner'), 80, w.scroll_maximum(named_scroll_state_id('inner')))
		scroll_test_events = []string{}
		scroll_test_payloads = []ElementEvent{}

		w.handle_touch_down(50, 80)
		w.handle_touch_move(50, 30)
		assert w.scroll_offset('inner') == 100
		assert w.scroll_offset('outer') == 30
		w.handle_touch_move(50, 0)
		assert w.scroll_offset('inner') == 100
		assert w.scroll_offset('outer') == 60
		w.handle_touch_move(50, 40)
		assert w.scroll_offset('inner') == 60
		assert w.scroll_offset('outer') == 60
		w.handle_touch_up(50, 40)
		assert scroll_test_events == ['inner', 'outer', 'outer', 'inner']
	}

	fn test_touch_drag_keeps_its_parent_chain_when_the_child_is_culled() {
		mut w := &Window{}
		reset_scroll_test_state(mut w)
		nested_scroll_test_panes(mut w)
		w.set_scroll_offset(named_scroll_state_id('inner'), 80, w.scroll_maximum(named_scroll_state_id('inner')))

		w.handle_touch_down(50, 80)
		assert w.touch.scroll_chain == [named_scroll_state_id('inner'), named_scroll_state_id('outer')]
		w.handle_touch_move(50, 30)
		assert w.scroll_offset('inner') == 100
		assert w.scroll_offset('outer') == 30

		// Simulate the next frame after the parent has moved the child outside
		// its viewport. Only the parent is registered, but the renderer retains
		// scroll state from the child's still-mounted element subtree.
		w.active_scrolls = map[string]bool{}
		w.reset_scroll_frame()
		clip := rect(0, 0, 300, 300)
		w.register_scroll_view_in_parent(named_scroll_state_id('outer'), '', clip, clip, 1200, true, true, false, scroll_test_target('outer'))
		w.retain_culled_scroll_state(Element{
			kind: .view
			children: [Element{
				kind: .scroll
				id: 'inner'
			}]
		}, 'root')
		w.prune_unmounted_state()
		assert named_scroll_state_id('inner') !in w.scroll_viewports
		assert w.scroll_offset('inner') == 100
		assert w.scroll_content_h[named_scroll_state_id('inner')] == 200
		assert w.scroll_parents.len == 0

		w.handle_touch_move(50, 0)
		assert w.scroll_offset('outer') == 60
		w.handle_touch_move(50, 40)
		assert w.scroll_offset('outer') == 20

		// Re-registering the child after it re-enters the viewport restores its
		// previous position instead of jumping back to the top.
		w.reset_scroll_frame()
		w.register_scroll_view_in_parent(named_scroll_state_id('outer'), '', clip, clip, 1200, true, true, false, scroll_test_target('outer'))
		assert w.register_scroll_view_in_parent(named_scroll_state_id('inner'), named_scroll_state_id('outer'), rect(20, 20, 100,
			100), clip, 200, true, true, false, scroll_test_target('inner')) == 100
		w.handle_touch_up(50, 40)
	}

	fn test_keyed_anonymous_text_areas_get_independent_nested_scroll_state() {
		mut w := &Window{}
		reset_scroll_test_state(mut w)
		first := Element{kind: .text_area, key: '0'}
		second := Element{kind: .text_area, key: '1'}
		first_id := text_area_scroll_id(first)
		second_id := text_area_scroll_id(second)
		assert first_id == anonymous_text_area_scroll_prefix + '0'
		assert second_id == anonymous_text_area_scroll_prefix + '1'
		assert first_id != second_id
		assert text_area_scroll_id(Element{kind: .text_area, id: 'notes', key: '0'}) == named_scroll_state_id('notes')
		assert text_area_scroll_id(Element{kind: .text_area}) == ''

		clip := rect(0, 0, 300, 200)
		w.register_scroll_view_in_parent(named_scroll_state_id('outer'), '', clip, clip, 1000, true, true, false, scroll_test_target('outer'))
		w.register_scroll_view_in_parent(first_id, '', rect(20, 20, 100, 100), clip, 600, true, true, false, scroll_test_target(first.id))
		w.register_scroll_view_in_parent(second_id, '', rect(140, 20, 100, 100), clip, 600, true, true, false, scroll_test_target(second.id))
		w.handle_mouse_scroll_vector(50, 50, 0, -1)
		assert w.scroll_state_offset(first_id) == 48
		assert w.scroll_state_offset(second_id) == 0
		assert w.scroll_offset('outer') == 0
		w.handle_mouse_scroll_vector(170, 50, 0, -2)
		assert w.scroll_state_offset(first_id) == 48
		assert w.scroll_state_offset(second_id) == 96
		assert w.scroll_offset('outer') == 0
	}

	fn test_short_disabled_and_hidden_scrollbar_panes() {
		mut w := &Window{}
		reset_scroll_test_state(mut w)
		frame := rect(0, 0, 100, 100)
		w.register_scroll_view_in_parent(named_scroll_state_id('short'), '', frame, frame, 50, true, true, false, scroll_test_target('short'))
		assert w.scroll_hit_test(50, 50) == ''
		scroll_test_events = []string{}
		scroll_test_payloads = []ElementEvent{}
		w.handle_mouse_scroll_vector(50, 50, 0, -1)
		assert w.scroll_offset('short') == 0
		assert scroll_test_events.len == 0
		w.reset_scroll_frame()
		w.register_scroll_view_in_parent(named_scroll_state_id('disabled'), '', frame, frame, 1000, false, true, false, scroll_test_target('disabled'))
		assert w.scroll_hit_test(50, 50) == ''
		w.reset_scroll_frame()
		w.register_scroll_view_in_parent(named_scroll_state_id('hidden-bar'), '', frame, frame, 1000, true, false, false, scroll_test_target('hidden-bar'))
		assert named_scroll_state_id('hidden-bar') !in w.scrollbar_geometries
		w.handle_mouse_scroll_vector(50, 50, 0, -0.5)
		assert w.scroll_offset('hidden-bar') == 24
	}

	fn test_scrollbar_geometry_matches_the_scroll_range() {
		frame := rect(0, 0, 100, 100)
		top := scrollbar_geometry(frame, 1000, 0, false)
		assert top.track == rect(91, 4, 5, 92)
		assert top.thumb == rect(91, 4, 5, 28)
		bottom := scrollbar_geometry(frame, 1000, 900, false)
		assert bottom.thumb.y + bottom.thumb.height == bottom.track.y + bottom.track.height
		assert scrollbar_geometry(frame, 50, 0, false) == ScrollbarGeometry{}
		persistent := scrollbar_geometry(frame, 50, 0, true)
		assert persistent.track == persistent.thumb
		assert scrollbar_geometry(rect(0, 0, 5, 5), 1000, 0, true) == ScrollbarGeometry{}
	}

	fn test_scrollbar_thumb_drag_and_track_click_reach_the_bottom() {
		mut w := &Window{}
		reset_scroll_test_state(mut w)
		frame := rect(0, 0, 100, 100)
		w.register_scroll_view_in_parent(named_scroll_state_id('text'), '', frame, frame, 1000, true, true, false, scroll_test_target('text'))
		w.handle_touch_down(94, 10)
		assert w.touch.scrollbar_drag
		w.handle_touch_move(94, 74)
		w.handle_touch_up(94, 74)
		assert w.scroll_offset('text') == 900
		assert w.focused_field == ''
		w.set_scroll_offset(named_scroll_state_id('text'), 0, 900)
		w.reset_scroll_frame()
		w.register_scroll_view_in_parent(named_scroll_state_id('text'), '', frame, frame, 1000, true, true, false, scroll_test_target('text'))
		w.handle_touch_down(94, 90)
		w.handle_touch_up(94, 90)
		assert w.scroll_offset('text') == 900
	}

	fn test_scroll_to_rect_uses_the_full_viewport_height() {
		mut w := &Window{}
		reset_scroll_test_state(mut w)
		w.register_scroll_view_in_parent(named_scroll_state_id('text'), '', rect(0, 0, 100, 100), rect(0, 0, 100, 50), 1000,
			true, true, false, scroll_test_target('text'))
		w.scroll_to_rect('text', 0, 950, 10, 10)
		assert w.scroll_offset('text') == 860
		w.scroll_to_rect('text', 0, 0, 10, 10)
		assert w.scroll_offset('text') == 0
	}

	fn test_unmounted_text_area_drops_scroll_and_wrapping_state() {
		mut w := &Window{}
		reset_scroll_test_state(mut w)
		scroll_test_panes(mut w)
		w.replace_text_area_layout('text', TextAreaLayout{text: 'abcdef', width: 30,
			lines: ['abc', 'def'], ranges: [TextAreaLineRange{start: 0, end: 3}, TextAreaLineRange{start: 3, end: 6}]})
		w.text_values['text'] = 'abcdef'
		w.text_kinds['text'] = .text_area
		w.active_scrolls = map[string]bool{}
		w.reset_scroll_frame()
		w.prune_unmounted_state()
		assert named_scroll_state_id('text') !in w.scroll_offsets
		assert named_scroll_state_id('text') !in w.scroll_content_h
		assert 'text' !in w.text_area_layouts
		assert w.scroll_hit_test(150, 50) == ''
	}

	fn test_scroll_to_offset_moves_a_registered_scroll_view() {
		mut w := &Window{}
		reset_scroll_test_state(mut w)
		frame := rect(0, 0, 100, 100)
		w.register_scroll_view_in_parent(named_scroll_state_id('notes'), '', frame, frame, 400, true, true, false, scroll_test_target('notes'))
		w.scroll_to_offset('notes', 120)
		assert w.scroll_offset('notes') == 120
		// Past the end settles at the end rather than scrolling into nothing.
		w.scroll_to_offset('notes', 10_000)
		assert w.scroll_offset('notes') == 300
		w.scroll_to_offset('notes', -50)
		assert w.scroll_offset('notes') == 0
	}

	fn test_scroll_to_offset_survives_until_the_view_exists() {
		mut w := &Window{}
		reset_scroll_test_state(mut w)
		// A screen that opens where it was last left asks before anything is laid out.
		w.scroll_to_offset('notes', 120)
		frame := rect(0, 0, 100, 100)
		w.register_scroll_view_in_parent(named_scroll_state_id('notes'), '', frame, frame, 400, true, true, false, scroll_test_target('notes'))
		assert w.scroll_offset('notes') == 120
	}

	fn test_scroll_to_offset_survives_frames_drawn_without_the_view() {
		mut w := &Window{}
		reset_scroll_test_state(mut w)
		// A conditional or asynchronously loaded pane is not in the tree yet, so frames
		// render without it. Those frames must not take the request away with them.
		w.scroll_to_offset('notes', 120)
		w.reset_scroll_frame()
		w.prune_unmounted_state()
		w.reset_scroll_frame()
		w.prune_unmounted_state()
		frame := rect(0, 0, 100, 100)
		w.register_scroll_view_in_parent(named_scroll_state_id('notes'), '', frame, frame, 400, true, true, false, scroll_test_target('notes'))
		assert w.scroll_offset('notes') == 120
	}

	fn test_scroll_to_offset_is_spent_once_the_view_takes_it() {
		mut w := &Window{}
		reset_scroll_test_state(mut w)
		w.scroll_to_offset('notes', 120)
		frame := rect(0, 0, 100, 100)
		w.register_scroll_view_in_parent(named_scroll_state_id('notes'), '', frame, frame, 400, true, true, false, scroll_test_target('notes'))
		assert w.scroll_offset('notes') == 120
		// The request is not reapplied over a position the user has since scrolled to.
		w.set_scroll_offset(named_scroll_state_id('notes'), 40, w.scroll_maximum(named_scroll_state_id('notes')))
		w.reset_scroll_frame()
		w.register_scroll_view_in_parent(named_scroll_state_id('notes'), '', frame, frame, 400, true, true, false, scroll_test_target('notes'))
		assert w.scroll_offset('notes') == 40
	}

	fn test_scroll_to_offset_is_clamped_once_the_range_is_known() {
		mut w := &Window{}
		reset_scroll_test_state(mut w)
		w.scroll_to_offset('notes', 10_000)
		frame := rect(0, 0, 100, 100)
		w.register_scroll_view_in_parent(named_scroll_state_id('notes'), '', frame, frame, 400, true, true, false, scroll_test_target('notes'))
		// Registering learns the real range, so the stored request is brought inside it.
		assert w.scroll_offset('notes') == 300
	}

	// A pane a hundred wide over four hundred of columns, with no vertical axis.
	fn register_horizontal_test_scroll(mut w Window, id string, frame Rect, clip Rect, height f64, enabled bool, scrollbar bool, persistent bool) f64 {
		return register_horizontal_test_scroll_in_parent(mut w, id, '', frame, clip, height, enabled, scrollbar, persistent)
	}

	fn register_horizontal_test_scroll_in_parent(mut w Window, id string, parent string, frame Rect, clip Rect, height f64, enabled bool, scrollbar bool, persistent bool) f64 {
		return w.register_scroll_view_in_parent(named_scroll_state_id(id), if parent.len > 0 { named_scroll_state_id(parent) } else { '' }, frame, clip, height, enabled, scrollbar, persistent, scroll_test_target(id))
	}

	// settle_scroll_test_frame runs the frame that rebuilds what was requested, so
	// nothing is pending.
	fn settle_scroll_test_frame(mut w Window) {
		if work := w.scheduler.begin_frame(0) { w.scheduler.finish_frame(work) }
		assert !w.scheduler.build_pending()
	}

	fn horizontal_scroll_test_pane(mut w Window) {
		frame := rect(0, 0, 100, 100)
		register_horizontal_test_scroll(mut w, 'columns', frame, frame, 0, true, false, false)
		w.register_scroll_view_width(named_scroll_state_id('columns'), 400, true, false, false)
	}

	fn test_horizontal_wheel_scrolls_a_sideways_pane_and_clamps_at_both_ends() {
		mut w := &Window{}
		reset_scroll_test_state(mut w)
		horizontal_scroll_test_pane(mut w)
		assert w.scroll_maximum(named_scroll_state_id('columns')) == 0
		assert w.scroll_maximum_x(named_scroll_state_id('columns')) == 300
		assert w.scroll_hit_test(50, 50) == named_scroll_state_id('columns')
		w.handle_mouse_scroll_vector(50, 50, -1, 0)
		assert w.scroll_horizontal_offset('columns') == 48
		// A plain wheel finds no vertical range here to move.
		w.handle_mouse_scroll_vector(50, 50, 0, -1)
		assert w.scroll_offset('columns') == 0
		assert w.scroll_horizontal_offset('columns') == 48
		w.handle_mouse_scroll_vector(50, 50, -1000, 0)
		assert w.scroll_horizontal_offset('columns') == 300
		w.handle_mouse_scroll_vector(50, 50, -1000, 0)
		w.handle_mouse_scroll_vector(50, 50, 1000, 0)
		assert w.scroll_horizontal_offset('columns') == 0
		assert scroll_test_events == ['columns', 'columns', 'columns']
	}

	fn test_sideways_strip_leaves_vertical_distance_to_its_parent() {
		mut w := &Window{}
		reset_scroll_test_state(mut w)
		clip := rect(0, 0, 300, 300)
		register_horizontal_test_scroll(mut w, 'list', clip, clip, 1200, true, true, false)
		register_horizontal_test_scroll_in_parent(mut w, 'strip', 'list', rect(20, 20, 100, 100), clip,
			0, true, false, false)
		w.register_scroll_view_width(named_scroll_state_id('strip'), 500, true, false, false)
		w.handle_mouse_scroll_vector(50, 50, 0, -1)
		assert w.scroll_offset('list') == 48
		assert w.scroll_offset('strip') == 0
		w.handle_mouse_scroll_vector(50, 50, -1, 0)
		assert w.scroll_horizontal_offset('strip') == 48
		assert w.scroll_horizontal_offset('list') == 0
		// A drag moves each axis in the pane that has room for it.
		w.handle_touch_down(50, 80)
		w.handle_touch_move(20, 50)
		w.handle_touch_up(20, 50)
		assert w.scroll_horizontal_offset('strip') == 78
		assert w.scroll_offset('list') == 78
		assert w.scroll_offset('strip') == 0
	}

	fn test_horizontal_offset_requests_only_paint_and_publish_both_axes() {
		mut w := &Window{}
		frame := rect(0, 0, 100, 100)
		id := named_scroll_state_id('pane')
		w.register_scroll_view_in_parent(id, '', frame, frame, 400, true, true, false, HitTarget{})
		w.register_scroll_view_width(id, 500, true, false, true)
		initial := w.scheduler.begin_frame(0) or { panic('initial work') }
		w.scheduler.finish_frame(initial)
		w.scroll_to_horizontal_offset('pane', 120)
		paint := w.scheduler.begin_frame(1) or { panic('missing paint') }
		assert paint.draw && !paint.build
		w.scheduler.finish_frame(paint)
		w.scroll_to_horizontal_offset('pane', 120)
		assert !w.scheduler.stats().pending
		w.scroll_targets[id] = scroll_test_target('pane')
		scroll_test_payloads.clear()
		w.scroll_to_offset('pane', 40)
		w.scroll_to_horizontal_offset('pane', 150)
		assert scroll_test_payloads.len == 2
		assert scroll_test_payloads[0].x == 120 && scroll_test_payloads[0].y == 40
		assert scroll_test_payloads[1].x == 150 && scroll_test_payloads[1].y == 40
		assert scroll_test_payloads[1].value == 40
	}

	fn test_horizontal_scrollbar_geometry_runs_along_the_bottom_edge() {
		frame := rect(0, 0, 100, 100)
		left := scrollbar_geometry_x(frame, 1000, 0, false, false)
		assert left.track == rect(4, 91, 92, 5)
		assert left.thumb == rect(4, 91, 28, 5)
		right := scrollbar_geometry_x(frame, 1000, 900, false, false)
		assert right.thumb.x + right.thumb.width == right.track.x + right.track.width
		// Beside a vertical scroller the track leaves the corner they would share.
		assert scrollbar_geometry_x(frame, 1000, 0, false, true).track == rect(4, 91, 83, 5)
		assert scrollbar_geometry_x(frame, 50, 0, false, false) == ScrollbarGeometry{}
		persistent := scrollbar_geometry_x(frame, 50, 0, true, false)
		assert persistent.track == persistent.thumb
		assert scrollbar_geometry_x(rect(0, 0, 5, 5), 1000, 0, true, false) == ScrollbarGeometry{}
	}

	fn test_horizontal_scrollbar_thumb_drag_and_track_click_reach_the_end() {
		mut w := &Window{}
		reset_scroll_test_state(mut w)
		horizontal_scroll_test_pane(mut w)
		w.handle_touch_down(10, 94)
		assert w.touch.scrollbar_drag
		assert w.touch.scrollbar_horizontal
		w.handle_touch_move(74, 94)
		w.handle_touch_up(74, 94)
		assert w.scroll_horizontal_offset('columns') == 300
		assert w.scroll_offset('columns') == 0
		w.set_scroll_offset_x(named_scroll_state_id('columns'), 0, 300)
		w.reset_scroll_frame()
		horizontal_scroll_test_pane(mut w)
		w.handle_touch_down(90, 94)
		w.handle_touch_up(90, 94)
		assert w.scroll_horizontal_offset('columns') == 300
	}

	fn test_strip_scrollbar_is_reachable_over_a_column_that_scrolls_beneath_it() {
		mut w := &Window{}
		reset_scroll_test_state(mut w)
		clip := rect(0, 0, 300, 100)
		register_horizontal_test_scroll(mut w, 'columns', clip, clip, 0, true, false, false)
		w.register_scroll_view_width(named_scroll_state_id('columns'), 900, true, false, false)
		register_horizontal_test_scroll_in_parent(mut w, 'column', 'columns', rect(0, 0, 150, 100), clip,
			400, true, true, false)
		// The press lands on the column, whose strip draws its scroller over it.
		w.handle_touch_down(20, 94)
		assert w.touch.scroll_chain == [named_scroll_state_id('column'), named_scroll_state_id('columns')]
		assert w.touch.scrollbar_drag
		assert w.touch.scrollbar_horizontal
		assert w.touch.scroll_id == named_scroll_state_id('columns')
		w.handle_touch_move(120, 94)
		w.handle_touch_up(120, 94)
		assert w.scroll_horizontal_offset('columns') > 300
		assert w.scroll_offset('column') == 0
		// The column's own scroller still answers further up.
		w.handle_touch_down(144, 20)
		assert w.touch.scrollbar_drag
		assert !w.touch.scrollbar_horizontal
		assert w.touch.scroll_id == named_scroll_state_id('column')
		w.handle_touch_up(144, 20)
	}

	fn test_scroll_to_rect_brings_a_column_into_view_sideways() {
		mut w := &Window{}
		reset_scroll_test_state(mut w)
		horizontal_scroll_test_pane(mut w)
		w.scroll_to_rect('columns', 350, 0, 50, 10)
		assert w.scroll_horizontal_offset('columns') == 300
		w.scroll_to_rect('columns', 120, 0, 50, 10)
		assert w.scroll_horizontal_offset('columns') == 120
		assert w.scroll_offset('columns') == 0
	}

	fn test_scroll_to_horizontal_offset_survives_until_the_view_exists() {
		mut w := &Window{}
		reset_scroll_test_state(mut w)
		// Opening a folder asks for the far end before its column has been laid out.
		w.scroll_to_horizontal_offset('columns', 10_000)
		w.reset_scroll_frame()
		w.prune_unmounted_state()
		horizontal_scroll_test_pane(mut w)
		assert w.scroll_horizontal_offset('columns') == 300
		w.scroll_to_horizontal_offset('columns', 120)
		assert w.scroll_horizontal_offset('columns') == 120
		w.scroll_to_horizontal_offset('columns', -50)
		assert w.scroll_horizontal_offset('columns') == 0
	}

	fn test_scroll_to_horizontal_offset_uses_the_latest_mounted_range() {
		mut w := &Window{}
		reset_scroll_test_state(mut w)
		horizontal_scroll_test_pane(mut w)
		// With no rebuild pending, an existing view clamps against its mounted range
		// and the request is spent.
		settle_scroll_test_frame(mut w)
		w.scroll_to_horizontal_offset('columns', 10_000)
		assert w.scroll_horizontal_offset('columns') == 300
		w.reset_scroll_frame()
		frame := rect(0, 0, 100, 100)
		register_horizontal_test_scroll(mut w, 'columns', frame, frame, 0, true, false, false)
		assert w.register_scroll_view_width(named_scroll_state_id('columns'), 600, true, false, false) == 300
		settle_scroll_test_frame(mut w)
		w.scroll_to_horizontal_offset('columns', 10_000)
		assert w.scroll_horizontal_offset('columns') == 500
		// The request is spent, so a later frame leaves a position the user moved to alone.
		w.set_scroll_offset_x(named_scroll_state_id('columns'), 40, w.scroll_maximum_x(named_scroll_state_id('columns')))
		w.reset_scroll_frame()
		register_horizontal_test_scroll(mut w, 'columns', frame, frame, 0, true, false, false)
		assert w.register_scroll_view_width(named_scroll_state_id('columns'), 600, true, false, false) == 40
		// One inside the range is taken at once and replaces what was still waiting.
		w.scroll_to_horizontal_offset('columns', 10_000)
		w.scroll_to_horizontal_offset('columns', 120)
		assert w.scroll_horizontal_offset('columns') == 120
		assert named_scroll_state_id('columns') !in w.pending_scroll_x
	}

	fn test_scroll_past_the_range_is_taken_up_again_after_a_pending_rebuild() {
		mut w := &Window{}
		reset_scroll_test_state(mut w)
		horizontal_scroll_test_pane(mut w)
		settle_scroll_test_frame(mut w)
		// Opening a folder adds a column and asks for the far end of the strip.
		w.request_refresh()
		w.scroll_to_horizontal_offset('columns', 10_000)
		assert w.scroll_horizontal_offset('columns') == 300
		settle_scroll_test_frame(mut w)
		w.reset_scroll_frame()
		frame := rect(0, 0, 100, 100)
		register_horizontal_test_scroll(mut w, 'columns', frame, frame, 0, true, false, false)
		w.register_scroll_view_width(named_scroll_state_id('columns'), 600, true, false, false)
		assert w.scroll_horizontal_offset('columns') == 500
		assert named_scroll_state_id('columns') !in w.pending_scroll_x
		// An offset inside the range is taken at once, rebuild or not.
		w.request_refresh()
		w.scroll_to_horizontal_offset('columns', 120)
		assert w.scroll_horizontal_offset('columns') == 120
		assert named_scroll_state_id('columns') !in w.pending_scroll_x
		settle_scroll_test_frame(mut w)
		reset_scroll_test_state(mut w)
		w.register_scroll_view_in_parent(named_scroll_state_id('notes'), '', frame, frame, 400,
			true, true, false, scroll_test_target('notes'))
		settle_scroll_test_frame(mut w)
		w.request_refresh()
		w.scroll_to_offset('notes', 10_000)
		assert w.scroll_offset('notes') == 300
		settle_scroll_test_frame(mut w)
		w.reset_scroll_frame()
		w.register_scroll_view_in_parent(named_scroll_state_id('notes'), '', frame, frame, 700,
			true, true, false, scroll_test_target('notes'))
		assert w.scroll_offset('notes') == 600
		assert named_scroll_state_id('notes') !in w.pending_scroll
	}

	fn test_sideways_state_goes_with_the_axis_and_with_the_pane() {
		mut w := &Window{}
		reset_scroll_test_state(mut w)
		horizontal_scroll_test_pane(mut w)
		w.scroll_to_horizontal_offset('columns', 120)
		// Rebuilt without a sideways axis, the pane has nothing left to be scrolled to.
		w.reset_scroll_frame()
		frame := rect(0, 0, 100, 100)
		register_horizontal_test_scroll(mut w, 'columns', frame, frame, 0, true, false, false)
		assert w.register_scroll_view_width(named_scroll_state_id('columns'), 0, false, false, false) == 0
		assert named_scroll_state_id('columns') !in w.scrollbar_geometries_x
		assert w.scroll_hit_test(50, 50) == ''
		w.reset_scroll_frame()
		horizontal_scroll_test_pane(mut w)
		w.scroll_to_horizontal_offset('columns', 120)
		w.active_scrolls = map[string]bool{}
		w.reset_scroll_frame()
		w.prune_unmounted_state()
		assert named_scroll_state_id('columns') !in w.scroll_offsets_x
		assert named_scroll_state_id('columns') !in w.scroll_content_w
	}
}

fn test_text_area_line_ranges_follow_wrapped_source_runes() {
	$if (android || (ios && ui2_custom_rendering ?)) && !ui2_headless ? {
		lines := ['one two', 'three']
		assert text_area_line_rune_ranges('one two three', lines) == [
			TextAreaLineRange{
				start: 0
				end: 7
			},
			TextAreaLineRange{
				start: 8
				end: 13
			},
		]
	}
}

fn test_text_area_line_ranges_keep_original_crlf_offsets() {
	$if (android || (ios && ui2_custom_rendering ?)) && !ui2_headless ? {
		assert text_area_line_rune_ranges('a\r\nbc', ['a', 'bc']) == [
			TextAreaLineRange{
				start: 0
				end: 1
			},
			TextAreaLineRange{
				start: 3
				end: 5
			},
		]
	}
}

fn test_text_area_vertical_and_line_boundary_navigation() {
	$if (android || linux || ((ios || macos || windows) && ui2_custom_rendering ?)) && !ui2_headless ? {
		mut w := &Window{}
		reset_scroll_test_state(mut w)
		w.focused_field = 'notes'
		w.replace_text_area_layout('notes', TextAreaLayout{
			text: 'one\ntwo\nthree'
			lines: ['one', 'two', 'three']
			ranges: [TextAreaLineRange{start: 0, end: 3}, TextAreaLineRange{start: 4, end: 7}, TextAreaLineRange{start: 8, end: 13}]
		})
		mut editor := text_editor('one\ntwo\nthree')
		editor.set_caret(6)
		assert w.move_focused_text_area_caret(mut editor, 1, false)
		assert editor.selection.caret == 10
		assert w.move_focused_text_area_caret(mut editor, -1, true)
		assert editor.selection == TextSelection{
			anchor: 10
			caret: 6
		}
		assert w.move_focused_text_area_line_boundary(mut editor, false, false)
		assert editor.selection.caret == 4
		assert w.move_focused_text_area_line_boundary(mut editor, true, true)
		assert editor.selection == TextSelection{
			anchor: 4
			caret: 7
		}
	}
}

fn test_text_area_shaped_source_lines_keep_crlf_navigation_and_owned_snapshot() {
	$if (linux || ((macos || windows) && ui2_custom_rendering ?)) && !ui2_headless ? {
		mut w := &Window{}
		reset_scroll_test_state(mut w)
		mut engine := new_text_engine(1)!
		defer { engine.free(); reset_scroll_test_state(mut w) }
		style := TextStyle{size: 16, font_family: 'Roboto Mono'}
		mut editor := text_editor('one\r\n\r\ntwo\n'.clone())
		shaped := engine.shape_area(editor.text, style, 400)!
		w.remember_shaped_text_area('notes', shaped, 400, style)
		snapshot := w.text_area_layouts['notes'] or { panic('missing layout') }
		assert snapshot.text.str != editor.text.str
		assert snapshot.lines == ['one', '', 'two', '']
		assert snapshot.ranges == [
			TextAreaLineRange{start: 0, end: 3},
			TextAreaLineRange{start: 5, end: 5},
			TextAreaLineRange{start: 7, end: 10},
			TextAreaLineRange{start: 11, end: 11},
		]
		w.focused_field = 'notes'
		editor.set_caret(2)
		assert w.move_focused_text_area_caret(mut editor, 1, false)
		assert editor.selection.caret == 5
		assert w.move_focused_text_area_caret(mut editor, 1, false)
		assert editor.selection.caret == 7
		assert w.move_focused_text_area_line_boundary(mut editor, true, false)
		assert editor.selection.caret == 10
		// Replacing the editor allocation cannot invalidate the stored source
		// string or line slices used by the next navigation event.
		w.replace_text_editor('notes', editor)
		w.replace_text_editor('notes', text_editor('replacement'.clone()))
		assert w.text_area_layouts['notes'].text == 'one\r\n\r\ntwo\n'
		assert w.text_area_layouts['notes'].lines == ['one', '', 'two', '']
		w.forget_text_state('notes')
		assert 'notes' !in w.text_area_layouts
	}
}

fn test_text_area_utf16_selection_preserves_rune_editor_contract_after_shaping() {
	$if (linux || ((macos || windows) && ui2_custom_rendering ?)) && !ui2_headless ? {
		mut w := &Window{}
		reset_scroll_test_state(mut w)
		mut engine := new_text_engine(1)!
		defer { engine.free(); reset_scroll_test_state(mut w) }
		value := 'A🙂e\u0301\nB'
		style := TextStyle{size: 16}
		shaped := engine.shape_area(value, style, 400)!
		w.remember_shaped_text_area('notes', shaped, 400, style)
		w.active_fields['notes'] = true
		w.text_kinds['notes'] = .text_area
		w.replace_text_value('notes', value)
		w.replace_text_editor('notes', text_editor(value.clone()))
		w.text_area_set_selection('notes', 1, 2)
		assert w.text_editors['notes'].selection == TextSelection{anchor: 1, caret: 2}
		assert w.text_area_caret('notes') == 3
		assert w.text_area_selection_length('notes') == 2
		selected := shaped.selection(1, 2)
		assert selected.len == 1
		assert selected[0].width > 0
		w.forget_text_state('notes')
	}
}

$if (android || linux || ((ios || macos || windows) && ui2_custom_rendering ?)) && !ui2_headless ? {
	fn test_registered_scroll_callbacks_keep_source_identity_and_fractional_offsets() {
		mut w := &Window{}
		reset_scroll_test_state(mut w)
		mut events := &[]ElementEvent{}
		callback := fn [mut events] (event ElementEvent) { events << event }
		pane := with_event(scroll('pane', rect(0, 0, 100, 100), 0xffffff, []Element{}), callback)
		w.register_scroll_view_in_parent(named_scroll_state_id(pane.id), '', pane.frame, pane.frame, 500, true, true, false,
			HitTarget{ id: pane.id, on_event: pane.on_event })
		w.scroll_to_offset(pane.id, 72.25)
		assert events.len == 1
		assert (*events)[0].kind == .scroll
		assert (*events)[0].id == 'pane'
		assert (*events)[0].value == 72.25
		// A rebuild installs the new declaration before a smaller range clamps it.
		mut replacement := &[]ElementEvent{}
		new_callback := fn [mut replacement] (event ElementEvent) { replacement << event }
		w.reset_scroll_frame()
		w.register_scroll_view_in_parent(named_scroll_state_id(pane.id), '', pane.frame, pane.frame, 120, true, true, false,
			HitTarget{ id: pane.id, on_event: new_callback })
		assert events.len == 1
		assert replacement.len == 1
		assert (*replacement)[0].kind == .scroll
		assert (*replacement)[0].id == 'pane'
		assert (*replacement)[0].value == 20
		w.scroll_to_offset(pane.id, 20)
		assert replacement.len == 1
	}

	fn test_vml_scroll_registration_notifies_the_declared_named_callback_on_wheel() {
		mut w := &Window{}
		reset_scroll_test_state(mut w)
		mut events := &[]ElementEvent{}
		callback := fn [mut events] (event ElementEvent) { events << event }
		pane := compiled_ui_scroll_immediate_3(rect(0, 0, 100, 100), callback)
		w.register_scroll_view_in_parent(named_scroll_state_id(pane.id), '', pane.frame, pane.frame, 500, true, true, false,
			HitTarget{ id: pane.id, on_event: pane.on_event })
		w.handle_mouse_scroll_vector(50, 50, 0, -1)
		assert events.len == 1
		assert (*events)[0].kind == .scroll
		assert (*events)[0].id == 'pane'
		assert (*events)[0].value == 48
	}

}


$if (android || linux || ((ios || macos || windows) && ui2_custom_rendering ?)) && !ui2_headless ? {
	fn test_anonymous_scroll_uses_private_identity_and_keeps_the_event_id_empty() {
		mut w := &Window{}
		reset_scroll_test_state(mut w)
		mut events := &[]ElementEvent{}
		callback := fn [mut events] (event ElementEvent) { events << event }
		pane := compiled_ui_scroll_immediate_2(rect(0, 0, 100, 100), callback)
		path := reconciliation_child_key('root', 0, pane)
		id := scroll_view_state_id(pane, path)
		assert id.len > 0
		assert id == scroll_view_state_id(pane, reconciliation_child_key('root', 2, pane))
		other := Element{ ...pane, key: 'other' }
		assert id != scroll_view_state_id(other, reconciliation_child_key('root', 0, other))
		w.register_scroll_view_in_parent(id, named_scroll_state_id('outer'), pane.frame, pane.frame, 500, true, true, false,
			HitTarget{ id: pane.id, on_event: pane.on_event })
		assert w.scroll_parents[id] == named_scroll_state_id('outer')
		w.handle_mouse_scroll_vector(50, 50, 0, -1)
		w.set_scroll_offset(id, 72.25, w.scroll_maximum(id))
		assert events.len == 2
		assert events.map(it.kind) == [.scroll, .scroll]
		assert events.map(it.id) == ['', '']
		assert events.map(it.value) == [48.0, 72.25]
		// Culling retains the same keyed child instead of treating it as unmounted.
		w.reset_scroll_frame()
		w.active_scrolls = map[string]bool{}
		w.retain_culled_scroll_state(view('', rect(0, 0, 100, 100), BoxStyle{}, [pane]), 'root')
		w.prune_unmounted_state()
		assert w.scroll_state_offset(id) == 72.25
		assert id in w.scroll_targets
		w.register_scroll_view_in_parent(id, '', pane.frame, pane.frame, 120, true, true, false,
			HitTarget{ id: pane.id, on_event: pane.on_event })
		assert events.len == 3
		assert (*events)[2].id == ''
		assert (*events)[2].value == 20
	}
}

$if (android || linux || ((ios || macos || windows) && ui2_custom_rendering ?)) && !ui2_headless ? {
	fn test_named_scroll_id_can_equal_an_anonymous_private_key_without_sharing_state() {
		mut w := &Window{}
		reset_scroll_test_state(mut w)
		defer { reset_scroll_test_state(mut w) }
		mut events := &[]ElementEvent{}
		callback := fn [mut events] (event ElementEvent) { events << event }
		anonymous := compiled_ui_scroll_immediate_1(rect(0, 0, 100, 100), callback)
		anonymous_path := reconciliation_child_key('root', 0, anonymous)
		anonymous_id := scroll_view_state_id(anonymous, anonymous_path)
		// Private spelling cannot reserve an otherwise valid authored identity.
		named := compiled_ui_scroll_immediate_0(rect(120, 0, 100, 100), callback, anonymous_id)
		validate_element_tree(screen(0xffffff, [anonymous, named])) or { panic(err) }
		named_id := scroll_view_state_id(named, reconciliation_child_key('root', 1, named))
		assert named.id == anonymous_id
		assert named_id != anonymous_id
		assert named_id != named_scroll_state_id(named_id)
		// A request made by the public id before mounting reaches only that node.
		w.scroll_to_offset(named.id, 18.25)
		clip := rect(0, 0, 240, 100)
		w.register_scroll_view_in_parent(anonymous_id, '', anonymous.frame, clip, 500, true, true, false,
			HitTarget{ id: anonymous.id, on_event: anonymous.on_event })
		w.register_scroll_view_in_parent(named_id, '', named.frame, clip, 500, true, true, false,
			HitTarget{ id: named.id, on_event: named.on_event })
		assert w.scroll_state_offset(anonymous_id) == 0
		assert w.scroll_offset(named.id) == 18.25
		w.handle_mouse_scroll_vector(50, 50, 0, -1)
		assert w.scroll_state_offset(anonymous_id) == 48
		assert w.scroll_offset(named.id) == 18.25
		w.scroll_to_offset(named.id, 72.25)
		assert w.scroll_state_offset(anonymous_id) == 48
		assert events.map(it.kind) == [.scroll, .scroll, .scroll]
		assert events.map(it.id) == [named.id, '', named.id]
		assert events.map(it.value) == [18.25, 48.0, 72.25]
		// Reordering and culling keep both private states independently mounted.
		w.reset_scroll_frame()
		w.active_scrolls = map[string]bool{}
		w.retain_culled_scroll_state(view('', clip, BoxStyle{}, [named, anonymous]), 'root')
		w.prune_unmounted_state()
		assert w.scroll_state_offset(anonymous_id) == 48
		assert w.scroll_offset(named.id) == 72.25
		assert anonymous_id == scroll_view_state_id(anonymous,
			reconciliation_child_key('root', 1, anonymous))
		w.register_scroll_view_in_parent(named_id, '', named.frame, clip, 120, true, true, false,
			HitTarget{ id: named.id, on_event: named.on_event })
		assert w.scroll_offset(named.id) == 20
		assert w.scroll_state_offset(anonymous_id) == 48
		assert (*events)[3].id == named.id
		assert (*events)[3].value == 20
	}

	fn test_named_multiline_input_id_can_equal_an_anonymous_input_private_key() {
		mut w := &Window{}
		reset_scroll_test_state(mut w)
		defer { reset_scroll_test_state(mut w) }
		input := text_area(TextAreaConfig{
			frame: rect(0, 0, 100, 100) }) or { panic(err) }
		anonymous := Element{ ...input, key: 'first' }
		anonymous_id := text_area_scroll_id(anonymous)
		named := text_area(TextAreaConfig{ id: anonymous_id,
			frame: rect(120, 0, 100, 100) }) or { panic(err) }
		validate_element_tree(screen(0xffffff, [anonymous, named])) or { panic(err) }
		named_id := text_area_scroll_id(named)
		assert named_id == named_scroll_state_id(named.id)
		assert anonymous_id != named_id
		clip := rect(0, 0, 240, 100)
		w.register_scroll_view_in_parent(anonymous_id, '', anonymous.frame, clip, 500, true, true, false,
			scroll_test_target(anonymous.id))
		w.register_scroll_view_in_parent(named_id, '', named.frame, clip, 500, true, true, false,
			scroll_test_target(named.id))
		w.handle_mouse_scroll_vector(50, 50, 0, -1)
		w.scroll_to_rect(named.id, 0, 150.5, 10, 10)
		assert w.scroll_state_offset(anonymous_id) == 48
		assert w.scroll_offset(named.id) == 60.5
		assert scroll_test_payloads.map(it.id) == ['', named.id]
		assert scroll_test_payloads.map(it.value) == [48.0, 60.5]
	}
}

// ScrollFixture is the model of the scroll fixtures: their scroll action.
@[heap]
struct ScrollFixture {
pub:
	callback_changed ElementCallback = unsafe { nil }
}

fn compiled_ui_scroll_immediate_0(frame Rect, callback_changed ElementCallback, fixture_id string) Element {
	mut app := &ScrollFixture{
		callback_changed: callback_changed
	}
	return Element{
		...ui_scroll_immediate_0_vml_framed(mut app, frame)
		id: fixture_id
	}
}

fn compiled_ui_scroll_immediate_1(frame Rect, callback_changed ElementCallback) Element {
	mut app := &ScrollFixture{
		callback_changed: callback_changed
	}
	return ui_scroll_immediate_1_vml_framed(mut app, frame)
}

fn compiled_ui_scroll_immediate_2(frame Rect, callback_changed ElementCallback) Element {
	mut app := &ScrollFixture{
		callback_changed: callback_changed
	}
	return ui_scroll_immediate_2_vml_framed(mut app, frame)
}

fn compiled_ui_scroll_immediate_3(frame Rect, callback_changed ElementCallback) Element {
	mut app := &ScrollFixture{
		callback_changed: callback_changed
	}
	return ui_scroll_immediate_3_vml_framed(mut app, frame)
}
