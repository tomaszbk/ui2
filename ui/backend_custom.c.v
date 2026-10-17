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

	fn backend_input_dispatch() CustomInputDispatch { return custom_input_dispatch(g_gg_app) }

	fn backend_own_activation(code KeyCode) { own_custom_activation(code) }

	fn backend_invalidate(reason RenderReason) { g_gg_app.scheduler.invalidate(reason) }

	pub fn control_support(kind Kind) BackendSupport {
		return match kind {
			.text_area, .dropdown { .partial }
			else { .supported }
		}
	}

	pub fn control_checked(id string) bool {
		if id in g_active_checkboxes { return checkbox_checked(id) }
		if id in g_active_switches { return switch_active(id) }
		if id in g_active_toggles { return toggle_button_pressed(id) }
		return false
	}

	pub fn set_control_checked(id string, value bool) {
		if id in g_active_checkboxes {
			g_checkbox_values[id] = value
			invalidate_custom_paint()
		}
		if id in g_active_switches { set_switch_active(id, value) }
		if id in g_active_toggles { set_toggle_button_pressed(id, value) }
	}

	fn backend_control_insets(element Element) ?LayoutPadding { return custom_renderer_insets(element) }

	// The host shows the menu bar and tray (platform.v); where it has no menu
	// bar of its own, the renderer draws one inside the window (menu_custom.c.v).
	fn backend_menu_bar_supported() bool { return host_menu_bar != .absent }

	fn backend_tray_supported() bool { return host_tray_supported() }

	fn backend_set_menu_bar(menus []Menu) {
		host_set_menu_bar(menus)
		// Rebuild bounds and paint after replacing the menu declaration.
		close_menu_bar()
		request_refresh()
	}

	fn backend_set_tray(cfg TrayConfig) { host_set_tray(cfg) }

	fn backend_remove_tray() { host_remove_tray() }

	fn backend_file_dialog(cfg FileDialogConfig) []string { return host_file_dialog(cfg) }

	fn backend_file_dialog_supported() bool { return host_file_dialog_supported() }

	fn backend_message_box(cfg MessageBoxConfig) MessageBoxResult { return host_message_box(cfg) }

	fn backend_message_box_supported() bool { return host_message_box_supported() }

	// UI-thread presentation update. A subsequent declarative rebuild replaces it.
	// A configured motion retargets its retained timeline without rebuilding.
	pub fn set_visual_transform(id string, transform VisualTransform) ! {
		if !backend_supports_visual_transforms {
			return error('visual transforms require the desktop custom text renderer')
		}
		if id.len == 0 { return error('visual transform updates require an element id') }
		root, found := replace_visual_transform(g_gg_app.declared_root, id, transform)!
		if !found { return error('unknown element `${id}`') }
		if g_gg_app.layout_tree.root.len > 0 {
			g_gg_app.layout_tree.set_transform(id, transform)!
		}
		g_gg_app.declared_root = root
		mounted, mounted_found := replace_visual_transform(g_focus_navigation.root, id, transform)!
		if mounted_found {
			g_focus_navigation.set_root(mounted)
			sync_focus_navigation()
		}
		g_gg_app.presentation_revision++
		invalidate_custom_paint()
	}

	// Current resolved mounted geometry includes controls outside paint culling.
	// Querying it never resolves layout or changes the last-presented snapshot.
	pub fn mounted_geometry(id string) !VisualGeometry {
		sync_focus_navigation()
		node := g_focus_navigation.node(id) or { return error('element `${id}` has no mounted geometry') }
		if node.hidden { return error('element `${id}` is hidden') }
		return VisualGeometry{
			frame:            node.local_frame
			transform:        node.transform
			parent_transform: node.parent_transform
			clip:             node.clip
		}
	}

	pub fn visual_geometry(id string) !VisualGeometry {
		return g_gg_app.visual_geometries[id] or { return error('element `${id}` has no presented geometry') }
	}

	fn switch_pointer_right(target HitTarget, x f64, y f64) bool {
		current := current_pointer_target(target) or { target }
		if !current.has_geometry { return x >= current.x + current.w / 2 }
		lx, _ := current.content_transform.inverse(x, y)
		return lx >= current.local_frame.x + current.local_frame.width / 2
	}
}
