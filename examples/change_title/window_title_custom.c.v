// vfmt off
module main

$if android || linux || ((macos || windows) && ui2_custom_rendering ?) {
	import gg
	import ui2

	fn apply_window_title(title string) {
		// The headless backend (tests) has no window to retitle.
		if ui2.backend_name == 'headless' { return }
		gg.set_window_title(title)
	}
}
