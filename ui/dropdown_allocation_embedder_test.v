// vtest vflags: -gc boehm -d no_gc_thread_local_alloc -d ui2_embedder
@[has_globals]
module ui2

$if macos && ui2_embedder ?&& !ui2_headless ? {
	import gg
	import sokol.gfx
	import sokol.sgl
}

fn test_open_dropdown_hover_reuses_targets_and_refreshes_scroll_and_selection() ! {
	$if macos && ui2_embedder ?&& !ui2_headless ? {
		previous_app := g_gg_app
		previous_build := g_build_screen
		previous_state := activate_custom_window_state(new_custom_window_state())
		environment := gfx.Environment{
			defaults: gfx.EnvironmentDefaults{ color_format: .bgra8, depth_format: .@none, sample_count: 1 }
			metal:    gfx.MetalEnvironment{ device: C.ui2_embedder_metal_device() }
		}
		mut ctx := new_surface_draw_context(gg.Config{ width: 320, height: 200 }, environment)!
		window := C.ui2_embedder_create(&C.ui2_embedder_config{ title: c'Dropdown allocation acceptance', width: 320, height: 200, visible: false }, &C.ui2_embedder_callbacks{}, unsafe { nil })
		assert window != unsafe { nil }
		defer {
			C.ui2_embedder_close(window)
			ctx.destroy()
			activate_custom_window_state(previous_state)
			g_build_screen = previous_build
			g_gg_app = previous_app
		}
		g_build_screen = unsafe { nil }
		chooser := dropdown('chooser', 'Uno', ['Uno', 'Dos', 'Tres', 'Cuatro', 'Cinco', 'Seis',
			'Siete', 'Ocho', 'Nueve', 'Diez'],
			rect(10, 10, 180, 28), BoxStyle{ bg: 0xf1f5f9 }, TextStyle{ size: 16 })
		g_gg_app = &GgApp{ ctx: ctx, native_window: window, has_root: true, declared_root: screen(0xffffff, [chooser]) }
		on_frame(mut g_gg_app)
		open_dropdown(hit_test(60, 24))
		on_frame(mut g_gg_app)
		assert g_open_dropdown == 'chooser' && g_dropdown_popup.mounted
		assert g_dropdown_popup.max_scroll > 0
		x := g_dropdown_popup.x + 80
		y := g_dropdown_popup.y + dropdown_popup_padding + g_dropdown_popup.row_height / 2
		first := gg.Event{ typ: .mouse_move, mouse_x: f32(x), mouse_y: f32(y) }
		second := gg.Event{ typ: .mouse_move, mouse_x: f32(x), mouse_y: f32(y + g_dropdown_popup.row_height) }
		for i in 0 .. 8 {
			on_event(if i % 2 == 0 { &first } else { &second }, g_gg_app)
			on_frame(mut g_gg_app)
		}
		assert hit_test(x, y).option_index == 0
		assert hit_test(x, y + g_dropdown_popup.row_height).option_index == 1
		before := gc_allocation_snapshot()!
		for i in 0 .. 100 {
			on_event(if i % 2 == 0 { &first } else { &second }, g_gg_app)
			on_frame(mut g_gg_app)
		}
		delta := gc_allocation_snapshot()!.delta_since(before)
		assert delta.allocated_bytes == 0
		assert delta.collections == 0
		assert sgl.error() == .no_error
		assert g_dropdown_hover == 1
		assert hit_test(x, y).option_index == 0
		on_event(&gg.Event{ typ: .mouse_scroll, mouse_x: f32(x), mouse_y: f32(y), scroll_y: -2 }, g_gg_app)
		on_frame(mut g_gg_app)
		assert g_dropdown_scroll == 48
		assert hit_test(x, y).option_index > 0
		selected := hit_test(x, y)
		assert selected.dropdown_option
		handle_dropdown_release(x, y)
		on_frame(mut g_gg_app)
		assert text('chooser') == selected.options[selected.option_index]
		assert g_open_dropdown == ''
		assert !g_hit_targets.any(it.dropdown_option)
		assert hit_test(60, 24).id == 'chooser'
	}
}
