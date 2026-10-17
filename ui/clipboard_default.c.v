// Fallback for targets with no clipboard this layer can drive — Android, whose
// ClipboardManager needs a JVM callback the C backend cannot install.
module ui2

fn native_clipboard_supported() bool {
	return false
}

fn native_set_clipboard_text(_text string) bool {
	return false
}

fn native_clipboard_text() ?string {
	return none
}
