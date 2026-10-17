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

	// Window exists so that shared code compiles; a document library never
	// opens one.
	@[heap]
	pub struct Window {
	mut:
		app    &App = unsafe { nil }
		menus  MenuDeclarations
		timers &TimerRuntime = &TimerRuntime{}
		event_modifiers KeyModifiers
	}

	fn (mut app App) open_backend_window(_config WindowConfig) !&Window { document_without_window('new_window') }

	fn (mut app App) run_backend() { document_without_window('run') }

	fn (mut w Window) on_close(_hook fn ()) { document_without_window('on_close') }

	pub fn (mut w Window) quit() { document_without_window('quit') }

	pub fn (mut w Window) bounds() Rect { document_without_window('bounds') }

	pub fn (mut w Window) safe_area_top() f64 { document_without_window('safe_area_top') }

	pub fn (mut w Window) request_refresh() { panic('compiled VML document library refresh requires a host publisher') }

	pub fn (mut w Window) refresh_element(_id string, _element Element) { panic('compiled VML document library updates require an attached host publisher') }

	fn (mut w Window) refresh_compiled_element(_id string, _node &CompiledVmlNode, _element Element) { panic('compiled VML document library updates require an attached host publisher') }

	fn (mut w Window) begin_compiled_snapshot() {}

	fn (mut w Window) end_compiled_snapshot() {}

	fn (mut w Window) backend_invalidate(_reason RenderReason) { panic('compiled VML document library refresh requires a host publisher') }

	pub fn (mut w Window) layout_stats() LayoutStats { document_without_window('layout_stats') }

	pub fn (mut w Window) invalidate_layout_environment(_environment LayoutEnvironment) { document_without_window('invalidate_layout_environment') }

	pub fn (mut w Window) on_key(_handler KeyFn) { document_without_window('on_key') }

	pub fn (mut w Window) on_key_event(_handler KeyEventFn) { document_without_window('on_key_event') }

	pub fn (mut w Window) consume_key() { document_without_window('consume_key') }

	pub fn (mut w Window) consume_text_key() { document_without_window('consume_text_key') }

	pub fn (mut w Window) on_drop(_handler DropFn) { document_without_window('on_drop') }

	fn (mut w Window) backend_input_dispatch() AlwaysValidDispatch { return AlwaysValidDispatch{} }

	fn (mut w Window) backend_own_activation(_code KeyCode) {}

	pub fn (mut w Window) text(_id string) string { document_without_window('text') }

	pub fn (mut w Window) set_text(_id string, _value string) { document_without_window('set_text') }

	pub fn (mut w Window) slider_value(_id string) f64 { document_without_window('slider_value') }

	pub fn (mut w Window) set_slider_value(_id string, _value f64) { document_without_window('set_slider_value') }

	pub fn (mut w Window) switch_active(_id string) bool { document_without_window('switch_active') }

	pub fn (mut w Window) set_switch_active(_id string, _active bool) { document_without_window('set_switch_active') }

	pub fn (mut w Window) toggle_button_pressed(_id string) bool { document_without_window('toggle_button_pressed') }

	pub fn (mut w Window) set_toggle_button_pressed(_id string, _pressed bool) { document_without_window('set_toggle_button_pressed') }

	pub fn (mut w Window) toggle_button_group_members(_id string) []string { document_without_window('toggle_button_group_members') }

	pub fn (mut w Window) control_checked(_id string) bool { document_without_window('control_checked') }

	pub fn (mut w Window) set_control_checked(_id string, _value bool) { document_without_window('set_control_checked') }

	pub fn start_barcode_scan(_on_result ScanCallback) { document_without_window('start_barcode_scan') }

	pub fn (mut w Window) focused_text_area_id() string { document_without_window('focused_text_area_id') }

	pub fn (mut w Window) insert_text_area_text(_id string, _value string) { document_without_window('insert_text_area_text') }

	pub fn (mut w Window) text_area_caret(_id string) int { document_without_window('text_area_caret') }

	pub fn (mut w Window) text_area_selection_length(_id string) int { document_without_window('text_area_selection_length') }

	pub fn (mut w Window) text_area_set_caret(_id string, _pos int) { document_without_window('text_area_set_caret') }

	pub fn (mut w Window) text_area_set_selection(_id string, _location int, _length int) { document_without_window('text_area_set_selection') }

	pub fn (mut w Window) scroll_offset(_id string) f64 { document_without_window('scroll_offset') }

	pub fn (mut w Window) scroll_to_offset(_id string, _offset f64) { document_without_window('scroll_to_offset') }

	pub fn (mut w Window) scroll_horizontal_offset(_id string) f64 { document_without_window('scroll_horizontal_offset') }

	pub fn (mut w Window) scroll_to_horizontal_offset(_id string, _offset f64) { document_without_window('scroll_to_horizontal_offset') }

	pub fn (mut w Window) scroll_to_rect(_id string, _x f64, _y f64, _width f64, _height f64) { document_without_window('scroll_to_rect') }

	pub fn (mut w Window) focus(_id string) { document_without_window('focus') }

	pub fn (mut w Window) focused_id() string { document_without_window('focused_id') }

	pub fn (mut w Window) dismiss_keyboard() { document_without_window('dismiss_keyboard') }

	fn (mut w Window) focus_manager() &FocusManager { document_without_window('focus navigation') }

	fn (mut w Window) sync_focus_navigation() { document_without_window('focus navigation') }

	fn (mut w Window) live_semantic_nodes(_nodes []SemanticNode) []SemanticNode { document_without_window('semantic_tree') }

	fn (mut w Window) activate_semantic_control(_id string, _action SemanticAction) bool { document_without_window('perform_semantic_action') }

	pub fn control_support(_kind Kind) BackendSupport { return .supported }

	pub fn (mut w Window) set_visual_transform(_id string, _transform VisualTransform) ! { return error('ui2 document libraries have no window; set_visual_transform must run in the host') }

	pub fn (mut w Window) mounted_geometry(_id string) !VisualGeometry { return error('ui2 document libraries have no window; mounted_geometry must run in the host') }

	pub fn (mut w Window) visual_geometry(_id string) !VisualGeometry { return error('ui2 document libraries have no window; visual_geometry must run in the host') }

	pub fn (mut w Window) drag_active() bool { return false }

	pub fn (mut w Window) cancel_drag() {}

	pub fn (mut w Window) image_resource_stats() ImageResourceStats { return ImageResourceStats{} }

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

	fn (mut w Window) backend_set_menu_bar(_menus []Menu) {}

	fn (mut w Window) backend_set_tray(_cfg TrayConfig) {}

	fn (mut w Window) backend_remove_tray() {}

	// There is no window, so no native one for the host to change.
	fn (w &Window) backend_native_window() voidptr { return unsafe { nil } }

	fn backend_file_dialog(_cfg FileDialogConfig) []string { return [] }

	fn backend_file_dialog_supported() bool { return false }

	fn backend_message_box(cfg MessageBoxConfig) MessageBoxResult { return message_box_default_result(cfg.buttons) }

	fn backend_message_box_supported() bool { return false }
}
