// vtest vflags: -d ui2_custom_rendering -d ui2_embedder
@[has_globals]
module ui2

$if macos && ui2_custom_rendering ?&& ui2_embedder ?&& !ui2_headless ? {
	import gg
	import sokol.gfx

	__global frame_work_counter = 0

	const frame_work_labels = 300

	fn frame_work_environment() gfx.Environment {
		return gfx.Environment{ defaults: gfx.EnvironmentDefaults{ color_format: .bgra8, depth_format: .@none, sample_count: 1 }, metal: gfx.MetalEnvironment{ device: C.ui2_embedder_metal_device() } }
	}

	// Every build declares new Elements for the same fixed-size labels; only the
	// counter text changes between ticks.
	fn frame_work_build() Element {
		mut children := []Element{cap: frame_work_labels + 1}
		children << label('counter', 'tick ${frame_work_counter}', rect(8, 8, 300, 24), TextStyle{})
		for i in 0 .. frame_work_labels {
			children << label('item-${i}', 'Item ${i} value ${(i * 7) % 97}',
				rect(8 + (i % 6) * 160, 40 + (i / 6) * 13, 150, 12), TextStyle{})
		}
		return screen(0xffffff, [view('labels', rect(0, 0, 1000, 700), BoxStyle{ transparent: true }, children)])
	}
}

fn test_counter_tick_relayouts_and_reshapes_only_the_changed_label() {
	$if macos && ui2_custom_rendering ?&& ui2_embedder ?&& !ui2_headless ? {
		previous := g_gg_app
		previous_build := g_build_screen
		previous_state := activate_custom_window_state(new_custom_window_state())
		mut ctx := new_surface_draw_context(gg.Config{ width: 1000, height: 700 }, frame_work_environment())!
		window := C.ui2_embedder_create(&C.ui2_embedder_config{ title: c'Frame work fixture', width: 1000, height: 700, visible: false }, &C.ui2_embedder_callbacks{}, unsafe { nil })
		assert window != unsafe { nil }
		defer {
			C.ui2_embedder_close(window)
			ctx.destroy()
			activate_custom_window_state(previous_state)
			g_build_screen = previous_build
			g_gg_app = previous
		}
		frame_work_counter = 0
		g_build_screen = frame_work_build
		g_gg_app = &GgApp{ ctx: ctx, native_window: window }
		request_refresh()
		on_frame(mut g_gg_app)
		assert g_gg_app.scheduler.stats().draws == 1
		assert g_focus_navigation.node('item-299') != none
		for tick in 1 .. 4 {
			frame_work_counter = tick
			before := g_gg_app.scheduler.stats()
			revision := g_focus_navigation.root_revision
			shape_builds := ctx.text.shape_builds
			shape_hits := ctx.text.shape_hits
			g_gg_app.layout_tree.reset_stats()
			request_refresh()
			on_frame(mut g_gg_app)
			after := g_gg_app.scheduler.stats()
			layout := layout_stats()
			assert after.builds == before.builds + 1 && after.draws == before.draws + 1
			assert g_focus_navigation.root_revision == revision + 1
			assert (g_focus_navigation.node('counter') or { panic('counter') }).el.text == 'tick ${tick}'
			// The changed label is a fixed-size relayout boundary: reconciling the
			// declaration must not measure or arrange any subtree again.
			assert layout.builds == 1 && layout.reconciled == frame_work_labels + 3
			assert layout.measure_visits == 0 && layout.text_measurements == 0
			assert layout.layout_visits == 0
			// Only the counter is shaped again; every unchanged label reuses its shape.
			assert ctx.text.shape_builds == shape_builds + 1
			assert ctx.text.shape_hits >= shape_hits + frame_work_labels
			println('tick ${tick}: reconciled=${layout.reconciled} measure_visits=${layout.measure_visits} layout_visits=${layout.layout_visits} shape_builds=${ctx.text.shape_builds - shape_builds} shape_hits=${ctx.text.shape_hits - shape_hits}')
		}
		// Without a change, no further frame is drawn.
		idle := g_gg_app.scheduler.stats()
		for _ in 0 .. 5 { on_frame(mut g_gg_app) }
		assert g_gg_app.scheduler.stats().draws == idle.draws
	}
}
