// Linux and Android hosts have no menu bar or status area of their own. The
// renderer draws the menu bar across the top of the window (menu_custom.c.v)
// and runs its shortcuts.
module ui2

const host_menu_bar = HostMenuBar.drawn
const host_menu_key_equivalents = false

fn host_set_menu_bar(_menus []Menu) {}

fn host_tray_supported() bool {
	return false
}

fn host_set_tray(_cfg TrayConfig) {}

fn host_remove_tray() {}
