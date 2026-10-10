// vfmt off
@[has_globals]
module ui2

$if (android || linux || ((macos || windows) && ui2_custom_rendering ?)) && !ui2_headless ? && !ui2_document_library ? {
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

	// A key belongs to the captured app, scheduler and mounted window. The
	// generation is owned by the window, never copied by capture/restore.
	// Blur, teardown, another key or a window switch invalidates continuations,
	// even if a nested callback restores the same window before returning.
	struct CustomInputDispatch {
		app &GgApp
		scheduler &FrameCoordinator
		window &CustomWindowState
		generation u64
	}

	fn custom_input_dispatch(app &GgApp) CustomInputDispatch {
		if g_active_custom_window_state == unsafe { nil } {
			adopt_custom_window_state()
		}
		return CustomInputDispatch{
			app: app
			scheduler: app.scheduler
			window: g_active_custom_window_state
			generation: g_active_custom_window_state.input_generation
		}
	}

	fn begin_custom_input_dispatch(app &GgApp) CustomInputDispatch {
		custom_input_dispatch(app)
		g_active_custom_window_state.input_generation++
		return custom_input_dispatch(app)
	}

	fn (dispatch CustomInputDispatch) owner_current() bool {
		return dispatch.app == g_gg_app
			&& dispatch.window == g_active_custom_window_state
			&& dispatch.scheduler == dispatch.app.scheduler
			&& !dispatch.scheduler.is_closed()
	}

	fn (dispatch CustomInputDispatch) valid() bool {
		return dispatch.owner_current() && dispatch.generation == dispatch.window.input_generation
	}

	fn own_custom_activation(code KeyCode) {
		g_custom_keyboard.set_held(unsafe { gg.KeyCode(int(code)) }, true)
		g_custom_keyboard.pending = code
	}

	fn reset_custom_keyboard() {
		if g_active_custom_window_state != unsafe { nil } {
			g_active_custom_window_state.input_generation++
		}
		g_custom_keyboard = CustomKeyboardState{}
	}

	fn custom_key_down(event &gg.Event, skip_dispatch bool, composing bool, dispatch CustomInputDispatch) bool {
		// Invalidation claims the event: callers and the native text host must
		// not reinterpret it as an editor command in a different context.
		if !dispatch.valid() { return true }
		g_custom_keyboard.pending = .invalid
		mut consumed := !skip_dispatch && event.key_repeat && g_custom_keyboard.held(event.key_code)
		if !skip_dispatch {
			if consumed {
				// Observers still receive owned repeats, before any new menu.
				dispatch_key_event(event, dispatch)
				if !dispatch.valid() { return true }
			} else {
				consumed = menu_bar_handle_key(event)
				if !dispatch.valid() { return true }
				if !consumed && g_open_dropdown.len > 0 {
					consumed = handle_dropdown_key(event.key_code)
					if !dispatch.valid() { return true }
				}
				if !consumed {
					consumed = dispatch_key_event(event, dispatch)
					if !dispatch.valid() { return true }
				}
			}
			if !consumed && !composing {
				consumed = handle_focus_key(immediate_key_event(event), event.key_repeat)
				if !dispatch.valid() { return true }
			}
		}
		if !event.key_repeat { g_custom_keyboard.set_held(event.key_code, consumed) }
		if consumed {
			g_custom_keyboard.pending = unsafe { KeyCode(int(event.key_code)) }
		}
		return consumed
	}

	fn custom_character_input(app &GgApp, character u32) CustomInputDispatch {
		dispatch := begin_custom_input_dispatch(app)
		if dispatch.valid() {
			app.scheduler.invalidate(.build)
			if !custom_consumed_character(character) { handle_char_input(character) }
		}
		return dispatch
	}

	fn custom_key_up(key gg.KeyCode) {
		if g_active_custom_window_state != unsafe { nil } {
			g_active_custom_window_state.input_generation++
		}
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
