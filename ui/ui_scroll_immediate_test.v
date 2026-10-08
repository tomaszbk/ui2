// vfmt off
@[has_globals]
module ui2

$if (android || linux || ((macos || windows) && ui2_custom_rendering ?)) && !ui2_headless ? {
	__global scroll_test_events = []string{}
	__global scroll_test_payloads = []ElementEvent{}
	__global scroll_test_measurements = 0

	fn reset_scroll_test_state() {
		reset_scroll_frame()
		g_scroll_offsets = map[string]f64{}
		g_pending_scroll = map[string]f64{}
		g_scroll_content_h = map[string]f64{}
		g_active_scrolls = map[string]bool{}
		g_active_fields = map[string]bool{}
		g_text_values = map[string]string{}
		g_text_props = map[string]string{}
		g_text_kinds = map[string]Kind{}
		g_text_editors = map[string]TextEditor{}
		clear_text_area_layouts()
		g_hit_targets = []HitTarget{}
		g_touch = TouchState{}
		g_focused_field = ''

		scroll_test_events = []string{}
		scroll_test_payloads = []ElementEvent{}
		scroll_test_measurements = 0
		close_dropdown()
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

	$if android {
		fn test_text_area_wraps_words_and_preserves_explicit_blank_lines() {
			reset_scroll_test_state()
			assert wrap_text_area_lines('one two three', 70, scroll_test_width) == ['one two', 'three']
			assert wrap_text_area_lines('one\r\n\r\ntwo\n', 100, scroll_test_width) == ['one', '', 'two', '']
			assert wrap_text_area_lines('', 100, scroll_test_width) == ['']
			assert wrap_text_area_lines('one\ttwo', 30, scroll_test_width) == ['one', 'two']
		}
	}

	fn test_page_navigation_scrolls_the_focused_text_area() {
		reset_scroll_test_state()
		frame := rect(0, 0, 100, 80)
		register_scroll_view(named_scroll_state_id('notes'), frame, frame, 400, true, true, false, scroll_test_target('notes'))
		g_focused_field = 'notes'
		page_focused_text_area(1)
		assert scroll_offset('notes') == 80
		page_focused_text_area(10)
		assert scroll_offset('notes') == 320
		page_focused_text_area(-1)
		assert scroll_offset('notes') == 240
	}

	$if android {
		fn test_text_area_wraps_long_words_without_splitting_utf8_bytes() {
			reset_scroll_test_state()
			assert wrap_text_area_lines('é界🙂abcd', 30, scroll_test_width) == ['é界🙂', 'abc', 'd']
			assert wrap_text_area_lines('é界', 1, scroll_test_width) == ['é', '界']
			assert wrap_text_area_lines('abc', 0, scroll_test_width).len == 0
			assert wrap_text_area_lines('abc', -1, scroll_test_width).len == 0
		}
	}

	$if android {
		fn test_text_area_does_not_limit_content_to_one_thousand_lines() {
			reset_scroll_test_state()
			mut lines := []string{}
			for index in 0 .. 1105 {
				lines << 'line ${index}'
			}
			assert wrap_text_area_lines(lines.join('\n'), 500, scroll_test_width) == lines
		}
	}

	$if android {
		fn test_text_area_wrap_cache_tracks_text_width_and_font_changes() {
			reset_scroll_test_state()
			style := TextStyle{}
			assert text_area_lines('text', 'abcdef', 30, style, 15, scroll_test_width) == ['abc', 'def']
			measured := scroll_test_measurements
			assert text_area_lines('text', 'abcdef', 30, style, 15, scroll_test_width) == ['abc', 'def']
			assert scroll_test_measurements == measured
			assert text_area_lines('text', 'abcdef', 60, style, 15, scroll_test_width) == ['abcdef']
			assert text_area_lines('text', 'new', 60, style, 15, scroll_test_width) == ['new']
			before_font := scroll_test_measurements
			text_area_lines('text', 'new', 60, TextStyle{size: 20}, 20, scroll_test_width)
			assert scroll_test_measurements > before_font
		}
	}

	fn test_text_area_content_is_top_aligned_and_clipped_inside_its_pane() {
		content := text_area_content_rect(rect(20, 100, 200, 216), 12, true)
		assert content == rect(32, 108, 176, 200)
		$if android {
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

	fn scroll_test_panes() {
		clip := rect(0, 0, 300, 200)
		// Read-only text areas register exactly like editable areas: registration
		// is outside the editable hit-target branch in render_element.
		register_scroll_view(named_scroll_state_id('info'), rect(0, 0, 100, 100), clip, 400, true, true, false, scroll_test_target('info'))
		register_scroll_view(named_scroll_state_id('text'), rect(120, 0, 100, 100), clip, 1000, true, true, false, scroll_test_target('text'))
	}

	fn test_readonly_panes_scroll_independently_with_wheel_and_drag() {
		reset_scroll_test_state()
		scroll_test_panes()
		scroll_test_events = []string{}
		scroll_test_payloads = []ElementEvent{}
		handle_mouse_scroll_vector(150, 50, 0, -2)
		assert scroll_offset('text') == 96
		assert scroll_offset('info') == 0
		handle_mouse_scroll_vector(50, 50, 0, -1)
		assert scroll_offset('info') == 48
		handle_mouse_scroll_vector(110, 50, 0, -1)
		assert scroll_offset('info') == 48
		assert scroll_offset('text') == 96
		handle_touch_down(150, 80)
		handle_touch_move(150, 30)
		handle_touch_up(150, 30)
		assert scroll_offset('text') == 146
		assert scroll_offset('info') == 48
		assert g_focused_field == ''
		assert scroll_test_events == ['text', 'info', 'text']
	}

	fn test_text_area_scroll_clamps_at_both_ends() {
		reset_scroll_test_state()
		scroll_test_panes()
		scroll_test_events = []string{}
		scroll_test_payloads = []ElementEvent{}
		handle_mouse_scroll_vector(150, 50, 0, -1000)
		assert scroll_offset('text') == 900
		handle_mouse_scroll_vector(150, 50, 0, -1000)
		assert scroll_test_events.len == 1
		handle_mouse_scroll_vector(150, 50, 0, 1000)
		assert scroll_offset('text') == 0
		handle_mouse_scroll_vector(150, 50, 0, 1000)
		assert scroll_test_events == ['text', 'text']
	}

	fn test_text_area_scroll_survives_rebuild_and_clamps_after_resize_or_edit() {
		reset_scroll_test_state()
		scroll_test_panes()
		handle_mouse_scroll_vector(150, 50, 0, -2)
		reset_scroll_frame()
		clip := rect(0, 0, 500, 500)
		assert register_scroll_view(named_scroll_state_id('text'), rect(120, 0, 200, 200), clip, 1000, true, true, false, scroll_test_target('text')) == 96
		scroll_test_events = []string{}
		scroll_test_payloads = []ElementEvent{}
		reset_scroll_frame()
		assert register_scroll_view(named_scroll_state_id('text'), rect(120, 0, 200, 950), clip, 1000, true, true, false, scroll_test_target('text')) == 50
		reset_scroll_frame()
		assert register_scroll_view(named_scroll_state_id('text'), rect(120, 0, 200, 950), clip, 30, true, true, false, scroll_test_target('text')) == 0
		assert scroll_test_events == ['text', 'text']
	}

	fn test_text_area_scroll_hit_testing_uses_visible_clip_and_inner_first_order() {
		reset_scroll_test_state()
		clip := rect(0, 0, 300, 300)
		register_scroll_view(named_scroll_state_id('outer'), clip, clip, 1000, true, true, false, scroll_test_target('outer'))
		register_scroll_view(named_scroll_state_id('inner'), rect(20, 20, 100, 200), rect(0, 0, 300, 100), 1000,
			true, true, false, scroll_test_target('inner'))
		assert scroll_maximum(named_scroll_state_id('inner')) == 800
		assert g_scroll_areas[named_scroll_state_id('inner')] == rect(20, 20, 100, 80)
		handle_mouse_scroll_vector(50, 50, 0, -1)
		assert scroll_offset('inner') == 48
		assert scroll_offset('outer') == 0
		handle_mouse_scroll_vector(50, 150, 0, -1)
		assert scroll_offset('outer') == 48
		assert scroll_offset('inner') == 48
	}

	fn test_scroll_hit_testing_falls_through_a_fitted_child_to_its_parent() {
		reset_scroll_test_state()
		clip := rect(0, 0, 300, 300)
		register_scroll_view(named_scroll_state_id('outer'), clip, clip, 1000, true, true, false, scroll_test_target('outer'))
		register_scroll_view(named_scroll_state_id('inner'), rect(20, 20, 100, 100), clip, 100, true, true,
			false, scroll_test_target('inner'))
		assert scroll_maximum(named_scroll_state_id('inner')) == 0
		assert scroll_hit_test(50, 50) == named_scroll_state_id('outer')
		handle_mouse_scroll_vector(50, 50, 0, -1)
		assert scroll_offset('inner') == 0
		assert scroll_offset('outer') == 48
	}

	fn nested_scroll_test_panes() {
		clip := rect(0, 0, 300, 300)
		register_scroll_view(named_scroll_state_id('outer'), clip, clip, 1200, true, true, false, scroll_test_target('outer'))
		register_scroll_view_in_parent(named_scroll_state_id('inner'), named_scroll_state_id('outer'), rect(20, 20, 100, 100), clip,
			200, true, true, false, scroll_test_target('inner'))
	}

	fn test_mouse_wheel_chains_remaining_delta_to_a_parent_at_child_boundary() {
		reset_scroll_test_state()
		nested_scroll_test_panes()
		set_scroll_offset(named_scroll_state_id('inner'), 80, scroll_maximum(named_scroll_state_id('inner')))
		scroll_test_events = []string{}
		scroll_test_payloads = []ElementEvent{}

		handle_mouse_scroll_vector(50, 50, 0, -1)
		assert scroll_offset('inner') == 100
		assert scroll_offset('outer') == 28
		handle_mouse_scroll_vector(50, 50, 0, -1)
		assert scroll_offset('inner') == 100
		assert scroll_offset('outer') == 76
		assert scroll_test_events == ['inner', 'outer', 'outer']

		set_scroll_offset(named_scroll_state_id('inner'), 0, scroll_maximum(named_scroll_state_id('inner')))
		scroll_test_events = []string{}
		handle_mouse_scroll_vector(50, 50, 0, 1)
		assert scroll_offset('inner') == 0
		assert scroll_offset('outer') == 28
		assert scroll_test_events == ['outer']
	}

	fn test_touch_drag_chains_remaining_delta_and_reverses_into_the_child() {
		reset_scroll_test_state()
		nested_scroll_test_panes()
		set_scroll_offset(named_scroll_state_id('inner'), 80, scroll_maximum(named_scroll_state_id('inner')))
		scroll_test_events = []string{}
		scroll_test_payloads = []ElementEvent{}

		handle_touch_down(50, 80)
		handle_touch_move(50, 30)
		assert scroll_offset('inner') == 100
		assert scroll_offset('outer') == 30
		handle_touch_move(50, 0)
		assert scroll_offset('inner') == 100
		assert scroll_offset('outer') == 60
		handle_touch_move(50, 40)
		assert scroll_offset('inner') == 60
		assert scroll_offset('outer') == 60
		handle_touch_up(50, 40)
		assert scroll_test_events == ['inner', 'outer', 'outer', 'inner']
	}

	fn test_touch_drag_keeps_its_parent_chain_when_the_child_is_culled() {
		reset_scroll_test_state()
		nested_scroll_test_panes()
		set_scroll_offset(named_scroll_state_id('inner'), 80, scroll_maximum(named_scroll_state_id('inner')))

		handle_touch_down(50, 80)
		assert g_touch.scroll_chain == [named_scroll_state_id('inner'), named_scroll_state_id('outer')]
		handle_touch_move(50, 30)
		assert scroll_offset('inner') == 100
		assert scroll_offset('outer') == 30

		// Simulate the next frame after the parent has moved the child outside
		// its viewport. Only the parent is registered, but the renderer retains
		// scroll state from the child's still-mounted element subtree.
		g_active_scrolls = map[string]bool{}
		reset_scroll_frame()
		clip := rect(0, 0, 300, 300)
		register_scroll_view(named_scroll_state_id('outer'), clip, clip, 1200, true, true, false, scroll_test_target('outer'))
		retain_culled_scroll_state(Element{
			kind: .view
			children: [Element{
				kind: .scroll
				id: 'inner'
			}]
		}, 'root')
		prune_unmounted_state()
		assert named_scroll_state_id('inner') !in g_scroll_viewports
		assert scroll_offset('inner') == 100
		assert g_scroll_content_h[named_scroll_state_id('inner')] == 200
		assert g_scroll_parents.len == 0

		handle_touch_move(50, 0)
		assert scroll_offset('outer') == 60
		handle_touch_move(50, 40)
		assert scroll_offset('outer') == 20

		// Re-registering the child after it re-enters the viewport restores its
		// previous position instead of jumping back to the top.
		reset_scroll_frame()
		register_scroll_view(named_scroll_state_id('outer'), clip, clip, 1200, true, true, false, scroll_test_target('outer'))
		assert register_scroll_view_in_parent(named_scroll_state_id('inner'), named_scroll_state_id('outer'), rect(20, 20, 100,
			100), clip, 200, true, true, false, scroll_test_target('inner')) == 100
		handle_touch_up(50, 40)
	}

	fn test_keyed_anonymous_text_areas_get_independent_nested_scroll_state() {
		reset_scroll_test_state()
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
		register_scroll_view(named_scroll_state_id('outer'), clip, clip, 1000, true, true, false, scroll_test_target('outer'))
		register_scroll_view(first_id, rect(20, 20, 100, 100), clip, 600, true, true, false, scroll_test_target(first.id))
		register_scroll_view(second_id, rect(140, 20, 100, 100), clip, 600, true, true, false, scroll_test_target(second.id))
		handle_mouse_scroll_vector(50, 50, 0, -1)
		assert scroll_state_offset(first_id) == 48
		assert scroll_state_offset(second_id) == 0
		assert scroll_offset('outer') == 0
		handle_mouse_scroll_vector(170, 50, 0, -2)
		assert scroll_state_offset(first_id) == 48
		assert scroll_state_offset(second_id) == 96
		assert scroll_offset('outer') == 0
	}

	fn test_short_disabled_and_hidden_scrollbar_panes() {
		reset_scroll_test_state()
		frame := rect(0, 0, 100, 100)
		register_scroll_view(named_scroll_state_id('short'), frame, frame, 50, true, true, false, scroll_test_target('short'))
		assert scroll_hit_test(50, 50) == ''
		scroll_test_events = []string{}
		scroll_test_payloads = []ElementEvent{}
		handle_mouse_scroll_vector(50, 50, 0, -1)
		assert scroll_offset('short') == 0
		assert scroll_test_events.len == 0
		reset_scroll_frame()
		register_scroll_view(named_scroll_state_id('disabled'), frame, frame, 1000, false, true, false, scroll_test_target('disabled'))
		assert scroll_hit_test(50, 50) == ''
		reset_scroll_frame()
		register_scroll_view(named_scroll_state_id('hidden-bar'), frame, frame, 1000, true, false, false, scroll_test_target('hidden-bar'))
		assert named_scroll_state_id('hidden-bar') !in g_scrollbar_geometries
		handle_mouse_scroll_vector(50, 50, 0, -0.5)
		assert scroll_offset('hidden-bar') == 24
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
		reset_scroll_test_state()
		frame := rect(0, 0, 100, 100)
		register_scroll_view(named_scroll_state_id('text'), frame, frame, 1000, true, true, false, scroll_test_target('text'))
		handle_touch_down(94, 10)
		assert g_touch.scrollbar_drag
		handle_touch_move(94, 74)
		handle_touch_up(94, 74)
		assert scroll_offset('text') == 900
		assert g_focused_field == ''
		set_scroll_offset(named_scroll_state_id('text'), 0, 900)
		reset_scroll_frame()
		register_scroll_view(named_scroll_state_id('text'), frame, frame, 1000, true, true, false, scroll_test_target('text'))
		handle_touch_down(94, 90)
		handle_touch_up(94, 90)
		assert scroll_offset('text') == 900
	}

	fn test_scroll_to_rect_uses_the_full_viewport_height() {
		reset_scroll_test_state()
		register_scroll_view(named_scroll_state_id('text'), rect(0, 0, 100, 100), rect(0, 0, 100, 50), 1000,
			true, true, false, scroll_test_target('text'))
		scroll_to_rect('text', 0, 950, 10, 10)
		assert scroll_offset('text') == 860
		scroll_to_rect('text', 0, 0, 10, 10)
		assert scroll_offset('text') == 0
	}

	fn test_unmounted_text_area_drops_scroll_and_wrapping_state() {
		reset_scroll_test_state()
		scroll_test_panes()
		replace_text_area_layout('text', TextAreaLayout{text: 'abcdef', width: 30,
			lines: ['abc', 'def'], ranges: [TextAreaLineRange{start: 0, end: 3}, TextAreaLineRange{start: 3, end: 6}]})
		g_text_values['text'] = 'abcdef'
		g_text_kinds['text'] = .text_area
		g_active_scrolls = map[string]bool{}
		reset_scroll_frame()
		prune_unmounted_state()
		assert named_scroll_state_id('text') !in g_scroll_offsets
		assert named_scroll_state_id('text') !in g_scroll_content_h
		assert 'text' !in g_text_area_layouts
		assert scroll_hit_test(150, 50) == ''
	}

	fn test_scroll_to_offset_moves_a_registered_scroll_view() {
		reset_scroll_test_state()
		frame := rect(0, 0, 100, 100)
		register_scroll_view(named_scroll_state_id('notes'), frame, frame, 400, true, true, false, scroll_test_target('notes'))
		scroll_to_offset('notes', 120)
		assert scroll_offset('notes') == 120
		// Past the end settles at the end rather than scrolling into nothing.
		scroll_to_offset('notes', 10_000)
		assert scroll_offset('notes') == 300
		scroll_to_offset('notes', -50)
		assert scroll_offset('notes') == 0
	}

	fn test_scroll_to_offset_survives_until_the_view_exists() {
		reset_scroll_test_state()
		// A screen that opens where it was last left asks before anything is laid out.
		scroll_to_offset('notes', 120)
		frame := rect(0, 0, 100, 100)
		register_scroll_view(named_scroll_state_id('notes'), frame, frame, 400, true, true, false, scroll_test_target('notes'))
		assert scroll_offset('notes') == 120
	}

	fn test_scroll_to_offset_survives_frames_drawn_without_the_view() {
		reset_scroll_test_state()
		// A conditional or asynchronously loaded pane is not in the tree yet, so frames
		// render without it. Those frames must not take the request away with them.
		scroll_to_offset('notes', 120)
		reset_scroll_frame()
		prune_unmounted_state()
		reset_scroll_frame()
		prune_unmounted_state()
		frame := rect(0, 0, 100, 100)
		register_scroll_view(named_scroll_state_id('notes'), frame, frame, 400, true, true, false, scroll_test_target('notes'))
		assert scroll_offset('notes') == 120
	}

	fn test_scroll_to_offset_is_spent_once_the_view_takes_it() {
		reset_scroll_test_state()
		scroll_to_offset('notes', 120)
		frame := rect(0, 0, 100, 100)
		register_scroll_view(named_scroll_state_id('notes'), frame, frame, 400, true, true, false, scroll_test_target('notes'))
		assert scroll_offset('notes') == 120
		// The request is not reapplied over a position the user has since scrolled to.
		set_scroll_offset(named_scroll_state_id('notes'), 40, scroll_maximum(named_scroll_state_id('notes')))
		reset_scroll_frame()
		register_scroll_view(named_scroll_state_id('notes'), frame, frame, 400, true, true, false, scroll_test_target('notes'))
		assert scroll_offset('notes') == 40
	}

	fn test_scroll_to_offset_is_clamped_once_the_range_is_known() {
		reset_scroll_test_state()
		scroll_to_offset('notes', 10_000)
		frame := rect(0, 0, 100, 100)
		register_scroll_view(named_scroll_state_id('notes'), frame, frame, 400, true, true, false, scroll_test_target('notes'))
		// Registering learns the real range, so the stored request is brought inside it.
		assert scroll_offset('notes') == 300
	}
}

fn test_text_area_line_ranges_follow_wrapped_source_runes() {
	$if android && !ui2_headless ? {
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
	$if android && !ui2_headless ? {
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
	$if (android || linux || ((macos || windows) && ui2_custom_rendering ?)) && !ui2_headless ? {
		reset_scroll_test_state()
		g_focused_field = 'notes'
		replace_text_area_layout('notes', TextAreaLayout{
			text: 'one\ntwo\nthree'
			lines: ['one', 'two', 'three']
			ranges: [TextAreaLineRange{start: 0, end: 3}, TextAreaLineRange{start: 4, end: 7}, TextAreaLineRange{start: 8, end: 13}]
		})
		mut editor := text_editor('one\ntwo\nthree')
		editor.set_caret(6)
		assert move_focused_text_area_caret(mut editor, 1, false)
		assert editor.selection.caret == 10
		assert move_focused_text_area_caret(mut editor, -1, true)
		assert editor.selection == TextSelection{
			anchor: 10
			caret: 6
		}
		assert move_focused_text_area_line_boundary(mut editor, false, false)
		assert editor.selection.caret == 4
		assert move_focused_text_area_line_boundary(mut editor, true, true)
		assert editor.selection == TextSelection{
			anchor: 4
			caret: 7
		}
	}
}

fn test_text_area_shaped_source_lines_keep_crlf_navigation_and_owned_snapshot() {
	$if (linux || ((macos || windows) && ui2_custom_rendering ?)) && !ui2_headless ? {
		reset_scroll_test_state()
		mut engine := new_text_engine(1)!
		defer { engine.free(); reset_scroll_test_state() }
		style := TextStyle{size: 16, font_family: 'Roboto Mono'}
		mut editor := text_editor('one\r\n\r\ntwo\n'.clone())
		shaped := engine.shape_area(editor.text, style, 400)!
		remember_shaped_text_area('notes', shaped, 400, style)
		snapshot := g_text_area_layouts['notes'] or { panic('missing layout') }
		assert snapshot.text.str != editor.text.str
		assert snapshot.lines == ['one', '', 'two', '']
		assert snapshot.ranges == [
			TextAreaLineRange{start: 0, end: 3},
			TextAreaLineRange{start: 5, end: 5},
			TextAreaLineRange{start: 7, end: 10},
			TextAreaLineRange{start: 11, end: 11},
		]
		g_focused_field = 'notes'
		editor.set_caret(2)
		assert move_focused_text_area_caret(mut editor, 1, false)
		assert editor.selection.caret == 5
		assert move_focused_text_area_caret(mut editor, 1, false)
		assert editor.selection.caret == 7
		assert move_focused_text_area_line_boundary(mut editor, true, false)
		assert editor.selection.caret == 10
		// Replacing the editor allocation cannot invalidate the stored source
		// string or line slices used by the next navigation event.
		replace_text_editor('notes', editor)
		replace_text_editor('notes', text_editor('replacement'.clone()))
		assert g_text_area_layouts['notes'].text == 'one\r\n\r\ntwo\n'
		assert g_text_area_layouts['notes'].lines == ['one', '', 'two', '']
		forget_text_state('notes')
		assert 'notes' !in g_text_area_layouts
	}
}

fn test_text_area_utf16_selection_preserves_rune_editor_contract_after_shaping() {
	$if (linux || ((macos || windows) && ui2_custom_rendering ?)) && !ui2_headless ? {
		reset_scroll_test_state()
		mut engine := new_text_engine(1)!
		defer { engine.free(); reset_scroll_test_state() }
		value := 'A🙂e\u0301\nB'
		style := TextStyle{size: 16}
		shaped := engine.shape_area(value, style, 400)!
		remember_shaped_text_area('notes', shaped, 400, style)
		g_active_fields['notes'] = true
		g_text_kinds['notes'] = .text_area
		replace_text_value('notes', value)
		replace_text_editor('notes', text_editor(value.clone()))
		text_area_set_selection('notes', 1, 2)
		assert g_text_editors['notes'].selection == TextSelection{anchor: 1, caret: 2}
		assert text_area_caret('notes') == 3
		assert text_area_selection_length('notes') == 2
		selected := shaped.selection(1, 2)
		assert selected.len == 1
		assert selected[0].width > 0
		forget_text_state('notes')
		forget_portable_text_area_selection('notes')
	}
}

$if (android || linux || ((macos || windows) && ui2_custom_rendering ?)) && !ui2_headless ? {
	fn test_registered_scroll_callbacks_keep_source_identity_and_fractional_offsets() {
		reset_scroll_test_state()
		mut events := &[]ElementEvent{}
		callback := fn [mut events] (event ElementEvent) { events << event }
		pane := with_event(scroll('pane', rect(0, 0, 100, 100), 0xffffff, []Element{}), callback)
		register_scroll_view(named_scroll_state_id(pane.id), pane.frame, pane.frame, 500, true, true, false,
			HitTarget{ id: pane.id, on_event: pane.on_event })
		scroll_to_offset(pane.id, 72.25)
		assert events.len == 1
		assert (*events)[0].kind == .scroll
		assert (*events)[0].id == 'pane'
		assert (*events)[0].value == 72.25
		// A rebuild installs the new declaration before a smaller range clamps it.
		mut replacement := &[]ElementEvent{}
		new_callback := fn [mut replacement] (event ElementEvent) { replacement << event }
		reset_scroll_frame()
		register_scroll_view(named_scroll_state_id(pane.id), pane.frame, pane.frame, 120, true, true, false,
			HitTarget{ id: pane.id, on_event: new_callback })
		assert events.len == 1
		assert replacement.len == 1
		assert (*replacement)[0].kind == .scroll
		assert (*replacement)[0].id == 'pane'
		assert (*replacement)[0].value == 20
		scroll_to_offset(pane.id, 20)
		assert replacement.len == 1
	}

	fn test_vml_scroll_registration_notifies_the_declared_named_callback_on_wheel() {
		reset_scroll_test_state()
		mut events := &[]ElementEvent{}
		callback := fn [mut events] (event ElementEvent) { events << event }
		pane := element_from_vml_with_callbacks('Scroll { id: pane on_scroll: changed }',
			rect(0, 0, 100, 100), { 'changed': callback }) or { panic(err) }
		register_scroll_view(named_scroll_state_id(pane.id), pane.frame, pane.frame, 500, true, true, false,
			HitTarget{ id: pane.id, on_event: pane.on_event })
		handle_mouse_scroll_vector(50, 50, 0, -1)
		assert events.len == 1
		assert (*events)[0].kind == .scroll
		assert (*events)[0].id == 'pane'
		assert (*events)[0].value == 48
	}

}


$if (android || linux || ((macos || windows) && ui2_custom_rendering ?)) && !ui2_headless ? {
	fn test_anonymous_scroll_uses_private_identity_and_keeps_the_event_id_empty() {
		reset_scroll_test_state()
		mut events := &[]ElementEvent{}
		callback := fn [mut events] (event ElementEvent) { events << event }
		pane := element_from_vml_with_callbacks('Scroll { key: pane on_scroll: changed }',
			rect(0, 0, 100, 100), { 'changed': callback }) or { panic(err) }
		path := reconciliation_child_key('root', 0, pane)
		id := scroll_view_state_id(pane, path)
		assert id.len > 0
		assert id == scroll_view_state_id(pane, reconciliation_child_key('root', 2, pane))
		other := Element{ ...pane, key: 'other' }
		assert id != scroll_view_state_id(other, reconciliation_child_key('root', 0, other))
		register_scroll_view_in_parent(id, named_scroll_state_id('outer'), pane.frame, pane.frame, 500, true, true, false,
			HitTarget{ id: pane.id, on_event: pane.on_event })
		assert g_scroll_parents[id] == named_scroll_state_id('outer')
		handle_mouse_scroll_vector(50, 50, 0, -1)
		set_scroll_offset(id, 72.25, scroll_maximum(id))
		assert events.len == 2
		assert events.map(it.kind) == [.scroll, .scroll]
		assert events.map(it.id) == ['', '']
		assert events.map(it.value) == [48.0, 72.25]
		// Culling retains the same keyed child instead of treating it as unmounted.
		reset_scroll_frame()
		g_active_scrolls = map[string]bool{}
		retain_culled_scroll_state(view('', rect(0, 0, 100, 100), BoxStyle{}, [pane]), 'root')
		prune_unmounted_state()
		assert scroll_state_offset(id) == 72.25
		assert id in g_scroll_targets
		register_scroll_view(id, pane.frame, pane.frame, 120, true, true, false,
			HitTarget{ id: pane.id, on_event: pane.on_event })
		assert events.len == 3
		assert (*events)[2].id == ''
		assert (*events)[2].value == 20
	}
}

$if (android || linux || ((macos || windows) && ui2_custom_rendering ?)) && !ui2_headless ? {
	fn test_named_scroll_id_can_equal_an_anonymous_private_key_without_sharing_state() {
		reset_scroll_test_state()
		defer { reset_scroll_test_state() }
		mut events := &[]ElementEvent{}
		callback := fn [mut events] (event ElementEvent) { events << event }
		anonymous := element_from_vml_with_callbacks('Scroll { key: first on_scroll: changed }',
			rect(0, 0, 100, 100), { 'changed': callback }) or { panic(err) }
		anonymous_path := reconciliation_child_key('root', 0, anonymous)
		anonymous_id := scroll_view_state_id(anonymous, anonymous_path)
		// Private spelling cannot reserve an otherwise valid authored identity.
		named := element_from_vml_with_callbacks('Scroll { id: "${anonymous_id}" on_scroll: changed }',
			rect(120, 0, 100, 100), { 'changed': callback }) or { panic(err) }
		validate_element_tree(screen(0xffffff, [anonymous, named])) or { panic(err) }
		named_id := scroll_view_state_id(named, reconciliation_child_key('root', 1, named))
		assert named.id == anonymous_id
		assert named_id != anonymous_id
		assert named_id != named_scroll_state_id(named_id)
		// A request made by the public id before mounting reaches only that node.
		scroll_to_offset(named.id, 18.25)
		clip := rect(0, 0, 240, 100)
		register_scroll_view(anonymous_id, anonymous.frame, clip, 500, true, true, false,
			HitTarget{ id: anonymous.id, on_event: anonymous.on_event })
		register_scroll_view(named_id, named.frame, clip, 500, true, true, false,
			HitTarget{ id: named.id, on_event: named.on_event })
		assert scroll_state_offset(anonymous_id) == 0
		assert scroll_offset(named.id) == 18.25
		handle_mouse_scroll_vector(50, 50, 0, -1)
		assert scroll_state_offset(anonymous_id) == 48
		assert scroll_offset(named.id) == 18.25
		scroll_to_offset(named.id, 72.25)
		assert scroll_state_offset(anonymous_id) == 48
		assert events.map(it.kind) == [.scroll, .scroll, .scroll]
		assert events.map(it.id) == [named.id, '', named.id]
		assert events.map(it.value) == [18.25, 48.0, 72.25]
		// Reordering and culling keep both private states independently mounted.
		reset_scroll_frame()
		g_active_scrolls = map[string]bool{}
		retain_culled_scroll_state(view('', clip, BoxStyle{}, [named, anonymous]), 'root')
		prune_unmounted_state()
		assert scroll_state_offset(anonymous_id) == 48
		assert scroll_offset(named.id) == 72.25
		assert anonymous_id == scroll_view_state_id(anonymous,
			reconciliation_child_key('root', 1, anonymous))
		register_scroll_view(named_id, named.frame, clip, 120, true, true, false,
			HitTarget{ id: named.id, on_event: named.on_event })
		assert scroll_offset(named.id) == 20
		assert scroll_state_offset(anonymous_id) == 48
		assert (*events)[3].id == named.id
		assert (*events)[3].value == 20
	}

	fn test_named_multiline_input_id_can_equal_an_anonymous_input_private_key() {
		reset_scroll_test_state()
		defer { reset_scroll_test_state() }
		input := text_input(TextInputConfig{ multiline: true,
			frame: rect(0, 0, 100, 100) }) or { panic(err) }
		anonymous := Element{ ...input, key: 'first' }
		anonymous_id := text_area_scroll_id(anonymous)
		named := text_input(TextInputConfig{ id: anonymous_id, multiline: true,
			frame: rect(120, 0, 100, 100) }) or { panic(err) }
		validate_element_tree(screen(0xffffff, [anonymous, named])) or { panic(err) }
		named_id := text_area_scroll_id(named)
		assert named_id == named_scroll_state_id(named.id)
		assert anonymous_id != named_id
		clip := rect(0, 0, 240, 100)
		register_scroll_view(anonymous_id, anonymous.frame, clip, 500, true, true, false,
			scroll_test_target(anonymous.id))
		register_scroll_view(named_id, named.frame, clip, 500, true, true, false,
			scroll_test_target(named.id))
		handle_mouse_scroll_vector(50, 50, 0, -1)
		scroll_to_rect(named.id, 0, 150.5, 10, 10)
		assert scroll_state_offset(anonymous_id) == 48
		assert scroll_offset(named.id) == 60.5
		assert scroll_test_payloads.map(it.id) == ['', named.id]
		assert scroll_test_payloads.map(it.value) == [48.0, 60.5]
	}
}
