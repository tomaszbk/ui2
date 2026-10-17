// vtest vflags: -d ui2_embedder
@[has_globals]
module ui2

import gg
import sokol.gfx

$if macos && ui2_embedder ?&& !ui2_headless ? {
	fn compiled_build_tick_environment() gfx.Environment {
		return gfx.Environment{ defaults: gfx.EnvironmentDefaults{ color_format: .bgra8, depth_format: .@none, sample_count: 1 }, metal: gfx.MetalEnvironment{ device: C.ui2_embedder_metal_device() } }
	}

	fn compiled_build_tick(mut app CompiledBuildTickModel) Element {
		return $vml('fixtures/compiled_build_tick.vml')
	}
}

pub struct CompiledBuildTickModel {
pub mut:
	counter int
}

// An application-data change refreshed with request_refresh rebuilds the
// compiled document. That frame must present the new value, not a patch the
// previous build queued, and must not schedule a follow-up frame.
fn test_compiled_build_presents_current_value_in_one_frame() {
	$if macos && ui2_embedder ?&& !ui2_headless ? {
		previous := g_gg_app
		previous_build := g_build_screen
		previous_state := activate_custom_window_state(new_custom_window_state())
		mut ctx := new_surface_draw_context(gg.Config{ width: 320, height: 240 }, compiled_build_tick_environment())!
		window := C.ui2_embedder_create(&C.ui2_embedder_config{ title: c'Compiled build fixture', width: 320, height: 240, visible: false }, &C.ui2_embedder_callbacks{}, unsafe { nil })
		assert window != unsafe { nil }
		mut model := &CompiledBuildTickModel{}
		mut controller := &CompiledVmlController[CompiledBuildTickModel]{ build: compiled_build_tick, model: model }
		mut runtime := compiled_vml_runtime()
		runtime.initial_bounds = rect(0, 0, 320, 240)
		declaration := controller.build(mut controller.model)
		runtime.initial_bounds = none
		controller.node = declaration.compiled_node
		runtime.controller = voidptr(controller)
		runtime.root = controller.node
		defer {
			dispose_compiled_vml()
			C.ui2_embedder_close(window)
			ctx.destroy()
			activate_custom_window_state(previous_state)
			g_build_screen = previous_build
			g_gg_app = previous
		}
		g_build_screen = compiled_vml_controller_build[CompiledBuildTickModel]
		g_gg_app = &GgApp{ ctx: ctx, native_window: window }
		request_refresh()
		on_frame(mut g_gg_app)
		for _ in 0 .. 3 { on_frame(mut g_gg_app) }
		assert (g_focus_navigation.node('counter') or { panic('counter') }).el.text == 'tick 0'
		for tick in 1 .. 4 {
			model.counter = tick
			before := g_gg_app.scheduler.stats()
			request_refresh()
			on_frame(mut g_gg_app)
			assert (g_focus_navigation.node('counter') or { panic('counter') }).el.text == 'tick ${tick}'
			assert g_gg_app.declared_root.children[0].children[0].text == 'tick ${tick}'
			for _ in 0 .. 3 { on_frame(mut g_gg_app) }
			after := g_gg_app.scheduler.stats()
			assert after.builds == before.builds + 1
			assert after.draws == before.draws + 1
			assert (g_focus_navigation.node('counter') or { panic('counter') }).el.text == 'tick ${tick}'
		}
	}
}
