// Keep AppKit imports behind the native backend switch so custom builds do not
// mix AppKit's MRC bridge with Sokol's ARC sources.
module ui2

$if macos && !ui2_custom_rendering ?&& !ui2_headless ? {
	import macos

	fn layout_measure_appkit_text(text string, style TextStyle, max_width f64) !LayoutSize {
		pool := macos.autorelease_pool_new()
		defer { macos.release(pool) }
		font := native_text_style_font(style)
		line_height := macos.msg_f64(font, 'ascender') - macos.msg_f64(font, 'descender') +
			macos.msg_f64(font, 'leading')
		attrs := native_text_attributes(style.color, 0, style.size, style.font_family,
			style.bold, style.italic, style.underline, style.strikethrough, style.vertical_align)
		measured := layout_measure_text_lines(text, style, max_width, line_height, fn [attrs] (line string) f64 {
			attributed := macos.msg_id2(macos.alloc('NSAttributedString'), 'initWithString:attributes:', macos.nsstring(line), attrs)
			size := macos.msg_point(attributed, 'size')
			macos.release(attributed)
			return size.x
		})!
		// NSTextField's cell adds line fragment spacing beyond font ascent and
		// descent. Ask the actual control at the assigned content width, rather
		// than rounding shared logical layout or under-sizing wrapped labels.
		frame := native_rect(0, 0, (if max_width < 0 { measured.width } else { max_width }) + 4, 0)
		field := native_new_label(frame, text, style.color, style.size, style.bold,
			style.italic, style.underline, align_value(style.align), style.lines, .top, false)
		defer { macos.release(field) }
		macos.msg_void1(field, 'setFont:', font)
		height := if style.lines > 1 {
			native_label_content_height(field, frame, style.lines)
		} else {
			macos.msg_point(macos.msg_id(field, 'cell'), 'cellSize').y
		}
		return LayoutSize{ ...measured, height: height }
	}
}
