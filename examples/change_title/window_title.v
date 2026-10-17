module main

import gg

// The window is sokol's on every OS; it ignores the title where there is no
// caption to show it in.
fn apply_window_title(title string) {
	gg.set_window_title(title)
}
