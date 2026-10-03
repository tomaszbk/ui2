module vglyph

import log

$if macos {
	import os
}

#include "font_fallback_compat.h"

fn C.vglyph_font_map_set_emoji_families(&C.PangoFcFontMap, &char)

// FontMetricsEntry stores cached font metrics in Pango units.
struct FontMetricsEntry {
	ascent  int // Pango units
	descent int // Pango units
	linegap int // Pango units (0 if not available)
}

// MetricsCache is an LRU cache for font metrics keyed by (face, size) tuple.
struct MetricsCache {
mut:
	entries      map[u64]FontMetricsEntry
	access_order []u64 // Most recent at end
	capacity     int = 256
	// Profile fields - only accessed when -d profile is used
	hits   int
	misses int
}

fn (mut cache MetricsCache) get(key u64) ?FontMetricsEntry {
	if key in cache.entries {
		$if profile ? {
			cache.hits++
		}
		// Move to end (most recent)
		cache.access_order = cache.access_order.filter(it != key)
		cache.access_order << key
		return cache.entries[key]
	}
	$if profile ? {
		cache.misses++
	}
	return none
}

fn (mut cache MetricsCache) put(key u64, entry FontMetricsEntry) {
	if cache.entries.len >= cache.capacity && key !in cache.entries {
		// Evict oldest (first in access_order)
		if cache.access_order.len > 0 {
			evict_key := cache.access_order[0]
			cache.entries.delete(evict_key)
			cache.access_order.delete(0)
		}
	}
	cache.entries[key] = entry
	// Remove existing position if present, add to end
	cache.access_order = cache.access_order.filter(it != key)
	cache.access_order << key
}

$if profile ? {
	pub struct ProfileMetrics {
	pub mut:
		// Frame timing (nanoseconds)
		layout_time_ns    i64
		rasterize_time_ns i64
		upload_time_ns    i64
		draw_time_ns      i64

		// Cache statistics (INST-03)
		glyph_cache_hits       int
		glyph_cache_misses     int
		glyph_cache_evictions  int
		layout_cache_hits      int
		layout_cache_misses    int
		layout_cache_evictions int
		layout_cache_size      int
		// Note: metrics_cache_hits/misses added in Phase 9 when metrics cache implemented

		// Atlas statistics (INST-05)
		atlas_inserts      int
		atlas_grows        int
		atlas_resets       int
		atlas_used_pixels  i64
		atlas_total_pixels i64
		atlas_page_count   int // Number of active atlas pages

		// Memory tracking (INST-04)
		peak_atlas_bytes    i64
		current_atlas_bytes i64
	}

	// glyph_cache_hit_rate returns glyph cache hit rate as percentage (0-100).
	pub fn (m ProfileMetrics) glyph_cache_hit_rate() f32 {
		total := m.glyph_cache_hits + m.glyph_cache_misses
		if total == 0 {
			return 0.0
		}
		return f32(m.glyph_cache_hits) / f32(total) * 100.0
	}

	// layout_cache_hit_rate returns layout cache hit rate as percentage (0-100).
	pub fn (m ProfileMetrics) layout_cache_hit_rate() f32 {
		total := m.layout_cache_hits + m.layout_cache_misses
		if total == 0 {
			return 0.0
		}
		return f32(m.layout_cache_hits) / f32(total) * 100.0
	}

	// atlas_utilization returns atlas utilization as percentage (0-100).
	pub fn (m ProfileMetrics) atlas_utilization() f32 {
		if m.atlas_total_pixels == 0 {
			return 0.0
		}
		return f32(m.atlas_used_pixels) / f32(m.atlas_total_pixels) * 100.0
	}

	// print_summary outputs all profile metrics to stdout.
	pub fn (m ProfileMetrics) print_summary() {
		total_ns := m.layout_time_ns + m.rasterize_time_ns + m.upload_time_ns + m.draw_time_ns
		println('=== VGlyph Profile Metrics ===')
		println('Frame Time Breakdown:')
		println('  Layout:    ${m.layout_time_ns / 1000} us')
		println('  Rasterize: ${m.rasterize_time_ns / 1000} us')
		println('  Upload:    ${m.upload_time_ns / 1000} us')
		println('  Draw:      ${m.draw_time_ns / 1000} us')
		println('  Total:     ${total_ns / 1000} us')
		glyph_total := m.glyph_cache_hits + m.glyph_cache_misses
		layout_total := m.layout_cache_hits + m.layout_cache_misses
		rate1 := m.glyph_cache_hit_rate()
		rate2 := m.layout_cache_hit_rate()
		util := m.atlas_utilization()
		println('Glyph Cache: ${rate1:.1}% (${m.glyph_cache_hits}/${glyph_total}), ' + '${m.glyph_cache_evictions} evictions')
		println('Layout Cache: ${rate2:.1}% (${m.layout_cache_hits}/${layout_total}), ' + '${m.layout_cache_evictions} evictions, size ${m.layout_cache_size}')
		println('Atlas: ${m.atlas_page_count} pages, ${util:.1}% utilized ' +
			'(${m.atlas_used_pixels}/${m.atlas_total_pixels} px)')
		cur_kb := m.current_atlas_bytes / 1024
		peak_kb := m.peak_atlas_bytes / 1024
		println('Memory: ${cur_kb} KB current, ${peak_kb} KB peak')
	}
}

pub struct Context {
	scale_factor   f32 = 1.0
	scale_inv      f32 = 1.0
	max_text_bytes int = max_text_length
mut:
	ft_lib         &C.FT_LibraryRec
	pango_font_map PangoFontMap
	pango_context  PangoContext
	metrics_cache  MetricsCache
	// Font maps cache only a bounded set of fontsets and hold weak font refs.
	// Keep fonts backing baked layouts/metric keys alive until map invalidation.
	pango_fonts map[u64]&C.PangoFont
pub mut:
	// Profile timing fields - only accessed when -d profile is used
	layout_time_ns i64
}

// ContextConfig preserves upstream defaults unless the caller explicitly asks
// for fractional logical metrics or a different text-size budget.
pub struct ContextConfig {
pub:
	round_glyph_positions bool = true
	// Zero disables the byte budget; UTF-8 and NUL validation still apply.
	max_text_bytes int = max_text_length
}

// new_context initializes the global Pango and FreeType environment.
//
// Operations:
// 1. Boots FreeType.
// 2. Creates Pango Font Map (based on FreeType/FontConfig).
// 3. Creates root Pango Context.
//
// Keep context alive for application duration. Passing this to `layout_text`
// shares the font cache.
//
// Returns error if:
// - FreeType library initialization fails
// - Pango font map creation fails
// - Pango context creation fails
pub fn new_context(scale_factor f32) !&Context {
	return new_context_with_config(scale_factor, ContextConfig{})
}

// new_context_with_config supports CPU layout and per-window device scaling.
// Disabling Pango advance rounding keeps logical widths stable across DPI.
pub fn new_context_with_config(scale_factor f32, cfg ContextConfig) !&Context {
	if cfg.max_text_bytes < 0 {
		return error('max_text_bytes must be non-negative')
	}
	// Initialize pointer to null
	ft_lib := &C.FT_LibraryRec(unsafe { nil })
	if C.FT_Init_FreeType(&ft_lib) != 0 {
		log.error('${@FILE_LINE}: failed to initialize FreeType library')
		return error('failed to initialize FreeType library')
	}

	pango_font_map := C.pango_ft2_font_map_new()
	if voidptr(pango_font_map) == unsafe { nil } {
		C.FT_Done_FreeType(ft_lib)
		log.error('${@FILE_LINE}: failed to create Pango font map')
		return error('failed to create Pango font map')
	}
	// Set default resolution to 72 DPI * scale_factor.
	// This ensures that 1 pt == 1 px (logical).
	safe_scale := if scale_factor > 0 { scale_factor } else { 1.0 }
	ft2_font_map := C.PANGO_FT2_FONT_MAP(pango_font_map)
	C.pango_ft2_font_map_set_resolution(ft2_font_map, 72.0 * safe_scale, 72.0 * safe_scale)

	pango_context := C.pango_font_map_create_context(pango_font_map)
	if voidptr(pango_context) == unsafe { nil } {
		C.g_object_unref(pango_font_map)
		C.FT_Done_FreeType(ft_lib)
		log.error('${@FILE_LINE}: failed to create Pango context')
		return error('failed to create Pango context')
	}
	C.pango_context_set_round_glyph_positions(pango_context, cfg.round_glyph_positions)

	// Auto-register system fonts on macOS
	$if macos {
		// Ensure config is loaded
		mut config := C.FcConfigGetCurrent()
		if config == unsafe { nil } {
			config = C.FcInitLoadConfigAndFonts()
		}
		if config != unsafe { nil } {
			C.FcConfigAppFontAddDir(config, c'/System/Library/Fonts')
			C.FcConfigAppFontAddDir(config, c'/Library/Fonts')
			// User fonts?
			home := os.getenv('HOME')
			if home != '' {
				path := '${home}/Library/Fonts'
				C.FcConfigAppFontAddDir(config, &char(path.str))
			}
			// Trigger update
			fc_font_map := C.PANGO_FC_FONT_MAP(pango_font_map)
			C.pango_fc_font_map_config_changed(fc_font_map)
		}
	}

	return &Context{
		ft_lib:         ft_lib
		pango_font_map: PangoFontMap{
			ptr: pango_font_map
		}
		pango_context:  PangoContext{
			ptr: pango_context
		}
		scale_factor:   safe_scale
		scale_inv:      1.0 / safe_scale
		max_text_bytes: cfg.max_text_bytes
	}
}

// free releases Pango context, font map, and FreeType library resources.
pub fn (mut ctx Context) free() {
	ctx.release_fonts()
	ctx.pango_context.free()
	ctx.pango_font_map.free()

	if voidptr(ctx.ft_lib) != unsafe { nil } {
		C.FT_Done_FreeType(ctx.ft_lib)
		ctx.ft_lib = unsafe { nil }
	}
	ctx.metrics_cache.entries.clear()
	ctx.metrics_cache.access_order.clear()
}

// add_font_file loads a font file from the given path to the Pango context.
// Uses FontConfig to register application font.
//
// Returns error if:
// - FontConfig initialization fails
// - FcConfigAppFontAddFile fails (invalid font file format)
pub fn (mut ctx Context) add_font_file(path string) ! {
	// Retrieve current FontConfig configuration. Pango uses this by default.
	// Explicit initialization ensures safety when modifying.
	mut config := C.FcConfigGetCurrent()
	if config == unsafe { nil } {
		// Fallback: Initialize config if not currently available.
		config = C.FcInitLoadConfigAndFonts()
		if config == unsafe { nil } {
			return error('fontconfig initialization failed at ${@FILE}:${@LINE}')
		}
	}

	res := C.FcConfigAppFontAddFile(config, &char(path.str))
	if res != 1 {
		return error('FcConfigAppFontAddFile() failed for "${path}" at ${@FILE}:${@LINE}')
	}
	ctx.fonts_changed()
}

// fonts_changed synchronizes an existing context after another context adds an
// application font to process-wide Fontconfig state.
pub fn (mut ctx Context) fonts_changed() {
	if ctx.pango_font_map.is_nil() { return }
	ctx.release_fonts()
	fc_font_map := C.PANGO_FC_FONT_MAP(ctx.pango_font_map.ptr)
	C.pango_fc_font_map_config_changed(fc_font_map)
	ctx.metrics_cache.entries.clear()
	ctx.metrics_cache.access_order.clear()
}

// set_emoji_families opts into application fallback precedence for emoji runs,
// including ZWJ sequences and variation selectors. Preferences affect only this
// context's font map, and may select outline fonts for a legacy text profile.
// Call before shaping; previously returned layouts borrow that map's faces.
// An empty list restores normal Pango/Fontconfig emoji fallback.
pub fn (mut ctx Context) set_emoji_families(families []string) ! {
	if ctx.pango_font_map.is_nil() {
		return error('text context is closed')
	}
	for family in families {
		validate_layout_text_input(family, 0, @FN)!
		if family.trim_space().len == 0 || family.contains(',') {
			return error('emoji family must be a nonempty family name without commas')
		}
	}
	joined := families.join(',')
	ctx.release_fonts()
	C.vglyph_font_map_set_emoji_families(C.PANGO_FC_FONT_MAP(ctx.pango_font_map.ptr),
		&char(joined.str))
	ctx.metrics_cache.entries.clear()
	ctx.metrics_cache.access_order.clear()
}

// retain_font makes the FT_Face borrowed by a baked layout and the face identity
// in metric/glyph cache keys independent of Pango's fontset-cache eviction.
fn (mut ctx Context) retain_font(font &C.PangoFont) {
	if font == unsafe { nil } { return }
	key := u64(voidptr(font))
	if key in ctx.pango_fonts { return }
	C.g_object_ref(font)
	ctx.pango_fonts[key] = font
}

fn (mut ctx Context) release_fonts() {
	for _, font in ctx.pango_fonts {
		C.g_object_unref(font)
	}
	ctx.pango_fonts.clear()
}

// font_height returns the total visual height (ascent + descent) of the font
// described by cfg.
//
// Returns error if:
// - font description creation fails (invalid font name)
// - font loading fails (font not found)
// - FreeType face unavailable from Pango font
// - font metrics unavailable
pub fn (mut ctx Context) font_height(cfg TextConfig) !f32 {
	mut desc := ctx.create_font_description(cfg.style)
	if desc.is_nil() {
		return error('failed to create Pango font description at ${@FILE}:${@LINE}')
	}
	defer { desc.free() }

	// Load font to get FT_Face for cache key
	mut font := PangoFont{
		ptr: C.pango_context_load_font(ctx.pango_context.ptr, desc.ptr)
	}
	if font.is_nil() {
		return error('failed to load Pango font at ${@FILE}:${@LINE}')
	}
	defer { font.free() }
	ctx.retain_font(font.ptr)

	face := C.pango_ft2_font_get_face(font.ptr)
	if face == unsafe { nil } {
		return error('FreeType face unavailable from Pango font at ${@FILE}:${@LINE}')
	}
	size_units := C.pango_font_description_get_size(desc.ptr)
	cache_key := u64(voidptr(face)) ^ (u64(size_units) << 32)

	// Check cache
	if entry := ctx.metrics_cache.get(cache_key) {
		return (f32(entry.ascent + entry.descent) / f32(pango_scale)) / ctx.scale_factor
	}

	// Cache miss: fetch from Pango
	language := C.pango_language_get_default()
	mut metrics := PangoFontMetrics{
		ptr: C.pango_font_get_metrics(font.ptr, language)
	}
	if metrics.is_nil() {
		return error('failed to get Pango font metrics at ${@FILE}:${@LINE}')
	}
	defer { metrics.free() }

	ascent := C.pango_font_metrics_get_ascent(metrics.ptr)
	descent := C.pango_font_metrics_get_descent(metrics.ptr)

	// Store in cache
	ctx.metrics_cache.put(cache_key, FontMetricsEntry{
		ascent:  ascent
		descent: descent
		linegap: 0
	})

	// descent is positive distance from baseline down even though it's "down"
	return (f32(ascent + descent) / f32(pango_scale)) / ctx.scale_factor
}

// font_metrics returns detailed metrics for the font, including ascender, descender,
// and line gap. All values are in pixels.
//
// Returns error if:
// - font description creation fails (invalid font name)
// - font loading fails (font not found)
// - FreeType face unavailable from Pango font
// - font metrics unavailable
pub fn (mut ctx Context) font_metrics(cfg TextConfig) !TextMetrics {
	mut desc := ctx.create_font_description(cfg.style)
	if desc.is_nil() {
		return error('failed to create Pango font description at ${@FILE}:${@LINE}')
	}
	defer { desc.free() }

	// Load font to get FT_Face for cache key
	mut font := PangoFont{
		ptr: C.pango_context_load_font(ctx.pango_context.ptr, desc.ptr)
	}
	if font.is_nil() {
		return error('failed to load Pango font at ${@FILE}:${@LINE}')
	}
	defer { font.free() }
	ctx.retain_font(font.ptr)

	face := C.pango_ft2_font_get_face(font.ptr)
	if face == unsafe { nil } {
		return error('FreeType face unavailable from Pango font at ${@FILE}:${@LINE}')
	}
	size_units := C.pango_font_description_get_size(desc.ptr)
	cache_key := u64(voidptr(face)) ^ (u64(size_units) << 32)

	scale := f32(pango_scale) * ctx.scale_factor

	// Check cache
	if entry := ctx.metrics_cache.get(cache_key) {
		ascender_px := f32(entry.ascent) / scale
		descender_px := f32(entry.descent) / scale
		return TextMetrics{
			ascender:  ascender_px
			descender: descender_px
			height:    ascender_px + descender_px
			line_gap:  f32(entry.linegap) / scale
		}
	}

	// Cache miss: fetch from Pango
	language := C.pango_language_get_default()
	mut metrics := PangoFontMetrics{
		ptr: C.pango_font_get_metrics(font.ptr, language)
	}
	if metrics.is_nil() {
		return error('failed to get Pango font metrics at ${@FILE}:${@LINE}')
	}
	defer { metrics.free() }

	ascent := C.pango_font_metrics_get_ascent(metrics.ptr)
	descent := C.pango_font_metrics_get_descent(metrics.ptr)

	// Store in cache
	ctx.metrics_cache.put(cache_key, FontMetricsEntry{
		ascent:  ascent
		descent: descent
		linegap: 0
	})

	ascender_px := f32(ascent) / scale
	descender_px := f32(descent) / scale

	return TextMetrics{
		ascender:  ascender_px
		descender: descender_px
		height:    ascender_px + descender_px
		line_gap:  0 // Standard Pango metrics don't typically include line gap separately
	}
}

// resolve_font_name returns the actual font family name that Pango resolves
// for the given font description string. Useful for debugging system font loading.
//
// Returns error if:
// - font description string is invalid
// - font loading fails (font not found)
// - FreeType face unavailable from Pango font
pub fn (mut ctx Context) resolve_font_name(font_desc_str string) !string {
	mut desc := PangoFontDescription{
		ptr: C.pango_font_description_from_string(font_desc_str.str)
	}
	if desc.is_nil() {
		return error('invalid font description "${font_desc_str}" at ${@FILE}:${@LINE}')
	}
	defer { desc.free() }

	// Resolve aliases
	fam_ptr := C.vglyph_pango_font_description_get_family_borrowed(desc.ptr)
	fam := if fam_ptr != unsafe { nil } { unsafe { cstring_to_vstring(fam_ptr) } } else { '' }
	resolved_fam := resolve_family_alias(fam)
	C.pango_font_description_set_family(desc.ptr, resolved_fam.str)

	mut font := PangoFont{
		ptr: C.pango_context_load_font(ctx.pango_context.ptr, desc.ptr)
	}
	if font.is_nil() {
		return error('could not load font "${font_desc_str}" at ${@FILE}:${@LINE}')
	}
	defer { font.free() }

	// Get the FT_Face from the Pango font (specific to pangoft2 backend)
	face := C.pango_ft2_font_get_face(font.ptr)
	if face == unsafe { nil } {
		return error('could not get FT_Face for "${font_desc_str}" at ${@FILE}:${@LINE}')
	}

	return unsafe { cstring_to_vstring(face.family_name) }
}

// resolve_font_alias resolves font name aliases and appends platform fallbacks.
pub fn resolve_font_alias(name string) string {
	// Parse the font description string into a Pango object.
	// This safely handles complex strings like "Sans Bold 17px" without us resolving it manually.
	mut desc := PangoFontDescription{
		ptr: C.pango_font_description_from_string(name.str)
	}
	if desc.is_nil() {
		log.error('${@FILE_LINE}: failed to create Pango font description')
		return name
	}
	defer { desc.free() }

	// Get the family name (comma separated list)
	fam_ptr := C.vglyph_pango_font_description_get_family_borrowed(desc.ptr)
	fam := if fam_ptr != unsafe { nil } { unsafe { cstring_to_vstring(fam_ptr) } } else { '' }

	// Apply aliases
	resolved_fam := resolve_family_alias(fam)

	// Set the modified family list back to the description
	C.pango_font_description_set_family(desc.ptr, resolved_fam.str)

	// Serialize description back to string (Pango handles formatting: "Family List Size Style")
	// Note: Pango might strip info; prefer using `desc` directly in other functions.
	new_str_ptr := C.pango_font_description_to_string(desc.ptr)
	if new_str_ptr == unsafe { nil } {
		log.error('${@FILE_LINE}: failed to serialize Pango font description')
		return name // Should not happen
	}
	final_name := unsafe { cstring_to_vstring(new_str_ptr) }
	C.g_free(new_str_ptr) // Free the string allocated by Pango

	return final_name
}

fn resolve_family_alias(fam string) string {
	aliases := $if macos {
		['SF Pro Display', 'System Font']
	} $else $if windows {
		['Segoe UI']
	} $else {
		// On Linux/BSD, trust FontConfig for aliases (e.g. Sans -> Noto Sans).
		// Append 'Sans' for sans-serif fallback if requested font missing.
		['Sans']
	}
	mut new_fam := fam
	for alias in aliases {
		if new_fam.len > 0 {
			new_fam += ', '
		}
		new_fam += alias
	}
	return new_fam
}

// create_font_description helper function to create and configure a PangoFontDescription
// based on the provided TextStyle. It handles font name parsing, alias resolution,
// and variable font axes.
// Caller is responsible for freeing the returned description.
pub fn (mut ctx Context) create_font_description(style TextStyle) PangoFontDescription {
	desc_ptr := C.pango_font_description_from_string(style.font_name.str)
	if desc_ptr == unsafe { nil } {
		return PangoFontDescription{
			ptr: unsafe { nil }
		}
	}
	desc := PangoFontDescription{
		ptr: desc_ptr
	}

	// Resolve and set family aliases
	fam_ptr := C.vglyph_pango_font_description_get_family_borrowed(desc.ptr)
	fam := if fam_ptr != unsafe { nil } { unsafe { cstring_to_vstring(fam_ptr) } } else { '' }
	resolved_fam := resolve_family_alias(fam)
	C.pango_font_description_set_family(desc.ptr, resolved_fam.str)

	// Apply typeface (bold/italic override)
	apply_typeface(desc.ptr, style.typeface)

	// Apply variable font axes
	if unsafe { style.features != nil } && style.features.variation_axes.len > 0 {
		mut axes_str := ''
		mut first := true
		for a in style.features.variation_axes {
			if !first {
				axes_str += ','
			}
			axes_str += '${a.tag}=${a.value}'
			first = false
		}
		C.pango_font_description_set_variations(desc.ptr, &char(axes_str.str))
	}

	// Apply Explicit Size (overrides size in font_name)
	if style.size > 0 {
		// pango_font_description_set_size takes Pango units (1/1024 of a point)
		// We cast to int because pango_scale is 1024 (integer).
		C.pango_font_description_set_size(desc.ptr, int(style.size * pango_scale))
	}

	return desc
}

// apply_typeface sets weight/style on a font description based on Typeface enum.
fn apply_typeface(desc &C.PangoFontDescription, typeface Typeface) {
	match typeface {
		.regular {}
		.bold {
			C.pango_font_description_set_weight(desc, .pango_weight_bold)
		}
		.italic {
			C.pango_font_description_set_style(desc, .pango_style_italic)
		}
		.bold_italic {
			C.pango_font_description_set_weight(desc, .pango_weight_bold)
			C.pango_font_description_set_style(desc, .pango_style_italic)
		}
	}
}
