// Linux (whose window sokol makes, with decorations from the window manager),
// Android and iOS keep their frame: there is no title bar to replace.
module ui2

fn host_window_chrome_supported() bool {
	return false
}

fn host_set_window_chrome(_native voidptr, _chrome WindowChrome) bool {
	return false
}

fn host_start_window_drag(_native voidptr) bool {
	return false
}

fn host_minimize_window(_native voidptr) bool {
	return false
}

fn host_toggle_maximize_window(_native voidptr) bool {
	return false
}

fn host_window_is_maximized(_native voidptr) bool {
	return false
}

fn host_window_controls_leading_inset(_native voidptr) f64 {
	return 0
}

fn host_window_draws_own_controls() bool {
	return false
}
