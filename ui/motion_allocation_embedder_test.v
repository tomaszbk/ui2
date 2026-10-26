// vtest vflags: -gc boehm -d no_gc_thread_local_alloc -d ui2_custom_rendering -d ui2_embedder
@[has_globals]
module ui2

$if macos && ui2_custom_rendering ?&& ui2_embedder ?&& !ui2_headless ? {
	import gg
	import sokol.gfx

	__global motion_allocation_now = f64(0)

	fn motion_allocation_clock() f64 {
		return motion_allocation_now
	}

	fn motion_allocation_environment() gfx.Environment {
		return gfx.Environment{
			defaults: gfx.EnvironmentDefaults{
				color_format: .bgra8
				depth_format: .@none
				sample_count: 1
			}
			metal:    gfx.MetalEnvironment{ device: C.ui2_embedder_metal_device() }
		}
	}
}

// The measured loop drives a real owned Metal window, text shaping, focus,
// public geometry queries, transformed pointer hits and GPU submission. It
// performs no declaration writes or geometry captures and advances only the
// injected motion clock.
fn test_actual_running_motion_frames_keep_gc_and_layout_idle_after_warmup() ! {
	motion_allocation_acceptance(false)!
}

fn test_actual_rotating_scaled_scroll_motion_frames_allocate_nothing() ! {
	motion_allocation_acceptance(true)!
}

fn motion_allocation_acceptance(rotating bool) ! {
	$if macos && ui2_custom_rendering ?&& ui2_embedder ?&& !ui2_headless ? {
		mut ctx := new_surface_draw_context(gg.Config{ width: 400, height: 300 },
			motion_allocation_environment())!
		window := C.ui2_embedder_create(&C.ui2_embedder_config{
			title:   c'Motion allocation acceptance'
			width:   400
			height:  300
			visible: false
		}, &C.ui2_embedder_callbacks{}, unsafe { nil })
		assert window != unsafe { nil }
		defer {
			C.ui2_embedder_close(window)
			ctx.destroy()
		}
		motion_allocation_now = 0
		button_el := button('hover', 'España café ñ', rect(12, 12, 160, 28),
			BoxStyle{ bg: 0xabcdef, radius: 6 }, TextStyle{ size: 16 })
		field := text_input(TextInputConfig{
			id:         'edit'
			text:       'año selección'
			frame:      rect(12, 60, 170, 30)
			box:        BoxStyle{ bg: 0xffffff }
			text_style: TextStyle{ size: 16 }
		})!
		pane := if rotating {
			scroll('panel', rect(40, 30, 250, 150), 0xdbeafe, [button_el, field])
		} else {
			view('panel', rect(40, 30, 250, 150), BoxStyle{ bg: 0xdbeafe }, [
				button_el,
				field,
			])
		}
		panel := with_motion(pane, MotionConfig{
			clock:            motion_allocation_clock
			enter:            MotionStyle{
				opacity:     0
				translate_x: -20
				scale_x:     0.9
				scale_y:     0.9
				rotation:    if rotating { 19.0 } else { 0.0 }
				origin_x:    125
				origin_y:    75
			}
			enter_transition: MotionTransition{ duration: 30 }
		})
		content := if rotating {
			with_motion(scaled_content('fixed', rect(10, 10, 380, 280), 400, 300,
				BoxStyle{ transparent: true }, [panel]), MotionConfig{
				clock:            motion_allocation_clock
				enter:            MotionStyle{
					opacity:  0.5
					rotation: -7
					origin_x: 190
					origin_y: 140
				}
				enter_transition: MotionTransition{ duration: 30 }
			})
		} else {
			panel
		}
		root := Element{
			...screen(0xffffff, [content])
			id:    'root'
			frame: rect(0, 0, 400, 300)
		}
		mut w := &Window{ ctx: ctx, native_window: window, has_root: true, declared_root: root }
		defer { w.motion_tree.dispose() }
		on_frame(mut w)
		w.focus('edit')
		for i in 1 .. 9 {
			motion_allocation_now = f64(i) / 60
			on_frame(mut w)
			assert w.mounted_geometry('hover')!.bounds().width > 0
		}
		before_frames := w.scheduler.stats()
		before_layout := w.layout_stats()
		before_shapes := ctx.text.shape_builds
		before := gc_allocation_snapshot()!
		for i in 9 .. 1009 {
			motion_allocation_now = f64(i) / 60
			on_frame(mut w)
			geometry := w.mounted_geometry('hover')!
			bounds := geometry.bounds()
			point := geometry.transform.point(geometry.frame.x + 80, geometry.frame.y + 14)
			assert presentation_bounds_contains(bounds, point.x, point.y)
			assert geometry.contains(point.x, point.y)
			assert w.hit_test(point.x, point.y).id == 'hover'
			assert w.focused_field == 'edit'
		}
		delta := gc_allocation_snapshot()!.delta_since(before)
		after_frames := w.scheduler.stats()
		after_layout := w.layout_stats()
		println('owned Metal motion: rotating=${rotating} frames=1000 bytes=${delta.allocated_bytes} collections=${delta.collections}')
		assert after_frames.draws == before_frames.draws + 1000
		assert after_frames.builds == before_frames.builds
		assert after_layout.measure_visits == before_layout.measure_visits
		assert after_layout.layout_visits == before_layout.layout_visits
		assert ctx.text.shape_builds == before_shapes
		assert ctx.inner.r.error() == .no_error
		assert delta.allocated_bytes == 0
		assert delta.collections == 0
		motion_allocation_now = 30
		on_frame(mut w)
		completed := w.scheduler.stats()
		assert !completed.motion_active && !completed.pending
		for _ in 0 .. 8 { on_frame(mut w) }
		assert w.scheduler.stats().draws == completed.draws
	}
}
