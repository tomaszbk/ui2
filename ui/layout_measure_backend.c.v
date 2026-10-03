module ui2

// measure_layout_text uses the active backend's metrics when available, with
// vglyph CPU measurement before desktop custom windows open. Android, headless
// and native backends without an adapter retain Fontstash. Sizes remain points.
// Like layout/build, call this on the UI thread while a window is mounted.
pub fn measure_layout_text(text string, style TextStyle, max_width f64) !LayoutSize {
	layout_validate_text_measurement(style, max_width)!
	$if macos && !ui2_custom_rendering ?&& !ui2_headless ? {
		return layout_measure_appkit_text(text, style, max_width)
	} $else $if (linux || ((macos || windows) && ui2_custom_rendering ?)) && !ui2_headless ? {
		return layout_measure_vglyph_text(text, style, max_width)
	} $else $if android && !ui2_headless ? {
		ctx := g_gg_app.ctx
		if !g_gg_app.scheduler.is_closed() && ctx != unsafe { nil } && ctx.font_inited {
			ensure_symbol_fallbacks(ctx)
			return layout_measure_text_lines(text, style, max_width, font_style_line_height(style), fn [ctx, style] (line string) f64 {
				return menu_text_width(ctx, line, style)
			})
		}
	}
	$if !(linux || ((macos || windows) && ui2_custom_rendering ?)) || ui2_headless ? {
		return layout_measure_cpu_text(text, style, max_width)
	}
}

$if ( android || linux || ( ( macos || windows ) && ui2_custom_rendering ?) ) && !ui2_headless ? {
	fn layout_measure_custom_text_area(text string, style TextStyle, max_width f64) !LayoutSize {
		layout_validate_text_measurement(style, max_width)!
		$if !android {
			return layout_measure_vglyph_editor_text(text, style, max_width)
		} $else {
			ctx := g_gg_app.ctx
			if !g_gg_app.scheduler.is_closed() && ctx != unsafe { nil } && ctx.font_inited {
				ensure_symbol_fallbacks(ctx)
				return layout_measure_text_area_lines(text, style, max_width, font_style_line_height(style), fn [ctx, style] (line string) f64 {
					return menu_text_width(ctx, line, style)
				})
			}
			return layout_measure_cpu_fontstash(text, style, max_width, true)
		}
	}
}
