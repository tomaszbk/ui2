// vtest vflags: -d ui2_custom_rendering
@[has_globals]
module ui2

$if ( linux || ( ( macos || windows ) && ui2_custom_rendering ?) ) && !ui2_headless ? {
	fn test_owned_text_reuses_layout_and_owns_editor_input() {
		mut engine := new_text_engine(1)!
		defer { engine.free() }
		mut ctx := DrawContext{ text: engine }
		style := TextStyle{ size: 18 }
		mut source := 'año café pingüino'.clone()
		first := ctx.shape_text(source, style, 400, 1, false)!
		assert engine.shape_builds == 1
		unsafe { source.free() }
		ctx.content_transform = ContentTransform{ xx: 0, xy: -2, yx: 3, yy: 0, x: 200 }
		again := ctx.shape_text('año café pingüino', style, 400, 1, false)!
		assert engine.shape_builds == 1
		assert again.text == 'año café pingüino'
		assert again.size == first.size && again.lines[0].text == again.text
		assert again.cursor(4) == first.cursor(4)
		narrow := ctx.shape_text_area(again.text, style, 40)!
		assert engine.shape_builds == 2 && narrow.size.height > first.size.height
		larger := ctx.shape_text(again.text, TextStyle{ ...style, size: 30 }, 400, 1, false)!
		assert engine.shape_builds == 3 && larger.size.height > first.size.height
		changed := ctx.shape_text('different', style, 400, 1, false)!
		assert engine.shape_builds == 4 && changed.text == 'different'
		// Environment changes invalidate the owned engine independently of position.
		engine.invalidate_environment()
		ctx.shape_text('different', style, 400, 1, false)!
		assert engine.shape_builds == 5
		ctx.destroyed = true
		if _ := ctx.shape_text('closed', style, 100, 1, false) { assert false }
		ctx.destroyed = false
		ctx.text = unsafe { nil }
		if _ := ctx.shape_text_area('closed', style, 100) { assert false }
	}

	fn test_owned_rich_text_has_one_cache_per_context_and_validates_constraints() {
		mut first_engine := new_text_engine(1)!
		mut second_engine := new_text_engine(1)!
		defer {
			first_engine.free()
			second_engine.free()
		}
		mut first := DrawContext{ text: first_engine }
		mut second := DrawContext{ text: second_engine }
		style := TextStyle{ size: 18 }
		runs := [TextRun{ text: 'España ', style: style },
			TextRun{ text: 'café', style: TextStyle{ ...style, weight: 700 } }]
		shaped := first.shape_runs(runs, style, 400, 1, false)!
		first.shape_runs(runs, style, 400, 1, false)!
		second.shape_runs(runs, style, 400, 1, false)!
		assert first_engine.shape_builds == 1 && second_engine.shape_builds == 1
		assert shaped.text == 'España café'
		if _ := first.shape_runs(runs, TextStyle{ size: -1 }, 400, 1, false) {
			assert false
		}
		assert first_engine.shape_builds == 1
	}
	fn test_owned_wrappers_environment_font_dpi_and_rich_ellipsis_keys() {
		previous_app := g_gg_app
		previous := activate_custom_window_state(new_custom_window_state())
		mut engine := new_text_engine(1)!
		mut dpi_engine := new_text_engine(2)!
		defer { activate_custom_window_state(previous); g_gg_app = previous_app; engine.free(); dpi_engine.free() }
		g_gg_app = &GgApp{ctx: &DrawContext{text: engine}}
		mut ctx := g_gg_app.ctx
		style := TextStyle{size: 18, color: 0xff0000}
		ctx.shape_text('environment ñ café', style, 300, 1, false)!
		layout_measure_vglyph_text('environment ñ café', style, 300)!
		mut cpu := g_cpu_text_engine
		cpu_before := cpu.shape_builds
		before := engine.shape_builds
		cpu_version := cpu.environment_version
		draw_version := engine.environment_version
		invalidate_layout_environment(LayoutEnvironment{version: 7})
		assert cpu != engine && cpu.environment_version == cpu_version + 1
		assert engine.environment_version == draw_version + 1
		ctx.shape_text('environment ñ café', style, 300, 1, false)!
		layout_measure_vglyph_text('environment ñ café', style, 300)!
		assert engine.shape_builds == before + 1 && cpu.shape_builds == cpu_before + 1
		ctx.shape_text('environment ñ café', style, 300, 1, false)!
		layout_measure_vglyph_text('environment ñ café', style, 300)!
		assert engine.shape_builds == before + 1 && cpu.shape_builds == cpu_before + 1
		// A CPU-only environment change must reach retained measurement keys
		// even while a distinct draw context exists.
		key := layout_effective_environment(LayoutEnvironment{}, measure_layout_text)
		cpu.invalidate_environment()
		assert layout_effective_environment(LayoutEnvironment{}, measure_layout_text) != key
		// Exercise the font-generation key without installing/rebinding fonts.
		g_text_font_mutex.lock()
		g_text_font_generation++
		g_text_font_mutex.unlock()
		ctx.shape_text('environment ñ café', style, 300, 1, false)!
		assert engine.shape_builds == before + 2
		ctx.shape_text('environment ñ café', style, 300, 1, false)!
		assert engine.shape_builds == before + 2
		ctx.text = dpi_engine
		ctx.scale = 2
		ctx.shape_text('environment ñ café', style, 300, 1, false)!
		ctx.shape_text('environment ñ café', style, 300, 1, false)!
		assert dpi_engine.scale == 2 && dpi_engine.shape_builds == 1 && dpi_engine.shape_hits == 1
		ctx.text = engine
		ctx.scale = 1
		runs := [TextRun{text: 'short', style: style}, TextRun{text: '\nhidden', style: TextStyle{...style, color: 0x0000ff}}]
		first := ctx.shape_runs(runs, style, 300, 1, true)!
		rich_builds := engine.shape_builds
		changed := runs.map(TextRun{text: it.text, style: TextStyle{...it.style, color: 0x00aa00}})
		recolored := ctx.shape_runs(changed, style, 300, 1, true)!
		assert engine.shape_builds == rich_builds && recolored.truncated
		assert first.size == recolored.size && first.lines == recolored.lines
		for item in first.layout.items { assert item.color == hex_color(0xff0000) }
		for item in recolored.layout.items { assert item.color == hex_color(0x00aa00) }
	}

}
