module ui2

$if (android || ios || linux || macos || windows) && !ui2_headless ?&& !ui2_document_library ? {
	pub fn (mut w Window) text_area_set_selection(id string, location int, length int) {
		if id !in g_active_fields || (g_text_kinds[id] or { Kind.screen }) != .text_area {
			return
		}
		value := w.text(id)
		selection := clamped_text_area_selection(value, location, length)
		record_portable_text_area_selection(id, selection)
		mut editor := g_text_editors[id] or { text_editor(value.clone()) }
		start := utf16_offset_to_rune_index(value, selection.location)
		end := utf16_offset_to_rune_index(value, selection.location + selection.length)
		editor.set_selection(start, end)
		replace_text_editor(id, editor)
		w.invalidate_custom_paint()
	}

	pub fn (mut w Window) text_area_set_caret(id string, pos int) {
		w.text_area_set_selection(id, pos, 0)
	}

	pub fn (mut w Window) text_area_caret(id string) int {
		if (g_text_kinds[id] or { Kind.screen }) != .text_area {
			return 0
		}
		editor := g_text_editors[id] or { return portable_text_area_selection(id).location }
		return rune_index_to_utf16_offset(editor.text, editor.selection.caret)
	}

	pub fn (mut w Window) text_area_selection_length(id string) int {
		if (g_text_kinds[id] or { Kind.screen }) != .text_area {
			return 0
		}
		editor := g_text_editors[id] or { return portable_text_area_selection(id).length }
		start, end := editor.selection.ordered()
		return rune_index_to_utf16_offset(editor.text, end) - rune_index_to_utf16_offset(editor.text,
			start)
	}
}
