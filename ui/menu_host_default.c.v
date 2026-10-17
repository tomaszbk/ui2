// Linux and Android hosts have no menu bar, status area or popup menus of
// their own. The renderer draws the menu bar across the top of the window and
// runs its shortcuts, and it draws popup menus too (popup_menu_immediate.c.v).
module ui2

const host_menu_bar = HostMenuBar.drawn
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
