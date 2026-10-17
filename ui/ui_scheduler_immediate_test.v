@[has_globals]
module ui2

$if (android || ios || linux || macos || windows) && !ui2_headless ? {
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
	fn scheduler_motion_frame(mut app GgApp, now i64) !FrameWork {
		work := app.scheduler.begin_frame(now) or { return error('expected a frame at ${now}') }
		resolve_custom_layout(mut app, work, measure_layout_text, take_custom_layout_patches(mut app))!
		app.scheduler.set_motion_active(motion_tree_needs_frame(app.declared_root))
		app.scheduler.finish_frame(work)
		return work
	}

	fn scheduler_immediate_finish(mut app GgApp, now i64) FrameWork {
		work := app.scheduler.begin_frame(now) or { panic('expected custom renderer work') }
		app.scheduler.finish_frame(work)
		return work
	}

	fn test_custom_scheduler_lifecycle_restores_surface_after_all_suspensions_end() {
		previous_app := g_gg_app
		previous_touch := g_touch
		previous_tooltip := g_tooltip
		previous_events := g_scheduler_immediate_events.clone()
		defer {
			g_gg_app = previous_app
			g_touch = previous_touch
			g_tooltip = previous_tooltip
			g_scheduler_immediate_events = previous_events.clone()
		}
		mut app := &GgApp{ scheduler: new_frame_coordinator() }
		g_gg_app = app
		g_scheduler_immediate_events = []string{}
		g_scheduler_element_events = []ElementEvent{}
		scheduler_immediate_finish(mut app, 0)
		g_tooltip = TooltipState{ pointer_in: true, visible: true, key: 'hover' }
		g_touch = TouchState{
			down:             true
			current_x:        20
			current_y:        30
			pointer_captured: true
			pointer_target:   HitTarget{ id: 'drag', on_event: scheduler_immediate_event, draggable: true }
		}
		app.scheduler.set_deadline(500)
		on_event(&gg.Event{ typ: .iconified }, app)
		assert app.scheduler.stats().suspended
		assert app.scheduler.stats().next_deadline == -1
		assert !g_tooltip.pointer_in && !g_tooltip.visible
		assert !g_touch.down
		assert g_scheduler_element_events == [ElementEvent{ kind: .pointer_up, id: 'drag', x: 20, y: 30 }]
		on_event(&gg.Event{ typ: .suspended }, app)
		on_event(&gg.Event{ typ: .restored }, app)
		assert app.scheduler.stats().suspended
		if _ := app.scheduler.begin_frame(1_000) {
			assert false, 'restoring an iconified window must not resume a suspended app'
		}
		on_event(&gg.Event{ typ: .resumed }, app)
		assert !app.scheduler.stats().suspended
		restored := scheduler_immediate_finish(mut app, 1_001)
		assert restored.build && restored.draw
		assert restored.reasons.has(.surface)
		if _ := app.scheduler.begin_frame(1_002) {
			assert false, 'the restored surface must return to idle'
		}
		on_event(&gg.Event{ typ: .resized }, app)
		resized := scheduler_immediate_finish(mut app, 1_003)
		assert resized.build && resized.draw
		assert resized.reasons.has(.surface)
	}

	fn test_custom_scheduler_stationary_tooltip_deadline_and_unmount_cancellation() {
		previous_app := g_gg_app
		previous_tooltip := g_tooltip
		previous_targets := g_tooltip_targets.clone()
		previous_touch := g_touch
		previous_dropdown := g_open_dropdown
		previous_menu := g_menu_open_path.clone()
		defer {
			g_gg_app = previous_app
			g_tooltip = previous_tooltip
			g_tooltip_targets = previous_targets.clone()
			g_touch = previous_touch
			g_open_dropdown = previous_dropdown
			g_menu_open_path = previous_menu.clone()
		}
		mut app := &GgApp{ scheduler: new_frame_coordinator() }
		g_gg_app = app
		g_tooltip = TooltipState{}
		g_touch = TouchState{}
		g_open_dropdown = ''
		g_menu_open_path = []int{}
		g_tooltip_targets = [TooltipTarget{
			key:   'help'
			text:  'Stationary pointer help'
			frame: rect(0, 0, 100, 40)
		}]
		scheduler_immediate_finish(mut app, 1_000)
		g_tooltip.pointer_moved(20, 20, 1_000)
		update_tooltip(1_000)
		assert custom_visual_deadline() == 1_500
		app.scheduler.set_deadline(custom_visual_deadline())
		if _ := app.scheduler.begin_frame(1_499) {
			assert false, 'a resting tooltip must wait until its deadline'
		}
		timer := app.scheduler.begin_frame(1_500) or { panic('tooltip deadline did not wake') }
		assert timer.reasons == RenderReason.timer
		assert !timer.build && timer.draw
		update_tooltip(1_500)
		assert g_tooltip.visible
		assert g_tooltip.text == 'Stationary pointer help'
		app.scheduler.set_deadline(custom_visual_deadline())
		app.scheduler.finish_frame(timer)
		assert app.scheduler.stats().next_deadline == -1
		if _ := app.scheduler.begin_frame(1_501) {
			assert false, 'a visible tooltip must not keep requesting frames'
		}

		g_tooltip.pointer_left()
		g_tooltip.pointer_moved(20, 20, 2_000)
		update_tooltip(2_000)
		app.scheduler.set_deadline(custom_visual_deadline())
		assert app.scheduler.stats().next_deadline == 2_500
		g_tooltip_targets = []TooltipTarget{}
		update_tooltip(2_100)
		app.scheduler.set_deadline(custom_visual_deadline())
		assert app.scheduler.stats().next_deadline == -1
		if _ := app.scheduler.begin_frame(2_500) {
			assert false, 'an unmounted tooltip target must cancel its deadline'
		}
	}

	fn test_custom_scheduler_long_press_fires_once_and_cancels_after_movement() {
		previous_app := g_gg_app
		previous_touch := g_touch
		previous_tooltip := g_tooltip
		previous_targets := g_hit_targets.clone()
		previous_events := g_scheduler_immediate_events.clone()
		defer {
			g_gg_app = previous_app
			g_touch = previous_touch
			g_tooltip = previous_tooltip
			g_hit_targets = previous_targets.clone()
			g_scheduler_immediate_events = previous_events.clone()
		}
		mut app := &GgApp{ scheduler: new_frame_coordinator() }
		g_gg_app = app
		g_tooltip = TooltipState{}
		g_scheduler_immediate_events = []string{}
		g_scheduler_element_events = []ElementEvent{}
		g_hit_targets = [HitTarget{
			id:         'hold'
			on_event:   scheduler_immediate_event
			long_press: true
			x:          0
			y:          0
			w:          100
			h:          40
		}]
		g_touch = TouchState{ down: true, start_x: 20, start_y: 20, start_time: 1_000 }
		scheduler_immediate_finish(mut app, 1_000)
		assert custom_visual_deadline() == 1_450
		app.scheduler.set_deadline(custom_visual_deadline())
		if _ := app.scheduler.begin_frame(1_449) {
			assert false, 'long press must wait until its deadline'
		}
		g_touch.start_time = renderer_now_ms() - 450
		app.scheduler.set_deadline(custom_visual_deadline())
		timer := app.scheduler.begin_frame(renderer_now_ms()) or { panic('long press deadline did not wake') }
		assert timer.reasons == RenderReason.timer
		check_long_press()
		check_long_press()
		assert g_scheduler_element_events == [ElementEvent{ kind: .long_press, id: 'hold' }]
		assert custom_visual_deadline() == -1
		app.scheduler.set_deadline(custom_visual_deadline())
		app.scheduler.finish_frame(timer)
		// The application handler runs during the visual frame; its requested
		// model build must survive completion of that frame.
		assert app.scheduler.stats().pending_reasons == RenderReason.build
		scheduler_immediate_finish(mut app, renderer_now_ms())
		if _ := app.scheduler.begin_frame(renderer_now_ms()) {
			assert false, 'a completed long press must return to idle'
		}
		g_touch = TouchState{ down: true, start_x: 20, start_y: 20, start_time: 3_000 }
		app.scheduler.set_deadline(custom_visual_deadline())
		g_touch.moved = true
		app.scheduler.set_deadline(custom_visual_deadline())
		assert app.scheduler.stats().next_deadline == -1
		if _ := app.scheduler.begin_frame(4_000) {
			assert false, 'moving a held pointer must cancel long press work'
		}
		on_event(&gg.Event{ typ: .touches_cancelled }, app)
		assert !g_touch.down
		assert custom_visual_deadline() == -1
		assert g_scheduler_element_events == [ElementEvent{ kind: .long_press, id: 'hold' }]
	}

	fn test_custom_scheduler_setters_only_paint_and_preserve_editor_state() {
		previous_app := g_gg_app
		previous_values := g_text_values.clone()
		previous_editors := g_text_editors.clone()
		previous_active_fields := g_active_fields.clone()
		previous_focused := g_focused_field
		previous_offsets := g_scroll_offsets.clone()
		previous_sliders := g_slider_values.clone()
		previous_specs := g_slider_specs.clone()
		previous_active_sliders := g_active_sliders.clone()
		defer {
			free_owned_string(g_text_values['editor'])
			free_owned_string(g_text_editors['editor'].text)
			g_gg_app = previous_app
			g_text_values = previous_values.clone()
			g_text_editors = previous_editors.clone()
			g_active_fields = previous_active_fields.clone()
			g_focused_field = previous_focused
			g_scroll_offsets = previous_offsets.clone()
			g_slider_values = previous_sliders.clone()
			g_slider_specs = previous_specs.clone()
			g_active_sliders = previous_active_sliders.clone()
		}
		mut app := &GgApp{ scheduler: new_frame_coordinator() }
		g_gg_app = app
		g_text_values = map[string]string{}
		g_text_editors = map[string]TextEditor{}
		g_active_fields = {
			'editor': true
		}
		g_focused_field = 'editor'
		g_scroll_offsets = {
			named_scroll_state_id('editor'): 42.0
		}
		g_slider_values = {
			'volume': 0.0
		}
		g_slider_specs = {
			'volume': SliderSpec{ min: 0, max: 100 }
		}
		g_active_sliders = {
			'volume': true
		}
		replace_text_value('editor', 'local draft')
		replace_text_editor('editor', TextEditor{
			text:      'local draft'.clone()
			selection: TextSelection{ anchor: 1, caret: 5 }
		})
		scheduler_immediate_finish(mut app, 0)
		set_slider_value('volume', 75)
		assert text('editor') == 'local draft'
		assert g_text_editors['editor'].selection == TextSelection{ anchor: 1, caret: 5 }
		assert g_focused_field == 'editor'
		assert scroll_offset('editor') == 42
		paint := scheduler_immediate_finish(mut app, 1)
		assert paint.reasons == RenderReason.paint
		assert !paint.build && paint.draw
		assert slider_value('volume') == 75
		set_text('editor', 'replacement')
		assert text('editor') == 'replacement'
		assert g_text_editors['editor'].selection == TextSelection{ anchor: 1, caret: 5 }
		assert g_focused_field == 'editor'
		assert scroll_offset('editor') == 42
		replacement := scheduler_immediate_finish(mut app, 2)
		assert !replacement.build && replacement.reasons == RenderReason.paint
		set_text('missing', 'ignored')
		set_slider_value('missing', 25)
		if _ := app.scheduler.begin_frame(3) {
			assert false, 'setters on unmounted controls must not request work'
		}
	}

	fn test_custom_scheduler_motion_completion_requests_final_model_build() ! {
		previous_app := g_gg_app
		previous_events := g_scheduler_immediate_events.clone()
		defer {
			g_gg_app.motion_tree.dispose()
			g_gg_app = previous_app
			g_scheduler_immediate_events = previous_events.clone()
		}
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
		mut app := &GgApp{ scheduler: new_frame_coordinator(), has_root: true, declared_root: root }
		g_gg_app = app
		initial := scheduler_motion_frame(mut app, 1_000)!
		assert initial.build
		assert app.scheduler.stats().motion_active
		g_scheduler_motion_now = 1
		terminal := scheduler_motion_frame(mut app, 2_000)!
		// The first frame's progress handler asked for a build; the motion itself
		// did not.
		assert terminal.reasons.has(.motion) && terminal.reasons.has(.motion_follow_up)
		assert g_scheduler_immediate_events == ['progress', 'completed']
		assert !app.scheduler.stats().motion_active
		// The model changed after the terminal frame's build. Its handler must
		// request another build even though motion no longer needs frames.
		follow_up := scheduler_motion_frame(mut app, 2_001)!
		assert follow_up.build
		assert follow_up.reasons == RenderReason.motion_follow_up
		assert g_scheduler_immediate_events == ['progress', 'completed']
		if _ := app.scheduler.begin_frame(2_002) {
			assert false, 'completion follow-up must return to idle'
		}
	}

	fn test_custom_scheduler_hidden_looping_timelines_cannot_keep_drawing() ! {
		previous_app := g_gg_app
		previous_events := g_scheduler_immediate_events.clone()
		defer {
			g_gg_app.motion_tree.dispose()
			g_gg_app = previous_app
			g_scheduler_immediate_events = previous_events.clone()
		}
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
		mut app := &GgApp{ scheduler: new_frame_coordinator(), has_root: true, declared_root: root }
		g_gg_app = app
		scheduler_motion_frame(mut app, 1_000)!
		g_scheduler_motion_now = 0.25
		scheduler_motion_frame(mut app, 1_250)!
		assert app.scheduler.stats().motion_active
		assert app.declared_root.children[0].presented_opacity() == 0.5
		app.declared_root = Element{
			...app.declared_root
			hidden: true
		}
		app.declaration_pending = true
		app.scheduler.invalidate(.build)
		g_scheduler_motion_now = 0.5
		scheduler_motion_frame(mut app, 1_500)!
		assert !app.scheduler.stats().motion_active
		// Nothing samples the hidden timeline, so no handler asks for a frame.
		if _ := app.scheduler.begin_frame(1_900) {
			assert false, 'a hidden looping timeline must not keep drawing'
		}
		// Showing the subtree samples the retained timeline where it stands.
		app.declared_root = root
		app.declaration_pending = true
		app.scheduler.invalidate(.build)
		g_scheduler_motion_now = 1.75
		scheduler_motion_frame(mut app, 2_750)!
		assert app.declared_root.children[0].presented_opacity() == 0.5
		assert app.scheduler.stats().motion_active
	}
}
