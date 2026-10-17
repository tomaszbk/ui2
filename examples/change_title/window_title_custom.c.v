// vfmt off
module main

$if android || linux || ((macos || windows) && ui2_custom_rendering ?) {
	import gg
	import sokol.sapp

	fn apply_window_title(title string) {
		// Tests run without a window, so there is nothing to retitle.
		if !sapp.isvalid() { return }
		gg.set_window_title(title)
	}
}
