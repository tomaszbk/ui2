module ui2

// TextAreaSelectionRange is stored in UTF-16 code units to match the native
// NSTextView, UITextView, Win32 and Qt text-control APIs.
pub struct TextAreaSelectionRange {
pub:
	location int
	length   int
}

fn clamped_text_area_selection(text string, location int, length int) TextAreaSelectionRange {
	text_length := text_area_utf16_length(text)
	start := clamp_int(location, 0, text_length)
	return TextAreaSelectionRange{
		location: start
		length: clamp_int(length, 0, text_length - start)
	}
}

fn text_area_utf16_length(text string) int {
	mut length := 0
	for value in text.runes() {
		length += if value > 0xffff { 2 } else { 1 }
	}
	return length
}

fn utf16_offset_to_rune_index(text string, offset int) int {
	target := if offset < 0 { 0 } else { offset }
	mut units := 0
	mut index := 0
	for value in text.runes() {
		next := units + if value > 0xffff { 2 } else { 1 }
		if next > target {
			break
		}
		units = next
		index++
	}
	return index
}

fn rune_index_to_utf16_offset(text string, rune_index int) int {
	target := clamp_int(rune_index, 0, rune_len(text))
	mut units := 0
	for index, value in text.runes() {
		if index >= target {
			break
		}
		units += if value > 0xffff { 2 } else { 1 }
	}
	return units
}

// text_area_replace_selection replaces the UTF-16 selection of text with value
// and returns the new text with the caret after the inserted value.
fn text_area_replace_selection(text string, selection TextAreaSelectionRange, value string) (string, int) {
	range := clamped_text_area_selection(text, selection.location, selection.length)
	runes := text.runes()
	start := utf16_offset_to_rune_index(text, range.location)
	end := utf16_offset_to_rune_index(text, range.location + range.length)
	return runes[..start].string() + value + runes[end..].string(), range.location +
		text_area_utf16_length(value)
}
