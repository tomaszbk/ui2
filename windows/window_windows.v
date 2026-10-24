// vfmt off
// Win32 windows and the process's message loop: App.new_window creates a
// top-level window and App.run pumps messages until the last one closes.
module ui2

$if windows && !ui2_custom_rendering ? && !ui2_headless ? && !ui2_document_library ? {

fn C.ui2_win_root_of(hwnd voidptr) voidptr

fn C.ui2_win_focus_root() voidptr

// WindowsHost is the process's side of Win32: the window classes are
// registered once, one message loop runs every window, and the window
// procedure and control subclasses, which call V with a handle alone, find
// their Window through the top-level handle registered here.
@[heap]
struct WindowsHost {
mut:
	registered bool
	failed     bool
	windows    map[u64]&Window
}

const windows_host_singleton = &WindowsHost{}

fn windows_host() &WindowsHost {
	return unsafe { windows_host_singleton }
}

// windows_window_for finds the window a handle belongs to: a top-level
// window, or a control inside one.
fn windows_window_for(hwnd voidptr) ?&Window {
	if hwnd == unsafe { nil } { return none }
	host := windows_host()
	if w := host.windows[windows_handle_id(hwnd)] { return w }
	root := C.ui2_win_root_of(hwnd)
	if w := host.windows[windows_handle_id(root)] { return w }
	return none
}

// windows_focus_window is the window keyboard input goes to, for messages
// that carry no handle.
fn windows_focus_window() ?&Window {
	return windows_window_for(C.ui2_win_focus_root())
}

fn windows_window_open(w &Window) bool {
	for _, open in windows_host().windows {
		if open == w { return true }
	}
	return false
}

fn windows_register() ! {
	mut host := windows_host()
	if host.registered { return }
	if host.failed || C.ui2_win_register_classes() == 0 {
		host.failed = true
		C.ui2_win_shutdown_accessibility()
		return error('ui2: failed to register Win32 window classes')
	}
	host.registered = true
}

fn (mut app App) open_backend_window(config WindowConfig) !&Window {
	windows_register()!
	mut w := &Window{
		app: app
		title: config.title
		width: config.width
		height: config.height
		min_width: config.min_width
		min_height: config.min_height
		build: config.build
	}
	wide_title := config.title.to_wide()
	root := C.ui2_win_create_main_window(wide_title, config.width, config.height)
	unsafe { free(wide_title) }
	if root == unsafe { nil } {
		return error('ui2: failed to create the Win32 window')
	}
	w.root = root
	mut host := windows_host()
	host.windows[windows_handle_id(root)] = w
	return w
}

// windows_fixture_window opens a window for in-process tests: a registered
// top-level window that no message loop runs. close_fixture destroys it.
fn windows_fixture_window(title string, width int, height int) &Window {
	windows_register() or { panic(err) }
	mut w := &Window{
		title: title
		width: width
		height: height
	}
	wide_title := title.to_wide()
	w.root = C.ui2_win_create_main_window(wide_title, width, height)
	unsafe { free(wide_title) }
	mut host := windows_host()
	host.windows[windows_handle_id(w.root)] = w
	return w
}

fn (mut w Window) close_fixture() {
	root := w.root
	w.closed = true
	windows_forget(w)
	w.windows_dispose_all()
	C.ui2_win_destroy(root)
}

// windows_forget takes w out of the registry under whichever handle it is
// registered with.
fn windows_forget(w &Window) {
	mut host := windows_host()
	for handle, open in host.windows.clone() {
		if open == w { host.windows.delete(handle) }
	}
}

fn (mut app App) run_backend() {
	if app.windows.len == 0 { return }
	for mut w in app.windows.clone() {
		// The menu bar and the tray can be declared before the window exists;
		// attach whatever was declared now that there is a window to attach to.
		w.install_declared_menus()
		w.rebuild_now()
		C.ui2_win_show_main_window(w.root)
	}
	C.ui2_win_message_loop()
	host_remove_tray()
	C.ui2_win_shutdown_accessibility()
}

// close_native forgets a destroyed window: its controls' resources, its close
// hooks and its app. The message loop ends with the last window.
fn (mut w Window) close_native() {
	if w.closed { return }
	w.closed = true
	windows_forget(w)
	w.windows_dispose_all()
	hooks := w.close_hooks.clone()
	w.close_hooks.clear()
	for hook in hooks { hook() }
	if w.app != unsafe { nil } {
		mut app := w.app
		app.forget_window(w)
	}
	if windows_host().windows.len == 0 { C.ui2_win_post_quit(0) }
}

// on_close runs hook as the window closes.
fn (mut w Window) on_close(hook fn ()) { w.close_hooks << hook }

// quit closes the window. The app's run returns once its last window closed.
pub fn (mut w Window) quit() {
	if w.closed { return }
	C.ui2_win_close(w.root)
}

pub fn (mut w Window) safe_area_top() f64 { return host_safe_area_top() }

fn (mut w Window) backend_invalidate(_reason RenderReason) { w.request_refresh() }

// The host's per-window services act on the HWND (platform.v).
fn (w &Window) backend_native_window() voidptr { return w.root }

// host_menu_owner names this window to the host's menu bar and tray.
fn (w &Window) host_menu_owner() HostMenuOwner {
	return HostMenuOwner{ window: w, native: w.root, app_name: w.title }
}

// The menu bar sits in the window's frame and the icon in the notification
// area (menu_host_windows.c.v).
fn backend_menu_bar_supported() bool { return host_menu_bar != .absent }

fn backend_tray_supported() bool { return host_tray_supported() }

fn (mut w Window) backend_set_menu_bar(menus []Menu) {
	if w.root == unsafe { nil } { return }
	host_set_menu_bar(w.host_menu_owner(), menus)
}

fn (mut w Window) backend_set_tray(cfg TrayConfig) {
	if w.root == unsafe { nil } { return }
	host_set_tray(w.host_menu_owner(), cfg)
}

fn (mut w Window) backend_remove_tray() { host_remove_tray() }

// windows_menu_shortcut runs the menu bar row whose accelerator is the key.
// Win32 runs accelerators only from a message loop that translates them, and
// the menu bar is built by the host without a table, so the window matches
// them against its own key presses, before the application's handlers.
fn (mut w Window) windows_menu_shortcut(key string) bool {
	pressed := parse_menu_shortcut(key)
	if w.menus.bar.len == 0 || !menu_shortcut_bindable(pressed) { return false }
	for m in w.menus.bar {
		item := find_menu_shortcut(m.items, pressed) or { continue }
		w.emit_menu_callback(item.on_select, item.id)
		return true
	}
	return false
}

}
