// vfmt off
// Win32's side of the backend contract (ui/backend.v): its capability
// constants and the hooks that do not belong to its window or control files.
module ui2

$if windows && !ui2_custom_rendering ? && !ui2_headless ? && !ui2_document_library ? {
	pub const backend_name = 'win32'
	pub const backend_supports_overlays = false
	pub const backend_supports_motion = false
	pub const backend_supports_visual_transforms = false
	pub const backend_supports_vector_canvas = false
	pub const backend_supports_drag_drop = false
	pub const backend_native_controls = true
	pub const backend_embedder = false
	pub const backend_needs_host = false

	fn (mut w Window) backend_input_dispatch() AlwaysValidDispatch { return AlwaysValidDispatch{} }

	fn (mut w Window) backend_own_activation(_code KeyCode) {}

	fn (mut w Window) refresh_compiled_element(id string, _node &CompiledVmlNode, element Element) { w.refresh_compiled_by_id(id, element) }

	fn (mut w Window) begin_compiled_snapshot() {}

	fn (mut w Window) end_compiled_snapshot() {}

	pub fn control_support(kind Kind) BackendSupport {
		return match kind {
			.image, .text_area { .partial }
			else { .supported }
		}
	}

	pub fn (mut w Window) control_checked(id string) bool {
		if (w.view_kinds[id] or { Kind.view }) !in [.checkbox, .switch_control, .toggle_button] {
			return false
		}
		hwnd := w.views[id] or { return false }
		return C.ui2_win_get_checked(hwnd) != 0
	}

	pub fn (mut w Window) set_control_checked(id string, value bool) {
		kind := w.view_kinds[id] or { return }
		if kind == .switch_control { w.set_switch_active(id, value) }
		if kind == .toggle_button { w.set_toggle_button_pressed(id, value) }
		if kind == .checkbox {
			hwnd := w.views[id] or { return }
			C.ui2_win_set_checked(hwnd, windows_bool(value))
		}
	}

	pub fn (mut w Window) set_visual_transform(_id string, _transform VisualTransform) ! { return error('visual transforms require the custom renderer (-d ui2_custom_rendering)') }

	pub fn (mut w Window) mounted_geometry(_id string) !VisualGeometry { return error('mounted visual geometry requires the custom renderer (-d ui2_custom_rendering)') }

	pub fn (mut w Window) visual_geometry(_id string) !VisualGeometry { return error('visual geometry requires the custom renderer (-d ui2_custom_rendering)') }

	// Drag declarations are rejected by validation, so no drag can be active.
	pub fn (mut w Window) drag_active() bool { return false }

	pub fn (mut w Window) cancel_drag() {}

	pub fn (mut w Window) image_resource_stats() ImageResourceStats { return ImageResourceStats{} }

	fn backend_measure_text(text string, style TextStyle, max_width f64) !LayoutSize {
		return layout_measure_cpu_text(text, style, max_width)
	}

	fn backend_measure_element_text(element Element, content string, max_width f64) !LayoutSize {
		return measure_layout_text(content, element.text_style, max_width)
	}

	fn backend_control_insets(_element Element) ?LayoutPadding { return none }

	fn backend_layout_environment(environment LayoutEnvironment) LayoutEnvironment { return environment }

	fn backend_file_dialog(cfg FileDialogConfig) []string { return host_file_dialog(cfg) }

	fn backend_file_dialog_supported() bool { return host_file_dialog_supported() }

	fn backend_message_box(cfg MessageBoxConfig) MessageBoxResult { return host_message_box(cfg) }

	fn backend_message_box_supported() bool { return host_message_box_supported() }

	// Win32 has no barcode camera; the scan reports an error at once.
	pub fn start_barcode_scan(on_result ScanCallback) { host_start_barcode_scan(on_result) }
}
