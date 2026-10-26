// vfmt off
// AppKit windows and the process's application: App.new_window opens an
// NSWindow and App.run runs NSApp until the last window closes.
module ui2

$if macos && !ui2_custom_rendering ? && !ui2_headless ? && !ui2_document_library ? {

import macos

fn C.ui2_macos_stop_app()

// AppkitHost is the process's NSApplication side. AppKit calls the classes
// ui2 registers (backend_appkit_darwin.v) with their receiver alone, so the
// host maps each NSWindow and each window's control handler back to its
// Window. NSApp is one per process, and so is this registry.
@[heap]
struct AppkitHost {
mut:
	launched bool
	running  bool
	// NSApp finished launching: it accepts a main menu and a status item.
	finished bool
	delegate NativeView
	// NSWindow pointer -> window, and control handler pointer -> window.
	windows  map[u64]&Window
	handlers map[u64]&Window
}

const appkit_host_singleton = &AppkitHost{}

fn appkit_host() &AppkitHost {
	return unsafe { appkit_host_singleton }
}

// appkit_launch prepares NSApp once: the runtime classes, a regular
// activation policy and the application delegate.
fn appkit_launch() {
	mut host := appkit_host()
	if host.launched { return }
	host.launched = true
	ensure_runtime_classes()
	native_set_activation_policy_regular()
	host.delegate = native_new_object('UI2AppDelegate')
	native_set_delegate(host.delegate)
}

// appkit_window_for finds the window an AppKit callback belongs to: the
// receiver's NSWindow for views and windows, or the window whose control
// handler the receiver is.
fn appkit_window_for(receiver voidptr) ?&Window {
	if receiver == unsafe { nil } { return none }
	host := appkit_host()
	key := u64(receiver)
	if w := host.windows[key] { return w }
	if w := host.handlers[key] { return w }
	if macos.responds_to(macos.Id(receiver), 'window') {
		window := macos.msg_id(macos.Id(receiver), 'window')
		if window != unsafe { nil } {
			if w := host.windows[u64(voidptr(window))] { return w }
		}
	}
	return none
}

// appkit_key_window is the window that receives keyboard input, for
// callbacks whose receiver belongs to no window.
fn appkit_key_window() ?&Window {
	key := macos.msg_id(native_current_app(), 'keyWindow')
	if key != unsafe { nil } {
		if w := appkit_host().windows[u64(voidptr(key))] { return w }
	}
	return none
}

fn appkit_window_open(w &Window) bool {
	for _, open in appkit_host().windows {
		if open == w { return true }
	}
	return false
}

fn (mut app App) open_backend_window(config WindowConfig) !&Window {
	appkit_launch()
	mut w := &Window{
		app: app
		title: config.title
		width: config.width
		height: config.height
		min_width: config.min_width
		min_height: config.min_height
		build: config.build
	}
	w.open_native()
	return w
}

// open_native makes the NSWindow and its flipped root view and shows it.
// The tree is built once the app runs, or at once when it already does.
fn (mut w Window) open_native() {
	frame := native_rect(120, 120, f64(w.width), f64(w.height))
	w.window = native_new_window(frame, w.title)
	native_set_content_min_size(w.window, f64(w.min_width), f64(w.min_height))
	mut host := appkit_host()
	// The app delegate doubles as window delegate for windowDidResize: and
	// windowWillClose:.
	macos.msg_void1(w.window, 'setDelegate:', host.delegate)
	root_frame := native_rect(0, 0, f64(w.width), f64(w.height))
	w.root_view = native_new_flipped_view(root_frame, BoxStyle{
		bg: 0xffffff
	})
	C.ui2_macos_add_tracking_area(w.root_view)
	native_register_drop_types(w.root_view)
	native_set_content_view(w.window, w.root_view)
	macos.release(w.root_view)
	w.button_handler = native_new_object('UI2ButtonHandler')
	host.windows[u64(voidptr(w.window))] = w
	host.handlers[u64(voidptr(w.button_handler))] = w
	native_make_key_and_order_front(w.window)
	if host.running { w.start_native() }
}

// appkit_fixture_window opens a window for in-process tests: an NSWindow with
// its root view and control handler, registered with the host like any
// other, while NSApp does not run. close_fixture closes it again.
fn appkit_fixture_window(title string, width int, height int) &Window {
	native_current_app()
	ensure_runtime_classes()
	mut w := &Window{
		title: title
		width: width
		height: height
	}
	w.open_native()
	return w
}

fn (mut w Window) close_fixture() {
	window := w.window
	w.close_native()
	macos.msg_void(window, 'close')
}

// start_native installs the window's declared menus and builds its tree.
fn (mut w Window) start_native() {
	// The menu bar goes in even when none was declared: macOS needs its
	// application menu to handle Cmd+Q.
	w.install_declared_menus()
	w.rebuild_now()
}

fn (mut app App) run_backend() {
	if app.windows.len == 0 { return }
	appkit_launch()
	mut host := appkit_host()
	host.running = true
	native_run_app()
	host.running = false
}

@[export: 'ui2_app_did_finish_launching']
fn ui2_app_did_finish_launching(_self voidptr, _cmd voidptr, _notification voidptr) {
	mut host := appkit_host()
	host.finished = true
	native_activate()
	for _, mut w in host.windows.clone() { w.start_native() }
}

// App.run returns once its last window closed (close_native), so NSApp does
// not terminate the process itself.
@[export: 'ui2_app_should_terminate_after_last_window_closed']
fn ui2_app_should_terminate_after_last_window_closed(_self voidptr, _cmd voidptr, _sender voidptr) bool {
	return false
}

// AppKit closes the window, from its close button or from quit; the window
// forgets its views, runs its close hooks and leaves its app.
@[export: 'ui2_window_will_close']
fn ui2_window_will_close(_self voidptr, _cmd voidptr, notification voidptr) {
	window := macos.msg_id(macos.Id(notification), 'object')
	mut w := appkit_host().windows[u64(voidptr(window))] or { return }
	w.close_native()
}

fn (mut w Window) close_native() {
	if w.closed { return }
	w.closed = true
	mut host := appkit_host()
	host.windows.delete(u64(voidptr(w.window)))
	host.handlers.delete(u64(voidptr(w.button_handler)))
	hooks := w.close_hooks.clone()
	w.close_hooks.clear()
	for hook in hooks { hook() }
	if w.app != unsafe { nil } {
		mut app := w.app
		app.forget_window(w)
	}
	if host.running && host.windows.len == 0 { C.ui2_macos_stop_app() }
}

@[export: 'ui2_window_did_resize']
fn ui2_window_did_resize(_self voidptr, _cmd voidptr, notification voidptr) {
	window := macos.msg_id(macos.Id(notification), 'object')
	mut w := appkit_host().windows[u64(voidptr(window))] or { return }
	w.rebuild_now()
}

// on_close runs hook as the window closes.
fn (mut w Window) on_close(hook fn ()) { w.close_hooks << hook }

// quit closes the window. NSApp terminates once its last window closed.
pub fn (mut w Window) quit() {
	if w.closed || native_is_nil(w.window) { return }
	macos.msg_void(w.window, 'close')
}

pub fn (mut w Window) safe_area_top() f64 { return host_safe_area_top() }

// request_refresh schedules a rebuild on the main thread; safe to call from
// background threads (sync loops, network fetches, timers).
pub fn (mut w Window) request_refresh() {
	w.rebuild_queued = true
	native_dispatch_window_refresh(w)
}

fn (mut w Window) backend_invalidate(_reason RenderReason) { w.request_refresh() }

// The dispatcher carries the window's address; a window that closed before
// the main thread got to it is no longer registered and is left alone.
@[export: 'ui2_dispatch_window_refresh']
fn ui2_dispatch_window_refresh(_self voidptr, _cmd voidptr, boxed_window voidptr) {
	pointer := macos.msg_u64(unsafe { macos.Id(boxed_window) }, 'unsignedLongLongValue')
	mut host := appkit_host()
	for _, mut w in host.windows {
		if u64(voidptr(w)) == pointer {
			w.rebuild_now()
			return
		}
	}
}

@[export: 'ui2_dispatch_window_screenshot']
fn ui2_dispatch_window_screenshot(_self voidptr, _cmd voidptr, boxed_window voidptr) {
	pointer := macos.msg_u64(unsafe { macos.Id(boxed_window) }, 'unsignedLongLongValue')
	mut host := appkit_host()
	for _, mut w in host.windows {
		if u64(voidptr(w)) == pointer {
			w.capture_screenshot_on_main()
			return
		}
	}
}

// set_window_title updates the window's title bar.
pub fn (mut w Window) set_window_title(title string) {
	w.title = title
	if !native_is_nil(w.window) {
		macos.msg_void1(w.window, 'setTitle:', macos.nsstring(title))
	}
}

// The host's per-window services act on the NSWindow (platform.v).
fn (w &Window) backend_native_window() voidptr { return voidptr(w.window) }

// host_menu_owner names this window to the host's menu bar and tray.
fn (w &Window) host_menu_owner() HostMenuOwner {
	return HostMenuOwner{ window: w, native: voidptr(w.window), app_name: w.title }
}

// AppKit shows the menu bar and the status item (menu_host_darwin.v).
fn backend_menu_bar_supported() bool { return host_menu_bar != .absent }

fn backend_tray_supported() bool { return host_tray_supported() }

// Menus declared before NSApp finished launching are installed as it does
// (start_native).
fn (mut w Window) backend_set_menu_bar(menus []Menu) {
	if !appkit_host().finished { return }
	host_set_menu_bar(w.host_menu_owner(), menus)
}

fn (mut w Window) backend_set_tray(cfg TrayConfig) {
	if !appkit_host().finished { return }
	host_set_tray(w.host_menu_owner(), cfg)
}

fn (mut w Window) backend_remove_tray() { host_remove_tray() }

}
