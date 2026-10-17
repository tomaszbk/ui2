// vfmt off
// The Windows host's menu bar, notification area icon and popup menus
// (platform.v). Each is built from the declaration in one go rather than
// reconciled: a menu is small, and rebuilding it is what keeps the declared
// rows and the HMENU in step. The window is the one the renderer published to
// menu.v.
module ui2

#flag windows -luser32
#flag windows -lcomctl32
#flag windows -lshell32

#insert "@VMODROOT/ui/menu_host_windows.h"

fn C.ui2_host_menu_attach(hwnd voidptr)

fn C.ui2_host_menu_create() voidptr

fn C.ui2_host_menubar_create() voidptr

fn C.ui2_host_menu_destroy(menu voidptr)

fn C.ui2_host_menu_add_item(menu voidptr, command u32, title &u16, enabled int, checked int)

fn C.ui2_host_menu_add_separator(menu voidptr)

fn C.ui2_host_menu_add_submenu(menu voidptr, submenu voidptr, title &u16, enabled int)

fn C.ui2_host_set_menubar(hwnd voidptr, menu voidptr)

fn C.ui2_host_tray_set(hwnd voidptr, tooltip &u16, icon_path &u16)

fn C.ui2_host_tray_remove()

fn C.ui2_host_tray_popup(hwnd voidptr, menu voidptr) u32

fn C.ui2_host_popup_post(hwnd voidptr) int

fn C.ui2_host_popup_track(hwnd voidptr, menu voidptr, x int, y int, width int, height int) u32

// The menu bar sits in the window's frame. Win32 only runs accelerators from a
// message loop that asks it to, which sokol's does not, so the renderer
// matches the declared shortcuts against its own key events (menu_custom.c.v).
const host_menu_bar = HostMenuBar.native
const host_menu_key_equivalents = false

const win_wm_lbutton_up = u32(0x0202)
const win_wm_rbutton_up = u32(0x0205)
const win_wm_contextmenu = u32(0x007b)

// Commands start well above zero, which TrackPopupMenu returns for a menu
// dismissed without a choice.
const win_menu_command_base = u32(0x1000)

@[heap]
struct WindowsMenuState {
mut:
	bar_commands map[u32]MenuItem
	tray_active  bool
	// The popup menu posted to the window and not yet shown, if popup_pending.
	popup         PopupMenuConfig
	popup_result  PopupMenuCallback = unsafe { nil }
	popup_pending bool
}

const windows_menu_state_singleton = &WindowsMenuState{
	bar_commands: map[u32]MenuItem{}
}

fn windows_menu_state() &WindowsMenuState {
	return unsafe { windows_menu_state_singleton }
}

fn host_set_menu_bar(menus []Menu) {
	mut st := windows_menu_state()
	st.bar_commands = map[u32]MenuItem{}
	window := menu_state().window
	if window == unsafe { nil } {
		// Declared before the window exists; the renderer installs it again
		// once there is something to attach it to.
		return
	}
	C.ui2_host_menu_attach(window)
	if menus.len == 0 {
		C.ui2_host_set_menubar(window, unsafe { nil })
		return
	}
	menubar := C.ui2_host_menubar_create()
	if menubar == unsafe { nil } {
		return
	}
	mut commands := map[u32]MenuItem{}
	mut next := win_menu_command_base
	for m in menus {
		popup_menu := C.ui2_host_menu_create()
		if popup_menu == unsafe { nil } {
			continue
		}
		next = windows_fill_menu(popup_menu, m.items, mut commands, next)
		wide_title := m.title.to_wide()
		C.ui2_host_menu_add_submenu(menubar, popup_menu, wide_title, 1)
		unsafe { free(wide_title) }
	}
	st.bar_commands = commands.move()
	C.ui2_host_set_menubar(window, menubar)
}

fn host_tray_supported() bool { return true }

fn host_set_tray(cfg TrayConfig) {
	mut st := windows_menu_state()
	window := menu_state().window
	if window == unsafe { nil } {
		return
	}
	C.ui2_host_menu_attach(window)
	// Windows has no room for a text-only notification area item, so the
	// title falls back into the tooltip when none was given.
	tooltip := if cfg.tooltip.len > 0 { cfg.tooltip } else { cfg.title }
	wide_tooltip := tooltip.to_wide()
	wide_icon := cfg.icon.to_wide()
	C.ui2_host_tray_set(window, wide_tooltip, wide_icon)
	unsafe {
		free(wide_tooltip)
		free(wide_icon)
	}
	st.tray_active = true
}

fn host_remove_tray() {
	mut st := windows_menu_state()
	if !st.tray_active {
		return
	}
	C.ui2_host_tray_remove()
	st.tray_active = false
}

// A popup menu opens over the window the renderer published to menu.v.
fn host_popup_menu_supported() bool { return menu_state().window != unsafe { nil } }

// TrackPopupMenuEx runs a modal loop of its own, so the menu is posted to the
// window's message queue and shown from there, once the input callback that
// asked for it has returned.
fn host_show_popup_menu(cfg PopupMenuConfig, on_result PopupMenuCallback) {
	mut st := windows_menu_state()
	window := menu_state().window
	if st.popup_pending || window == unsafe { nil } || cfg.items.len == 0 {
		on_result(PopupMenuResult{})
		return
	}
	C.ui2_host_menu_attach(window)
	st.popup = cfg
	st.popup_result = on_result
	st.popup_pending = true
	if C.ui2_host_popup_post(window) == 0 {
		st.popup = PopupMenuConfig{}
		st.popup_result = unsafe { nil }
		st.popup_pending = false
		on_result(PopupMenuResult{})
	}
}

// ui2_host_popup_message shows the posted popup menu and answers it. The
// anchor's bottom-left corner places the menu, and a select's frame is kept
// clear of it: the menu opens above the select when it does not fit below.
@[export: 'ui2_host_popup_message']
fn ui2_host_popup_message() {
	mut st := windows_menu_state()
	if !st.popup_pending {
		return
	}
	cfg := st.popup
	on_result := st.popup_result
	st.popup = PopupMenuConfig{}
	st.popup_result = unsafe { nil }
	st.popup_pending = false
	window := menu_state().window
	menu := C.ui2_host_menu_create()
	if window == unsafe { nil } || menu == unsafe { nil } {
		on_result(PopupMenuResult{})
		return
	}
	mut commands := map[u32]MenuItem{}
	_ := windows_fill_menu(menu, cfg.items, mut commands, win_menu_command_base)
	// The window's client area is in device pixels.
	scale := if cfg.scale > 0 { cfg.scale } else { 1.0 }
	command := C.ui2_host_popup_track(window, menu, int(cfg.anchor.x * scale + 0.5),
		int(cfg.anchor.y * scale + 0.5), int(cfg.anchor.width * scale + 0.5),
		int(cfg.anchor.height * scale + 0.5))
	C.ui2_host_menu_destroy(menu)
	chosen := commands[command] or {
		on_result(PopupMenuResult{})
		return
	}
	on_result(PopupMenuResult{ chosen: true, item: chosen })
}

// windows_fill_menu appends one level of rows, numbering each emitting one
// into `commands`. Win32 draws whatever follows a tab right-aligned in the row,
// which is how a menu shows its accelerator.
fn windows_fill_menu(menu voidptr, items []MenuItem, mut commands map[u32]MenuItem, first_command u32) u32 {
	mut next := first_command
	for item in items {
		if item.separator {
			C.ui2_host_menu_add_separator(menu)
			continue
		}
		if item.items.len > 0 {
			child := C.ui2_host_menu_create()
			if child == unsafe { nil } {
				continue
			}
			next = windows_fill_menu(child, item.items, mut commands, next)
			wide_title := item.title.to_wide()
			C.ui2_host_menu_add_submenu(menu, child, wide_title, windows_bool(item.enabled))
			unsafe { free(wide_title) }
			continue
		}
		command := next
		next++
		commands[command] = item
		row_label := if parse_menu_shortcut(item.shortcut).key.len > 0 {
			'${item.title}\t${menu_shortcut_label(item.shortcut)}'
		} else {
			item.title
		}
		wide_label := row_label.to_wide()
		C.ui2_host_menu_add_item(menu, command, wide_label, windows_bool(item.enabled), windows_bool(item.checked))
		unsafe { free(wide_label) }
	}
	return next
}

fn windows_bool(value bool) int {
	return if value { 1 } else { 0 }
}

// ui2_host_menu_command runs the menu bar row a WM_COMMAND names.
@[export: 'ui2_host_menu_command']
fn ui2_host_menu_command(command u32) {
	st := windows_menu_state()
	item := st.bar_commands[command] or { return }
	emit_host_menu_callback(item.on_select, item.id)
}

// ui2_host_tray_message answers a click on the notification area icon. The
// menu is built on demand so it always shows the current declaration.
@[export: 'ui2_host_tray_message']
fn ui2_host_tray_message(mouse_message u32) {
	cfg := tray()
	if mouse_message !in [win_wm_lbutton_up, win_wm_rbutton_up, win_wm_contextmenu] {
		return
	}
	if cfg.menu.len == 0 {
		if mouse_message == win_wm_lbutton_up {
			emit_host_menu_callback(cfg.on_event, cfg.id)
		}
		return
	}
	window := menu_state().window
	menu := C.ui2_host_menu_create()
	if window == unsafe { nil } || menu == unsafe { nil } {
		return
	}
	// The tray rows are numbered into their own table, so building the menu
	// cannot renumber the menu bar's.
	mut commands := map[u32]MenuItem{}
	_ := windows_fill_menu(menu, cfg.menu, mut commands, win_menu_command_base)
	chosen := commands[C.ui2_host_tray_popup(window, menu)] or { MenuItem{} }
	C.ui2_host_menu_destroy(menu)
	emit_host_menu_callback(chosen.on_select, chosen.id)
}
