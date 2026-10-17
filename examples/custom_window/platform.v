module main

import ui2

// ui2 draws the whole window, so the frame is the host's to give up:
// hidden_titlebar runs the content under macOS's transparent title bar and
// removes the Windows caption (see ui2.Window.set_chrome). Other hosts keep
// their frame, and the header is only decoration there.
fn configure_custom_window(mut window ui2.Window) {
	if ui2.window_chrome_supported(.hidden_titlebar) {
		window.set_chrome(.hidden_titlebar)
	}
}

fn custom_window_uses_transparent_screen() bool {
	return false
}

fn custom_window_screen_background() u32 {
	return u32(0x0f172a)
}

fn custom_window_platform_note() string {
	return if ui2.window_chrome_supported(.hidden_titlebar) {
		'The header replaces the title bar; drag it to move the window.'
	} else {
		'This platform keeps its own window frame.'
	}
}
