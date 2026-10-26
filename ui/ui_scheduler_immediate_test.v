// vtest vflags: -d ui2_custom_rendering
@[has_globals]
module ui2

$if (android || linux || ((ios || macos || windows) && ui2_custom_rendering ?)) && !ui2_headless ? {
	import gg

	__global g_scheduler_immediate_events = []string{}
	__global g_scheduler_element_events = []ElementEvent{}

	fn scheduler_immediate_event(event ElementEvent) {
		g_scheduler_element_events << event
	}

	__global g_scheduler_motion_now = f64(0)

	fn scheduler_motion_clock() f64 {
		return g_scheduler_motion_now
	}

	fn scheduler_immediate_motion_event(event MotionEvent) {
		match event.kind {
			.complete { g_scheduler_immediate_events << 'completed' }
			.progress { g_scheduler_immediate_events << 'progress' }
			else {}
		}
	}

	// scheduler_motion_frame runs one frame's layout and motion the way on_frame does.
	fn scheduler_motion_frame(mut w Window, now i64) !FrameWork {
		work := w.scheduler.begin_frame(now) or { return error('expected a frame at ${now}') }
		w.resolve_custom_layout(work, measure_layout_text, w.take_custom_layout_patches())!
		w.scheduler.set_motion_active(motion_tree_needs_frame(w.declared_root))
		w.scheduler.finish_frame(work)
		return work
	}

	fn scheduler_immediate_finish(mut w Window, now i64) FrameWork {
		work := w.scheduler.begin_frame(now) or { panic('expected custom renderer work') }
		w.scheduler.finish_frame(work)
		return work
	}

	fn test_custom_scheduler_lifecycle_restores_surface_after_all_suspensions_end() {
		previous_events := g_scheduler_immediate_events.clone()
		mut w := &Window{}
		previous_touch := w.touch
		previous_tooltip := w.tooltip
		defer {
			w.touch = previous_touch
			w.tooltip = previous_tooltip
			g_scheduler_immediate_events = previous_events.clone()
		}
		g_scheduler_immediate_events = []string{}
		g_scheduler_element_events = []ElementEvent{}
		scheduler_immediate_finish(mut w, 0)
		w.tooltip = TooltipState{ pointer_in: true, visible: true, key: 'hover' }
		w.touch = TouchState{
			down:             true
			current_x:        20
			current_y:        30
			pointer_captured: true
			pointer_target:   HitTarget{ id: 'drag', on_event: scheduler_immediate_event, draggable: true }
		}
		w.scheduler.set_deadline(500)
		on_event(&gg.Event{ typ: .iconified }, mut w)
		assert w.scheduler.stats().suspended
		assert w.scheduler.stats().next_deadline == -1
		assert !w.tooltip.pointer_in && !w.tooltip.visible
		assert !w.touch.down
		assert g_scheduler_element_events == [ElementEvent{ window: w, kind: .pointer_up, id: 'drag', x: 20, y: 30 }]
		on_event(&gg.Event{ typ: .suspended }, mut w)
		on_event(&gg.Event{ typ: .restored }, mut w)
		assert w.scheduler.stats().suspended
		if _ := w.scheduler.begin_frame(1_000) {
			assert false, 'restoring an iconified window must not resume a suspended w'
		}
		on_event(&gg.Event{ typ: .resumed }, mut w)
		assert !w.scheduler.stats().suspended
		restored := scheduler_immediate_finish(mut w, 1_001)
		assert restored.build && restored.draw
		assert restored.reasons.has(.surface)
		if _ := w.scheduler.begin_frame(1_002) {
			assert false, 'the restored surface must return to idle'
		}
		on_event(&gg.Event{ typ: .resized }, mut w)
		resized := scheduler_immediate_finish(mut w, 1_003)
		assert resized.build && resized.draw
		assert resized.reasons.has(.surface)
	}

	fn test_custom_scheduler_stationary_tooltip_deadline_and_unmount_cancellation() {
		mut w := &Window{}
		previous_tooltip := w.tooltip
		previous_targets := w.tooltip_targets.clone()
		previous_touch := w.touch
		previous_dropdown := w.dropdown_id
		previous_menu := w.menu_open_path.clone()
		defer {
			w.tooltip = previous_tooltip
			w.tooltip_targets = previous_targets.clone()
			w.touch = previous_touch
			w.dropdown_id = previous_dropdown
			w.menu_open_path = previous_menu.clone()
		}
		w.tooltip = TooltipState{}
		w.touch = TouchState{}
		w.dropdown_id = ''
		w.menu_open_path = []int{}
		w.tooltip_targets = [TooltipTarget{
			key:   'help'
			text:  'Stationary pointer help'
			frame: rect(0, 0, 100, 40)
		}]
		scheduler_immediate_finish(mut w, 1_000)
		w.tooltip.pointer_moved(20, 20, 1_000)
		w.update_tooltip(1_000)
		assert w.custom_visual_deadline() == 1_500
		w.scheduler.set_deadline(w.custom_visual_deadline())
		if _ := w.scheduler.begin_frame(1_499) {
			assert false, 'a resting tooltip must wait until its deadline'
		}
		timer := w.scheduler.begin_frame(1_500) or { panic('tooltip deadline did not wake') }
		assert timer.reasons == RenderReason.timer
		assert !timer.build && timer.draw
		w.update_tooltip(1_500)
		assert w.tooltip.visible
		assert w.tooltip.text == 'Stationary pointer help'
		w.scheduler.set_deadline(w.custom_visual_deadline())
		w.scheduler.finish_frame(timer)
		assert w.scheduler.stats().next_deadline == -1
		if _ := w.scheduler.begin_frame(1_501) {
			assert false, 'a visible tooltip must not keep requesting frames'
		}

		w.tooltip.pointer_left()
		w.tooltip.pointer_moved(20, 20, 2_000)
		w.update_tooltip(2_000)
		w.scheduler.set_deadline(w.custom_visual_deadline())
		assert w.scheduler.stats().next_deadline == 2_500
		w.tooltip_targets = []TooltipTarget{}
		w.update_tooltip(2_100)
		w.scheduler.set_deadline(w.custom_visual_deadline())
		assert w.scheduler.stats().next_deadline == -1
		if _ := w.scheduler.begin_frame(2_500) {
			assert false, 'an unmounted tooltip target must cancel its deadline'
		}
	}

	fn test_custom_scheduler_long_press_fires_once_and_cancels_after_movement() {
		previous_events := g_scheduler_immediate_events.clone()
		mut w := &Window{}
		previous_touch := w.touch
		previous_tooltip := w.tooltip
		previous_targets := w.hit_targets.clone()
		defer {
			w.touch = previous_touch
			w.tooltip = previous_tooltip
			w.hit_targets = previous_targets.clone()
			g_scheduler_immediate_events = previous_events.clone()
		}
		w.tooltip = TooltipState{}
		g_scheduler_immediate_events = []string{}
		g_scheduler_element_events = []ElementEvent{}
		w.hit_targets = [HitTarget{
			id:         'hold'
			on_event:   scheduler_immediate_event
			long_press: true
			x:          0
			y:          0
			w:          100
			h:          40
		}]
		w.touch = TouchState{ down: true, start_x: 20, start_y: 20, start_time: 1_000 }
		scheduler_immediate_finish(mut w, 1_000)
		assert w.custom_visual_deadline() == 1_450
		w.scheduler.set_deadline(w.custom_visual_deadline())
		if _ := w.scheduler.begin_frame(1_449) {
			assert false, 'long press must wait until its deadline'
		}
		w.touch.start_time = renderer_now_ms() - 450
		w.scheduler.set_deadline(w.custom_visual_deadline())
		timer := w.scheduler.begin_frame(renderer_now_ms()) or { panic('long press deadline did not wake') }
		assert timer.reasons == RenderReason.timer
		w.check_long_press()
		w.check_long_press()
		assert g_scheduler_element_events == [ElementEvent{ window: w, kind: .long_press, id: 'hold' }]
		assert w.custom_visual_deadline() == -1
		w.scheduler.set_deadline(w.custom_visual_deadline())
		w.scheduler.finish_frame(timer)
		// The application handler runs during the visual frame; its requested
		// model build must survive completion of that frame.
		assert w.scheduler.stats().pending_reasons == RenderReason.build
		scheduler_immediate_finish(mut w, renderer_now_ms())
		if _ := w.scheduler.begin_frame(renderer_now_ms()) {
			assert false, 'a completed long press must return to idle'
		}
		w.touch = TouchState{ down: true, start_x: 20, start_y: 20, start_time: 3_000 }
		w.scheduler.set_deadline(w.custom_visual_deadline())
		w.touch.moved = true
		w.scheduler.set_deadline(w.custom_visual_deadline())
		assert w.scheduler.stats().next_deadline == -1
		if _ := w.scheduler.begin_frame(4_000) {
			assert false, 'moving a held pointer must cancel long press work'
		}
		on_event(&gg.Event{ typ: .touches_cancelled }, mut w)
		assert !w.touch.down
		assert w.custom_visual_deadline() == -1
		assert g_scheduler_element_events == [ElementEvent{ window: w, kind: .long_press, id: 'hold' }]
	}

	fn test_custom_scheduler_setters_only_paint_and_preserve_editor_state() {
		mut w := &Window{}
		previous_values := w.text_values.clone()
		previous_editors := w.text_editors.clone()
		previous_active_fields := w.active_fields.clone()
		previous_focused := w.focused_field
		previous_offsets := w.scroll_offsets.clone()
		previous_sliders := w.slider_values.clone()
		previous_specs := w.slider_specs.clone()
		previous_active_sliders := w.active_sliders.clone()
		defer {
			free_owned_string(w.text_values['editor'])
			free_owned_string(w.text_editors['editor'].text)
			w.text_values = previous_values.clone()
			w.text_editors = previous_editors.clone()
			w.active_fields = previous_active_fields.clone()
			w.focused_field = previous_focused
			w.scroll_offsets = previous_offsets.clone()
			w.slider_values = previous_sliders.clone()
			w.slider_specs = previous_specs.clone()
			w.active_sliders = previous_active_sliders.clone()
		}
		w.text_values = map[string]string{}
		w.text_editors = map[string]TextEditor{}
		w.active_fields = {
			'editor': true
		}
		w.focused_field = 'editor'
		w.scroll_offsets = {
			named_scroll_state_id('editor'): 42.0
		}
		w.slider_values = {
			'volume': 0.0
		}
		w.slider_specs = {
			'volume': SliderSpec{ min: 0, max: 100 }
		}
		w.active_sliders = {
			'volume': true
		}
		w.replace_text_value('editor', 'local draft')
		w.replace_text_editor('editor', TextEditor{
			text:      'local draft'.clone()
			selection: TextSelection{ anchor: 1, caret: 5 }
		})
		scheduler_immediate_finish(mut w, 0)
		w.set_slider_value('volume', 75)
		assert w.text('editor') == 'local draft'
		assert w.text_editors['editor'].selection == TextSelection{ anchor: 1, caret: 5 }
		assert w.focused_field == 'editor'
		assert w.scroll_offset('editor') == 42
		paint := scheduler_immediate_finish(mut w, 1)
		assert paint.reasons == RenderReason.paint
		assert !paint.build && paint.draw
		assert w.slider_value('volume') == 75
		w.set_text('editor', 'replacement')
		assert w.text('editor') == 'replacement'
		assert w.text_editors['editor'].selection == TextSelection{ anchor: 1, caret: 5 }
		assert w.focused_field == 'editor'
		assert w.scroll_offset('editor') == 42
		replacement := scheduler_immediate_finish(mut w, 2)
		assert !replacement.build && replacement.reasons == RenderReason.paint
		w.set_text('missing', 'ignored')
		w.set_slider_value('missing', 25)
		if _ := w.scheduler.begin_frame(3) {
			assert false, 'setters on unmounted controls must not request work'
		}
	}

	fn test_custom_scheduler_motion_completion_requests_final_model_build() ! {
		previous_events := g_scheduler_immediate_events.clone()
		g_scheduler_motion_now = 0
		g_scheduler_immediate_events = []string{}
		root := screen(0xffffff, [
			with_motion(view('animated', rect(0, 0, 40, 40), BoxStyle{}, []), MotionConfig{
				clock:            scheduler_motion_clock
				enter:            MotionStyle{ translate_x: -100 }
				enter_transition: MotionTransition{ duration: 1 }
				on_motion:        scheduler_immediate_motion_event
			}),
		])
		mut w := &Window{ scheduler: new_frame_coordinator(), has_root: true, declared_root: root }
		defer {
			w.motion_tree.dispose()
			g_scheduler_immediate_events = previous_events.clone()
		}
		initial := scheduler_motion_frame(mut w, 1_000)!
		assert initial.build
		assert w.scheduler.stats().motion_active
		g_scheduler_motion_now = 1
		terminal := scheduler_motion_frame(mut w, 2_000)!
		// The first frame's progress handler asked for a build; the motion itself
		// did not.
		assert terminal.reasons.has(.motion) && terminal.reasons.has(.motion_follow_up)
		assert g_scheduler_immediate_events == ['progress', 'completed']
		assert !w.scheduler.stats().motion_active
		// The model changed after the terminal frame's build. Its handler must
		// request another build even though motion no longer needs frames.
		follow_up := scheduler_motion_frame(mut w, 2_001)!
		assert follow_up.build
		assert follow_up.reasons == RenderReason.motion_follow_up
		assert g_scheduler_immediate_events == ['progress', 'completed']
		if _ := w.scheduler.begin_frame(2_002) {
			assert false, 'completion follow-up must return to idle'
		}
	}

	fn test_custom_scheduler_hidden_looping_timelines_cannot_keep_drawing() ! {
		previous_events := g_scheduler_immediate_events.clone()
		g_scheduler_motion_now = 0
		g_scheduler_immediate_events = []string{}
		pulse := with_motion(view('animated', rect(0, 0, 40, 40), BoxStyle{}, []), MotionConfig{
			clock:     scheduler_motion_clock
			enter:     MotionStyle{}
			timeline:  motion_keyframes(1, MotionKeyframe{ at: 0.5, style: MotionStyle{ opacity: 0 } },
				MotionKeyframe{ at: 1, style: MotionStyle{ opacity: 1 } }).looped()
			on_motion: scheduler_immediate_motion_event
		})
		root := screen(0xffffff, [pulse])
		mut w := &Window{ scheduler: new_frame_coordinator(), has_root: true, declared_root: root }
		defer {
			w.motion_tree.dispose()
			g_scheduler_immediate_events = previous_events.clone()
		}
		scheduler_motion_frame(mut w, 1_000)!
		g_scheduler_motion_now = 0.25
		scheduler_motion_frame(mut w, 1_250)!
		assert w.scheduler.stats().motion_active
		assert w.declared_root.children[0].presented_opacity() == 0.5
		w.declared_root = Element{
			...w.declared_root
			hidden: true
		}
		w.declaration_pending = true
		w.scheduler.invalidate(.build)
		g_scheduler_motion_now = 0.5
		scheduler_motion_frame(mut w, 1_500)!
		assert !w.scheduler.stats().motion_active
		// Nothing samples the hidden timeline, so no handler asks for a frame.
		if _ := w.scheduler.begin_frame(1_900) {
			assert false, 'a hidden looping timeline must not keep drawing'
		}
		// Showing the subtree samples the retained timeline where it stands.
		w.declared_root = root
		w.declaration_pending = true
		w.scheduler.invalidate(.build)
		g_scheduler_motion_now = 1.75
		scheduler_motion_frame(mut w, 2_750)!
		assert w.declared_root.children[0].presented_opacity() == 0.5
		assert w.scheduler.stats().motion_active
	}
}
