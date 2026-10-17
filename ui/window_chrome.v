module ui2

// WindowChrome is how much of the platform's window frame a window keeps.
pub enum WindowChrome {
	native          // the platform's title bar and frame
	hidden_titlebar // content runs under a transparent title bar; draw your own (title_bar)
}

// set_chrome changes w's frame. With `hidden_titlebar` the application draws
// its own title bar at the top of the window: macOS keeps its window controls
// over the content's leading corner (see controls_leading_inset),
// Windows removes the caption but keeps the resizable border, and the
// application draws the window buttons (window_draws_own_controls). It reports
// whether the platform did it; Linux, Android, iOS and windows without a
// native window keep their frame.
pub fn (mut w Window) set_chrome(chrome WindowChrome) bool {
	return host_set_window_chrome(w.backend_native_window(), chrome)
}

// window_chrome_supported reports whether set_chrome can apply chrome.
pub fn window_chrome_supported(chrome WindowChrome) bool {
	return chrome == .native || host_window_chrome_supported()
}

// start_move lets the platform move w with the pointer, as a press on a title
// bar does. Call it while handling a `.pointer_down` event from your own title
// bar; it reports whether a move started.
pub fn (mut w Window) start_move() bool {
	return host_start_window_drag(w.backend_native_window())
}

// minimize sends w to the Dock or taskbar.
pub fn (mut w Window) minimize() bool {
	return host_minimize_window(w.backend_native_window())
}

// toggle_maximize maximizes w, or restores it when it already is (zoom on
// macOS), as a double click on a title bar does.
pub fn (mut w Window) toggle_maximize() bool {
	return host_toggle_maximize_window(w.backend_native_window())
}

// is_maximized reports whether w is maximized (zoomed).
pub fn (w &Window) is_maximized() bool {
	return host_window_is_maximized(w.backend_native_window())
}

// controls_leading_inset is how much room the platform's own window controls
// take at the leading edge of w's hidden title bar: macOS's close, minimize
// and zoom buttons. Elsewhere it is zero.
pub fn (w &Window) controls_leading_inset() f64 {
	return host_window_controls_leading_inset(w.backend_native_window())
}

// window_draws_own_controls reports whether an application with a hidden title
// bar must draw the minimize, maximize and close buttons itself (Windows).
pub fn window_draws_own_controls() bool {
	return host_window_draws_own_controls()
}
