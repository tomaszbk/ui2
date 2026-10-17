module ui2

// # Host services
//
// ui2 draws every control itself, the way a browser engine does: the custom
// renderer (backend_custom.c.v and the `*_immediate.c.v` files) paints the
// whole window with sokol through gg on every OS. The operating system is
// only the host the renderer runs in. It provides the services below and no
// controls.
//
// Each service is a set of `host_*` functions and constants that every OS
// defines, in files named after the service with V's OS suffixes
// (`_darwin.v`, `_ios.v`, `_windows.c.v`, `_linux.v`, `_default.c.v`, ...).
// They hold plain `$if macos`-style checks at most, never a backend flag
// (backend.v), and the headless and document backends compile them too:
// shared code and tests may call any of them. The custom backend forwards the
// backend contract's menu, tray, dialog, safe area and scanner hooks to them.
//
// | Service            | macOS                    | Windows           | Linux                 | Android     | iOS                      |
// |--------------------|--------------------------|-------------------|-----------------------|-------------|--------------------------|
// | window, event loop | sokol_app (or embedder)  | sokol_app         | sokol_app (X11, EGL)  | sokol_app   | sokol_app (UIKit, Metal) |
// | menu bar           | global NSMenu bar        | window HMENU      | drawn by the renderer | drawn       | none                     |
// | tray               | NSStatusItem             | notification area | none                  | none        | none                     |
// | clipboard          | NSPasteboard             | Win32 clipboard   | wl-clipboard, xclip   | none        | UIPasteboard             |
// | message box        | NSAlert                  | MessageBoxW       | zenity, kdialog       | none        | UIAlertController        |
// | file dialog        | NSOpenPanel, NSSavePanel | IFileDialog       | zenity, kdialog       | none        | none                     |
// | window chrome      | NSWindow style mask      | caption subclass  | none                  | none        | none                     |
// | key modifiers      | NSEvent                  | GetKeyState       | last renderer event   | last event  | last event               |
// | safe area          | none                     | none              | none                  | none        | root view safeAreaInsets |
// | barcode scanner    | none                     | none              | none                  | none        | AVFoundation camera      |
//
// ## Window and event loop
//
// The renderer opens its window with gg (ui_immediate.c.v run_window), whose
// sokol_app owns the event loop on every OS; on iOS sokol_app runs
// UIApplicationMain itself, which is why the renderer defines SOKOL_NO_ENTRY
// there. Once the window exists the renderer publishes its native handle (an
// NSWindow, an HWND, or nil) to menu.v with publish_menu_context and installs
// the declared menus. The macOS embedder (-d ui2_embedder,
// embedder_*_darwin.c.v) is a host variant of the same renderer: it owns
// AppKit windows and their Metal surfaces instead of a sokol window, which
// gives it several windows and NSTextInputClient text input. Linux waits for
// events itself while idle (linux_idle_linux.c.v). On iOS the renderer shows
// sokol's on-screen keyboard while an editable field has focus.
//
// ## Menu bar and tray (menu_host_*)
//
//   const host_menu_bar HostMenuBar: where the menu bar lives.
//   const host_menu_key_equivalents bool: the native menu bar runs its own
//     shortcuts; otherwise the renderer matches them against its key events.
//   fn host_set_menu_bar(menus []Menu): install a native menu bar; a no-op
//     where the renderer draws it (menu_custom.c.v).
//   fn host_tray_supported() bool
//   fn host_set_tray(cfg TrayConfig)
//   fn host_remove_tray()
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
//   fn host_set_window_chrome(chrome WindowChrome) bool
//   fn host_start_window_drag() bool
//   fn host_minimize_window() bool
//   fn host_toggle_maximize_window() bool
//   fn host_window_is_maximized() bool
//   fn host_window_controls_leading_inset() f64
//   fn host_window_draws_own_controls() bool
//
// ## Key modifiers (key_modifiers_*)
//
//   fn host_key_modifiers() KeyModifiers
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
