// vtest vflags: -gc boehm -d no_gc_thread_local_alloc -d ui2_custom_rendering -d ui2_embedder
@[has_globals]
module ui2

$if macos && ui2_custom_rendering ?&& ui2_embedder ?&& !ui2_headless ? {
	import gg
	import sokol.gfx
	import sokol.sgl

	fn affine_allocation_environment() gfx.Environment {
		return gfx.Environment{
			defaults: gfx.EnvironmentDefaults{ color_format: .bgra8, depth_format: .@none, sample_count: 1 }
			metal:    gfx.MetalEnvironment{ device: C.ui2_embedder_metal_device() }
		}
	}
}

fn test_complete_affine_scaled_scroll_scene_hover_allocates_nothing() ! {
	$if macos && ui2_custom_rendering ?&& ui2_embedder ?&& !ui2_headless ? {
		previous_app := g_gg_app
		previous_build := g_build_screen
		previous_state := activate_custom_window_state(new_custom_window_state())
		mut ctx := new_surface_draw_context(gg.Config{ width: 400, height: 300 }, affine_allocation_environment())!
		window := C.ui2_embedder_create(&C.ui2_embedder_config{ title: c'Affine allocation acceptance', width: 400, height: 300, visible: false }, &C.ui2_embedder_callbacks{}, unsafe { nil })
		assert window != unsafe { nil }
		defer {
			C.ui2_embedder_close(window)
			ctx.destroy()
			activate_custom_window_state(previous_state)
			g_build_screen = previous_build
			g_gg_app = previous_app
		}
		g_build_screen = unsafe { nil }
		hover := Element{
			...button('hover', 'España café', rect(12, 12, 120, 28), BoxStyle{ bg: 0xabcdef, radius: 6 }, TextStyle{ size: 16 })
			interaction_style: InteractionStyle{ hover: BoxStylePatch{ bg: 0xcdefab }, hover_text: TextStylePatch{ color: 0xaa1010 } }
		}
		pane := with_transform(scroll('pane', rect(40, 30, 220, 160), 0xdbeafe, [
			hover,
			label('first', 'año selección', rect(8, 52, 170, 24), TextStyle{ size: 16 }),
			label('second', 'segunda línea', rect(8, 90, 170, 24), TextStyle{ size: 16 }),
			dropdown('chooser', 'España', ['España', 'café ñ'], rect(8, 124, 170, 28), BoxStyle{ bg: 0xf1f5f9 }, TextStyle{ size: 16 }),
			label('outside', 'fuera', rect(8, 220, 170, 24), TextStyle{ size: 16 }),
		]), VisualTransform{ rotation: 19, origin_x: 110, origin_y: 80 })
		fixed := with_transform(scaled_content('fixed', rect(10, 10, 360, 260), 400, 300, BoxStyle{ transparent: true }, [pane]),
			VisualTransform{ rotation: -7, origin_x: 180, origin_y: 130 })
		root := Element{ ...screen(0xffffff, [fixed]), id: 'root', frame: rect(0, 0, 400, 300) }
		g_gg_app = &GgApp{ ctx: ctx, native_window: window, has_root: true, declared_root: root }
		on_frame(mut g_gg_app)
		geometry := visual_geometry('hover')!
		point := geometry.transform.point(geometry.frame.x + 60, geometry.frame.y + 14)
		assert geometry.contains(point.x, point.y)
		assert hit_test(point.x, point.y).id == 'hover'
		choice_geometry := visual_geometry('chooser')!
		choice_point := choice_geometry.transform.point(choice_geometry.frame.x + 85, choice_geometry.frame.y + 14)
		assert choice_geometry.contains(choice_point.x, choice_point.y)
		assert hit_test(choice_point.x, choice_point.y).options == ['España', 'café ñ']
		choice_hover := gg.Event{ typ: .mouse_move, mouse_x: f32(choice_point.x), mouse_y: f32(choice_point.y) }
		inside := gg.Event{ typ: .mouse_move, mouse_x: f32(point.x), mouse_y: f32(point.y) }
		outside := gg.Event{ typ: .mouse_move, mouse_x: 390, mouse_y: 290 }
		for i in 0 .. 8 {
			on_event(match i % 3 {
				0 { &inside }
				1 { &outside }
				else { &choice_hover }
			}, g_gg_app)
			on_frame(mut g_gg_app)
		}
		draws_before := g_gg_app.scheduler.stats().draws
		before := gc_allocation_snapshot()!
		for i in 0 .. 100 {
			on_event(match i % 3 {
				0 { &inside }
				1 { &outside }
				else { &choice_hover }
			}, g_gg_app)
			on_frame(mut g_gg_app)
		}
		delta := gc_allocation_snapshot()!.delta_since(before)
		assert g_gg_app.scheduler.stats().draws - draws_before == 100
		assert sgl.error() == .no_error
		assert delta.allocated_bytes == 0
		assert delta.collections == 0
		assert hit_test(point.x, point.y).id == 'hover'
		old_chooser := g_focus_navigation.node('chooser') or { panic('chooser must be mounted') }
		old_options := old_chooser.menu_options_snapshot()
		refresh_element('chooser', Element{
			...old_chooser.el
			menu: [MenuEntry{ id: 'one', title: 'Perú' }, MenuEntry{ id: 'two', title: 'año' }]
		})
		on_frame(mut g_gg_app)
		new_chooser := g_focus_navigation.node('chooser') or { panic('chooser must stay mounted') }
		assert old_options == ['España', 'café ñ']
		assert new_chooser.menu_options_snapshot() == ['Perú', 'año']
		assert hit_test(choice_point.x, choice_point.y).options == ['Perú', 'año']
		assert mounted_menu_options(new_chooser.el, new_chooser.path).data == new_chooser.menu_options.data
		for i in 0 .. 8 {
			on_event(if i % 2 == 0 { &choice_hover } else { &outside }, g_gg_app)
			on_frame(mut g_gg_app)
		}
		changed_draws_before := g_gg_app.scheduler.stats().draws
		changed_before := gc_allocation_snapshot()!
		for i in 0 .. 100 {
			on_event(if i % 2 == 0 { &choice_hover } else { &outside }, g_gg_app)
			on_frame(mut g_gg_app)
		}
		changed_delta := gc_allocation_snapshot()!.delta_since(changed_before)
		assert g_gg_app.scheduler.stats().draws - changed_draws_before == 100
		assert changed_delta.allocated_bytes == 0
		assert changed_delta.collections == 0
	}
}

fn test_clip_cache_misses_and_cancellation_preserve_published_clip_snapshots() ! {
	$if macos && ui2_custom_rendering ?&& ui2_embedder ?&& !ui2_headless ? {
		mut ctx := new_surface_draw_context(gg.Config{ width: 400, height: 300 }, affine_allocation_environment())!
		defer { ctx.destroy() }
		transform := VisualTransform{ rotation: 19, origin_x: 60, origin_y: 40 }.matrix(rect(10, 10, 120, 80))!
		ctx.begin()
		first := ctx.retained_clip(ClipRegion{}, rect(10, 10, 120, 80), transform)
		first_snapshot := first
		first_bounds := first.bounds()
		ctx.cancel()
		ctx.begin()
		changed := ctx.retained_clip(ClipRegion{}, rect(10, 10, 140, 80), transform)
		ctx.cancel()
		assert changed.bounds() != first_bounds
		assert first == first_snapshot && first.bounds() == first_bounds
		ctx.begin()
		cached := ctx.retained_clip(ClipRegion{}, rect(10, 10, 140, 80), transform)
		ctx.cancel()
		assert cached == changed
		assert ctx.clip_snapshots.len == 1
		before := gc_allocation_snapshot()!
		for _ in 0 .. 100 {
			ctx.begin()
			_ = ctx.retained_clip(ClipRegion{}, rect(10, 10, 140, 80), transform)
			ctx.cancel()
		}
		delta := gc_allocation_snapshot()!.delta_since(before)
		assert delta.allocated_bytes == 0
		assert delta.collections == 0
	}
}
