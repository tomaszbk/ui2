module ui2

$if windows && !ui2_custom_rendering ? && !ui2_headless ? && !ui2_document_library ? {
	pub fn (mut w Window) text_area_set_selection(id string, location int, length int) {
		selection := clamped_text_area_selection(w.text(id), location, length)
		w.text_area_selections[id] = selection
		hwnd := w.windows_text_area_handle(id) or { return }
		windows_native_set_selection(hwnd, selection)
	}

	pub fn (mut w Window) text_area_set_caret(id string, pos int) {
		w.text_area_set_selection(id, pos, 0)
	}

	pub fn (mut w Window) text_area_caret(id string) int {
		hwnd := w.windows_text_area_handle(id) or { return (w.text_area_selections[id] or { TextAreaSelectionRange{} }).location }
		selection := windows_native_get_selection(hwnd)
		w.text_area_selections[id] = selection
		return selection.location
	}

	pub fn (mut w Window) text_area_selection_length(id string) int {
		hwnd := w.windows_text_area_handle(id) or { return (w.text_area_selections[id] or { TextAreaSelectionRange{} }).length }
		selection := windows_native_get_selection(hwnd)
		w.text_area_selections[id] = selection
		return selection.length
	}
}
