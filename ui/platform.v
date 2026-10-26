module ui2

// # Host services
//
// ui2 runs in one of two modes (backend.v): native, where macOS, Windows and
// iOS show the operating system's own controls, and custom, where the custom
// renderer (backend_custom.c.v and the `*_immediate.c.v` files) paints the
// whole window with sokol through gg. Either way the operating system is the
// host the window runs in, and it provides the services below.
//
// Each service is a set of `host_*` functions and constants that every OS
// defines, in files named after the service with V's OS suffixes
// (`_darwin.v`, `_ios.v`, `_windows.c.v`, `_linux.v`, `_default.c.v`, ...).
// They hold plain `$if macos`-style checks at most, never a backend flag
// (backend.v), and the headless and document backends compile them too:
// shared code and tests may call any of them. The windowed backends forward
// the backend contract's menu, tray, dialog, safe area and scanner hooks to
// them.
//
// | Service            | macOS                    | Windows           | Linux                 | Android     | iOS                      |
// |--------------------|--------------------------|-------------------|-----------------------|-------------|--------------------------|
// | window, event loop | NSApp; custom: sokol_app | message loop; custom: sokol_app | sokol_app (X11, EGL) | sokol_app | UIApplicationMain; custom: sokol_app |
// | menu bar           | global NSMenu bar        | window HMENU      | drawn by the renderer | drawn       | none                     |
// | tray               | NSStatusItem             | notification area | none                  | none        | none                     |
// | popup menu         | NSMenu pop-up            | TrackPopupMenuEx  | drawn by the renderer | drawn       | drawn                    |
// | clipboard          | NSPasteboard             | Win32 clipboard   | wl-clipboard, xclip   | none        | UIPasteboard             |
// | message box        | NSAlert                  | MessageBoxW       | zenity, kdialog       | none        | UIAlertController        |
// | file dialog        | NSOpenPanel, NSSavePanel | IFileDialog       | zenity, kdialog       | none        | none                     |
// | window chrome      | NSWindow style mask      | caption subclass  | none                  | none        | none                     |
// | key modifiers      | NSEvent                  | GetKeyState       | last renderer event   | last event  | last event               |
// | safe area          | none                     | none              | none                  | none        | root view safeAreaInsets |
// | barcode scanner    | none                     | none              | none                  | none        | AVFoundation camera      |
//
// "custom" is the custom renderer on an OS whose default is native (macOS,
// Windows, iOS); Linux and Android run only the renderer, and "drawn" means
// the renderer draws the service inside its window.
//
// ## Window and event loop
//
// The native backends own their event loop: AppKit runs NSApp, which shows
// each App window as an NSWindow (appkit/window_appkit_darwin.v); Win32 pumps
// one message loop for its top-level windows (windows/window_windows.v); UIKit
// runs UIApplicationMain with the one window an iOS app has
// (uikit/ui_ios.v). Each records its Window in a process host so that the
// OS's callbacks, which name only a native object, reach it.
//
// The renderer opens its window with gg (ui_immediate.c.v Window.run_sokol),
// whose sokol_app owns the event loop, one window per process; on iOS
// sokol_app runs UIApplicationMain itself, which is why the renderer defines
// SOKOL_NO_ENTRY there. Once the window exists the renderer records its
// native handle (an NSWindow, an HWND, or nil) and installs the menus the
// window declared. The macOS embedder (-d ui2_embedder,
// embedder_*_darwin.c.v) is a host variant of the same renderer: it owns
// AppKit windows and their Metal surfaces instead of a sokol window, which
// gives it several windows and NSTextInputClient text input. Linux waits for
// events itself while idle (linux_idle_linux.c.v). On iOS the renderer shows
// sokol's on-screen keyboard while an editable field has focus.
//
// ## Menu bar, tray and popup menus (menu_host_*)
//
// The menu bar and status area are the system's, one per process, and their
// native commands reach V through exported C functions that carry no
// context. Each host therefore keeps its native menu objects in one host
// state, together with the HostMenuOwner of the window that installed them,
// to which it delivers their commands.
//
//   const host_menu_bar HostMenuBar: where the menu bar lives.
//   const host_menu_key_equivalents bool: the native menu bar runs its own
//     shortcuts; otherwise the renderer matches them against its key events.
//   fn host_set_menu_bar(owner HostMenuOwner, menus []Menu): install a
//     native menu bar for owner; a no-op where the renderer draws it
//     (menu_custom.c.v).
//   fn host_tray_supported() bool
//   fn host_set_tray(owner HostMenuOwner, cfg TrayConfig)
//   fn host_remove_tray()
//   fn host_popup_menu_supported(native voidptr) bool: whether
//     host_show_popup_menu can show a native menu over the native window.
//     Where it cannot, the renderer draws a context menu as a context-menu
//     overlay and a select keeps its drawn list (popup_menu_immediate.c.v).
//   fn host_show_popup_menu(native voidptr, cfg PopupMenuConfig, on_result PopupMenuCallback):
//     show cfg.items at cfg.anchor, in the native window's logical
//     coordinates, and report the chosen row or a dismissal to on_result
//     exactly once, on the UI thread. The answer is asynchronous: a host opens
//     the menu once the input callback that asked for it has returned and
//     answers from its own run loop, never from inside a renderer callback. A
//     host without popup menus reports a dismissal at once.
//
// ## Clipboard (clipboard_*)
//
//   fn host_clipboard_supported() bool
//   fn host_set_clipboard_text(text string) bool
//   fn host_clipboard_text() ?string
//
// ## Dialogs (message_box_*, file_dialog_*)
//
//   fn host_message_box_supported() bool
//   fn host_message_box(cfg MessageBoxConfig) MessageBoxResult
//   fn host_file_dialog_supported() bool
//   fn host_file_dialog(cfg FileDialogConfig) []string
//
// ## Window chrome (window_chrome_*)
//
//   fn host_window_chrome_supported() bool
// The window functions act on native, the window's NSWindow or HWND
// (nil when it has none, which they refuse):
//
//   fn host_set_window_chrome(native voidptr, chrome WindowChrome) bool
//   fn host_start_window_drag(native voidptr) bool
//   fn host_minimize_window(native voidptr) bool
//   fn host_toggle_maximize_window(native voidptr) bool
//   fn host_window_is_maximized(native voidptr) bool
//   fn host_window_controls_leading_inset(native voidptr) f64
//   fn host_window_draws_own_controls() bool
//
// ## Key modifiers (key_modifiers_*)
//
//   fn host_key_modifiers(last_event KeyModifiers) KeyModifiers: the
//     modifiers held now, or last_event, those of the last event the window
//     received, where the platform cannot be asked
//
// ## Safe area (safe_area_*)
//
//   fn host_safe_area_top() f64: how far system chrome reaches into the top
//     of a full-screen window, in logical units.
//
// ## Barcode scanner (scanner_*)
//
//   fn host_start_barcode_scan(on_result ScanCallback): present the camera
//     and report one ScanResult; hosts without one report an error at once.
//
// The iOS services share the Objective-C runtime helpers in objc_ios.v.

// HostMenuOwner is the window a native menu bar or status area icon belongs
// to: their commands are delivered to window, and they attach to its native
// window (an NSWindow, an HWND, or nil) under its application name.
struct HostMenuOwner {
	window   &Window = unsafe { nil }
	native   voidptr
	app_name string
}

// HostMenuBar is where a host shows the application's menu bar.
enum HostMenuBar {
	// The system shows it outside the drawn content: macOS's global menu bar,
	// the menu in a Windows window's frame.
	native
	// The renderer draws it across the top of the window.
	drawn
	// The platform has no menu bar; declared menus are kept but not shown.
	absent
}
