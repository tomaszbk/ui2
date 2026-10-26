// vfmt off
// UIKit's side of the backend contract (ui/backend.v): its capability
// constants, the hooks that do not belong to its view or text files, and the
// desktop entry points that have a UIKit meaning.
module ui2

$if ios && !ui2_custom_rendering ? && !ui2_headless ? && !ui2_document_library ? {
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

	fn (mut w Window) backend_input_dispatch() AlwaysValidDispatch { return AlwaysValidDispatch{} }

	fn (mut w Window) backend_own_activation(_code KeyCode) {}

	fn (mut w Window) backend_invalidate(_reason RenderReason) { w.request_refresh() }

	fn (mut w Window) refresh_compiled_element(id string, _node &CompiledVmlNode, element Element) { w.refresh_compiled_by_id(id, element) }

	fn (mut w Window) begin_compiled_snapshot() {}

	fn (mut w Window) end_compiled_snapshot() {}

	// iOS apps are not quit programmatically; the system ends them.
	pub fn (mut w Window) quit() {}

	// UIKit delivers neither hardware key events nor window drops to ui2 yet, so
	// these handlers are not called and there is nothing to consume.
	pub fn (mut w Window) on_key(_handler KeyFn) {}

	pub fn (mut w Window) on_key_event(_handler KeyEventFn) {}

	pub fn (mut w Window) consume_key() {}

	pub fn (mut w Window) consume_text_key() {}

	pub fn (mut w Window) on_drop(_handler DropFn) {}

	// insert_text_area_text replaces the selection, or inserts at the caret, and
	// leaves the caret after the inserted text.
	pub fn (mut w Window) insert_text_area_text(id string, value string) {
		if (w.view_kinds[id] or { Kind.view }) != .text_area { return }
		updated, caret := text_area_replace_selection(w.text(id), TextAreaSelectionRange{ location: w.text_area_caret(id), length: w.text_area_selection_length(id) }, value)
		w.set_text(id, updated)
		w.text_area_set_caret(id, caret)
	}

	pub fn (mut w Window) scroll_offset(id string) f64 {
		view := w.views[id] or { return w.scroll_offsets[id] or { 0 } }
		return scroll_content_offset(view).y
	}

	pub fn (mut w Window) scroll_horizontal_offset(id string) f64 {
		view := w.views[id] or { return w.scroll_offsets_x[id] or { 0 } }
		return scroll_content_offset(view).x
	}

	// A Scroll that is not mounted yet keeps the request and opens there.
	pub fn (mut w Window) scroll_to_offset(id string, offset f64) {
		if id.len == 0 { return }
		wanted := if offset < 0 { 0.0 } else { offset }
		if view := w.views[id] {
			if (w.view_kinds[id] or { Kind.view }) == .scroll {
				set_scroll_content_offset(view, scroll_content_offset(view).x, wanted)
			}
			return
		}
		w.scroll_offsets[id] = wanted
	}

	pub fn (mut w Window) scroll_to_horizontal_offset(id string, offset f64) {
		if id.len == 0 { return }
		wanted := if offset < 0 { 0.0 } else { offset }
		if view := w.views[id] {
			if (w.view_kinds[id] or { Kind.view }) == .scroll {
				set_scroll_content_offset(view, wanted, scroll_content_offset(view).y)
			}
			return
		}
		w.scroll_offsets_x[id] = wanted
	}

	pub fn (mut w Window) scroll_to_rect(id string, x f64, y f64, width f64, height f64) {
		if (w.view_kinds[id] or { Kind.view }) != .scroll { return }
		view := w.views[id] or { return }
		C.ui2_ios_scroll_rect_visible(view, x, y, width, height, false)
	}

	pub fn control_support(kind Kind) BackendSupport {
		return match kind {
			.text_area, .checkbox, .image { .partial }
			else { .supported }
		}
	}

	pub fn (mut w Window) control_checked(id string) bool {
		native := w.views[id] or { return false }
		return match w.view_kinds[id] or { Kind.view } {
			.switch_control { macos.msg_bool(native, 'isOn') }
			.checkbox, .toggle_button { macos.msg_bool(native, 'isSelected') }
			else { false }
		}
	}

	pub fn (mut w Window) set_control_checked(id string, value bool) {
		match w.view_kinds[id] or { return } {
			.switch_control { w.set_switch_active(id, value) }
			.toggle_button { w.set_toggle_button_pressed(id, value) }
			.checkbox {
				native := w.views[id] or { return }
				macos.msg_void_bool(native, 'setSelected:', value)
			}
			else {}
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

	// iOS has no menu bar or status area.
	fn backend_menu_bar_supported() bool { return false }

	fn backend_tray_supported() bool { return false }

	fn (mut w Window) backend_set_menu_bar(_menus []Menu) {}

	fn (mut w Window) backend_set_tray(_cfg TrayConfig) {}

	fn (mut w Window) backend_remove_tray() {}

	// The host's per-window services have nothing to act on (platform.v).
	fn (w &Window) backend_native_window() voidptr { return unsafe { nil } }

	fn backend_file_dialog(cfg FileDialogConfig) []string { return host_file_dialog(cfg) }

	fn backend_file_dialog_supported() bool { return host_file_dialog_supported() }

	fn backend_message_box(cfg MessageBoxConfig) MessageBoxResult { return host_message_box(cfg) }

	fn backend_message_box_supported() bool { return host_message_box_supported() }
}
