module vglyph

import log
import strings
import gg

$if profile ? {
	import time
}

const space_char = u8(32)

// Coordinate Systems (vglyph conventions):
// - Pango units: 1/PANGO_SCALE of a point (1024 units per point)
// - Logical pixels: 1pt = 1px before DPI scaling
// - Physical pixels: logical * scale_factor (for rasterization)
// - Screen Y: Down is positive (standard graphics convention)
// - Baseline Y: Up is positive (FreeType/typography convention)
//
// Vertical Text Flow:
// - Characters stack top-to-bottom (pen moves DOWN)
// - Each glyph centered horizontally in column
// - Column width = line_height (ascent + descent)

// layout_text shapes, wraps, and arranges text using Pango.
//
// Algorithm:
// 1. Create transient `PangoLayout`.
// 2. Apply config: Width, Alignment, Font, Markup.
// 3. Iterate layout to decompose text into visual "Run"s (glyphs sharing font/attrs).
// 4. Extract glyph info (index, position) to V `Item`s.
// 5. "Bake" hit-testing data (char bounding boxes).
//
// Trade-offs:
// - **Performance**: Shaping is expensive. Call only when text changes.
//   Resulting `Layout` is cheap to draw.
// - **Memory**: Duplicates glyph indices/positions to V structs to decouple
//   lifecycle from Pango.
// - **Color**: Manually map Pango attrs to `gg.Color` for rendering. Pango
//   attaches colors as metadata, not to glyphs directly.
//
// Returns error if:
// - text is empty, exceeds max length (10KB), or contains invalid UTF-8
// - Pango layout creation fails
pub fn (mut ctx Context) layout_text(text string, cfg TextConfig) !Layout {
	$if profile ? {
		start := time.sys_mono_now()
		defer {
			ctx.layout_time_ns += time.sys_mono_now() - start
		}
	}
	if text.len == 0 {
		return Layout{}
	}

	// Defensive validation (API boundary validates, this is defense-in-depth).
	validate_layout_text_input(text, ctx.max_text_bytes, @FN)!

	markup_rise_pango := int(cfg.style.rise * ctx.scale_factor * pango_scale)
	compose_markup_rise := cfg.use_markup && markup_rise_pango != 0
	pango_cfg := if compose_markup_rise { config_without_base_rise(cfg) } else { cfg }
	mut layout := setup_pango_layout(mut ctx, text, pango_cfg) or {
		log.error('${@FILE_LINE}: ${err.msg()}')
		return err
	}
	defer { layout.free() }

	if compose_markup_rise {
		compose_markup_style_rise(layout, markup_rise_pango)
	}
	return build_layout_from_pango(mut ctx, layout, text, ctx.scale_factor, cfg)
}

fn config_without_base_rise(cfg TextConfig) TextConfig {
	return TextConfig{
		...cfg
		style: TextStyle{
			...cfg.style
			rise: 0
		}
	}
}

fn validate_layout_text_input(text string, max_bytes int, location string) ! {
	validate_text_input(text, max_bytes, location)!
	for i in 0 .. text.len {
		if text[i] == 0 {
			return error('NUL byte not allowed at ${location}')
		}
	}
}

fn compose_markup_style_rise(layout PangoLayout, style_rise int) {
	base_attrs := layout.get_attributes()
	plain_text_ptr := C.vglyph_pango_layout_get_text_borrowed(layout.ptr)
	plain_len := if plain_text_ptr == unsafe { nil } {
		0
	} else {
		unsafe { cstring_to_vstring(plain_text_ptr).len }
	}
	if plain_len == 0 {
		return
	}

	mut composed := new_pango_attr_list()
	if base_attrs == unsafe { nil } {
		insert_rise_attr(composed, 0, plain_len, style_rise)
		layout.set_attributes(composed)
		composed.free()
		return
	}

	iter := C.pango_attr_list_get_iterator(base_attrs)
	if iter == unsafe { nil } {
		insert_rise_attr(composed, 0, plain_len, style_rise)
		layout.set_attributes(composed)
		composed.free()
		return
	}

	for {
		mut start := 0
		mut end := 0
		C.pango_attr_iterator_range(iter, &start, &end)
		if start < 0 {
			start = 0
		}
		if end < 0 || end > plain_len {
			end = plain_len
		}
		if start < end {
			markup_rise := copy_effective_attrs_without_rise(iter, composed, start, end)
			insert_rise_attr(composed, start, end, style_rise + markup_rise)
		}
		if !C.pango_attr_iterator_next(iter) {
			break
		}
	}
	C.pango_attr_iterator_destroy(iter)
	layout.set_attributes(composed)
	composed.free()
}

fn copy_effective_attrs_without_rise(iter &C.PangoAttrIterator, attrs PangoAttrList, start int,
	end int) int {
	mut markup_rise := 0
	mut attr_node := C.pango_attr_iterator_get_attrs(iter)
	mut node := attr_node
	for node != unsafe { nil } {
		mut attr_copy := &C.PangoAttribute(unsafe { nil })
		mut rise_delta := 0
		unsafe {
			attr := &C.PangoAttribute(node.data)
			if attr.klass.type == .pango_attr_rise {
				int_attr := &C.PangoAttrInt(attr)
				rise_delta = int_attr.value
			} else {
				attr_copy = C.pango_attribute_copy(attr)
			}
			C.pango_attribute_destroy(attr)
		}
		markup_rise += rise_delta
		if attr_copy != unsafe { nil } {
			attr_copy.start_index = u32(start)
			attr_copy.end_index = u32(end)
			C.pango_attr_list_insert(attrs.ptr, attr_copy)
		}
		node = node.next
	}
	if attr_node != unsafe { nil } {
		C.g_slist_free(attr_node)
	}
	return markup_rise
}

fn insert_rise_attr(attrs PangoAttrList, start int, end int, rise int) {
	if rise == 0 || start >= end {
		return
	}
	mut attr := C.pango_attr_rise_new(rise)
	attr.start_index = u32(start)
	attr.end_index = u32(end)
	C.pango_attr_list_insert(attrs.ptr, attr)
}

// layout_rich_text layouts text with multiple styles (RichText).
// It combines the base configuration (cfg) with per-run style overrides.
// It concatenates the text from all runs to form the full paragraph.
//
// Returns error if:
// - any run's text is empty, exceeds max length (10KB), or contains invalid UTF-8
// - Pango layout creation fails
pub fn (mut ctx Context) layout_rich_text(rt RichText, cfg TextConfig) !Layout {
	$if profile ? {
		start := time.sys_mono_now()
		defer {
			ctx.layout_time_ns += time.sys_mono_now() - start
		}
	}
	if rt.runs.len == 0 {
		return Layout{}
	}

	// Defensive validation of each run's text (defense-in-depth).
	for run in rt.runs {
		validate_layout_text_input(run.text, ctx.max_text_bytes, @FN)!
	}

	// 1. Build Full Text and Calculate Indices
	mut full_text := strings.new_builder(0)
	// Note: Strings in Pango are byte-indexed. We must track byte offsets.

	// Temporary struct to hold calculated ranges
	struct RunRange {
		start int
		end   int
		style TextStyle
	}

	mut valid_runs := []RunRange{cap: rt.runs.len}

	mut current_idx := 0
	for run in rt.runs {
		full_text.write_string(run.text)
		encoded_len := run.text.len // Byte length
		valid_runs << RunRange{
			start: current_idx
			end:   current_idx + encoded_len
			style: run.style
		}
		current_idx += encoded_len
	}

	text := full_text.str()
	validate_layout_text_input(text, ctx.max_text_bytes, @FN)!

	// 2. Setup base layout with global config. Rich text applies rise per run
	// below so Pango geometry uses VGlyph's cumulative rise semantics.
	pango_cfg := config_without_base_rise(cfg)
	mut layout := setup_pango_layout(mut ctx, text, pango_cfg) or {
		log.error('${@FILE_LINE}: ${err.msg()}')
		return err
	}
	defer { layout.free() }

	// 3. Modify attributes with runs
	base_list := layout.get_attributes()
	mut attr_list := PangoAttrList{}

	if base_list != unsafe { nil } {
		attr_list.ptr = C.pango_attr_list_copy(base_list)
		track_attr_list_alloc()
	} else {
		attr_list = new_pango_attr_list()
	}

	// Apply styles from runs
	mut cloned_ids := []string{}
	for run in valid_runs {
		effective_rise := cfg.style.rise + run.style.rise
		effective_rise_pango := int(effective_rise * ctx.scale_factor * pango_scale)
		apply_rich_text_style(mut ctx, attr_list, run.style, run.start, run.end,
			effective_rise_pango, mut cloned_ids)
	}

	layout.set_attributes(attr_list)
	attr_list.free()

	// 4. Process layout
	mut result := build_layout_from_pango(mut ctx, layout, text, ctx.scale_factor, cfg)
	// Absolute line-height attributes apply per font run in Pango. Mixed
	// ascenders/descenders can enlarge the resulting line box despite the
	// requested advance. Restore the shared grid without changing glyph sizes.
	if !result.ellipsized && !cfg.block.strict_line_height && cfg.orientation == .horizontal && cfg.block.line_height > 0 {
		normalize_absolute_line_height(layout, mut result, cfg.block.line_height,
			ctx.scale_factor, compute_line_rises(layout))
	}
	result.cloned_object_ids = cloned_ids
	return result
}

// build_layout_from_pango extracts V Items, Lines, and Rects from a configured PangoLayout.
fn build_layout_from_pango(mut ctx Context, layout PangoLayout, text string, scale_factor f32,
	cfg TextConfig) Layout {
	// Iterator lifecycle:
	// 1. Create via pango_layout_get_iter (caller owns)
	// 2. Iterate with next_run/next_char/next_line until returns false
	// 3. DO NOT reuse after exhausted - create new iterator
	// 4. MUST free via pango_layout_iter_free (defer handles this)
	mut iter := layout.get_iter()
	if iter.is_nil() {
		// handle error gracefully
		return Layout{}
	}
	defer { iter.free() }
	mut iter_exhausted := false

	// Pre-calculate inverse scale for faster pixel conversion
	pixel_scale := 1.0 / (f64(pango_scale) * f64(scale_factor))

	// Get primary font metrics for vertical alignment of emojis
	mut primary_ascent := f64(0)
	mut primary_descent := f64(0)
	mut primary_strike_pos := f64(0)
	mut primary_strike_thick := f64(0)
	font_desc := C.vglyph_pango_layout_get_font_description_borrowed(layout.ptr)
	if font_desc != unsafe { nil } {
		// Create a temporary metrics context
		pango_ctx := C.pango_layout_get_context(layout.ptr)
		lang := C.pango_language_get_default()
		metrics := C.pango_context_get_metrics(pango_ctx, font_desc, lang)
		if metrics != unsafe { nil } {
			val_ascent := C.pango_font_metrics_get_ascent(metrics)
			val_descent := C.pango_font_metrics_get_descent(metrics)
			primary_ascent = f64(val_ascent) * pixel_scale
			primary_descent = f64(val_descent) * pixel_scale
			primary_strike_pos = f64(C.pango_font_metrics_get_strikethrough_position(metrics)) * pixel_scale
			primary_strike_thick = f64(C.pango_font_metrics_get_strikethrough_thickness(metrics)) * pixel_scale
			C.pango_font_metrics_unref(metrics)
		}
	}

	// Fallback: derive from first run's font if base desc
	// yielded no metrics (e.g. RTF with empty base style)
	if primary_ascent == 0 {
		run_ptr := C.pango_layout_iter_get_run_readonly(iter.ptr)
		if run_ptr != unsafe { nil } {
			run := unsafe { &C.PangoLayoutRun(run_ptr) }
			font := run.item.analysis.font
			if font != unsafe { nil } {
				lang := run.item.analysis.language
				m := C.pango_font_get_metrics(font, lang)
				if m != unsafe { nil } {
					primary_ascent = f64(C.pango_font_metrics_get_ascent(m)) * pixel_scale
					primary_descent = f64(C.pango_font_metrics_get_descent(m)) * pixel_scale
					primary_strike_pos = f64(C.pango_font_metrics_get_strikethrough_position(m)) * pixel_scale
					primary_strike_thick = f64(C.pango_font_metrics_get_strikethrough_thickness(m)) * pixel_scale
					C.pango_font_metrics_unref(m)
				}
			}
		}
	}

	mut all_glyphs := []Glyph{}
	mut items := []Item{}
	line_rises := compute_line_rises(layout)

	// Track cumulative vertical position for vertical text stacking
	mut vertical_pen_y := match cfg.orientation {
		.horizontal { init_vertical_pen_horizontal() }
		.vertical { init_vertical_pen_vertical(primary_ascent) }
	}

	for {
		$if debug {
			if iter_exhausted {
				panic('layout iterator reused after exhaustion')
			}
		}
		run_ptr := C.pango_layout_iter_get_run_readonly(iter.ptr)
		if run_ptr != unsafe { nil } {
			run := unsafe { &C.PangoLayoutRun(run_ptr) }
			ctx.retain_font(run.item.analysis.font)
			vertical_pen_y = process_run(mut items, mut all_glyphs, vertical_pen_y, ProcessRunConfig{
				run:                  run
				iter:                 iter.ptr
				text:                 text
				scale_factor:         scale_factor
				pixel_scale:          pixel_scale
				primary_ascent:       primary_ascent
				primary_descent:      primary_descent
				primary_strike_pos:   primary_strike_pos
				primary_strike_thick: primary_strike_thick
				base_color:           cfg.style.color
				orientation:          cfg.orientation
				stroke_width:         cfg.style.stroke_width
				stroke_color:         cfg.style.stroke_color
				line_rises:           line_rises
			})
		}

		if !C.pango_layout_iter_next_run(iter.ptr) {
			iter_exhausted = true
			break
		}
	}

	mut char_rects := []CharRect{}
	mut char_rect_by_index := map[int]int{}
	if !cfg.no_hit_testing {
		char_rects = compute_hit_test_rects(layout, text, scale_factor, line_rises, cfg.orientation)
		// Build index map for O(1) lookup
		for i, cr in char_rects {
			char_rect_by_index[cr.index] = i
		}
	}
	lines := compute_lines(layout, scale_factor, line_rises, cfg.orientation)

	ink_rect := C.PangoRectangle{}
	logical_rect := C.PangoRectangle{}
	C.pango_layout_get_extents(layout.ptr, &ink_rect, &logical_rect)

	// Convert Pango units to pixels
	l_width := (f32(logical_rect.width) / f32(pango_scale)) / scale_factor
	l_height := (f32(logical_rect.height) / f32(pango_scale)) / scale_factor
	mut v_width := (f32(ink_rect.width) / f32(pango_scale)) / scale_factor
	mut v_height := (f32(ink_rect.height) / f32(pango_scale)) / scale_factor

	v_width, v_height = match cfg.orientation {
		.horizontal {
			compute_dimensions_horizontal(f32(ink_rect.width), f32(ink_rect.height),
				f32(pango_scale), scale_factor)
		}
		.vertical {
			compute_dimensions_vertical(l_height, f32(vertical_pen_y))
		}
	}

	// Extract LogAttr data while PangoLayout is still valid
	log_attr_result := extract_log_attrs(layout, text)

	mut result := Layout{
		text:               text
		ellipsized:         C.pango_layout_is_ellipsized(layout.ptr)
		items:              items
		glyphs:             all_glyphs
		char_rects:         char_rects
		char_rect_by_index: char_rect_by_index
		lines:              lines
		log_attrs:          log_attr_result.attrs
		log_attr_by_index:  log_attr_result.by_index
		width:              l_width
		height:             l_height
		visual_width:       v_width
		visual_height:      v_height
	}
	if (result.ellipsized || cfg.block.strict_line_height) && cfg.orientation == .horizontal && cfg.block.line_height > 0 {
		normalize_absolute_line_height(layout, mut result, cfg.block.line_height,
			scale_factor, line_rises)
	}
	return result
}

// Pango shapes its synthetic ellipsis without the absolute-line-height
// attribute and can expand mixed-font line extents. Restore the line grid for
// queries; keep the font ascent/descent so rasterization retains its size.
fn normalize_absolute_line_height(pango_layout PangoLayout, mut layout Layout,
	line_height f32, scale_factor f32, line_rises []LineRise) {
	mut shifts := []f32{len: layout.lines.len}
	for i, line in layout.lines {
		y := f32(i) * line_height
		shifts[i] = y - line.rect.y + (line_height - line.rect.height) * 0.5
		layout.lines[i] = Line{
			...line
			rect:     gg.Rect{ ...line.rect, y: y, height: line_height }
			baseline: line.baseline + shifts[i]
		}
	}
	for i, item in layout.items {
		line_index := layout_line_for_byte(layout.lines, item.start_index)
		if line_index >= 0 {
			layout.items[i] = Item{ ...item, y: item.y + f64(shifts[line_index]) }
		}
	}
	for i, character in layout.char_rects {
		line_index := layout_line_for_byte(layout.lines, character.index)
		if line_index >= 0 {
			layout.char_rects[i] = CharRect{
				...character
				rect: gg.Rect{
					...character.rect
					y:      layout.lines[line_index].rect.y
					height: line_height
				}
			}
		}
	}
	layout.height = line_height * f32(layout.lines.len)

	// Ink height also follows the displaced baselines. Its horizontal bounds
	// and each glyph's advance stay exactly as shaped by Pango.
	mut iter := pango_layout.get_iter()
	if iter.is_nil() { return }
	defer { iter.free() }
	pixel_scale := 1.0 / (f32(pango_scale) * scale_factor)
	mut ink_top := f32(0)
	mut ink_bottom := f32(0)
	mut has_ink := false
	for i, line in layout.lines {
		ink := C.PangoRectangle{}
		C.pango_layout_iter_get_line_extents(iter.ptr, &ink, unsafe { nil })
		if ink.height > 0 {
			rise := f32(resolve_line_rise(line.start_index, line.length, line_rises, 0)) * pixel_scale
			top := f32(ink.y) * pixel_scale - rise + shifts[i]
			bottom := top + f32(ink.height) * pixel_scale
			if !has_ink || top < ink_top { ink_top = top }
			if !has_ink || bottom > ink_bottom { ink_bottom = bottom }
			has_ink = true
		}
		if !C.pango_layout_iter_next_line(iter.ptr) { break }
	}
	if has_ink { layout.visual_height = ink_bottom - ink_top }
}

// Lines are sorted by source byte offset even when their visual runs are bidi.
fn layout_line_for_byte(lines []Line, index int) int {
	mut low := 0
	mut high := lines.len
	for low < high {
		mid := low + (high - low) / 2
		if lines[mid].start_index <= index { low = mid + 1 } else { high = mid }
	}
	return low - 1
}
