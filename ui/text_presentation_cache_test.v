// vtest vflags: -d ui2_custom_rendering
module ui2

$if ( linux || ( ( macos || windows ) && ui2_custom_rendering ?) ) && !ui2_headless ? {
	fn test_presented_text_reuses_layout_and_owns_editor_input() {
		mut engine := new_text_engine(1)!
		defer { engine.free() }
		mut ctx := DrawContext{ text: engine }
		style := TextStyle{ size: 18 }
		mut source := 'año café pingüino'.clone()
		first := ctx.shape_text(source, style, 400, 1, false)!
		assert ctx.text_layouts == 1
		unsafe { source.free() }
		ctx.content_transform = ContentTransform{ xx: 0, xy: -2, yx: 3, yy: 0, x: 200 }
		again := ctx.shape_text('año café pingüino', style, 400, 1, false)!
		assert ctx.text_layouts == 1
		assert again.text == 'año café pingüino'
		assert again.size == first.size && again.lines[0].text == again.text
		assert again.cursor(4) == first.cursor(4)
		narrow := ctx.shape_text_area(again.text, style, 40)!
		assert ctx.text_layouts == 2 && narrow.size.height > first.size.height
		larger := ctx.shape_text(again.text, TextStyle{ ...style, size: 30 }, 400, 1, false)!
		assert ctx.text_layouts == 3 && larger.size.height > first.size.height
		changed := ctx.shape_text('different', style, 400, 1, false)!
		assert ctx.text_layouts == 4 && changed.text == 'different'
		// Font generation changes invalidate presentation independently of position.
		ctx.text_presentation_generation = -1
		ctx.shape_text('different', style, 400, 1, false)!
		assert ctx.text_layouts == 5
	}

	fn test_presented_rich_text_has_one_cache_per_context_and_validates_constraints() {
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
		assert first.text_layouts == 1 && second.text_layouts == 1
		assert shaped.text == 'España café'
		if _ := first.shape_runs(runs, TextStyle{ size: -1 }, 400, 1, false) {
			assert false
		}
		assert first.text_layouts == 1
	}
}
