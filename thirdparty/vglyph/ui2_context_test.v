module vglyph

import math
import os

fn ui2_test_font() string {
	return os.join_path(os.dir(os.dir(@VMODROOT)), 'assets', 'fonts', 'Roboto-Regular.ttf')
}

fn test_ui2_emoji_preferences_shape_and_rasterize_zwj_and_variation_selectors() {
	font_dir := os.dir(ui2_test_font())
	for scale in [f32(1), f32(2)] {
		mut ctx := new_context_with_config(scale, ContextConfig{
			round_glyph_positions: false
		})!
		defer { ctx.free() }
		ctx.add_font_file(ui2_test_font())!
		ctx.add_font_file(os.join_path(font_dir, 'NotoEmoji-Regular.ttf'))!
		ctx.add_font_file(os.join_path(font_dir, 'NotoSansSymbols2-Regular.ttf'))!
		ctx.set_emoji_families(['Noto Emoji'])!
		cfg := TextConfig{
			// A trailing comma makes the family list literal: otherwise Pango
			// parses the last family's numeric suffix as the description's size.
			style: TextStyle{ font_name: 'Roboto, Noto Sans Symbols 2,', size: 21 }
			block: BlockStyle{ width: -1, line_height: 26.25 }
		}
		// Pango normally substitutes its generic emoji family for these runs;
		// the application preference must survive both ZWJ and VS16 itemization.
		for text in ['👩‍💻', '👨‍👩‍👧‍👦', '🙂', '☀️'] {
			layout := ctx.layout_text(text, cfg)!
			assert layout.get_font_name_at_index(0) == 'Noto Emoji'
			assert layout.width > 0
			assert layout.items.len == 1
			item := layout.items[0]
			mut visible_glyphs := 0
			for glyph in layout.glyphs {
				if glyph.index == 0x0fffffff { continue }
				assert glyph.index & pango_glyph_unknown_flag == 0
				assert C.FT_Load_Glyph(item.ft_face, glyph.index,
					C.FT_LOAD_RENDER | C.FT_LOAD_COLOR) == 0
				bitmap := item.ft_face.glyph.bitmap
				assert bitmap.width > 0 && bitmap.rows > 0
				pixels := ft_bitmap_to_bitmap(&bitmap, item.ft_face, int(item.ascent * scale))!
				mut alpha := u64(0)
				for i := 3; i < pixels.data.len; i += 4 { alpha += pixels.data[i] }
				assert alpha > 0
				visible_glyphs++
			}
			assert visible_glyphs == 1
		}
		assert ctx.layout_text('♜', cfg)!.get_font_name_at_index(0) == 'Noto Sans Symbols 2'
		// Emoji preference is separate from the normal family list: Pango 1.50
		// can select an explicitly listed emoji font for ASCII digits after Arabic.
		// Normal text retains the primary font for all scripts it covers.
		for source in ['Latin office café · Ελληνικά · Кириллица',
			'العربية · English 123'] {
			shaped := ctx.layout_text(source, cfg)!
			for part in ['Latin', 'Ελληνικά', 'Кириллица', '123'] {
				if index := source.index(part) {
					assert shaped.get_font_name_at_index(index) == 'Roboto'
				}
			}
		}
		// A different window/context can choose a different outline symbol face
		// without changing the first context's emoji or Latin resolution.
		mut other := new_context_with_config(scale, ContextConfig{})!
		defer { other.free() }
		other.set_emoji_families(['Noto Sans Symbols 2'])!
		assert other.layout_text('☀️', cfg)!.get_font_name_at_index(0) == 'Noto Sans Symbols 2'
		assert ctx.layout_text('☀️', cfg)!.get_font_name_at_index(0) == 'Noto Emoji'
		other.set_emoji_families([]string{})!
		assert other.layout_text('☀️', cfg)!.width > 0
	}
}

fn test_ui2_baked_layout_faces_survive_pango_font_cache_eviction() {
	mut ctx := new_context_with_config(1, ContextConfig{
		round_glyph_positions: false
	})!
	defer { ctx.free() }
	ctx.add_font_file(ui2_test_font())!
	cfg := TextConfig{
		style: TextStyle{ font_name: 'Roboto', size: 17 }
		block: BlockStyle{ width: -1, line_height: 21.25 }
	}
	first := ctx.layout_text('office café Ω', cfg)!
	face := first.items[0].ft_face
	glyph := first.glyphs[0].index
	assert C.FT_Load_Glyph(face, glyph, C.FT_LOAD_RENDER) == 0
	width := face.glyph.bitmap.width
	rows := face.glyph.bitmap.rows
	assert width > 0 && rows > 0
	// Pango's bounded fontset cache may discard all its own references after
	// layout extraction. Force that eviction through its public cache API.
	C.pango_fc_font_map_cache_clear(C.PANGO_FC_FONT_MAP(ctx.pango_font_map.ptr))
	for size in [f32(12), 24, 33] {
		ctx.layout_text('new font size', TextConfig{
			...cfg
			style: TextStyle{ ...cfg.style, size: size }
		})!
	}
	assert first.get_font_name_at_index(0) == 'Roboto'
	assert C.FT_Load_Glyph(face, glyph, C.FT_LOAD_RENDER) == 0
	assert face.glyph.bitmap.width == width
	assert face.glyph.bitmap.rows == rows
	// An explicit registration/configuration change ends the borrowed-layout
	// lifetime; fresh shaping remains usable and teardown is still idempotent.
	ctx.fonts_changed()
	assert ctx.layout_text('office café Ω', cfg)!.width == first.width
	ctx.free()
	ctx.free()
}

fn test_ui2_fractional_layout_is_independent_of_device_scale() {
	cfg := TextConfig{
		style: TextStyle{ font_name: 'Roboto', size: 16 }
		block: BlockStyle{ width: 131, line_height: 20 }
	}
	mut base := new_context_with_config(1, ContextConfig{
		round_glyph_positions: false
	})!
	defer { base.free() }
	base.add_font_file(ui2_test_font())!
	text := 'office café Ω sans 012345 wide WWW iii'
	reference := base.layout_text(text, cfg)!
	assert reference.lines.len == 3
	assert reference.height == 60
	for scale in [f32(1.25), f32(1.5), f32(2)] {
		mut ctx := new_context_with_config(scale, ContextConfig{
			round_glyph_positions: false
		})!
		layout := ctx.layout_text(text, cfg)!
		assert math.abs(layout.width - reference.width) < 0.002
		assert layout.height == reference.height
		assert layout.lines.len == reference.lines.len
		for index, line in layout.lines {
			assert line.start_index == reference.lines[index].start_index
			assert line.length == reference.lines[index].length
			assert line.rect.y == f32(index) * 20
			assert line.rect.height == 20
		}
		ctx.free()
		ctx.free()
	}
}

fn test_ui2_text_budget_accepts_long_text_without_weakening_validation() {
	mut standard := new_context(1)!
	defer { standard.free() }
	mut configured := new_context_with_config(1, ContextConfig{
		round_glyph_positions: false
		max_text_bytes:        0
	})!
	defer { configured.free() }
	configured.add_font_file(ui2_test_font())!
	cfg := TextConfig{
		style:          TextStyle{ font_name: 'Roboto', size: 16 }
		no_hit_testing: true
	}
	long_text := 'long text '.repeat(1500)
	if _ := standard.layout_text(long_text, cfg) {
		assert false, 'the upstream default byte budget must remain intact'
	}
	layout := configured.layout_text(long_text, cfg)!
	assert layout.width > 0
	assert layout.glyphs.len > 10240
	for invalid in [[u8(0xff)].bytestr(), [u8(97), 0, 98].bytestr()] {
		if _ := configured.layout_text(invalid, cfg) {
			assert false, 'an unlimited byte budget must still validate UTF-8 and NUL'
		}
	}
	assert configured.layout_text('', cfg)!.items.len == 0
}

fn test_ui2_zero_width_and_single_line_ellipsis_have_explicit_semantics() {
	mut ctx := new_context_with_config(1, ContextConfig{
		round_glyph_positions: false
	})!
	defer { ctx.free() }
	ctx.add_font_file(ui2_test_font())!
	style := TextStyle{ font_name: 'Roboto', size: 16 }
	intrinsic := ctx.layout_text('one longerword two', TextConfig{
		style: style
		block: BlockStyle{ width: 0 }
	})!
	unbounded := ctx.layout_text('one longerword two', TextConfig{ style: style })!
	assert intrinsic.lines.len == 3
	assert intrinsic.width > 0
	assert intrinsic.width < unbounded.width
	limited := ctx.layout_text('one longerword two\nnext paragraph', TextConfig{
		style: style
		block: BlockStyle{ width: 80, line_height: 20, max_lines: 1, ellipsize: true }
	})!
	assert limited.lines.len == 1
	assert limited.ellipsized
	assert limited.height == 20
}

fn test_ui2_cached_layout_distinguishes_block_metrics_and_visual_hyphens() {
	mut ctx := new_context_with_config(1, ContextConfig{ round_glyph_positions: false })!
	defer { ctx.free() }
	ctx.add_font_file(ui2_test_font().replace('Roboto-Regular.ttf', 'RobotoMono-Regular.ttf'))!
	// Exercise only the CPU layout-cache API; presentation needs no renderer.
	mut system := TextSystem{
		ctx:             ctx
		renderer:        unsafe { nil }
		am:              unsafe { nil }
		cache:           map[u64]&CachedLayout{}
		font_hash_cache: map[string]u64{}
	}
	style := TextStyle{ font_name: 'Roboto Mono', size: 16 }
	advance := ctx.layout_text('M', TextConfig{ style: style })!.width
	cfg := TextConfig{
		style: style
		block: BlockStyle{
			width:          advance * 2 + 0.05
			wrap:           .word_char
			line_height:    20
			insert_hyphens: false
		}
	}
	plain := system.layout_text_cached('MMMMM', cfg)!
	assert plain.lines.len == 3
	assert plain.height == 60
	assert plain.glyphs.len == 5
	hyphenated := system.layout_text_cached('MMMMM', TextConfig{
		...cfg
		block: BlockStyle{ ...cfg.block, insert_hyphens: true }
	})!
	assert hyphenated.glyphs.len > plain.glyphs.len
	assert hyphenated.lines.len > plain.lines.len
	spaced := system.layout_text_cached('MMMMM', TextConfig{
		...cfg
		block: BlockStyle{ ...cfg.block, line_height: 30 }
	})!
	assert spaced.height == 90
	limited := system.layout_text_cached('MMMMM', TextConfig{
		...cfg
		block: BlockStyle{ ...cfg.block, max_lines: 1, ellipsize: true }
	})!
	assert limited.lines.len == 1
	assert limited.ellipsized
	assert limited.height == 20
}

fn test_ui2_monospace_ellipsis_preserves_the_explicit_line_grid() {
	font := ui2_test_font().replace('Roboto-Regular.ttf', 'RobotoMono-Regular.ttf')
	for scale in [f32(1), f32(1.5), f32(2)] {
		mut ctx := new_context_with_config(scale, ContextConfig{ round_glyph_positions: false })!
		ctx.add_font_file(font)!
		style := TextStyle{ font_name: 'Roboto Mono', size: 16 }
		reference := ctx.layout_text('M', TextConfig{
			style: style
			block: BlockStyle{ line_height: 20, insert_hyphens: false }
		})!
		for limit in [1, 2] {
			text := 'MMMMMM'
			layout := ctx.layout_text(text, TextConfig{
				style: style
				block: BlockStyle{
					width:          reference.width * 2 + 0.05
					wrap:           .word_char
					line_height:    20
					max_lines:      limit
					ellipsize:      true
					insert_hyphens: false
				}
			})!
			assert layout.ellipsized
			assert layout.lines.len == limit
			assert layout.height == f32(limit * 20)
			for i, line in layout.lines {
				assert line.rect.y == f32(i * 20)
				assert line.rect.height == 20
				for item in layout.items {
					if item.start_index >= line.start_index && item.start_index < line.start_index + line.length {
						// A synthetic ellipsis uses the same font baseline as an
						// untruncated row, including fractional device scales.
						assert math.abs(item.y - reference.items[0].y - f64(i * 20)) < 0.002
					}
				}
			}
			for index in [0, text.len] {
				cursor := layout.get_cursor_pos(index) or { panic('missing cursor geometry at ${index}') }
				assert cursor.height == 20
				assert cursor.y == if index == 0 { f32(0) } else { f32((limit - 1) * 20) }
			}
			selection := layout.get_selection_rects(0, text.len)
			assert selection.len == limit
			for i, region in selection {
				assert region.y == f32(i * 20)
				assert region.height == 20
			}
			for character in layout.char_rects {
				assert character.rect.height == 20
				assert character.rect.y >= 0
				assert character.rect.y + character.rect.height <= layout.height
			}
		}
		ctx.free()
	}
}

fn test_ui2_empty_first_line_keeps_its_font_baseline() {
	mut ctx := new_context_with_config(1, ContextConfig{ round_glyph_positions: false })!
	defer { ctx.free() }
	ctx.add_font_file(ui2_test_font())!
	cfg := TextConfig{
		style: TextStyle{ font_name: 'Roboto', size: 16 }
		block: BlockStyle{ line_height: 20 }
	}
	reference := ctx.layout_text('M', cfg)!
	blank_first := ctx.layout_text('\nM', cfg)!
	assert blank_first.lines.len == 2
	assert blank_first.lines[0].baseline == reference.lines[0].baseline
	assert blank_first.lines[1].baseline == reference.lines[0].baseline + 20
	assert blank_first.items[0].y == f64(blank_first.lines[1].baseline)
}
