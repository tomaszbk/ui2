module ui2

// iOS has no menu bar or status area; declared menus are kept, not shown.
const host_menu_bar = HostMenuBar.absent
const host_menu_key_equivalents = false

fn host_set_menu_bar(_menus []Menu) {}

fn host_tray_supported() bool {
	return false
}

fn host_set_tray(_cfg TrayConfig) {}

fn host_remove_tray() {}
