// vfmt off
// The Windows host's window chrome (platform.v): the caption of the window's
// HWND, which sokol made.
module ui2

#flag windows -luser32
#flag windows -lcomctl32

#insert "@VMODROOT/ui/window_chrome_windows.h"

fn C.ui2_chrome_set(window voidptr, hidden int) int
fn C.ui2_chrome_start_drag(window voidptr) int
fn C.ui2_chrome_minimize(window voidptr) int
fn C.ui2_chrome_toggle_maximize(window voidptr) int
fn C.ui2_chrome_is_maximized(window voidptr) int

fn host_window_chrome_supported() bool {
	return true
}

fn host_set_window_chrome(native voidptr, chrome WindowChrome) bool {
	return C.ui2_chrome_set(native, if chrome == .hidden_titlebar { 1 } else { 0 }) != 0
}

fn host_start_window_drag(native voidptr) bool {
	return C.ui2_chrome_start_drag(native) != 0
}

fn host_minimize_window(native voidptr) bool {
	return C.ui2_chrome_minimize(native) != 0
}

fn host_toggle_maximize_window(native voidptr) bool {
	return C.ui2_chrome_toggle_maximize(native) != 0
}

fn host_window_is_maximized(native voidptr) bool {
	return C.ui2_chrome_is_maximized(native) != 0
}

fn host_window_controls_leading_inset(_native voidptr) f64 {
	return 0
}

fn host_window_draws_own_controls() bool {
	return true
}
