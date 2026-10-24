module ui2

$if ios && !ui2_custom_rendering ? && !ui2_headless ? && !ui2_document_library ? {

pub fn (mut w Window) text_area_set_selection(id string, location int, length int) {
	view := w.views[id] or { return }
	selection := clamped_text_area_selection(w.text(id), location, length)
	native_text_view_set_selected_range(view, u64(selection.location), u64(selection.length))
}

pub fn (mut w Window) text_area_set_caret(id string, pos int) {
	w.text_area_set_selection(id, pos, 0)
}

pub fn (mut w Window) text_area_caret(id string) int {
	view := w.views[id] or { return 0 }
	return int(native_text_view_selected_range(view).location)
}

pub fn (mut w Window) text_area_selection_length(id string) int {
	view := w.views[id] or { return 0 }
	return int(native_text_view_selected_range(view).length)
}

}
