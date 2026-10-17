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
	const backend_feedback_strips = false
	const backend_clips_rounded_children = false

	fn backend_input_dispatch() AlwaysValidDispatch { return AlwaysValidDispatch{} }

	fn backend_own_activation(_code KeyCode) {}

	fn backend_invalidate(_reason RenderReason) { request_refresh() }

	fn refresh_compiled_element(id string, _node &CompiledVmlNode, element Element) { refresh_compiled_by_id(id, element) }

	fn begin_compiled_snapshot() {}

	fn end_compiled_snapshot() {}

	pub fn control_support(kind Kind) BackendSupport {
		return match kind {
			.image, .text_area { .partial }
			else { .supported }
		}
	}

	pub fn control_checked(id string) bool {
		st := windows_state()
		if (st.view_kinds[id] or { Kind.view }) !in [.checkbox, .switch_control, .toggle_button] {
			return false
		}
		hwnd := st.views[id] or { return false }
		return C.ui2_win_get_checked(hwnd) != 0
	}

	pub fn set_control_checked(id string, value bool) {
		st := windows_state()
		kind := st.view_kinds[id] or { return }
		if kind == .switch_control { set_switch_active(id, value) }
		if kind == .toggle_button { set_toggle_button_pressed(id, value) }
		if kind == .checkbox {
			hwnd := st.views[id] or { return }
			C.ui2_win_set_checked(hwnd, windows_bool(value))
		}
	}

	pub fn set_visual_transform(_id string, _transform VisualTransform) ! { return error('visual transforms require the custom renderer') }

	pub fn mounted_geometry(_id string) !VisualGeometry { return error('mounted visual geometry requires a running custom renderer') }

	pub fn visual_geometry(_id string) !VisualGeometry { return error('visual geometry requires a running custom renderer') }

	// Drag declarations are rejected by validation, so no drag can be active.
	pub fn drag_active() bool { return false }

	pub fn cancel_drag() {}

	pub fn image_resource_stats() ImageResourceStats { return ImageResourceStats{} }

	fn backend_measure_text(text string, style TextStyle, max_width f64) !LayoutSize {
		return layout_measure_cpu_text(text, style, max_width)
	}

	fn backend_measure_element_text(element Element, content string, max_width f64) !LayoutSize {
		return measure_layout_text(content, element.text_style, max_width)
	}

	fn backend_control_insets(_element Element) ?LayoutPadding { return none }

	fn backend_layout_environment(environment LayoutEnvironment) LayoutEnvironment { return environment }

	fn backend_file_dialog(cfg FileDialogConfig) []string { return native_file_dialog(cfg) }

	fn backend_file_dialog_supported() bool { return native_file_dialog_supported() }

	fn backend_message_box(cfg MessageBoxConfig) MessageBoxResult { return native_message_box(cfg) }

	fn backend_message_box_supported() bool { return native_message_box_supported() }
}
