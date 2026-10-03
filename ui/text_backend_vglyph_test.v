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
