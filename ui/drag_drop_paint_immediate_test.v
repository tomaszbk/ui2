// vtest build: macos && ui2_custom_rendering? && !ui2_headless?
// vtest vflags: -d ui2_custom_rendering
@[has_globals]
module ui2

$if macos && ui2_custom_rendering ? && !ui2_headless ? {
	__global paint_drag_events = []ElementEvent{}
	__global paint_drag_current_events = []ElementEvent{}
	__global paint_drag_stage = ''
	__global paint_drag_change = ''
	__global paint_drag_changed = false
	__global paint_drag_accepts = 0
	__global paint_drag_anonymous = false

	fn paint_drag_accept(_ DragOffer) DragOperation {
		paint_drag_accepts++
		if paint_drag_stage == 'accept' && paint_drag_accepts == 3 {
			paint_drag_changed = true
			refresh()
		}
		return .move
	}
	fn paint_drag_reject(_ DragOffer) DragOperation { return .none }
	fn paint_drag_current(event ElementEvent) { paint_drag_current_events << event }
	fn paint_drag_record(event ElementEvent) {
		paint_drag_events << event
		if (paint_drag_stage == 'enter' && event.kind == .drag_enter)
			|| (paint_drag_stage == 'over' && event.kind == .drag_over) {
			paint_drag_changed = true
			refresh()
		}
	}
	fn paint_drag_build() Element {
		mut source := with_event(with_drag_source(view(if paint_drag_anonymous { '' } else { 'paint-source' },
			rect(10, 20, 40, 40), BoxStyle{}, []), DragSource{}), paint_drag_record)
		mut target := with_event(with_drop_target(view(if paint_drag_anonymous { '' } else { 'paint-target' },
			rect(100, 20, 60, 50), BoxStyle{}, []), DropTarget{accept: paint_drag_accept}), paint_drag_record)
		mut caption := rich_label('caption', [TextRun{text: 'Move here', style: TextStyle{color: 0xffffff}}],
			rect(0, 80, 150, 30), TextStyle{})
		if paint_drag_change.starts_with('area_') { caption = Element{kind: .text_area, id: 'caption', text: 'line\n'.repeat(30), frame: rect(200, 0, 80, 80)} }
		if paint_drag_change == 'dropdown_size' { caption = Element{kind: .dropdown, id: 'caption', frame: rect(200, 0, 80, 80)} }
		if paint_drag_changed {
			target = Element{...target,
				box: BoxStyle{bg: 0x15803d, radius: 8, transparent: true, border_color: 0xff0000,
					border_left: 3, border_top: 4, border_right: 5, border_bottom: 6,
					border_pattern: .dashed, dash_length: 2, dash_gap: 1,
					outline_color: 0x0000ff, outline_width: 3, outline_offset: 2},
				interaction_style: InteractionStyle{hover: BoxStylePatch{bg: u32(0x123456), radius: 12},
					pressed_text: TextStylePatch{color: u32(0xabcdef)}},
				text_style: TextStyle{color: 0xff0000, background_color: 0xeeeeee},
				rotation: 30, slider_style: SliderStyle{track_color: 0xff0000, thumb_size: 30},
				switch_style: SwitchStyle{active_track_color: 0xff0000}}
			caption = Element{...caption, text: 'Highlighted niño / café',
				text_style: TextStyle{size: 24, color: 0x00ff00},
				text_runs: [TextRun{text: 'Highlighted niño / café', style: TextStyle{size: 24, color: 0x00ff00}}]}
			if paint_drag_change.starts_with('area_') {
				caption = Element{kind: .text_area, id: 'caption', text: 'line\n'.repeat(30), frame: rect(200, 0, 80, 80),
					text_style: if paint_drag_change == 'area_color' { TextStyle{color: 0xff0000, background_color: 0xeeeeee} }
					else { TextStyle{size: 24, line_height: 30} }}
			}
			if paint_drag_change == 'dropdown_size' { caption = Element{kind: .dropdown, id: 'caption', frame: rect(200, 0, 80, 80), text_style: TextStyle{size: 24}} }
			if paint_drag_change == 'current_callbacks' {
				source = Element{...source, on_event: paint_drag_current}
				target = Element{...target, on_event: paint_drag_current}
			}
			if paint_drag_change == 'disallow' { source = Element{...source, drag_source: DragSource{allowed: [.copy]}} }
			if paint_drag_change == 'reject' { target = Element{...target, drop_target: DropTarget{accept: paint_drag_reject}} }
			if paint_drag_change == 'withdraw' { target = Element{...target, drop_target: none} }
			if paint_drag_change == 'move' { target = Element{...target, frame: rect(300, 20, 60, 50)} }
			if paint_drag_change == 'resize' { target = Element{...target, frame: rect(100, 20, 20, 50)} }
			if paint_drag_change == 'reorder' { return screen(0, [target, source, caption]) }
			if paint_drag_change == 'new_blocker' {
				return screen(0, [source, target, caption, with_event(Element{kind: .button,
					id: 'new-blocker', frame: rect(100, 20, 60, 50)}, paint_drag_current)])
			}
		}
		return screen(0, [source, target, caption])
	}
	fn mount_paint_drag(stage string, change string, anonymous bool) {
		g_gg_app = &GgApp{}
		g_touch = TouchState{}
		g_drag_registry = DragRegistry{}
		g_tooltip = TooltipState{}
		g_scroll_offsets = map[string]f64{}
		g_active_scrolls = map[string]bool{}
		set_menu_bar([]Menu{})
		reset_scroll_frame()
		close_dropdown()
		paint_drag_stage = stage
		paint_drag_change = change
		paint_drag_changed = false
		paint_drag_anonymous = anonymous
		paint_drag_accepts = 0
		paint_drag_events = []ElementEvent{}
		paint_drag_current_events = []ElementEvent{}
		g_build_screen = paint_drag_build
		assert build_custom_declaration(mut g_gg_app)
		refresh_drag_owners(g_gg_app.declared_root)
		source := g_drag_registry.owners[if anonymous { 'path:root/i:0' } else { 'id:paint-source' }]
		target := g_drag_registry.owners[if anonymous { 'path:root/i:1' } else { 'id:paint-target' }]
		// This fixture seeds the rendered rectangles, then completes mount work.
		// Changes below use only application state, build and public refresh.
		g_hit_targets = [HitTarget{...source, x: 10, y: 20, w: 40, h: 40},
			HitTarget{...target, x: 100, y: 20, w: 60, h: 50}]
		work := g_gg_app.scheduler.begin_frame(0) or { panic('missing mount') }
		g_gg_app.scheduler.finish_frame(work)
		g_gg_app.hit_declaration = g_gg_app.declared_root
		g_gg_app.has_hit_declaration = true
		assert RenderReason.surface !in g_gg_app.scheduler.stats().pending_reasons
	}
	fn test_paint_highlight_enter_over_and_final_accept_drop_before_next_frame() {
		for anonymous in [false, true] {
			for stage in ['enter', 'over', 'accept'] {
				mount_paint_drag(stage, '', anonymous)
				handle_touch_down(20, 30)
				handle_touch_up(120, 30)
				assert paint_drag_changed
				assert paint_drag_events.map(it.kind) == [.drag_start, .drag_enter, .drag_over, .drop, .drag_leave, .drag_end]
				assert !g_touch.down && !g_touch.pointer_captured && !drag_active()
				assert g_gg_app.scheduler.stats().draws == 0
				assert g_gg_app.scheduler.stats().flushes == 1 && g_gg_app.scheduler.stats().pending
				println('PAINT ${stage} anonymous=${anonymous} drop1 cancel0 before-frame PASS')
			}
		}
	}
	fn test_paint_refresh_keeps_current_callback_ownership_and_operation_validation() {
		mount_paint_drag('enter', 'current_callbacks', false)
		handle_touch_down(20, 30)
		handle_touch_up(120, 30)
		// The source callback is captured at down; the destination is current.
		assert paint_drag_current_events.map(it.kind) == [.drop, .drag_leave]
		assert paint_drag_events.map(it.kind) == [.drag_start, .drag_enter, .drag_over, .drag_end]
		for change in ['disallow', 'reject', 'withdraw', 'move', 'resize', 'reorder', 'new_blocker', 'area_metrics', 'dropdown_size'] {
			mount_paint_drag('over', change, false)
			handle_touch_down(20, 30)
			handle_touch_up(120, 30)
			assert paint_drag_events.filter(it.kind == .drop || it.kind == .tap).len == 0
			assert paint_drag_events.filter(it.kind == .drag_cancel).len == 1
			assert !g_touch.down && !g_touch.pointer_captured && !drag_active()
		}
	}
	fn test_text_area_color_preserves_drop_but_scroll_metrics_wait_for_frame() {
		mount_paint_drag('over', 'area_color', false)
		handle_touch_down(20, 30)
		handle_touch_up(120, 30)
		assert paint_drag_events.filter(it.kind == .drop).len == 1
		assert paint_drag_events.filter(it.kind == .drag_cancel).len == 0
	}
	fn test_paint_unchanged_refresh_still_drops_before_frame() {
		mount_paint_drag('', '', false)
		refresh()
		handle_touch_down(20, 30)
		handle_touch_up(120, 30)
		assert paint_drag_events.filter(it.kind == .drop).len == 1
		assert paint_drag_events.filter(it.kind == .drag_cancel || it.kind == .tap).len == 0
	}
}
