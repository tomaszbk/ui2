// vfmt off
// The Windows host's window chrome (platform.v): the caption of sokol's
// window.
module ui2

#flag windows -luser32
#flag windows -lcomctl32

#insert "@VMODROOT/ui/window_chrome_windows.h"

fn C.ui2_chrome_set(hidden int) int
fn C.ui2_chrome_start_drag() int
fn C.ui2_chrome_minimize() int
fn C.ui2_chrome_toggle_maximize() int
fn C.ui2_chrome_is_maximized() int

fn host_window_chrome_supported() bool {
	return true
}

fn host_set_window_chrome(chrome WindowChrome) bool {
	return C.ui2_chrome_set(if chrome == .hidden_titlebar { 1 } else { 0 }) != 0
}

fn host_start_window_drag() bool {
	return C.ui2_chrome_start_drag() != 0
}

fn host_minimize_window() bool {
	return C.ui2_chrome_minimize() != 0
}

fn host_toggle_maximize_window() bool {
	return C.ui2_chrome_toggle_maximize() != 0
}

fn host_window_is_maximized() bool {
	return C.ui2_chrome_is_maximized() != 0
}

fn host_window_controls_leading_inset() f64 {
	return 0
}

fn host_window_draws_own_controls() bool {
	return true
}
