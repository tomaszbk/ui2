// vtest vflags: -d ui2_custom_rendering -d ui2_embedder -d ui2_geometry_capture
@[has_globals]
module ui2

import gg
import sokol.gfx
import sokol.sapp

$if macos && ui2_custom_rendering ?&& ui2_embedder ?&& ui2_geometry_capture ?&& !ui2_headless ? {
	__global controls_vertices = []PaintVertex{}

	fn observe_controls_polygon(vertices []PaintVertex) { controls_vertices << vertices }

	fn compiled_controls_environment() gfx.Environment {
		return gfx.Environment{ defaults: gfx.EnvironmentDefaults{ color_format: .bgra8, depth_format: .@none, sample_count: 1 }, metal: gfx.MetalEnvironment{ device: C.ui2_embedder_metal_device() } }
	}

	fn compiled_controls(mut app CompiledControlsModel) Element {
		return $vml('fixtures/compiled_controls.vml')
	}

	fn controls_node(kind Kind) FocusNode {
		for node in g_focus_navigation.nodes {
			if node.el.kind == kind && (kind != .view || node.el.button_behavior) { return node }
		}
		panic('missing ${kind}')
	}

	fn controls_mouse(typ sapp.EventType, x f64, y f64) {
		on_event(&gg.Event{ typ: typ, mouse_x: f32(x), mouse_y: f32(y) }, g_gg_app)
		on_frame(mut g_gg_app)
	}

	// Count ring-colored vertices painted around the tile only.
	fn controls_ring_vertices(r f64, g f64, b f64) int {
		tile := controls_node(.view).frame
		return controls_vertices.filter(it.r == r && it.g == g && it.b == b && it.x >= tile.x - 10
			&& it.x <= tile.x + tile.width + 10 && it.y >= tile.y - 10 && it.y <= tile.y + tile.height + 10).len
	}

	fn controls_declared_ring_vertices() int { return controls_ring_vertices(0x10, 0xb9, 0x81) }

	fn controls_default_ring_vertices() int { return controls_ring_vertices(0x25, 0x63, 0xeb) }
}

pub struct CompiledControlsModel {
pub mut:
	level f64 = 40
	dark  bool
	taps  int
}

fn test_compiled_slider_switch_and_focus_ring_follow_the_pointer() {
	$if macos && ui2_custom_rendering ?&& ui2_embedder ?&& ui2_geometry_capture ?&& !ui2_headless ? {
		previous := g_gg_app
		previous_build := g_build_screen
		previous_state := activate_custom_window_state(new_custom_window_state())
		mut ctx := new_surface_draw_context(gg.Config{ width: 400, height: 300 }, compiled_controls_environment())!
		window := C.ui2_embedder_create(&C.ui2_embedder_config{ title: c'Compiled controls fixture', width: 400, height: 300, visible: false }, &C.ui2_embedder_callbacks{}, unsafe { nil })
		assert window != unsafe { nil }
		mut model := &CompiledControlsModel{}
		mut controller := &CompiledVmlController[CompiledControlsModel]{ build: compiled_controls, model: model }
		mut runtime := compiled_vml_runtime()
		runtime.initial_bounds = rect(0, 0, 400, 300)
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
			controls_vertices.clear()
		}
		g_build_screen = compiled_vml_controller_build[CompiledControlsModel]
		g_gg_app = &GgApp{ ctx: ctx, native_window: window }
		ctx.submitted_polygon = observe_controls_polygon
		refresh()
		on_frame(mut g_gg_app)
		// Slider: press near the right end, drag to the left end.
		slider := controls_node(.slider).frame
		controls_mouse(.mouse_down, slider.x + slider.width - 12, slider.y + slider.height / 2)
		controls_mouse(.mouse_move, slider.x + slider.width / 2, slider.y + slider.height / 2)
		assert model.level > 40 && model.level < 60, 'level ${model.level}'
		controls_mouse(.mouse_up, slider.x + 12, slider.y + slider.height / 2)
		assert model.level < 10, 'level ${model.level}'
		assert controls_node(.slider).el.value == model.level
		// Switch: a click with a small jitter toggles exactly once, wherever it lands.
		for side in [0.75, 0.25, 0.25, 0.75] {
			track := controls_node(.switch_control).frame
			before := model.dark
			x := track.x + track.width * side
			y := track.y + track.height / 2
			controls_mouse(.mouse_down, x, y)
			controls_mouse(.mouse_move, x + 2, y + 1)
			controls_mouse(.mouse_up, x + 2, y + 1)
			for _ in 0 .. 3 { on_frame(mut g_gg_app) }
			assert model.dark == !before, 'side ${side}'
			assert controls_node(.switch_control).el.checked == model.dark
		}
		// A pointer press focuses without painting the keyboard focus ring.
		tile := controls_node(.view).frame
		controls_vertices.clear()
		controls_mouse(.mouse_down, tile.x + 40, tile.y + 40)
		controls_mouse(.mouse_up, tile.x + 40, tile.y + 40)
		assert model.taps == 1
		controls_vertices.clear()
		on_event(&gg.Event{ typ: .mouse_move, mouse_x: 390, mouse_y: 290 }, g_gg_app)
		on_frame(mut g_gg_app)
		assert controls_default_ring_vertices() == 0 && controls_declared_ring_vertices() == 0
		// Keyboard input makes focus visible: exactly the declared outline is drawn.
		on_event(&gg.Event{ typ: .key_down, key_code: .left_shift }, g_gg_app)
		controls_vertices.clear()
		on_frame(mut g_gg_app)
		assert controls_declared_ring_vertices() > 0
		assert controls_default_ring_vertices() == 0
	}
}
