// The macOS host's clipboard (platform.v): NSPasteboard through the
// Objective-C runtime bridge.
module ui2

import macos

#flag darwin -framework AppKit

const ns_pasteboard_type_string = 'public.utf8-plain-text'

fn host_clipboard_supported() bool {
	return true
}

fn general_pasteboard() macos.Id {
	return macos.msg_id(macos.get_class('NSPasteboard'), 'generalPasteboard')
}

fn host_set_clipboard_text(text string) bool {
	pool := macos.autorelease_pool_new()
	defer {
		macos.release(pool)
	}
	pasteboard := general_pasteboard()
	if pasteboard == unsafe { nil } {
		return false
	}
	macos.msg_i64(pasteboard, 'clearContents')
	objects := macos.msg_id1(macos.get_class('NSArray'), 'arrayWithObject:', macos.nsstring(text))
	return macos.msg_bool_id(pasteboard, 'writeObjects:', objects)
}

fn host_clipboard_text() ?string {
	pool := macos.autorelease_pool_new()
	defer {
		macos.release(pool)
	}
	pasteboard := general_pasteboard()
	if pasteboard == unsafe { nil } {
		return none
	}
	value := macos.msg_id1(pasteboard, 'stringForType:', macos.nsstring(ns_pasteboard_type_string))
	if value == unsafe { nil } {
		return none
	}
	return macos.utf8_string(value)
}
