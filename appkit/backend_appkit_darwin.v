// vfmt off
// AppKit's side of the backend contract (ui/backend.v): its capability
// constants and the hooks that do not belong to its window, view or text files.
module ui2

$if macos && !ui2_custom_rendering ? && !ui2_headless ? && !ui2_document_library ? {
	import macos

	pub const backend_name = 'appkit'
	pub const backend_supports_overlays = false
	pub const backend_supports_motion = false
	pub const backend_supports_visual_transforms = false
	pub const backend_supports_vector_canvas = false
	pub const backend_supports_drag_drop = false
	pub const backend_native_controls = true
	pub const backend_embedder = false
	pub const backend_needs_host = false
	const backend_feedback_strips = false
	// A view with a corner radius masks its layer, which clips its children.
	const backend_clips_rounded_children = true

	fn backend_input_dispatch() AlwaysValidDispatch { return AlwaysValidDispatch{} }

	fn backend_own_activation(_code KeyCode) {}

	fn backend_invalidate(_reason RenderReason) { request_refresh() }

	fn refresh_compiled_element(id string, _node &CompiledVmlNode, element Element) { refresh_compiled_by_id(id, element) }

	fn begin_compiled_snapshot() {}

	fn end_compiled_snapshot() {}

	pub fn control_support(kind Kind) BackendSupport {
		return if kind == .image { .partial } else { .supported }
	}

	pub fn control_checked(id string) bool {
		st := state()
		if (st.view_kinds[id] or { Kind.view }) !in [.checkbox, .switch_control, .toggle_button] {
			return false
		}
		native := st.views[id] or { return false }
		return macos.msg_i64(native, 'state') != 0
	}

	pub fn set_control_checked(id string, value bool) {
		st := state()
		kind := st.view_kinds[id] or { return }
		if kind == .switch_control { set_switch_active(id, value) }
		if kind == .toggle_button { set_toggle_button_pressed(id, value) }
		if kind == .checkbox {
			native := st.views[id] or { return }
			macos.msg_void_i64(native, 'setState:', if value { i64(1) } else { i64(0) })
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
		return layout_measure_appkit_text(text, style, max_width)
	}

	fn backend_measure_element_text(element Element, content string, max_width f64) !LayoutSize {
		return measure_layout_text(content, element.text_style, max_width)
	}

	fn backend_control_insets(element Element) ?LayoutPadding { return appkit_insets(element) }

	fn backend_layout_environment(environment LayoutEnvironment) LayoutEnvironment { return environment }

	fn backend_file_dialog(cfg FileDialogConfig) []string { return host_file_dialog(cfg) }

	fn backend_file_dialog_supported() bool { return host_file_dialog_supported() }

	fn backend_message_box(cfg MessageBoxConfig) MessageBoxResult { return host_message_box(cfg) }

	fn backend_message_box_supported() bool { return host_message_box_supported() }
}
