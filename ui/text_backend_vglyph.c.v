// vfmt off
@[has_globals]
module ui2

// Desktop custom text owns its Pango context independently of the window/GPU.
// The Android, native and explicitly headless adapters retain their legacy path.
$if (linux || ((macos || windows) && ui2_custom_rendering ?)) && !ui2_headless ? && !ui2_document_library ? {
	import gg
	import math
	import os
	import os.font
	import sync
	import ui2.thirdparty.vglyph

	#flag -I @VMODROOT/ui
	#include "text_fontconfig.h"
	fn C.ui2_font_family(path &char) &char
	fn C.free(voidptr)

	enum TextMeasureMode { available min_content max_content }

	// -1 means unspecified/unbounded; zero is a real constraint. Known width
	// takes precedence and asks for height at that exact logical width. Intrinsic
	// modes describe available space, never a substitute for hard constraints.
	struct TextMeasureRequest {
		known_width f64 = -1
		known_height f64 = -1
		available_width f64 = -1
		mode TextMeasureMode
		// -1 keeps the style's label limit (at least one); zero is unlimited.
		max_lines int = -1
		wrap_long_words bool
	}

	struct TextMeasurement {
		size LayoutSize
		baseline f64
	}

	struct ShapedLine {
		text string
		start int
		end int
		x f64
		y f64
		width f64
		height f64
	}

	struct ShapedText {
		text string
		size LayoutSize
		baseline f64
		lines []ShapedLine
		truncated bool
		layout vglyph.Layout
	}

	@[heap]
	struct TextEngine {
	mut:
		context &vglyph.Context = unsafe { nil }
		scale f32 = 1
		regular string
		bold string
		index map[string]string
		indexed bool
		families map[string]string
		fallback_families []string
		font_generation int = -1
		shape_cache map[string]ShapedText
		shape_builds u64
		shape_hits u64
		environment_version u64
	}

	// Fontconfig application-font registration is process-wide in vglyph. Guard
	// it, including CPU measurements, and register each file once; GPU resources
	// and shaping contexts remain per window. No worker touches a window context.
	__global g_text_font_mutex = sync.new_mutex()
	__global g_text_registered_fonts = map[string]string{}
	__global g_text_font_generation = 0
	__global g_cpu_text_engine = &TextEngine(unsafe { nil })

	fn new_text_engine(scale f32) !&TextEngine {
		g_text_font_mutex.lock()
		defer { g_text_font_mutex.unlock() }
		return new_text_engine_locked(scale)
	}

	fn new_text_engine_locked(scale f32) !&TextEngine {
		regular, bold := font_paths()
		mut engine := &TextEngine{
			context: vglyph.new_context_with_config(scale, vglyph.ContextConfig{
				round_glyph_positions: false
				max_text_bytes: 0
			})!
			scale: if scale > 0 { scale } else { f32(1) }
			regular: regular
			bold: if bold.len > 0 { bold } else { regular }
		}
		// Register bundled variants/fallbacks before the first layout, so a CPU
		// measurement sees exactly the same font set as a later drawing context.
		mut paths := []string{}
		for dir in font_bundle_dirs() {
			for path in os.walk_ext(dir, '.ttf') { paths << path }
			for path in os.walk_ext(dir, '.otf') { paths << path }
		}
		paths << [regular, bold]
		fallback_paths := font_symbol_paths()
		paths << fallback_paths
		for path in paths {
			if path.len > 0 {
				engine.register_font(path) or {
					engine.context.free()
					return err
				}
			}
		}
		mut emoji_families := []string{}
		for path in fallback_paths {
			family := engine.families[path] or { continue }
			is_emoji := family.to_lower().contains('emoji') || family in font_color_emoji_families()
			// Pango 1.50/Fontconfig can reorder ordinary digits to an emoji face
			// when that face appears in the normal family list. Emoji runs use
			// their own generic-family preference below instead.
			if !is_emoji && family !in engine.fallback_families { engine.fallback_families << family }
			if path == os.getenv('UI2_FONT_SYMBOLS') || is_emoji {
				if family !in emoji_families { emoji_families << family }
			}
		}
		// Pango uses the generic "emoji" family for emoji runs, bypassing the
		// ordinary family list. Preserve the same explicit/bundled preference
		// there, using a substitution owned by this context's font map.
		engine.context.set_emoji_families(emoji_families) or {
			engine.context.free()
			return err
		}
		return engine
	}

	fn (mut engine TextEngine) free() {
		if engine.context == unsafe { nil } { return }
		g_text_font_mutex.lock()
		defer { g_text_font_mutex.unlock() }
		engine.shape_cache.clear()
		engine.context.free()
		engine.context = unsafe { nil }
		engine.families.clear()
	}

	// Called under g_text_font_mutex. Font family names come from the file's
	// metadata rather than its filename (RobotoMono != "Roboto Mono").
	fn (mut engine TextEngine) register_font(path string) !string {
		if family := engine.families[path] { return family }
		if family := g_text_registered_fonts[path] {
			engine.families[path] = family
			return family
		}
		family_ptr := C.ui2_font_family(&char(path.str))
		if family_ptr == unsafe { nil } { return error('cannot read text font `${path}`') }
		family := unsafe { cstring_to_vstring(family_ptr) }
		unsafe { C.free(family_ptr) }
		engine.context.add_font_file(path)!
		engine.families[path] = family
		g_text_registered_fonts[path] = family
		g_text_font_generation++
		return family
	}

	fn (mut engine TextEngine) font_name(style TextStyle) !string {
		mut path := ''
		if style.font_family.len > 0 {
			if os.is_file(style.font_family) {
				path = style.font_family
			} else {
				if !engine.indexed {
					mut dirs := font_bundle_dirs()
					dirs << font_system_dirs()
					engine.index = font_index(dirs)
					engine.indexed = true
				}
				path = font_lookup(engine.index, style.font_family, text_style_weight(style) >= 600, style.italic)
				if path.len == 0 { path = font_lookup(engine.index, style.font_family, false, false) }
				if path.len == 0 && font_is_mono_family(style.font_family) {
					path = font_mono_path(engine.index, style.font_family, text_style_weight(style) >= 600, style.italic)
				}
				if path.len == 0 {
					// Let Fontconfig resolve aliases unknown to our file index, but
					// retain the legacy text face before symbol-only fallbacks when
					// the requested family is unavailable.
					regular_family := if engine.regular.len > 0 {
						engine.register_font(engine.regular)!
					} else { 'sans-serif' }
					return engine.with_fallback_families('${style.font_family}, ${regular_family}')
				}
			}
		} else {
			path = if text_style_weight(style) >= 600 { engine.bold } else { engine.regular }
			if style.italic {
				variant := font.get_path_variant(path, .italic)
				if os.is_file(variant) { path = variant }
			}
		}
		family := if path.len == 0 { 'sans-serif' } else { engine.register_font(path)! }
		return engine.with_fallback_families(family)
	}

	fn (engine &TextEngine) with_fallback_families(primary string) string {
		mut families := [primary]
		for family in engine.fallback_families {
			if family !in families { families << family }
		}
		// Terminate Pango's family list explicitly: otherwise a final number
		// or style word (for example “Noto Sans Symbols 2”) is parsed as size/style.
		return families.join(', ') + ','
	}

	fn (mut engine TextEngine) shape(text string, style TextStyle, max_width f64,
		max_lines int, ellipsize bool) !ShapedText {
		g_text_font_mutex.lock()
		defer { g_text_font_mutex.unlock() }
		return engine.shape_locked(text, style, max_width, max_lines, ellipsize, false)
	}

	fn (mut engine TextEngine) shape_area(text string, style TextStyle, max_width f64) !ShapedText {
		g_text_font_mutex.lock()
		defer { g_text_font_mutex.unlock() }
		return engine.shape_locked(text, style, max_width, 0, false, true)
	}

	fn (mut engine TextEngine) shape_locked(text string, style TextStyle, max_width f64,
		max_lines int, ellipsize bool, word_char bool) !ShapedText {
		return engine.shape_runs_locked(text, []TextRun{}, style, max_width, max_lines, ellipsize, word_char)
	}

	fn (mut engine TextEngine) shape_runs(runs []TextRun, style TextStyle, max_width f64,
		max_lines int, ellipsize bool) !ShapedText {
		g_text_font_mutex.lock()
		defer { g_text_font_mutex.unlock() }
		return engine.shape_runs_locked(text_runs_content(runs), runs, style, max_width, max_lines, ellipsize, false)
	}

	fn (mut engine TextEngine) glyph_style(style TextStyle) !vglyph.TextStyle {
		layout_validate_text_measurement(style, -1)!
		return vglyph.TextStyle{
			font_name: engine.font_name(style)!
			size: f32(style.size)
			weight: text_style_weight(style)
			typeface: if style.italic { .italic } else { .regular }
			color: hex_color(style.color)
			underline: style.underline
			strikethrough: style.strikethrough
			letter_spacing: f32(style.letter_spacing)
			rise: f32(style.baseline_offset)
			features: if style.tabular_figures { &vglyph.FontFeatures{opentype_features: [vglyph.FontFeature{tag: 'tnum', value: 1}]} } else { unsafe { nil } }
		}
	}

	fn (mut engine TextEngine) layout_runs(text string, runs []TextRun, cfg vglyph.TextConfig) !vglyph.Layout {
		if runs.len == 0 { return engine.context.layout_text(text, cfg) }
		mut glyph_runs := []vglyph.StyleRun{}
		for run in runs { glyph_runs << vglyph.StyleRun{text: run.text, style: engine.glyph_style(run.style)!} }
		return engine.context.layout_rich_text(vglyph.RichText{runs: glyph_runs}, cfg)
	}

	fn text_shape_style(style TextStyle) TextStyle {
		return TextStyle{ ...style, font_family: style.font_family.bytes().hex(), vertical_align: style.vertical_align.bytes().hex(), link: '', shadow: false, outline: false, color: 0, background_color: 0 }
	}

	fn (mut engine TextEngine) shape_cache_key(text string, runs []TextRun, style TextStyle, width f64, lines int, ellipsize bool, word_char bool) string {
		metrics := runs.map(TextRun{ text: it.text.bytes().hex(), style: text_shape_style(it.style) })
		return '${text.bytes().hex()}|${metrics}|${text_shape_style(style)}|${width}|${lines}|${ellipsize}|${word_char}|${engine.scale}|${g_text_font_generation}|${engine.environment_version}'
	}

	fn (mut engine TextEngine) invalidate_environment() {
		engine.shape_cache.clear()
		engine.environment_version++
		if engine.context != unsafe { nil } { engine.context.fonts_changed() }
	}

	fn (mut engine TextEngine) shape_runs_locked(text string, runs []TextRun, style TextStyle, max_width f64,
		max_lines int, ellipsize bool, word_char bool) !ShapedText {
		if engine.context == unsafe { nil } { return error('text context is closed') }
		if engine.font_generation != g_text_font_generation { engine.shape_cache.clear() }
		key := engine.shape_cache_key(text, runs, style, max_width, max_lines, ellipsize, word_char)
		mut shaped := ShapedText{}
		if cached := engine.shape_cache[key] {
			engine.shape_hits++
			shaped = cached
		} else {
			// Stable foreground attributes preserve rich-run boundaries while
			// excluding changing paint colors from shaping dependencies.
			mut canonical := []TextRun{cap: runs.len}
			for i, run in runs {
				canonical << TextRun{ text: run.text, style: TextStyle{ ...run.style, color: u32(i + 1), background_color: 0 } }
			}
			shaped = engine.build_shape_locked(text, canonical, TextStyle{ ...style, color: 0, background_color: 0 }, max_width, max_lines, ellipsize, word_char)!
			if engine.shape_cache.len >= 128 { engine.shape_cache.clear() }
			// Resolving a new font may advance the process font generation.
			engine.shape_cache[engine.shape_cache_key(text, runs, style, max_width, max_lines, ellipsize, word_char)] = shaped
		}
		mut items := shaped.layout.items.clone()
		for i, item in items {
			mut color := style.color
			if runs.len > 0 {
				// Pango attributes carry the canonical run owner even for a
				// synthetic tail ellipsis whose byte index reaches a hidden run.
				owner := int((u32(item.color.r) << 16) | (u32(item.color.g) << 8) | u32(item.color.b)) - 1
				if owner >= 0 && owner < runs.len { color = runs[owner].style.color }
			}
			items[i] = vglyph.Item{ ...item, color: hex_color(color) }
		}
		return ShapedText{ ...shaped, layout: vglyph.Layout{ ...shaped.layout, items: items } }
	}

	fn (mut engine TextEngine) build_shape_locked(source_text string, runs []TextRun, style TextStyle, max_width f64,
		max_lines int, ellipsize bool, word_char bool) !ShapedText {
		layout_validate_text_measurement(style, max_width)!
		if engine.context == unsafe { nil } { return error('text context is closed') }
		if max_lines < 0 { return error('text line limit must be nonnegative') }
		// Editors explicitly free their old buffer on replacement. Own the source
		// once per build so returned shapes, cached hits and vglyph's retained
		// text/debug views all survive that replacement without copying on hits.
		owned_text := source_text.clone()
		engine.shape_builds++
		line_height := text_style_line_height(style)
		cfg := vglyph.TextConfig{
			style: engine.glyph_style(style)!
			block: vglyph.BlockStyle{
				width: f32(max_width)
				wrap: if word_char { .word_char } else { .word }
				line_height: f32(line_height)
				strict_line_height: style.line_height > 0 || style.line_height_factor > 0
				insert_hyphens: false
				max_lines: max_lines
				ellipsize: ellipsize
				align: match style.align { .center { .center } .right { .right } else { .left } }
			}
		}
		if engine.font_generation != g_text_font_generation {
			engine.context.fonts_changed()
			engine.font_generation = g_text_font_generation
		}
		// Pango height zero can discard later paragraphs without inserting an
		// ellipsis when the first paragraph fits. Inspect its natural lines in
		// that case so the omitted paragraphs get an explicit visible marker.
		initial_cfg := if ellipsize && max_lines == 1 && (owned_text.contains('\n') || owned_text.contains('\r')) {
			vglyph.TextConfig{...cfg, block: vglyph.BlockStyle{...cfg.block, ellipsize: false, max_lines: 0}}
		} else { cfg }
		mut layout := engine.layout_runs(owned_text, runs, initial_cfg)!
		if ellipsize && max_lines > 0 && layout.lines.len > max_lines {
			// Pango's negative height limits each paragraph separately. Keep its
			// shaped prefix and shape the remaining source as one ellipsized line
			// to implement UI2's limit across the whole label, including newlines.
			last_line := layout.lines[max_lines - 1]
			mut tail_end := math.min(owned_text.len, last_line.start_index + last_line.length)
			for tail_end > last_line.start_index && owned_text[tail_end - 1] in [u8(10), u8(13)] { tail_end-- }
			tail_runs := text_runs_slice(runs, last_line.start_index, tail_end, true)
			tail := engine.layout_runs(owned_text[last_line.start_index..tail_end] + '…', tail_runs, vglyph.TextConfig{
				...cfg
				block: vglyph.BlockStyle{...cfg.block, max_lines: 1}
			})!
			layout = join_text_layout_tail(layout, tail, max_lines - 1, tail_end - last_line.start_index)
		}
		mut lines := []ShapedLine{cap: layout.lines.len}
		// Build offsets once: a large editor must not scan its entire prefix for
		// every visual line merely to translate byte indices back to runes.
		mut rune_offsets := []int{len: owned_text.len + 1}
		mut rune_count := 0
		for i, value in owned_text {
			rune_offsets[i] = rune_count
			if value & 0xc0 != 0x80 { rune_count++ }
		}
		rune_offsets[owned_text.len] = rune_count
		for line in layout.lines {
			start := math.min(owned_text.len, line.start_index)
			mut end := math.min(owned_text.len, start + line.length)
			for end > start && owned_text[end - 1] in [u8(10), u8(13)] { end-- }
			lines << ShapedLine{
				text: owned_text[start..end]
				start: rune_offsets[start]
				end: rune_offsets[end]
				x: line.rect.x
				y: line.rect.y
				width: line.rect.width
				height: line.rect.height
			}
		}
		if lines.len == 0 { lines << ShapedLine{height: line_height} }
		baseline := if layout.lines.len > 0 { f64(layout.lines[0].baseline) }
			else { f64(engine.context.font_metrics(cfg)!.ascender) }
		// The logical size remains fractional and independent of device pixels.
		return ShapedText{
			text: owned_text
			size: LayoutSize{width: f64(layout.width), height: if owned_text.len == 0 { line_height } else { f64(layout.height) }}
			baseline: baseline
			lines: lines
			truncated: layout.ellipsized
			layout: layout
		}
	}

	fn join_text_layout_tail(full vglyph.Layout, tail vglyph.Layout, line_index int, source_length int) vglyph.Layout {
		boundary := full.lines[line_index].start_index
		y := full.lines[line_index].rect.y
		mut items := full.items.filter(it.start_index < boundary)
		mut glyphs := full.glyphs.clone()
		for item in tail.items {
			items << vglyph.Item{
				...item
				y: item.y + y
				glyph_start: item.glyph_start + full.glyphs.len
				start_index: item.start_index + boundary
			}
		}
		glyphs << tail.glyphs
		mut lines := full.lines[..line_index].clone()
		for line in tail.lines {
			lines << vglyph.Line{
				...line
				start_index: line.start_index + boundary
				length: source_length
				baseline: line.baseline + y
				rect: gg.Rect { ...line.rect, y: line.rect.y + y }
			}
		}
		mut chars := full.char_rects.filter(it.index < boundary)
		for char_rect in tail.char_rects {
			chars << vglyph.CharRect{
				index: char_rect.index + boundary
				rect: gg.Rect { ...char_rect.rect, y: char_rect.rect.y + y }
			}
		}
		mut by_index := map[int]int{}
		for i, char_rect in chars { by_index[char_rect.index] = i }
		mut width := f32(0)
		for line in lines { width = math.max(width, line.rect.width) }
		return vglyph.Layout{
			...full
			items: items
			glyphs: glyphs
			lines: lines
			char_rects: chars
			char_rect_by_index: by_index
			width: width
			height: y + tail.height
			ellipsized: true
		}
	}

	fn text_rune_to_byte(text string, index int) int {
		if index <= 0 { return 0 }
		mut count := 0
		for byte_index, value in text {
			if value & 0xc0 != 0x80 {
				if count == index { return byte_index }
				count++
			}
		}
		return text.len
	}

	fn text_byte_to_rune(text string, index int) int {
		mut count := 0
		for byte_index, value in text {
			if byte_index >= index { break }
			if value & 0xc0 != 0x80 { count++ }
		}
		return count
	}

	fn (shaped ShapedText) cursor(index int) Rect {
		byte_index := text_rune_to_byte(shaped.text, index)
		if cursor := shaped.layout.get_cursor_pos(byte_index) {
			return rect(cursor.x, cursor.y, 1, cursor.height)
		}
		// Keep the editor's rune index; only its geometry snaps to a cluster edge.
		positions := shaped.layout.get_valid_cursor_positions()
		mut previous := 0
		for position in positions { if position > byte_index { break }; previous = position }
		if cursor := shaped.layout.get_cursor_pos(previous) {
			return rect(cursor.x, cursor.y, 1, cursor.height)
		}
		return rect(0, 0, 1, shaped.size.height)
	}

	fn (shaped ShapedText) selection(start int, end int) []Rect {
		mut result := []Rect{}
		for r in shaped.layout.get_selection_rects(text_rune_to_byte(shaped.text, start),
			text_rune_to_byte(shaped.text, end)) {
			result << rect(r.x, r.y, r.width, r.height)
		}
		return result
	}

	fn (shaped ShapedText) hit_test(x f64, y f64) int {
		return text_byte_to_rune(shaped.text, shaped.layout.get_closest_offset(f32(x), f32(y)))
	}

	fn (mut engine TextEngine) measure(text string, style TextStyle, request TextMeasureRequest) !TextMeasurement {
		for value in [request.known_width, request.known_height, request.available_width] {
			if !math.is_finite(value) || (value < 0 && value != -1) {
				return error('text dimensions must be nonnegative or -1')
			}
		}
		if request.max_lines < -1 { return error('text line limit must be nonnegative or -1') }
		width := if request.known_width >= 0 { request.known_width }
			else if request.mode == .max_content { -1.0 }
			else if request.mode == .min_content { 0.0 }
			else { request.available_width }
		// Word wrapping at zero reports the width of the largest unbreakable
		// segment from Pango; it is not the same as constraining the result to zero.
		line_limit := if request.max_lines >= 0 { request.max_lines }
			else { math.max(1, style.lines) }
		g_text_font_mutex.lock()
		shaped := engine.shape_locked(text, style, width,
			if request.mode == .min_content { 0 } else { line_limit },
			request.mode == .available && width >= 0 && line_limit > 0,
			request.wrap_long_words) or {
			g_text_font_mutex.unlock()
			return err
		}
		g_text_font_mutex.unlock()
		mut measured_width := shaped.size.width
		if request.known_width >= 0 { measured_width = request.known_width }
		else if request.mode == .available && request.available_width >= 0 {
			measured_width = math.min(measured_width, request.available_width)
		}
		measured_height := if line_limit > 0 && shaped.lines.len > line_limit {
			last := shaped.lines[line_limit - 1]
			last.y + last.height
		} else { shaped.size.height }
		return TextMeasurement{
			size: LayoutSize{
				width: measured_width
				height: if request.known_height >= 0 { request.known_height }
					else { measured_height }
			}
			baseline: shaped.baseline
		}
	}

	fn layout_measure_vglyph_text(text string, style TextStyle, max_width f64) !LayoutSize {
		return layout_measure_vglyph_request(text, style, TextMeasureRequest{available_width: max_width})
	}

	fn layout_measure_vglyph_editor_text(text string, style TextStyle, max_width f64) !LayoutSize {
		return layout_measure_vglyph_request(text, style, TextMeasureRequest{
			available_width: max_width
			max_lines: 0
			wrap_long_words: true
		})
	}

	fn layout_measure_vglyph_request(text string, style TextStyle, request TextMeasureRequest) !LayoutSize {
		// Lazily create the process-lifetime CPU context. Shaping itself locks the
		// same mutex; release it before measure to avoid recursively taking it.
		g_text_font_mutex.lock()
		if g_cpu_text_engine == unsafe { nil } {
			g_cpu_text_engine = new_text_engine_locked(1) or {
				g_text_font_mutex.unlock()
				return err
			}
		}
		mut engine := g_cpu_text_engine
		g_text_font_mutex.unlock()
		return engine.measure(text, style, request)!.size
	}

	fn layout_measure_vglyph_runs(runs []TextRun, style TextStyle, width f64) !LayoutSize {
		// Initialize the process context through the same public measurement route.
		layout_measure_vglyph_text('', style, width)!
		mut engine := g_cpu_text_engine
		limit := math.max(1, style.lines)
		shaped := engine.shape_runs(runs, style, width, limit, width >= 0)!
		// With unbounded width Pango does not ellipsize; its natural layout
		// still includes every paragraph. Match the ordinary label line budget.
		height := if shaped.lines.len > limit {
			shaped.lines[limit - 1].y + shaped.lines[limit - 1].height
		} else { shaped.size.height }
		return LayoutSize{width: if width >= 0 { math.min(width, shaped.size.width) } else { shaped.size.width }, height: height}
	}

}
