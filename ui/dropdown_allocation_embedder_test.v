// vtest vflags: -gc boehm -d no_gc_thread_local_alloc -d ui2_custom_rendering -d ui2_embedder
@[has_globals]
module ui2

$if macos && ui2_custom_rendering ?&& ui2_embedder ?&& !ui2_headless ? {
	import gg
	import sokol.gfx
	import sokol.sgl
}

fn test_open_dropdown_hover_reuses_targets_and_refreshes_scroll_and_selection() ! {
	$if macos && ui2_custom_rendering ?&& ui2_embedder ?&& !ui2_headless ? {
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
		}
		chooser := dropdown('chooser', 'Uno', ['Uno', 'Dos', 'Tres', 'Cuatro', 'Cinco', 'Seis',
			'Siete', 'Ocho', 'Nueve', 'Diez'],
			rect(10, 10, 180, 28), BoxStyle{ bg: 0xf1f5f9 }, TextStyle{ size: 16 })
		mut w := &Window{ ctx: ctx, native_window: window, has_root: true, declared_root: screen(0xffffff, [chooser]) }
		on_frame(mut w)
		w.open_dropdown(w.hit_test(60, 24))
		on_frame(mut w)
		assert w.dropdown_id == 'chooser' && w.dropdown_popup.mounted
		assert w.dropdown_popup.max_scroll > 0
		x := w.dropdown_popup.x + 80
		y := w.dropdown_popup.y + dropdown_popup_padding + w.dropdown_popup.row_height / 2
		first := gg.Event{ typ: .mouse_move, mouse_x: f32(x), mouse_y: f32(y) }
		second := gg.Event{ typ: .mouse_move, mouse_x: f32(x), mouse_y: f32(y + w.dropdown_popup.row_height) }
		for i in 0 .. 8 {
			on_event(if i % 2 == 0 { &first } else { &second }, mut w)
			on_frame(mut w)
		}
		assert w.hit_test(x, y).option_index == 0
		assert w.hit_test(x, y + w.dropdown_popup.row_height).option_index == 1
		before := gc_allocation_snapshot()!
		for i in 0 .. 100 {
			on_event(if i % 2 == 0 { &first } else { &second }, mut w)
			on_frame(mut w)
		}
		delta := gc_allocation_snapshot()!.delta_since(before)
		assert delta.allocated_bytes == 0
		assert delta.collections == 0
		assert sgl.error() == .no_error
		assert w.dropdown_hover == 1
		assert w.hit_test(x, y).option_index == 0
		on_event(&gg.Event{ typ: .mouse_scroll, mouse_x: f32(x), mouse_y: f32(y), scroll_y: -2 }, mut w)
		on_frame(mut w)
		assert w.dropdown_scroll == 48
		assert w.hit_test(x, y).option_index > 0
		selected := w.hit_test(x, y)
		assert selected.dropdown_option
		w.handle_dropdown_release(x, y)
		on_frame(mut w)
		assert w.text('chooser') == selected.options[selected.option_index]
		assert w.dropdown_id == ''
		assert !w.hit_targets.any(it.dropdown_option)
		assert w.hit_test(60, 24).id == 'chooser'
	}
}
