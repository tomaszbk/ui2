// vfmt off
@[has_globals]
module ui2

$if (android || linux || ((macos || windows) && ui2_custom_rendering ?)) && !ui2_headless ? {
	import gg

	// Sokol CHAR carries no physical key identity. Associate only the next
	// matching character with a consumed key-down, never all text while a key
	// remains held. Held activation keys separately consume their autorepeats
	// even when the first callback moved focus into an editor.
	struct CustomKeyboardState {
	mut:
		enter bool
		keypad_enter bool
		space bool
		pending KeyCode = .invalid
	}

	__global g_custom_keyboard = CustomKeyboardState{}

	fn (keyboard &CustomKeyboardState) held(key gg.KeyCode) bool {
		return match key {
			.enter { keyboard.enter }
			.kp_enter { keyboard.keypad_enter }
			.space { keyboard.space }
			else { false }
		}
	}

	fn (mut keyboard CustomKeyboardState) set_held(key gg.KeyCode, held bool) {
		match key {
			.enter { keyboard.enter = held }
			.kp_enter { keyboard.keypad_enter = held }
			.space { keyboard.space = held }
			else {}
		}
	}

	fn custom_key_down(event &gg.Event, skip_dispatch bool, composing bool) bool {
		g_custom_keyboard.pending = .invalid
		mut consumed := !skip_dispatch && event.key_repeat && g_custom_keyboard.held(event.key_code)
		if !skip_dispatch {
			if consumed {
				// Observers still receive the event, but the original press owns
				// it before a newly opened menu can treat it as a selection.
				dispatch_key_event(event)
			} else {
				consumed = menu_bar_handle_key(event)
				if !consumed && g_open_dropdown.len > 0 { consumed = handle_dropdown_key(event.key_code) }
				if !consumed { consumed = dispatch_key_event(event) }
			}
			if !consumed && !composing { consumed = handle_focus_key(immediate_key_event(event), event.key_repeat) }
		}
		if !event.key_repeat { g_custom_keyboard.set_held(event.key_code, consumed) }
		if consumed {
			g_custom_keyboard.pending = unsafe { KeyCode(int(event.key_code)) }
		}
		return consumed
	}

	fn custom_key_up(key gg.KeyCode) {
		g_custom_keyboard.set_held(key, false)
		g_custom_keyboard.pending = .invalid
	}

	fn custom_consumed_character(character u32) bool {
		pending := g_custom_keyboard.pending
		g_custom_keyboard.pending = .invalid
		return match pending {
			.space { character == ` ` }
			.tab { character == `\t` }
			.enter, .kp_enter { character in [u32(`\r`), u32(`\n`)] }
			else { false }
		}
	}
}
