module ui2

import math
import os

fn test_vglyph_symbol_fallback_does_not_replace_the_requested_text_face() {
	$if ( linux || ( ( macos || windows ) && ui2_custom_rendering ?) ) && !ui2_headless ? {
		mut engine := new_text_engine(1)!
		defer { engine.free() }
		text := 'Latin office café · Ελληνικά · Кириллица · 123'
		shaped := engine.shape(text, TextStyle{
			size:        21
			font_family: os.join_path(@VMODROOT, 'assets', 'fonts', 'Roboto-Regular.ttf')
		}, -1, 1, false)!
		for item in shaped.layout.items {
			assert shaped.layout.get_font_name_at_index(item.start_index) == 'Roboto', text[item.start_index..item.start_index + item.length]
		}
		// The numeric family suffix must survive Pango description parsing.
		symbol := engine.shape('♜', TextStyle{}, -1, 1, false)!
		assert symbol.layout.get_font_name_at_index(0) == 'Noto Sans Symbols 2'
		plain := 'ABC xyz 0123456789'
		default_text := engine.shape(plain, TextStyle{}, -1, 1, false)!
		missing_family := engine.shape(plain, TextStyle{
			font_family: 'UI2 Missing Test Family 8e4b4f'
		}, -1, 1, false)!
		assert math.abs(missing_family.size.width - default_text.size.width) < 0.02
		for item in missing_family.layout.items {
			assert missing_family.layout.get_font_name_at_index(item.start_index) == default_text.layout.get_font_name_at_index(item.start_index)
		}
	}
}

fn test_vglyph_measurement_before_a_window_and_device_scale_agree() {
	$if ( linux || ( ( macos || windows ) && ui2_custom_rendering ?) ) && !ui2_headless ? {
		style := TextStyle{ size: 15.25, lines: 20 }
		text := 'office café — hello world\nمرحبا بالعالم'
		before := measure_layout_text(text, style, 117.5)!
		assert before.width > 0 && before.height > 0
		mut reference := new_text_engine(1)!
		defer { reference.free() }
		base := reference.shape(text, style, 117.5, 20, false)!
		assert math.abs(before.width - math.min(117.5, base.size.width)) < 0.01
		assert math.abs(before.height - base.size.height) < 0.01
		for scale in [f32(1), 1.25, 1.5, 2] {
			mut engine := new_text_engine(scale)!
			shaped := engine.shape(text, style, 117.5, 20, false)!
			assert shaped.lines.len == base.lines.len
			assert math.abs(shaped.size.width - base.size.width) < 0.02
			assert math.abs(shaped.size.height - base.size.height) < 0.02
			for i, line in shaped.lines {
				assert line.start == base.lines[i].start && line.end == base.lines[i].end
				assert math.abs(line.y - base.lines[i].y) < 0.02
			}
			engine.free()
			engine.free()
		}
	}
}

fn test_vglyph_intrinsic_width_and_exact_width_are_distinct() {
	$if ( linux || ( ( macos || windows ) && ui2_custom_rendering ?) ) && !ui2_headless ? {
		mut engine := new_text_engine(1)!
		defer { engine.free() }
		style := TextStyle{ size: 16, lines: 20 }
		text := 'narrow extraordinary narrow'
		minimum := engine.measure(text, style, TextMeasureRequest{ mode: .min_content })!
		maximum := engine.measure(text, style, TextMeasureRequest{ mode: .max_content })!
		word := engine.shape('extraordinary', style, -1, 1, false)!
		assert minimum.size.width > 0
		assert math.abs(minimum.size.width - word.size.width) < 0.02
		assert maximum.size.width > minimum.size.width
		exact := engine.measure(text, style, TextMeasureRequest{ known_width: minimum.size.width + 1 })!
		assert exact.size.width == minimum.size.width + 1
		assert exact.size.height > maximum.size.height
		zero := engine.measure(text, style, TextMeasureRequest{ known_width: 0 })!
		assert zero.size.width == 0
		assert zero.size.height > 0
		fixed := engine.measure(text, style, TextMeasureRequest{ known_width: 20, known_height: 7.5 })!
		assert fixed.size == LayoutSize{ width: 20, height: 7.5 }
		if _ := engine.measure(text, style, TextMeasureRequest{ available_width: -2 }) {
			assert false
		}
	}
}

fn test_vglyph_preserves_empty_lines_whitespace_and_long_editor_content() {
	$if ( linux || ( ( macos || windows ) && ui2_custom_rendering ?) ) && !ui2_headless ? {
		mut engine := new_text_engine(1)!
		defer { engine.free() }
		style := TextStyle{ size: 14, lines: 20 }
		empty := engine.shape('', style, 100, 1, false)!
		assert empty.size.width == 0
		assert empty.size.height == font_line_height(14)
		assert empty.cursor(0).height > 0
		first_empty := engine.measure('\nM', style, TextMeasureRequest{})!
		first_filled := engine.measure('M', style, TextMeasureRequest{})!
		assert math.abs(first_empty.baseline - first_filled.baseline) < 0.02
		paragraphs := engine.shape_area('a\r\n\r\nb  c\n', style, 200)!
		assert paragraphs.lines.len == 4
		assert paragraphs.lines[0].text == 'a'
		assert paragraphs.lines[1].text == ''
		assert paragraphs.lines[2].text == 'b  c'
		assert paragraphs.lines[3].text == ''
		assert paragraphs.lines[2].start == 5
		long_text := 'line\n'.repeat(3000) + 'last'
		long := engine.shape_area(long_text, style, 200)!
		assert long.lines.len == 3001
		assert long.lines.last().text == 'last'
		assert long.lines.last().end == long_text.runes().len
		assert long.cursor(long_text.runes().len).y > long.cursor(0).y
	}
}

fn test_vglyph_byte_rune_boundaries_and_cluster_geometry() {
	$if ( linux || ( ( macos || windows ) && ui2_custom_rendering ?) ) && !ui2_headless ? {
		text := 'A🙂e\u0301👩\u200d💻Z'
		assert text_rune_to_byte(text, 0) == 0
		assert text_rune_to_byte(text, 2) == 5
		assert text_rune_to_byte(text, 4) == 8
		assert text_rune_to_byte(text, 8) == text.len
		for i in 0 .. text.runes().len + 1 {
			assert text_byte_to_rune(text, text_rune_to_byte(text, i)) == i
		}
		mut engine := new_text_engine(1)!
		defer { engine.free() }
		shaped := engine.shape(text, TextStyle{}, -1, 1, false)!
		assert shaped.cursor(2).x > shaped.cursor(0).x
		assert shaped.cursor(3).x == shaped.cursor(2).x
		selected := shaped.selection(1, 2)
		assert selected.len == 1
		assert selected[0].width > 0
		assert shaped.hit_test(-10, 0) == 0
		assert shaped.hit_test(shaped.size.width + 10, 0) == text.runes().len
	}
}

fn test_vglyph_labels_cap_paragraphs_and_report_ellipsis() {
	$if ( linux || ( ( macos || windows ) && ui2_custom_rendering ?) ) && !ui2_headless ? {
		mut engine := new_text_engine(1)!
		defer { engine.free() }
		style := TextStyle{ size: 15, lines: 2 }
		ellipsis := engine.shape('…', style, -1, 1, false)!
		ellipsis_item := ellipsis.layout.items[0]
		ellipsis_glyph := ellipsis.layout.glyphs[ellipsis_item.glyph_start].index
		shaped := engine.shape('one\ntwo\nthree\nfour', style, 100, 2, true)!
		assert shaped.lines.len == 2
		assert shaped.truncated
		last_item := shaped.layout.items.last()
		assert voidptr(last_item.ft_face) == voidptr(ellipsis_item.ft_face)
		assert shaped.layout.glyphs[last_item.glyph_start + last_item.glyph_count - 1].index == ellipsis_glyph
		assert math.abs(shaped.size.height - 2 * font_line_height(style.size)) < 0.02
		one := engine.shape('a very long line that will not fit', style, 35, 1, true)!
		assert one.lines.len == 1
		assert one.truncated
		assert one.size.width <= 35.02
		first_paragraph := engine.shape('short\nlater paragraph', style, 300, 1, true)!
		assert first_paragraph.lines.len == 1
		assert first_paragraph.truncated
		first_item := first_paragraph.layout.items.last()
		assert voidptr(first_item.ft_face) == voidptr(ellipsis_item.ft_face)
		assert first_paragraph.layout.glyphs[first_item.glyph_start + first_item.glyph_count - 1].index == ellipsis_glyph
		for line_limit in [1, 2, 4] {
			for width in [0.0, 20.0, 100.0] {
				bounded_style := TextStyle{ size: 15, lines: line_limit }
				text := 'one\ntwo\nthree\nfour'
				drawing := engine.shape(text, bounded_style, width, line_limit, true)!
				measured := engine.measure(text, bounded_style, TextMeasureRequest{ available_width: width })!
				assert math.abs(measured.size.width - math.min(width, drawing.size.width)) < 0.02
				assert math.abs(measured.size.height - drawing.size.height) < 0.02
			}
		}
	}
}

fn test_vglyph_paint_colors_reuse_typography_including_rich_run_boundaries() {
	$if ( linux || ( ( macos || windows ) && ui2_custom_rendering ?) ) && !ui2_headless ? {
		mut engine := new_text_engine(1)!
		defer { engine.free() }
		style := TextStyle{ size: 17.25, color: 0x112233 }
		first := engine.shape('café ñ', style, 80.5, 2, false)!
		builds := engine.shape_builds
		paint := engine.shape('café ñ', TextStyle{ ...style, color: 0x3366ff }, 80.5, 2, false)!
		assert engine.shape_builds == builds
		assert engine.shape_hits > 0
		assert paint.size == first.size
		assert paint.layout.items[0].color == hex_color(0x3366ff)
		assert first.layout.items[0].color == hex_color(0x112233), 'cached geometry must not be mutated by painting'
		runs := [TextRun{ text: 'WW', style: TextStyle{ size: 17.25, color: 0x123456 } },
			TextRun{ text: 'ii', style: TextStyle{ size: 17.25, color: 0xabcdef } }]
		rich := engine.shape_runs(runs, style, 80.5, 2, false)!
		rich_builds := engine.shape_builds
		changed_runs := runs.map(TextRun{ text: it.text, style: TextStyle{ ...it.style, color: 0xff0000 } })
		rich_paint := engine.shape_runs(changed_runs, style, 80.5, 2, false)!
		assert engine.shape_builds == rich_builds
		assert rich_paint.size == rich.size
		for item in rich_paint.layout.items { assert item.color == hex_color(0xff0000) }
		for item in rich.layout.items {
			assert item.color == hex_color(if item.start_index < 2 { u32(0x123456) } else { u32(0xabcdef) })
		}
		g_text_font_mutex.lock()
		engine.invalidate_environment()
		g_text_font_mutex.unlock()
		_ = engine.shape_runs(changed_runs, style, 80.5, 2, false)!
		assert engine.shape_builds == rich_builds + 1
	}
}

fn test_vglyph_repaint_counts_compare_identical_scene_with_uncached_shaping() {
	$if ( linux || ( ( macos || windows ) && ui2_custom_rendering ?) ) && !ui2_headless ? {
		mut reference := new_text_engine(1)!
		mut retained := new_text_engine(1)!
		defer { reference.free(); retained.free() }
		for i in 0 .. 20 {
			style := TextStyle{ size: 17.25, color: if i % 2 == 0 { u32(0x112233) } else { u32(0x3366ff) } }
			g_text_font_mutex.lock()
			before := reference.build_shape_locked('café ñ', [], style, 80.5, 2, false, false)!
			g_text_font_mutex.unlock()
			after := retained.shape('café ñ', style, 80.5, 2, false)!
			assert before.size == after.size
			assert before.layout.items[0].color == after.layout.items[0].color
		}
		assert reference.shape_builds == 20
		assert retained.shape_builds == 1
		assert retained.shape_hits == 19
		println('identical repaint scene: uncached_shape_builds=${reference.shape_builds} retained_shape_builds=${retained.shape_builds} retained_shape_hits=${retained.shape_hits}')
	}
}

fn test_vglyph_cached_tail_ellipsis_keeps_visible_run_paint_owner() {
	$if ( linux || ( ( macos || windows ) && ui2_custom_rendering ?) ) && !ui2_headless ? {
		mut engine := new_text_engine(1)!
		defer { engine.free() }
		base := TextStyle{ size: 17.25, color: 0x111111 }
		for runs in [
			[TextRun{ text: 'short', style: TextStyle{ ...base, color: 0xff0000 } }, TextRun{ text: '\nhidden', style: TextStyle{ ...base, color: 0x0000ff } }],
			[TextRun{ text: 'short\n', style: TextStyle{ ...base, color: 0xff0000 } }, TextRun{ text: 'hidden', style: TextStyle{ ...base, color: 0x0000ff } }],
			[TextRun{ text: 'this part', style: TextStyle{ ...base, color: 0xff0000 } }, TextRun{ text: ' is very long hidden text', style: TextStyle{ ...base, color: 0x0000ff } }],
		] {
			g_text_font_mutex.lock()
			reference := engine.build_shape_locked(text_runs_content(runs), runs, base, 300, 1, true, false)!
			g_text_font_mutex.unlock()
			cold := engine.shape_runs(runs, base, 300, 1, true)!
			builds := engine.shape_builds
			hit := engine.shape_runs(runs, base, 300, 1, true)!
			assert engine.shape_builds == builds
			assert cold.size == reference.size && hit.size == reference.size
			assert cold.layout.items.len == reference.layout.items.len
			for i, item in reference.layout.items {
				assert cold.layout.items[i].color == item.color
				assert hit.layout.items[i].color == item.color
			}
		}
	}
}

fn test_vglyph_link_and_external_paint_metadata_reuse_shaping() {
	$if ( linux || ( ( macos || windows ) && ui2_custom_rendering ?) ) && !ui2_headless ? {
		mut engine := new_text_engine(1)!
		defer { engine.free() }
		base := TextStyle{ size: 17.25, color: 0xff0000 }
		first := engine.shape('visible', base, 300, 1, false)!
		builds := engine.shape_builds
		paint := engine.shape('visible', TextStyle{ ...base, link: 'https://example.test/new', shadow: true, outline: true, background_color: 0xffee00 }, 300, 1, false)!
		assert paint.size == first.size
		assert engine.shape_builds == builds
		assert first.layout.items[0].color == hex_color(0xff0000)
	}
}

fn test_public_layout_environment_invalidates_cpu_and_window_shaping_once() {
	$if ( linux || ( ( macos || windows ) && ui2_custom_rendering ?) ) && !ui2_headless ? {
		previous := g_gg_app
		mut active := new_text_engine(1)!
		defer { g_gg_app = previous; active.free() }
		g_gg_app = &GgApp{ scheduler: new_frame_coordinator(), ctx: &DrawContext{ text: active, text_font_generation: 17 } }
		style := TextStyle{ size: 17.25 }
		_ = layout_measure_vglyph_text('cpu environment', style, 300.5)!
		_ = layout_measure_vglyph_text('cpu environment', style, 300.5)!
		cpu := g_cpu_text_engine
		before := cpu.shape_builds
		cpu_version := cpu.environment_version
		active_version := active.environment_version
		invalidate_layout_environment(LayoutEnvironment{ font_version: 1 })
		_ = layout_measure_vglyph_text('cpu environment', style, 300.5)!
		assert cpu.shape_builds == before + 1
		assert cpu.environment_version == cpu_version + 1
		assert active.environment_version == active_version + 1
		assert g_gg_app.ctx.text_font_generation == -1
		g_gg_app.ctx.text = cpu
		aliased := cpu.environment_version
		invalidate_layout_environment(LayoutEnvironment{ font_version: 2 })
		assert cpu.environment_version == aliased + 1
	}
}
