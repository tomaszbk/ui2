// vfmt off
// UIKit's side of the backend contract (ui/backend.v): its capability
// constants, the hooks that do not belong to its view or text files, and the
// desktop entry points that have a UIKit meaning.
module ui2

$if ios && !ui2_headless ? && !ui2_document_library ? {
	import macos

	pub const backend_name = 'uikit'
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

	// An iOS app has one full-screen window; the title and sizes do not apply.
	pub fn run_window(_title string, _width int, _height int, build BuildFn) { run(build) }

	fn run_window_with_min_size(_title string, _width int, _height int, _min_width int, _min_height int, build BuildFn) { run(build) }

	// iOS apps are not quit programmatically; the system ends them.
	pub fn quit() {}

	// UIKit delivers neither hardware key events nor window drops to ui2 yet, so
	// these handlers are not called and there is nothing to consume.
	pub fn on_key(_handler KeyFn) {}

	pub fn on_key_event(_handler KeyEventFn) {}

	pub fn consume_key() {}

	pub fn consume_text_key() {}

	pub fn on_drop(_handler DropFn) {}

	// insert_text_area_text replaces the selection, or inserts at the caret, and
	// leaves the caret after the inserted text.
	pub fn insert_text_area_text(id string, value string) {
		if (g_view_kinds[id] or { Kind.view }) != .text_area { return }
		updated, caret := text_area_replace_selection(text(id), TextAreaSelectionRange{ location: text_area_caret(id), length: text_area_selection_length(id) }, value)
		set_text(id, updated)
		text_area_set_caret(id, caret)
	}

	pub fn scroll_offset(id string) f64 {
		view := g_views[id] or { return g_scroll_offsets[id] or { 0 } }
		return scroll_content_offset(view).y
	}

	pub fn scroll_horizontal_offset(id string) f64 {
		view := g_views[id] or { return g_scroll_offsets_x[id] or { 0 } }
		return scroll_content_offset(view).x
	}

	// A Scroll that is not mounted yet keeps the request and opens there.
	pub fn scroll_to_offset(id string, offset f64) {
		if id.len == 0 { return }
		wanted := if offset < 0 { 0.0 } else { offset }
		if view := g_views[id] {
			if (g_view_kinds[id] or { Kind.view }) == .scroll {
				set_scroll_content_offset(view, scroll_content_offset(view).x, wanted)
			}
			return
		}
		g_scroll_offsets[id] = wanted
	}

	pub fn scroll_to_horizontal_offset(id string, offset f64) {
		if id.len == 0 { return }
		wanted := if offset < 0 { 0.0 } else { offset }
		if view := g_views[id] {
			if (g_view_kinds[id] or { Kind.view }) == .scroll {
				set_scroll_content_offset(view, wanted, scroll_content_offset(view).y)
			}
			return
		}
		g_scroll_offsets_x[id] = wanted
	}

	pub fn scroll_to_rect(id string, x f64, y f64, width f64, height f64) {
		if (g_view_kinds[id] or { Kind.view }) != .scroll { return }
		view := g_views[id] or { return }
		C.ui2_ios_scroll_rect_visible(view, x, y, width, height, false)
	}

	pub fn control_support(kind Kind) BackendSupport {
		return match kind {
			.text_area, .checkbox, .image { .partial }
			else { .supported }
		}
	}

	pub fn control_checked(id string) bool {
		native := g_views[id] or { return false }
		return match g_view_kinds[id] or { Kind.view } {
			.switch_control { macos.msg_bool(native, 'isOn') }
			.checkbox, .toggle_button { macos.msg_bool(native, 'isSelected') }
			else { false }
		}
	}

	pub fn set_control_checked(id string, value bool) {
		match g_view_kinds[id] or { return } {
			.switch_control { set_switch_active(id, value) }
			.toggle_button { set_toggle_button_pressed(id, value) }
			.checkbox {
				native := g_views[id] or { return }
				macos.msg_void_bool(native, 'setSelected:', value)
			}
			else {}
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

	// iOS has no menu bar or status area.
	fn backend_menu_bar_supported() bool { return false }

	fn backend_tray_supported() bool { return false }

	fn backend_set_menu_bar(_menus []Menu) {}

	fn backend_set_tray(_cfg TrayConfig) {}

	fn backend_remove_tray() {}

	fn backend_file_dialog(cfg FileDialogConfig) []string { return native_file_dialog(cfg) }

	fn backend_file_dialog_supported() bool { return native_file_dialog_supported() }

	fn backend_message_box(cfg MessageBoxConfig) MessageBoxResult { return native_message_box(cfg) }

	fn backend_message_box_supported() bool { return native_message_box_supported() }
}
