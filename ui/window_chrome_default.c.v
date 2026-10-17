// Linux (whose window sokol makes, with decorations from the window manager),
// Android and iOS keep their frame: there is no title bar to replace.
module ui2

fn host_window_chrome_supported() bool {
	return false
}

fn host_set_window_chrome(_chrome WindowChrome) bool {
	return false
}

fn host_start_window_drag() bool {
	return false
}

fn host_minimize_window() bool {
	return false
}

fn host_toggle_maximize_window() bool {
	return false
}

fn host_window_is_maximized() bool {
	return false
}

fn host_window_controls_leading_inset() f64 {
	return 0
}

fn host_window_draws_own_controls() bool {
	return false
}
