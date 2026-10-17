module ui2

// iOS has no menu bar, status area or popup menus; declared menus are kept,
// not shown, and popup menus are left to the renderer.
const host_menu_bar = HostMenuBar.absent
const host_menu_key_equivalents = false

fn host_set_menu_bar(_owner HostMenuOwner, _menus []Menu) {}

fn host_tray_supported() bool {
	return false
}

fn host_set_tray(_owner HostMenuOwner, _cfg TrayConfig) {}

fn host_remove_tray() {}

fn host_popup_menu_supported(_native voidptr) bool {
	return false
}

fn host_show_popup_menu(_native voidptr, _cfg PopupMenuConfig, on_result PopupMenuCallback) {
	on_result(PopupMenuResult{})
}
