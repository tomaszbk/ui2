module ui2

$if macos && ui2_embedder ?&& ui2_custom_rendering ?&& !ui2_headless ? {
	import gg
	import sokol.gfx
}

// Keep the test function present on other backends: the V test compiler cannot
// currently compile a file whose every test is removed by a platform guard.
fn test_owned_draw_resources_keep_other_window_fonts_and_device_alive() {
	$if macos && ui2_embedder ?&& ui2_custom_rendering ?&& !ui2_headless ? {
		regular, bold := font_paths()
		config := gg.Config{
			width:                 320
			height:                240
			font_path:             regular
			custom_bold_font_path: bold
		}
		environment := gfx.Environment{
			defaults: gfx.EnvironmentDefaults{
				color_format: .bgra8
				depth_format: .@none
				sample_count: 1
			}
			metal:    gfx.MetalEnvironment{ device: C.ui2_embedder_metal_device() }
		}
		mut first := new_surface_draw_context(config, environment)!
		defer { first.destroy() }
		mut second := new_surface_draw_context(config, environment)!
		defer { second.destroy() }
		mut third := new_surface_draw_context(config, environment)!
		defer { third.destroy() }
		mut fourth := new_surface_draw_context(config, environment)!
		defer { fourth.destroy() }
		assert first.ft.fons != second.ft.fons
		assert second.ft.fons != third.ft.fons
		assert third.ft.fons != fourth.ft.fons
		first.set_text_cfg(gg.TextCfg{ size: 12 })
		first_width := first.text_width_f('independent window')
		assert first_width > 0
		second.set_surface(320, 240, 2, gfx.Swapchain{})
		second.set_text_cfg(gg.TextCfg{ size: 30 })
		assert second.text_width_f('independent window') > first_width * 2
		assert first.text_width_f('independent window') == first_width

		first.destroy()
		assert gfx.is_valid()
		second.set_text_cfg(gg.TextCfg{ size: 30, bold: true })
		assert second.text_width_f('the other window remains usable') > 0
		second.destroy()
		assert gfx.is_valid()
		third.set_text_cfg(gg.TextCfg{ size: 12 })
		fourth.set_text_cfg(gg.TextCfg{ size: 30 })
		assert third.text_width_f('independent window') == first_width
		assert fourth.text_width_f('independent window') > first_width * 2
		third.destroy()
		assert gfx.is_valid()
		fourth.destroy()
		assert !gfx.is_valid()

		// A fresh window must be able to create the device and atlas again after
		// the previous final window released them.
		mut reopened := new_surface_draw_context(config, environment)!
		defer { reopened.destroy() }
		reopened.set_text_cfg(gg.TextCfg{ size: 12 })
		assert reopened.text_width_f('independent window') == first_width
		reopened.destroy()
		assert !gfx.is_valid()
	}
}
