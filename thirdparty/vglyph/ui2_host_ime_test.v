module vglyph

fn ui2_host_ime_marked(_ &char, _ i32, _ voidptr) {
	panic('host-owned vglyph must not receive native marked text')
}

fn ui2_host_ime_insert(_ &char, _ voidptr) {
	panic('host-owned vglyph must not receive native committed text')
}

fn ui2_host_ime_unmark(_ voidptr) {
	panic('host-owned vglyph must not receive native composition events')
}

fn ui2_host_ime_bounds(_ voidptr, _ &f32, _ &f32, _ &f32, _ &f32) bool {
	panic('host-owned vglyph must not request native candidate bounds')
}

fn ui2_host_ime_clause(_ i32, _ i32, _ i32, _ voidptr) {
	panic('host-owned vglyph must not receive native composition clauses')
}

fn ui2_host_ime_clauses(_ voidptr) {
	panic('host-owned vglyph must not receive native clause enumeration')
}

fn test_host_owned_ime_does_not_access_host_views_or_consume_input() {
	$if vglyph_native_ime ? {
		// This fixture verifies the default profile used by UI2. The optional
		// standalone native bridge requires its own platform integration tests.
	} $else {
		// These opaque host tokens deliberately are not Cocoa/MTKView pointers.
		// Hosted text APIs must not inspect them or change the host's focus.
		host := voidptr(1)
		assert ime_discover_mtkview(host) == unsafe { nil }
		assert ime_overlay_create_auto(host) == unsafe { nil }
		assert ime_overlay_create(host) == unsafe { nil }
		ime_register_callbacks(ui2_host_ime_marked, ui2_host_ime_insert, ui2_host_ime_unmark,
			ui2_host_ime_bounds, host)
		ime_overlay_register_callbacks(host, ui2_host_ime_marked, ui2_host_ime_insert,
			ui2_host_ime_unmark, ui2_host_ime_bounds, ui2_host_ime_clause, ui2_host_ime_clauses,
			ui2_host_ime_clauses, host)
		ime_overlay_set_focused_field(host, 'editor')
		ime_linux_focus_in()
		ime_linux_set_cursor_location(10, 20, 1, 24)
		assert !ime_linux_filter_key(0x41, 38, 0, false)
		assert !ime_did_handle_key()
		assert !ime_has_marked_text()
		ime_overlay_set_focused_field(host, '')
		ime_linux_focus_out()
		ime_overlay_free(host)
		assert !ime_did_handle_key()
		assert !ime_has_marked_text()
	}
}
