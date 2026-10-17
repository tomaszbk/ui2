// vfmt off
// The custom renderer's side of the backend contract (backend.v): its
// capability constants and the hooks that do not belong to its window, input,
// scrolling or text files.
@[has_globals]
module ui2

$if (android || ios || linux || macos || windows) && !ui2_headless ? && !ui2_document_library ? {
	pub const backend_name = 'custom'
	// Android and iOS keep gg/Fontstash text, which has no layered, faded or
	// transformed presentation.
	pub const backend_supports_overlays = $if android || ios { false } $else { true }
	pub const backend_supports_motion = $if android || ios { false } $else { true }
	pub const backend_supports_visual_transforms = $if android || ios { false } $else { true }
	pub const backend_embedder = $if ui2_embedder ? { true } $else { false }
	pub const backend_needs_host = false
	// sokol-gl spends some 370 vertices on every rounded rect and has 65,536 a
	// frame, so rings of round cells would blank a busy window.
	const backend_feedback_strips = true

	fn (mut w Window) backend_input_dispatch() CustomInputDispatch { return w.custom_input_dispatch() }

	fn (mut w Window) backend_own_activation(code KeyCode) { w.own_custom_activation(code) }

	fn (mut w Window) backend_invalidate(reason RenderReason) { w.scheduler.invalidate(reason) }

	pub fn control_support(kind Kind) BackendSupport {
		return match kind {
			.text_area, .dropdown { .partial }
			else { .supported }
		}
	}

	pub fn (mut w Window) control_checked(id string) bool {
		if id in w.active_checkboxes { return w.checkbox_checked(id) }
		if id in w.active_switches { return w.switch_active(id) }
		if id in w.active_toggles { return w.toggle_button_pressed(id) }
		return false
	}

	pub fn (mut w Window) set_control_checked(id string, value bool) {
		if id in w.active_checkboxes {
			w.checkbox_values[id] = value
			w.invalidate_custom_paint()
		}
		if id in w.active_switches { w.set_switch_active(id, value) }
		if id in w.active_toggles { w.set_toggle_button_pressed(id, value) }
	}

	fn backend_control_insets(element Element) ?LayoutPadding { return custom_renderer_insets(element) }

	// The host shows the menu bar and tray (platform.v); where it has no menu
	// bar of its own, the renderer draws one inside the window (menu_custom.c.v).
	fn backend_menu_bar_supported() bool { return host_menu_bar != .absent }

	fn backend_tray_supported() bool { return host_tray_supported() }

	// host_menu_owner names this window to the host's menu bar and tray.
	fn (w &Window) host_menu_owner() HostMenuOwner {
		return HostMenuOwner{ window: w, native: w.os_window, app_name: w.title }
	}

	fn (mut w Window) backend_set_menu_bar(menus []Menu) {
		host_set_menu_bar(w.host_menu_owner(), menus)
		// Rebuild bounds and paint after replacing the menu declaration.
		w.close_menu_bar()
		w.request_refresh()
	}

	fn (mut w Window) backend_set_tray(cfg TrayConfig) { host_set_tray(w.host_menu_owner(), cfg) }

	fn (mut w Window) backend_remove_tray() { host_remove_tray() }

	fn backend_file_dialog(cfg FileDialogConfig) []string { return host_file_dialog(cfg) }

	fn backend_file_dialog_supported() bool { return host_file_dialog_supported() }

	fn backend_message_box(cfg MessageBoxConfig) MessageBoxResult { return host_message_box(cfg) }

	fn backend_message_box_supported() bool { return host_message_box_supported() }

	// UI-thread presentation update. A subsequent declarative rebuild replaces it.
	// A configured motion retargets its retained timeline without rebuilding.
	pub fn (mut w Window) set_visual_transform(id string, transform VisualTransform) ! {
		if !backend_supports_visual_transforms {
			return error('visual transforms require the desktop custom text renderer')
		}
		if id.len == 0 { return error('visual transform updates require an element id') }
		root, found := replace_visual_transform(w.declared_root, id, transform)!
		if !found { return error('unknown element `${id}`') }
		if w.layout_tree.root.len > 0 {
			w.layout_tree.set_transform(id, transform)!
		}
		w.declared_root = root
		mounted, mounted_found := replace_visual_transform(w.navigation.root, id, transform)!
		if mounted_found {
			w.navigation.set_root(mounted)
			w.sync_focus_navigation()
		}
		w.presentation_revision++
		w.invalidate_custom_paint()
	}

	// Current resolved mounted geometry includes controls outside paint culling.
	// Querying it never resolves layout or changes the last-presented snapshot.
	pub fn (mut w Window) mounted_geometry(id string) !VisualGeometry {
		w.sync_focus_navigation()
		node := w.navigation.node(id) or { return error('element `${id}` has no mounted geometry') }
		if node.hidden { return error('element `${id}` is hidden') }
		return VisualGeometry{
			frame:            node.local_frame
			transform:        node.transform
			parent_transform: node.parent_transform
			clip:             node.clip
		}
	}

	pub fn (mut w Window) visual_geometry(id string) !VisualGeometry {
		return w.visual_geometries[id] or { return error('element `${id}` has no presented geometry') }
	}

	fn (mut w Window) switch_pointer_right(target HitTarget, x f64, y f64) bool {
		current := w.current_pointer_target(target) or { target }
		if !current.has_geometry { return x >= current.x + current.w / 2 }
		lx, _ := current.content_transform.inverse(x, y)
		return lx >= current.local_frame.x + current.local_frame.width / 2
	}
}
