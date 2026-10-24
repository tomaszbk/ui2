// vtest vflags: -d ui2_custom_rendering -d ui2_embedder -d vml_fixtures
@[has_globals]
module ui2

// vml: fixtures/compiled_build_tick.vml

import gg
import sokol.gfx

$if macos && ui2_custom_rendering ?&& ui2_embedder ?&& !ui2_headless ? {
	fn compiled_build_tick_environment() gfx.Environment {
		return gfx.Environment{ defaults: gfx.EnvironmentDefaults{ color_format: .bgra8, depth_format: .@none, sample_count: 1 }, metal: gfx.MetalEnvironment{ device: C.ui2_embedder_metal_device() } }
	}

	fn compiled_build_tick(mut app CompiledBuildTickModel) Element {
		return compiled_build_tick_vml(mut app)
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
	$if macos && ui2_custom_rendering ?&& ui2_embedder ?&& !ui2_headless ? {
		mut ctx := new_surface_draw_context(gg.Config{ width: 320, height: 240 }, compiled_build_tick_environment())!
		window := C.ui2_embedder_create(&C.ui2_embedder_config{ title: c'Compiled build fixture', width: 320, height: 240, visible: false }, &C.ui2_embedder_callbacks{}, unsafe { nil })
		assert window != unsafe { nil }
		mut model := &CompiledBuildTickModel{}
		mut controller := start_compiled_vml[CompiledBuildTickModel](
			model:  model
			build:  compiled_build_tick
			width:  320
			height: 240
		)!
		defer {
			controller.dispose()
			C.ui2_embedder_close(window)
			ctx.destroy()
		}
		mut w := &Window{
			ctx:           ctx
			native_window: window
			build:         fn [mut controller] (mut built Window) Element {
				return controller.build_frame(mut built)
			}
		}
		w.request_refresh()
		on_frame(mut w)
		for _ in 0 .. 3 { on_frame(mut w) }
		assert (w.navigation.node('counter') or { panic('counter') }).el.text == 'tick 0'
		for tick in 1 .. 4 {
			model.counter = tick
			before := w.scheduler.stats()
			w.request_refresh()
			on_frame(mut w)
			assert (w.navigation.node('counter') or { panic('counter') }).el.text == 'tick ${tick}'
			assert w.declared_root.children[0].children[0].text == 'tick ${tick}'
			for _ in 0 .. 3 { on_frame(mut w) }
			after := w.scheduler.stats()
			assert after.builds == before.builds + 1
			assert after.draws == before.draws + 1
			assert (w.navigation.node('counter') or { panic('counter') }).el.text == 'tick ${tick}'
		}
	}
}
