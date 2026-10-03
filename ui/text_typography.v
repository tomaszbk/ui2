module ui2

fn text_style_weight(style TextStyle) int {
	return if style.weight > 0 {
		style.weight
	} else if style.bold {
		700
	} else {
		400
	}
}

fn text_style_line_height(style TextStyle) f64 {
	return if style.line_height > 0 {
		style.line_height
	} else if style.line_height_factor > 0 {
		font_em_pixels(style.size) * style.line_height_factor
	} else {
		font_line_height(style.size)
	}
}

fn text_runs_content(runs []TextRun) string {
	mut content := ''
	for run in runs { content += run.text }
	return content
}

// Byte boundaries originate from the shaper, so slices never split UTF-8.
fn text_runs_slice(runs []TextRun, start int, end int, ellipsis bool) []TextRun {
	mut result := []TextRun{}
	mut offset := 0
	mut last := TextStyle{}
	for run in runs {
		run_end := offset + run.text.len
		if offset < end && run_end > start {
			a := if start > offset { start - offset } else { 0 }
			b := if end < run_end { end - offset } else { run.text.len }
			result << TextRun{ text: run.text[a..b], style: run.style }
			last = run.style
		}
		offset = run_end
	}
	if ellipsis && runs.len > 0 {
		result << TextRun{ text: '…', style: if result.len > 0 { last } else { runs[0].style } }
	}
	return result
}
