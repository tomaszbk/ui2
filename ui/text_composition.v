module ui2

// The committed editor remains unchanged while an input method owns preedit.
// Platform replacement ranges address the staged display in UTF-16. A staged
// span replaces one union of committed runes and can contain text outside the
// current marked subrange when an input method replaces only part of preedit.
struct TextComposition {
mut:
	field_id    string
	text        string
	start       int
	end         int
	mark_start  int
	mark_length int
	selection   TextSelection
}

fn utf16_offset_to_rune(text string, offset int) int {
	mut units := 0
	for index, ch in text.runes() {
		width := if ch > 0xffff { 2 } else { 1 }
		if units + width > offset {
			return index
		}
		units += width
	}
	return rune_len(text)
}

fn rune_offset_to_utf16(text string, offset int) int {
	mut units := 0
	for index, ch in text.runes() {
		if index >= offset {
			break
		}
		units += if ch > 0xffff { 2 } else { 1 }
	}
	return units
}

fn (mut composition TextComposition) update(id string, editor TextEditor, value string,
	selection_start int, selection_length int, replacement_start int, replacement_length int) {
	if composition.field_id != id {
		start, end := editor.selection.ordered()
		composition = TextComposition{
			field_id:    id
			start:       start
			end:         end
			text:        editor.text.runes()[start..end].string()
			mark_length: end - start
		}
	}
	composition.replace_display_range(editor, value, selection_start, selection_length,
		replacement_start, replacement_length)
}

// Keep every staged fragment outside the platform's replacement range. Extend
// the committed union when a replacement reaches before or after that span,
// so publishing it later still applies exactly one editor transaction.
fn (mut composition TextComposition) replace_display_range(editor TextEditor, value string,
	selection_start int, selection_length int, replacement_start int, replacement_length int) {
	shown := composition.display(editor).text
	from := if replacement_start >= 0 {
		utf16_offset_to_rune(shown, replacement_start)
	} else {
		composition.start + composition.mark_start
	}
	to := if replacement_start >= 0 {
		utf16_offset_to_rune(shown, replacement_start + replacement_length)
	} else {
		from + composition.mark_length
	}
	span_length := rune_len(composition.text)
	display_end := composition.start + span_length
	delta := span_length - (composition.end - composition.start)
	next_start := if from < composition.start { from } else { composition.start }
	next_end := if to > display_end { composition.end + to - display_end } else { composition.end }
	span := shown.runes()[next_start..next_end + delta].string()
	composition.text = replace_rune_range(span, from - next_start, to - next_start, value)
	composition.start = next_start
	composition.end = next_end
	composition.mark_start = from - next_start
	composition.mark_length = rune_len(value)
	composition.selection = TextSelection{
		anchor: composition.mark_start + utf16_offset_to_rune(value, selection_start)
		caret:  composition.mark_start + utf16_offset_to_rune(value, selection_start + selection_length)
	}
}

fn (composition TextComposition) display(editor TextEditor) TextEditor {
	if composition.field_id.len == 0 {
		return editor
	}
	return TextEditor{
		text:      replace_rune_range(editor.text, composition.start, composition.end, composition.text)
		selection: TextSelection{
			anchor: composition.start + composition.selection.anchor
			caret:  composition.start + composition.selection.caret
		}
	}
}

fn (mut composition TextComposition) commit(mut editor TextEditor, value string,
	replacement_start int, replacement_length int) {
	if composition.field_id.len == 0 {
		if replacement_start >= 0 {
			editor.set_selection(utf16_offset_to_rune(editor.text, replacement_start),
				utf16_offset_to_rune(editor.text, replacement_start + replacement_length))
		}
		editor.insert_text(value)
		return
	}
	composition.replace_display_range(editor, value, rune_offset_to_utf16(value, rune_len(value)),
		0, replacement_start, replacement_length)
	composition.finish(mut editor)
}

// Native unmark publishes the current staged display and selection without
// replacing the marked subrange again or duplicating its surrounding fragments.
fn (mut composition TextComposition) finish(mut editor TextEditor) {
	if composition.field_id.len == 0 { return }
	editor.set_selection(composition.start, composition.end)
	editor.insert_text(composition.text)
	editor.set_selection(composition.start + composition.selection.anchor,
		composition.start + composition.selection.caret)
	composition = TextComposition{}
}
