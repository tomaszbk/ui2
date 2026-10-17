// vfmt off
module ui2

$if (android || ios || linux || macos || windows) && !ui2_headless ? && !ui2_document_library ? {
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

	// Input belongs to its window and that window's scheduler. Blur,
	// teardown or newer input advances the window's generation, which
	// invalidates the continuations of earlier input.
	struct CustomInputDispatch {
		window &Window
		scheduler &FrameCoordinator
		generation u64
	}

	fn (mut w Window) custom_input_dispatch() CustomInputDispatch {
		return CustomInputDispatch{
			window: w
			scheduler: w.scheduler
			generation: w.input_generation
		}
	}

	fn (mut w Window) begin_custom_input_dispatch() CustomInputDispatch {
		w.input_generation++
		return w.custom_input_dispatch()
	}

	fn (dispatch CustomInputDispatch) owner_current() bool {
		mut scheduler := dispatch.scheduler
		return voidptr(dispatch.scheduler) == voidptr(dispatch.window.scheduler)
			&& !scheduler.is_closed()
	}

	fn (dispatch CustomInputDispatch) valid() bool {
		return dispatch.owner_current() && dispatch.generation == dispatch.window.input_generation
	}

	fn (mut w Window) own_custom_activation(code KeyCode) {
		w.keyboard.set_held(unsafe { gg.KeyCode(int(code)) }, true)
		w.keyboard.pending = code
	}

	fn (mut w Window) reset_custom_keyboard() {
		w.input_generation++
		w.keyboard = CustomKeyboardState{}
	}

	fn (mut w Window) custom_key_down(event &gg.Event, skip_dispatch bool, composing bool, dispatch CustomInputDispatch) bool {
		// Invalidation claims the event: callers and the native text host must
		// not reinterpret it as an editor command in a different context.
		if !dispatch.valid() { return true }
		w.keyboard.pending = .invalid
		mut consumed := !skip_dispatch && event.key_repeat && w.keyboard.held(event.key_code)
		if !skip_dispatch {
			if consumed {
				// Observers still receive owned repeats, before any new menu.
				w.dispatch_key_event(event, dispatch)
				if !dispatch.valid() { return true }
			} else {
				consumed = w.drawn_popup_menu_key(immediate_key_event(event))
				if !consumed { consumed = w.overlay_key(immediate_key_event(event), event.key_repeat) }
				if !consumed { consumed = w.menu_bar_handle_key(event) }
				if !dispatch.valid() { return true }
				if !consumed && w.dropdown_id.len > 0 {
					consumed = w.handle_dropdown_key(event.key_code)
					if !dispatch.valid() { return true }
				}
				if !consumed {
					consumed = w.dispatch_key_event(event, dispatch)
					if !dispatch.valid() { return true }
				}
			}
			if !consumed && !composing {
				consumed = w.handle_focus_key(immediate_key_event(event), event.key_repeat)
				if !dispatch.valid() { return true }
			}
		}
		if !event.key_repeat { w.keyboard.set_held(event.key_code, consumed) }
		if consumed {
			w.keyboard.pending = unsafe { KeyCode(int(event.key_code)) }
		}
		return consumed
	}

	fn (mut w Window) custom_character_input(character u32) CustomInputDispatch {
		dispatch := w.begin_custom_input_dispatch()
		if dispatch.valid() {
			w.scheduler.invalidate(.build)
			if !w.custom_consumed_character(character) { w.handle_char_input(character) }
		}
		return dispatch
	}

	fn (mut w Window) custom_key_up(key gg.KeyCode) {
		w.input_generation++
		w.keyboard.set_held(key, false)
		w.keyboard.pending = .invalid
	}

	fn (mut w Window) custom_consumed_character(character u32) bool {
		pending := w.keyboard.pending
		w.keyboard.pending = .invalid
		return match pending {
			.space { character == ` ` }
			.tab { character == `\t` }
			.enter, .kp_enter { character in [u32(`\r`), u32(`\n`)] }
			else { false }
		}
	}
}
