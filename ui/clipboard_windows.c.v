// vfmt off
// The Windows host's clipboard (platform.v).
module ui2

#flag windows -luser32

#insert "@VMODROOT/ui/clipboard_windows.h"

fn C.ui2_win_set_clipboard_text(text &u16, units int) int
fn C.ui2_win_clipboard_text() &u16
fn C.wcslen(text &u16) uint

fn host_clipboard_supported() bool {
	return true
}

fn host_set_clipboard_text(text string) bool {
	wide := text.to_wide()
	defer {
		unsafe { free(wide) }
	}
	return C.ui2_win_set_clipboard_text(wide, int(C.wcslen(wide))) != 0
}

fn host_clipboard_text() ?string {
	wide := C.ui2_win_clipboard_text()
	if wide == unsafe { nil } {
		return none
	}
	value := unsafe { string_from_wide(wide) }
	unsafe { C.free(wide) }
	return value
}
