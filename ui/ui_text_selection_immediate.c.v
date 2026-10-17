module ui2

$if (android || ios || linux || macos || windows) && !ui2_headless ? && !ui2_document_library ? {
	pub fn (mut w Window) text_area_set_selection(id string, location int, length int) {
		if id !in w.active_fields || (w.text_kinds[id] or { Kind.screen }) != .text_area {
			return
		}
		value := w.text(id)
		selection := clamped_text_area_selection(value, location, length)
		w.text_area_selections[id] = selection
		mut editor := w.text_editors[id] or { text_editor(value.clone()) }
		start := utf16_offset_to_rune_index(value, selection.location)
		end := utf16_offset_to_rune_index(value, selection.location + selection.length)
		editor.set_selection(start, end)
		w.replace_text_editor(id, editor)
		w.invalidate_custom_paint()
	}

	pub fn (mut w Window) text_area_set_caret(id string, pos int) {
		w.text_area_set_selection(id, pos, 0)
	}

	pub fn (mut w Window) text_area_caret(id string) int {
		if (w.text_kinds[id] or { Kind.screen }) != .text_area {
			return 0
		}
		editor := w.text_editors[id] or { return w.text_area_selection(id).location }
		return rune_index_to_utf16_offset(editor.text, editor.selection.caret)
	}

	pub fn (mut w Window) text_area_selection_length(id string) int {
		if (w.text_kinds[id] or { Kind.screen }) != .text_area {
			return 0
		}
		editor := w.text_editors[id] or { return w.text_area_selection(id).length }
		start, end := editor.selection.ordered()
		return rune_index_to_utf16_offset(editor.text, end) - rune_index_to_utf16_offset(editor.text,
			start)
	}

	// text_area_selection is the selection set for a text area that has no
	// editor yet.
	fn (w &Window) text_area_selection(id string) TextAreaSelectionRange {
		return w.text_area_selections[id] or { TextAreaSelectionRange{} }
	}
}
