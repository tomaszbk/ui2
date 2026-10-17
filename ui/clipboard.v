module ui2

// clipboard_supported reports whether this platform has a system clipboard
// set_clipboard_text and clipboard_text can reach. Linux needs wl-clipboard,
// xclip or xsel installed; Android has none this layer can drive.
pub fn clipboard_supported() bool {
	return host_clipboard_supported()
}

// set_clipboard_text replaces the system clipboard with plain text, as a copy
// button does. It reports whether the platform took it. Text fields keep
// handling their own copy and paste; this is for copying anything else.
pub fn set_clipboard_text(text string) bool {
	return host_set_clipboard_text(text)
}

// clipboard_text returns the plain text on the system clipboard, or none when
// it holds no text or the platform has no clipboard this layer can read.
pub fn clipboard_text() ?string {
	return host_clipboard_text()
}
