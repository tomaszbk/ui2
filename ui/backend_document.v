// vfmt off
// The document-library backend (backend.v), selected by -d ui2_document_library
// on every OS. The library holds compiled VML documents that a host window
// loads, as the designer preview does; it has no window of its own. Calls that
// need one panic, and compiled documents publish updates, refreshes and
// control commands through the handlers the host attaches. Validation accepts
// everything the custom renderer can show, because the host validates the
// published tree against its own backend.
module ui2

$if ui2_document_library ? {
	pub const backend_name = 'document'
	pub const backend_supports_overlays = true
	pub const backend_supports_motion = true
	pub const backend_supports_visual_transforms = true
	pub const backend_embedder = false
	pub const backend_needs_host = true
	// The designer builds a document library with its own backend flags, so the
	// library builds components and measures controls the way its host will
	// draw them: with the custom renderer, unless the host is headless. This is
	// the only backend condition this backend reads.
	const document_host_custom = $if ui2_headless ? { false } $else { true }

	@[noreturn]
	fn document_without_window(api string) {
		panic('ui2 document libraries have no window; ${api} must run in the host')
	}

	pub fn run(_build BuildFn) { document_without_window('run') }

	pub fn run_window(_title string, _width int, _height int, _build BuildFn) { document_without_window('run_window') }

	fn run_window_with_min_size(_title string, _width int, _height int, _min_width int, _min_height int, _build BuildFn) { document_without_window('run_window') }

	pub fn quit() { document_without_window('quit') }

	pub fn bounds() Rect { document_without_window('bounds') }

	pub fn safe_area_top() f64 { document_without_window('safe_area_top') }

	pub fn request_refresh() { panic('compiled VML document library refresh requires a host publisher') }

	pub fn refresh_element(_id string, _element Element) { panic('compiled VML document library updates require an attached host publisher') }

	fn refresh_compiled_element(_id string, _node &CompiledVmlNode, _element Element) { panic('compiled VML document library updates require an attached host publisher') }

	fn begin_compiled_snapshot() {}

	fn end_compiled_snapshot() {}

	fn backend_invalidate(_reason RenderReason) { panic('compiled VML document library refresh requires a host publisher') }

	pub fn layout_stats() LayoutStats { document_without_window('layout_stats') }

	pub fn invalidate_layout_environment(_environment LayoutEnvironment) { document_without_window('invalidate_layout_environment') }

	pub fn on_key(_handler KeyFn) { document_without_window('on_key') }

	pub fn on_key_event(_handler KeyEventFn) { document_without_window('on_key_event') }

	pub fn consume_key() { document_without_window('consume_key') }

	pub fn consume_text_key() { document_without_window('consume_text_key') }

	pub fn on_drop(_handler DropFn) { document_without_window('on_drop') }

	fn backend_input_dispatch() AlwaysValidDispatch { return AlwaysValidDispatch{} }

	fn backend_own_activation(_code KeyCode) {}

	pub fn text(_id string) string { document_without_window('text') }

	pub fn set_text(_id string, _value string) { document_without_window('set_text') }

	pub fn slider_value(_id string) f64 { document_without_window('slider_value') }

	pub fn set_slider_value(_id string, _value f64) { document_without_window('set_slider_value') }

	pub fn switch_active(_id string) bool { document_without_window('switch_active') }

	pub fn set_switch_active(_id string, _active bool) { document_without_window('set_switch_active') }

	pub fn toggle_button_pressed(_id string) bool { document_without_window('toggle_button_pressed') }

	pub fn set_toggle_button_pressed(_id string, _pressed bool) { document_without_window('set_toggle_button_pressed') }

	pub fn toggle_button_group_members(_id string) []string { document_without_window('toggle_button_group_members') }

	pub fn control_checked(_id string) bool { document_without_window('control_checked') }

	pub fn set_control_checked(_id string, _value bool) { document_without_window('set_control_checked') }

	pub fn start_barcode_scan(_on_result ScanCallback) { document_without_window('start_barcode_scan') }

	pub fn focused_text_area_id() string { document_without_window('focused_text_area_id') }

	pub fn insert_text_area_text(_id string, _value string) { document_without_window('insert_text_area_text') }

	pub fn text_area_caret(_id string) int { document_without_window('text_area_caret') }

	pub fn text_area_selection_length(_id string) int { document_without_window('text_area_selection_length') }

	pub fn text_area_set_caret(_id string, _pos int) { document_without_window('text_area_set_caret') }

	pub fn text_area_set_selection(_id string, _location int, _length int) { document_without_window('text_area_set_selection') }

	pub fn scroll_offset(_id string) f64 { document_without_window('scroll_offset') }

	pub fn scroll_to_offset(_id string, _offset f64) { document_without_window('scroll_to_offset') }

	pub fn scroll_horizontal_offset(_id string) f64 { document_without_window('scroll_horizontal_offset') }

	pub fn scroll_to_horizontal_offset(_id string, _offset f64) { document_without_window('scroll_to_horizontal_offset') }

	pub fn scroll_to_rect(_id string, _x f64, _y f64, _width f64, _height f64) { document_without_window('scroll_to_rect') }

	pub fn focus(_id string) { document_without_window('focus') }

	pub fn focused_id() string { document_without_window('focused_id') }

	pub fn dismiss_keyboard() { document_without_window('dismiss_keyboard') }

	fn focus_manager() &FocusManager { document_without_window('focus navigation') }

	fn sync_focus_navigation() { document_without_window('focus navigation') }

	fn live_semantic_nodes(_nodes []SemanticNode) []SemanticNode { document_without_window('semantic_tree') }

	fn activate_semantic_control(_id string, _action SemanticAction) bool { document_without_window('perform_semantic_action') }

	pub fn control_support(_kind Kind) BackendSupport { return .supported }

	pub fn set_visual_transform(_id string, _transform VisualTransform) ! { return error('ui2 document libraries have no window; set_visual_transform must run in the host') }

	pub fn mounted_geometry(_id string) !VisualGeometry { return error('ui2 document libraries have no window; mounted_geometry must run in the host') }

	pub fn visual_geometry(_id string) !VisualGeometry { return error('ui2 document libraries have no window; visual_geometry must run in the host') }

	pub fn drag_active() bool { return false }

	pub fn cancel_drag() {}

	pub fn image_resource_stats() ImageResourceStats { return ImageResourceStats{} }

	fn backend_measure_text(text string, style TextStyle, max_width f64) !LayoutSize {
		return layout_measure_cpu_text(text, style, max_width)
	}

	fn backend_measure_element_text(element Element, content string, max_width f64) !LayoutSize {
		return measure_layout_text(content, element.text_style, max_width)
	}

	fn backend_control_insets(element Element) ?LayoutPadding {
		if document_host_custom { return custom_renderer_insets(element) }
		return none
	}

	fn backend_layout_environment(environment LayoutEnvironment) LayoutEnvironment { return environment }

	// Menus are kept by menu.v; the host shows its own.
	fn backend_menu_bar_supported() bool { return false }

	fn backend_tray_supported() bool { return false }

	fn backend_set_menu_bar(_menus []Menu) {}

	fn backend_set_tray(_cfg TrayConfig) {}

	fn backend_remove_tray() {}

	fn backend_file_dialog(_cfg FileDialogConfig) []string { return [] }

	fn backend_file_dialog_supported() bool { return false }

	fn backend_message_box(cfg MessageBoxConfig) MessageBoxResult { return message_box_default_result(cfg.buttons) }

	fn backend_message_box_supported() bool { return false }
}
