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

	fn (mut w Window) backend_input_dispatch() AlwaysValidDispatch { return AlwaysValidDispatch{} }

	fn (mut w Window) backend_own_activation(_code KeyCode) {}

	fn (mut w Window) refresh_compiled_element(id string, _node &CompiledVmlNode, element Element) { w.refresh_compiled_by_id(id, element) }

	fn (mut w Window) begin_compiled_snapshot() {}

	fn (mut w Window) end_compiled_snapshot() {}

	pub fn control_support(kind Kind) BackendSupport {
		return if kind == .image { .partial } else { .supported }
	}

	pub fn (mut w Window) control_checked(id string) bool {
		if (w.view_kinds[id] or { Kind.view }) !in [.checkbox, .switch_control, .toggle_button] {
			return false
		}
		native := w.views[id] or { return false }
		return macos.msg_i64(native, 'state') != 0
	}

	pub fn (mut w Window) set_control_checked(id string, value bool) {
		kind := w.view_kinds[id] or { return }
		if kind == .switch_control { w.set_switch_active(id, value) }
		if kind == .toggle_button { w.set_toggle_button_pressed(id, value) }
		if kind == .checkbox {
			native := w.views[id] or { return }
			macos.msg_void_i64(native, 'setState:', if value { i64(1) } else { i64(0) })
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

	// AppKit has no barcode camera; the scan reports an error at once.
	pub fn start_barcode_scan(on_result ScanCallback) { host_start_barcode_scan(on_result) }

	fn layout_measure_appkit_text(text string, style TextStyle, max_width f64) !LayoutSize {
		pool := macos.autorelease_pool_new()
		defer { macos.release(pool) }
		font := native_text_style_font(style)
		line_height := macos.msg_f64(font, 'ascender') - macos.msg_f64(font, 'descender') +
			macos.msg_f64(font, 'leading')
		attrs := native_text_attributes(style.color, 0, style.size, style.font_family,
			text_style_weight(style), style.italic, style.underline, style.strikethrough, style.vertical_align)
		measured := layout_measure_text_lines(text, style, max_width, line_height, fn [attrs] (line string) f64 {
			attributed := macos.msg_id2(macos.alloc('NSAttributedString'), 'initWithString:attributes:', macos.nsstring(line), attrs)
			size := macos.msg_point(attributed, 'size')
			macos.release(attributed)
			return size.x
		})!
		// NSTextField's cell adds line fragment spacing beyond font ascent and
		// descent. Ask the actual control at the assigned content width, rather
		// than rounding shared logical layout or under-sizing wrapped labels.
		frame := native_rect(0, 0, (if max_width < 0 { measured.width } else { max_width }) + 4, 0)
		mut heights := map[string]f64{}
		field := native_new_label(frame, text, style.color, style.size, style.font_family, text_style_weight(style),
			style.italic, style.underline, align_value(style.align), text_line_budget(style.lines), .top, false, mut heights)
		defer { macos.release(field) }
		macos.msg_void1(field, 'setFont:', font)
		height := if text_line_budget(style.lines) > 1 {
			native_label_content_height(field, frame, text_line_budget(style.lines), mut heights)
		} else {
			macos.msg_point(macos.msg_id(field, 'cell'), 'cellSize').y
		}
		return LayoutSize{ ...measured, height: height }
	}
}
