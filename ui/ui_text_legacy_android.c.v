// vfmt off
// The Android renderer retains gg/Fontstash until its Pango dependencies can be
// built and packaged. Keep this legacy adapter out of desktop compilation.
@[has_globals]
module ui2

$if android && !ui2_headless ? {
	import fontstash
	import gg
	import math
	import os

	// text_font_file resolves a declared family to the file fontstash has to
	// load. gg reads TextCfg.family as a path and, when it cannot read one,
	// returns without touching the font state at all, leaving the string drawn
	// in whatever the previous element used. An unknown family therefore has to
	// come back empty so the default font is used instead.
	fn text_font_file(family string, bold bool, italic bool) string {
		if family.len == 0 {
			return ''
		}
		key := '${family}:${bold}:${italic}'
		if path := g_font_family_files[key] {
			return path
		}
		mut path := ''
		if os.is_file(family) {
			path = family
		} else {
			if !g_font_indexed {
				mut dirs := font_bundle_dirs()
				dirs << font_system_dirs()
				g_font_files = font_index(dirs)
				g_font_indexed = true
			}
			path = font_lookup(g_font_files, family, bold, italic)
			if path.len == 0 && (bold || italic) {
				// A family with no bold or italic file of its own still reads
				// better in its regular weight than in the default font.
				path = font_lookup(g_font_files, family, false, false)
			}
			if path.len == 0 && font_is_mono_family(family) {
				// Falling back to the proportional default would break the
				// column alignment the element asked for in the first place.
				path = font_mono_path(g_font_files, family, bold, italic)
			}
		}
		g_font_family_files[key] = path
		return path
	}

	// ensure_symbol_fallbacks hands fontstash the faces to look in when the font
	// a string is drawn in has no outline for one of its code points. fontstash
	// walks a font's fallback list whenever a glyph lookup lands on index 0 —
	// the empty box, or tofu — and rasterizes the first face that does have the
	// code point, so a label mixing letters and symbols is still drawn in one
	// pass and measured exactly the way it is drawn.
	//
	// The ids belong to the fontstash context gg loaded its fonts into. Sokol
	// builds a new one whenever the window is recreated, on an Android resume
	// among others, so the loaded faces are tracked against the context they
	// came from rather than behind a flag that a new context would not clear.
	fn ensure_symbol_fallbacks(ctx &DrawContext) {
		if !ctx.font_inited || ctx.ft == unsafe { nil } || ctx.ft.fons == unsafe { nil } {
			return
		}
		fons := ctx.ft.fons
		if g_font_symbol_fons != voidptr(fons) {
			g_font_symbol_fons = voidptr(fons)
			clear_text_area_layouts()
			g_font_symbol_ids = []int{}
			g_font_symbol_bases = map[int]bool{}
			for path in font_symbol_paths() {
				bytes := os.read_bytes(path) or { continue }
				id := fons.add_font_mem(path, bytes, true)
				if id != fontstash.invalid {
					g_font_symbol_ids << id
				}
			}
		}
		for base in [ctx.ft.font_normal, ctx.ft.font_bold, ctx.ft.font_mono, ctx.ft.font_italic] {
			add_symbol_fallbacks(fons, base)
		}
	}

	// add_symbol_fallbacks attaches the chain to one font, once. fontstash gives
	// a font a fixed number of fallback slots and appends to them blindly, so
	// registering the same face twice would spend them for nothing.
	fn add_symbol_fallbacks(fons &fontstash.Context, base int) {
		if base == fontstash.invalid || g_font_symbol_ids.len == 0 || base in g_font_symbol_bases {
			return
		}
		g_font_symbol_bases[base] = true
		for id in g_font_symbol_ids {
			if id != base {
				fons.add_fallback_font(base, id)
			}
		}
	}

	// ensure_family_fallbacks gives a face named by TextStyle.font_family the
	// same chain. gg loads such a file itself, on the first draw that asks for
	// it, and keeps the id in a map of its own; loading it here first puts the
	// id in that map before any glyph is rasterized from it, which is the only
	// moment the fallbacks can still be attached.
	fn ensure_family_fallbacks(ctx &DrawContext, path string) {
		if path.len == 0 || g_font_symbol_ids.len == 0 || !ctx.font_inited {
			return
		}
		mut id := ctx.ft.fonts_map[path]
		if id == 0 {
			bytes := os.read_bytes(path) or { return }
			id = ctx.ft.fons.add_font_mem(path, bytes, true)
			if id == fontstash.invalid {
				return
			}
			unsafe {
				ctx.ft.fonts_map[path] = id
			}
		}
		add_symbol_fallbacks(ctx.ft.fons, id)
	}

	// text_font_metrics reports the metrics to size a string with: the chosen
	// family's own, or the window font's when the element declared none.
	fn text_font_metrics(path string) FontMetrics {
		if path.len == 0 {
			return g_font_metrics
		}
		if metrics := g_font_family_metrics[path] {
			return metrics
		}
		metrics := font_file_metrics(path) or { g_font_metrics }
		g_font_family_metrics[path] = metrics
		return metrics
	}

	// text_ellipsis marks a line the renderer had to shorten. AppKit's cells
	// truncate with this glyph too, and the bundled Roboto always has it.
	const text_ellipsis = '\u2026'

	// fit_text shortens a line that is wider than the box it was given. Both
	// native backends hand their labels NSLineBreakByTruncatingTail, so a long
	// string ends in an ellipsis there; the immediate renderer draws straight
	// into the window and would otherwise run the tail over its neighbours and
	// off the window edge.
	// Break text into the lines a multi-line label draws: on its own newlines, and on
	// spaces wherever a line would outgrow the width. A word wider than the line is
	// left whole and truncated when it is drawn, rather than split mid-word.
	fn wrap_text_lines(ctx &DrawContext, t string, w f64, limit int, cfg gg.TextCfg) []string {
		if limit <= 1 || w <= 0 {
			return t.split('\n')
		}
		ctx.set_text_cfg(cfg)
		return wrap_text_lines_measured(t, w, limit, fn [ctx] (line string) f64 {
			return f64(ctx.text_width_f(line))
		})
	}

	fn fit_text(ctx &DrawContext, t string, w f64, cfg gg.TextCfg) string {
		if w <= 0 {
			return t
		}
		ctx.set_text_cfg(cfg)
		if f64(ctx.text_width_f(t)) <= w {
			return t
		}
		runes := t.runes()
		// The longest head that still fits, found by halving rather than by
		// dropping one rune at a time, so a long line costs a handful of
		// measurements instead of one per character.
		mut kept := 0
		mut high := runes.len
		for kept < high {
			mid := (kept + high + 1) / 2
			if f64(ctx.text_width_f(runes[..mid].string() + text_ellipsis)) <= w {
				kept = mid
			} else {
				high = mid - 1
			}
		}
		return runes[..kept].string() + text_ellipsis
	}

	fn draw_text_field_selection(ctx &DrawContext, display_text string, selection TextSelection, x f64, y f64, w f64, h f64, style TextStyle) {
		before, selected := text_field_selection_text(display_text, selection)
		if selected.len == 0 || w <= 0 {
			return
		}
		family := text_font_file(style.font_family, style.bold, style.italic)
		ensure_family_fallbacks(ctx, family)
		ctx.set_text_cfg(gg.TextCfg{
			color: hex_color(style.color)
			size: int(font_render_size(style.size, text_font_metrics(family)) + 0.5)
			bold: style.bold
			italic: style.italic
			family: family
			align: text_align(style.align)
			vertical_align: .middle
		})
		text_width := f64(ctx.text_width(display_text))
		text_origin := text_field_aligned_text_origin(x, w, text_width, style.align)
		mut left := text_origin + f64(ctx.text_width(before))
		mut right := left + f64(ctx.text_width(selected))
		if left < x {
			left = x
		}
		if right > x + w {
			right = x + w
		}
		if right > left {
			draw_rect(ctx, left, y + h * 0.2, right - left, h * 0.6, 0xb8d7ff, 0)
		}
	}

	fn draw_legacy_text_area_content(ctx &DrawContext, el Element, value string, x f64, y f64, clip Rect, scroll_parent_id string) {
		dispatch := custom_input_dispatch(g_gg_app)
		root := g_focus_navigation.root
		mut editor := g_text_editors[el.id] or { text_editor(value.clone()) }
		$if macos && ui2_embedder ? {
			editor = custom_composition_editor(el.id, editor)
		}
		shown := editor.text
		frame := rect(x, y, el.frame.width, el.frame.height)
		content := text_area_content_rect(frame, el.padding_left, !el.disable_scroll)
		style := el.text_style
		family := text_font_file(style.font_family, style.bold, style.italic)
		ensure_family_fallbacks(ctx, family)
		cfg := gg.TextCfg{
			color: hex_color(style.color)
			size: int(font_render_size(style.size, text_font_metrics(family)) + 0.5)
			bold: style.bold
			italic: style.italic
			family: family
			align: text_align(style.align)
			vertical_align: .middle
		}
		ctx.set_text_cfg(cfg)
		lines := text_area_lines(el.id, shown, content.width, style, cfg.size, fn [ctx] (line string) f64 {
			return f64(ctx.text_width_f(line))
		})
		line_ranges := text_area_line_rune_ranges(shown, lines)
		selection_start, selection_end := editor.selection.ordered()
		show_selection := g_focused_field == el.id && selection_start != selection_end
		line_height := math.max(1.0, font_line_height(style.size))
		content_height := f64(lines.len) * line_height + text_area_vertical_padding * 2
		// Read-only means not editable, not unscrollable. disable_scroll only
		// hides the scroller, matching Element's documented/native behavior.
		scroll_id := text_area_scroll_id(el)
		offset := register_scroll_view_in_parent(scroll_id, scroll_parent_id, frame, clip, content_height, el.enabled,
			!el.disable_scroll, el.persistent_scrollbars, HitTarget{ id: el.id, on_event: el.on_event })
		if !custom_frame_current(dispatch, ctx) || g_focus_navigation.root != root { return }
		text_clip := intersect_rect(content, clip)
		if text_clip.width > 0 && text_clip.height > 0 {
			apply_clip(ctx, text_clip)
			text_x := match style.align {
				.left { content.x }
				.center { content.x + content.width / 2 }
				.right { content.x + content.width }
			}
			first, last := visible_text_area_rows(lines.len, content.y, line_height, offset, text_clip)
			for index in first .. last {
				text_y := content.y + (f64(index) + 0.5) * line_height - offset
				if show_selection && index < line_ranges.len {
					line_range := line_ranges[index]
					from := if selection_start > line_range.start { selection_start } else { line_range.start }
					to := if selection_end < line_range.end { selection_end } else { line_range.end }
					if to > from {
						line_runes := lines[index].runes()
						prefix := line_runes[..from - line_range.start].string()
						selected := line_runes[from - line_range.start..to - line_range.start].string()
						line_width := f64(ctx.text_width_f(lines[index]))
						line_origin := text_field_aligned_text_origin(content.x, content.width, line_width,
							style.align)
						draw_rect(ctx, line_origin + f64(ctx.text_width_f(prefix)), text_y - line_height / 2,
							f64(ctx.text_width_f(selected)), line_height, 0xb8d7ff, 0)
					}
				}
				ctx.draw_text(int(text_x), int(text_y), lines[index], cfg)
				if g_focused_field == el.id && index < line_ranges.len {
					line_range := line_ranges[index]
					line_origin := text_field_aligned_text_origin(content.x, content.width,
						f64(ctx.text_width_f(lines[index])), style.align)
					if editor.selection.caret >= line_range.start && editor.selection.caret <= line_range.end {
						prefix := lines[index].runes()[..editor.selection.caret - line_range.start].string()
						caret_x := line_origin + f64(ctx.text_width_f(prefix))
						g_gg_app.text_caret = rect(caret_x, text_y - line_height / 2, 2, line_height)
						$if macos && ui2_embedder ? {
							draw_rect(ctx, caret_x, text_y - line_height / 2, 2, line_height, style.color, 0)
						}
					}
					$if macos && ui2_embedder ? {
						composition := g_gg_app.composition
						if composition.field_id == el.id {
							from := clamp_int(composition.start + composition.mark_start, line_range.start, line_range.end)
							to := clamp_int(composition.start + composition.mark_start + composition.mark_length, from, line_range.end)
							if to > from {
								line_runes := lines[index].runes()
								left := line_origin + f64(ctx.text_width_f(line_runes[..from - line_range.start].string()))
								right := line_origin + f64(ctx.text_width_f(line_runes[..to - line_range.start].string()))
								draw_rect(ctx, left, text_y + line_height / 2 - 1, right - left, 1, style.color, 0)
							}
						}
					}
				}
			}
		}
		pane_clip := intersect_rect(frame, clip)
		if !el.disable_scroll && pane_clip.width > 0 && pane_clip.height > 0 {
			apply_clip(ctx, pane_clip)
			draw_scrollbar(ctx, x, y, frame.width, frame.height, content_height, offset,
				el.persistent_scrollbars)
		}
		// Neither the next sibling nor the pane's scrollbar inherits the text clip.
		apply_clip(ctx, clip)
	}


	fn text_area_lines(id string, value string, width f64, style TextStyle, rendered_size int, measure fn (string) f64) []string {
		if id.len > 0 {
			if cached := g_text_area_layouts[id] {
				if cached.text == value && cached.width == width && cached.style == style
					&& cached.rendered_size == rendered_size {
					return cached.lines
				}
			}
		}
		lines := wrap_text_area_lines(value, width, measure)
		if id.len > 0 {
			replace_text_area_layout(id, TextAreaLayout{
				text: value
				width: width
				style: style
				rendered_size: rendered_size
				lines: lines
				ranges: text_area_line_rune_ranges(value, lines)
			})
		}
		return lines
	}

	// normalized_text_area_runes returns the renderer's newline-normalized runes
	// and the corresponding original source offset for every rune boundary.
	// Keeping this map makes selection offsets correct for CRLF input.
	fn normalized_text_area_runes(value string) ([]rune, []int) {
		source := value.runes()
		mut normalized := []rune{cap: source.len}
		mut source_offsets := []int{cap: source.len + 1}
		mut source_index := 0
		for source_index < source.len {
			source_offsets << source_index
			if source[source_index] == `\r` {
				normalized << `\n`
				if source_index + 1 < source.len && source[source_index + 1] == `\n` {
					source_index += 2
				} else {
					source_index++
				}
			} else {
				normalized << source[source_index]
				source_index++
			}
		}
		source_offsets << source.len
		return normalized, source_offsets
	}

	// text_area_line_rune_ranges maps rendered wrapped lines back to their
	// original source rune offsets. Whitespace discarded at wrap points is
	// intentionally outside every line range.
	fn text_area_line_rune_ranges(value string, lines []string) []TextAreaLineRange {
		runes, source_offsets := normalized_text_area_runes(value)
		mut ranges := []TextAreaLineRange{cap: lines.len}
		mut cursor := 0
		for line in lines {
			line_runes := line.runes()
			if line_runes.len == 0 {
				ranges << TextAreaLineRange{
					start: source_offsets[cursor]
					end: source_offsets[cursor]
				}
				continue
			}
			mut start := cursor
			for candidate := cursor; candidate + line_runes.len <= runes.len; candidate++ {
				mut matches := true
				for index in 0 .. line_runes.len {
					if runes[candidate + index] != line_runes[index] {
						matches = false
						break
					}
				}
				if matches {
					start = candidate
					break
				}
			}
			end := start + line_runes.len
			ranges << TextAreaLineRange{
				start: source_offsets[start]
				end: source_offsets[end]
			}
			cursor = end
		}
		return ranges
	}

	fn visible_text_area_rows(count int, top f64, line_height f64, offset f64, clip Rect) (int, int) {
		if count <= 0 || line_height <= 0 || clip.width <= 0 || clip.height <= 0 {
			return 0, 0
		}
		first := int(math.max(0.0, math.min(f64(count), math.floor((clip.y - top + offset) / line_height))))
		last := int(math.max(f64(first), math.min(f64(count), math.ceil((clip.y + clip.height - top + offset) / line_height))))
		return first, last
	}

	// Android retains this wrapping helper while desktop tooltips use shaped blocks.
	// tooltip_lines wraps tooltip text to a readable measure and reports the
	// width of the widest line, so short help gets a snug bubble. The line cap
	// keeps a long string from filling the window; its last line carries the
	// rest and is shortened when drawn.
	fn tooltip_lines(text string, measure fn (string) f64) ([]string, f64) {
		lines := wrap_text_lines_measured(text.trim_right(' \t\r\n'), tooltip_max_text_width,
			tooltip_max_lines, measure)
		mut widest := 0.0
		for line in lines {
			width := measure(line)
			if width > widest {
				widest = width
			}
		}
		return lines, math.min(math.ceil(widest), tooltip_max_text_width)
	}

	fn text_align(a Align) gg.HorizontalAlign {
		return match a {
			.left { .left }
			.center { .center }
			.right { .right }
		}
	}

	// draw_editable_text draws the text of a field the caller can type in.
	// Those controls place the caret by measuring the whole string, so a
	// shortened line would leave the caret sitting past the end of it.
	fn draw_editable_text(ctx &DrawContext, t string, x f64, y f64, w f64, h f64, style TextStyle) {
		draw_text_in_box(ctx, t, x, y, w, h, centered_text_style(style), false, Rect{})
	}

	fn text_field_selection_text(display_text string, selection TextSelection) (string, string) {
		runes := display_text.runes()
		start, end := selection.ordered()
		from := clamp_int(start, 0, runes.len)
		to := clamp_int(end, from, runes.len)
		return runes[..from].string(), runes[from..to].string()
	}

}
