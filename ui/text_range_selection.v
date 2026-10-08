module ui2

import math

// Pointer selection for read-only text that the caller lays out and paints
// itself, such as a chat transcript drawn on a canvas. UI2's text controls
// keep their own editor selection (TextSelection); this covers the rest:
//
// 1. Each frame, register the lines you paint as SelectableTextLine values,
//    in reading order.
// 2. On pointer events, map the pointer to a caret slot with text_position_at
//    and feed it to a TextRangeSelection (press, drag, release).
// 3. While painting, ask line_columns which runes of a line to highlight, and
//    use the same ranges to build the copied text.
//
// Columns are rune offsets, like TextSelection, so positions stay valid for
// UTF-8 text.

// text_selection_drag_threshold is how far (in logical units) the pointer must move
// after a press before the press becomes a selection drag. Below it the press
// is still a click, so links and buttons drawn over selectable text keep
// working.
pub const text_selection_drag_threshold = 3.0

// multi_click_interval_ms and multi_click_slop bound how quickly and how close
// together successive presses must land to count as a double or triple click.
pub const multi_click_interval_ms = i64(500)
pub const multi_click_slop = 4.0

// TextPosition is a caret slot in multi-block text. `block` is the caller's
// top-level unit (a chat message, a paragraph), `line` is a wrapped line
// inside that block, and `column` is a rune offset inside the line.
pub struct TextPosition {
pub:
	block  int
	line   int
	column int
}

// compare orders positions in reading order: -1 when a comes before b, 1 when
// it comes after, and 0 when they are the same slot.
pub fn (a TextPosition) compare(b TextPosition) int {
	if a.block != b.block {
		return if a.block < b.block { -1 } else { 1 }
	}
	if a.line != b.line {
		return if a.line < b.line { -1 } else { 1 }
	}
	if a.column != b.column {
		return if a.column < b.column { -1 } else { 1 }
	}
	return 0
}

// SelectableTextLine is one painted line of selectable text, in the same
// coordinates as the pointer events.
pub struct SelectableTextLine {
pub:
	block    int
	line     int
	x        f64
	y        f64
	width    f64
	height   f64
	rune_len int
}

// TextRangeSelection is an anchor/caret selection over TextPositions plus the
// press/drag/release state of the pointer that drives it. A press collapses
// the selection at the pointer; the selection only grows once the pointer has
// moved past text_selection_drag_threshold, so a plain click stays a click.
pub struct TextRangeSelection {
pub mut:
	anchor   TextPosition
	caret    TextPosition
	pressed  bool // the pointer is held after a press on selectable text
	dragging bool // the held pointer has moved far enough to select
	press_x  f64
	press_y  f64
}

// ordered returns the selection's start and end in reading order.
pub fn (s TextRangeSelection) ordered() (TextPosition, TextPosition) {
	if s.anchor.compare(s.caret) <= 0 {
		return s.anchor, s.caret
	}
	return s.caret, s.anchor
}

// is_empty reports whether nothing is selected.
pub fn (s TextRangeSelection) is_empty() bool {
	return s.anchor.compare(s.caret) == 0
}

// clear drops the selection and any pointer tracking.
pub fn (mut s TextRangeSelection) clear() {
	s = TextRangeSelection{}
}

// select replaces the selection, for word, line, or programmatic selection.
pub fn (mut s TextRangeSelection) select(anchor TextPosition, caret TextPosition) {
	s.anchor = anchor
	s.caret = caret
}

// press starts tracking a pointer press at pos. With extend (Shift+click) the
// existing anchor is kept and the selection grows to pos right away.
pub fn (mut s TextRangeSelection) press(pos TextPosition, x f64, y f64, extend bool) {
	if !extend {
		s.anchor = pos
	}
	s.caret = pos
	s.pressed = true
	s.dragging = extend
	s.press_x = x
	s.press_y = y
}

// drag moves the caret to pos while the pointer is held. It returns true when
// the selection changed and needs repainting.
pub fn (mut s TextRangeSelection) drag(pos TextPosition, x f64, y f64) bool {
	if !s.pressed {
		return false
	}
	if !s.dragging {
		if math.hypot(x - s.press_x, y - s.press_y) < text_selection_drag_threshold {
			return false
		}
		s.dragging = true
	}
	if s.caret.compare(pos) == 0 {
		return false
	}
	s.caret = pos
	return true
}

// release ends pointer tracking. It returns true when the press turned into a
// selection drag, in which case the caller should not also handle it as a
// click.
pub fn (mut s TextRangeSelection) release() bool {
	dragged := s.dragging
	s.pressed = false
	s.dragging = false
	return dragged
}

// line_columns returns the selected rune columns [from, to) of one line, or
// none when the selection does not reach it. rune_len is the line's length.
// A line strictly inside a multi-line selection is selected whole, even when
// it is empty, so callers can still mark blank lines as selected.
pub fn (s TextRangeSelection) line_columns(block int, line int, rune_len int) ?(int, int) {
	if s.is_empty() {
		return none
	}
	start, end := s.ordered()
	line_start := TextPosition{
		block: block
		line:  line
	}
	line_end := TextPosition{
		block:  block
		line:   line
		column: rune_len
	}
	if end.compare(line_start) <= 0 || start.compare(line_end) > 0 {
		return none
	}
	from := if start.block == block && start.line == line {
		clamp_int(start.column, 0, rune_len)
	} else {
		0
	}
	to := if end.block == block && end.line == line {
		clamp_int(end.column, from, rune_len)
	} else {
		rune_len
	}
	if from == to && (end.block == block && end.line == line) {
		return none
	}
	return from, to
}

// text_line_at returns the index in lines of the line whose row contains y.
// When several lines share that row (side-by-side columns), the one nearest
// to x wins. It returns -1 when no line's row contains y.
pub fn text_line_at(lines []SelectableTextLine, x f64, y f64) int {
	mut best := -1
	mut best_distance := 0.0
	for index, line in lines {
		if y < line.y || y >= line.y + line.height {
			continue
		}
		distance := if x < line.x {
			line.x - x
		} else if x > line.x + line.width {
			x - line.x - line.width
		} else {
			0.0
		}
		if best < 0 || distance < best_distance {
			best = index
			best_distance = distance
		}
	}
	return best
}

// text_position_at maps a pointer to the caret slot it addresses. Over a line,
// column_at converts the offset from the line's left edge into a rune column
// (text_column_at_x does this for simple text); left and right of the line
// clamp to its ends. Between lines the caret goes to the start of the next
// line below the pointer; above the first line it clamps to the start of the
// text and below the last line to its end. lines must be in reading order.
// It returns none when no line is registered.
pub fn text_position_at(lines []SelectableTextLine, x f64, y f64, column_at fn (line SelectableTextLine, offset f64) int) ?TextPosition {
	if lines.len == 0 {
		return none
	}
	index := text_line_at(lines, x, y)
	if index >= 0 {
		line := lines[index]
		column := if x <= line.x {
			0
		} else if x >= line.x + line.width {
			line.rune_len
		} else {
			clamp_int(column_at(line, x - line.x), 0, line.rune_len)
		}
		return TextPosition{
			block:  line.block
			line:   line.line
			column: column
		}
	}
	for line in lines {
		if line.y > y {
			return TextPosition{
				block: line.block
				line:  line.line
			}
		}
	}
	last := lines.last()
	return TextPosition{
		block:  last.block
		line:   last.line
		column: last.rune_len
	}
}

// text_column_at_x returns the caret slot in text closest to offset, the
// distance from the text's left edge. measure returns the drawn width of a
// prefix of text; a binary search keeps this to O(log n) measurements.
pub fn text_column_at_x(text string, offset f64, measure fn (prefix string) f64) int {
	if offset <= 0 || text.len == 0 {
		return 0
	}
	mut boundaries := []int{cap: text.len + 1}
	mut i := 0
	for i < text.len {
		boundaries << i
		i += utf8_char_len(text[i])
	}
	boundaries << text.len
	count := boundaries.len - 1
	mut lo := 0
	mut hi := count
	for lo < hi {
		mid := (lo + hi + 1) / 2
		if measure(text[..boundaries[mid]]) <= offset {
			lo = mid
		} else {
			hi = mid - 1
		}
	}
	if lo >= count {
		return count
	}
	left := if lo == 0 { 0.0 } else { measure(text[..boundaries[lo]]) }
	right := measure(text[..boundaries[lo + 1]])
	return if offset - left < right - offset { lo } else { lo + 1 }
}

// text_word_range returns the rune range [start, end) that a double-click at
// column selects: the surrounding word, the surrounding run of spaces, or a
// single other character. A column at the end of the text selects what
// precedes it.
pub fn text_word_range(text string, column int) (int, int) {
	runes := text.runes()
	if runes.len == 0 {
		return 0, 0
	}
	at := clamp_int(if column >= runes.len { runes.len - 1 } else { column }, 0, runes.len - 1)
	if is_word_rune(runes[at]) {
		mut start := at
		for start > 0 && is_word_rune(runes[start - 1]) {
			start--
		}
		mut end := at + 1
		for end < runes.len && is_word_rune(runes[end]) {
			end++
		}
		return start, end
	}
	if runes[at] == ` ` || runes[at] == `\t` {
		mut start := at
		for start > 0 && (runes[start - 1] == ` ` || runes[start - 1] == `\t`) {
			start--
		}
		mut end := at + 1
		for end < runes.len && (runes[end] == ` ` || runes[end] == `\t`) {
			end++
		}
		return start, end
	}
	return at, at + 1
}

// text_rune_slice returns the runes [from, to) of text, clamped to its length.
pub fn text_rune_slice(text string, from int, to int) string {
	runes := text.runes()
	start := clamp_int(from, 0, runes.len)
	end := clamp_int(to, start, runes.len)
	return runes[start..end].string()
}

// ClickCounter counts successive presses that land close together in space
// and time, for double- and triple-click gestures on custom-drawn content
// that receives only raw pointer events.
pub struct ClickCounter {
pub mut:
	count   int
	last_ms i64
	last_x  f64
	last_y  f64
}

// press records a press at (x, y) and returns its click count: 1 for a
// single click, 2 for a double click, 3 for a triple click. A fourth quick
// press starts over at 1.
pub fn (mut c ClickCounter) press(x f64, y f64, now_ms i64) int {
	quick := c.count > 0 && now_ms - c.last_ms <= multi_click_interval_ms
	near := math.abs(x - c.last_x) <= multi_click_slop && math.abs(y - c.last_y) <= multi_click_slop
	c.count = if quick && near && c.count < 3 { c.count + 1 } else { 1 }
	c.last_ms = now_ms
	c.last_x = x
	c.last_y = y
	return c.count
}
