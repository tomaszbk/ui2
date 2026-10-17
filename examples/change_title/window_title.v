module main

import gg
import sokol.sapp

// The window is sokol's on every OS; it ignores the title where there is no
// caption to show it in. Tests run without a window, so there is nothing to
// retitle.
fn apply_window_title(title string) {
	if !sapp.isvalid() {
		return
	}
	gg.set_window_title(title)
}
