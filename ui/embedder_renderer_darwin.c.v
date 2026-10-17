// vfmt off
@[has_globals]
module ui2

$if macos && ui2_embedder ? && !ui2_headless ? && !ui2_document_library ? {
	import gg
	import sokol.gfx

	// update runs task for this window on the main thread and requests its
	// build. Activation is scoped, including nested callbacks during close.
	// It returns false for a closed window or a call from another thread.
	pub fn (mut w Window) update(task fn ()) bool {
		if !C.ui2_embedder_is_main_thread() { return false }
		if w.scheduler.is_closed() { return false }
		previous_state := activate_custom_window_state(w.window_state)
		w.callback_depth++
		defer {
			w.finish_embedder_callback()
			activate_custom_window_state(previous_state)
		}
		task()
		w.scheduler.invalidate(.build)
		return true
	}

	// The borrowed NSWindow is for main-thread platform integrations only.
	pub fn (w &Window) native_handle() voidptr {
		if !C.ui2_embedder_is_main_thread() { return unsafe { nil } }
		if w.scheduler.is_closed() { return unsafe { nil } }
		return C.ui2_embedder_native_window(w.native_window)
	}

	// Native userData is an opaque pointer outside the V collector's roots: the
	// app's window list keeps a shown window alive until it closes.
	fn (mut app App) open_embedder_window(config WindowConfig) !&Window {
		if !C.ui2_embedder_is_main_thread() { return error('windows must be created on the main thread') }
		first := g_active_custom_window_state == unsafe { nil }
		state := if first { adopt_custom_window_state() } else { new_custom_window_state() }
		previous_state := activate_custom_window_state(state)
		defer {
			activate_custom_window_state(previous_state)
		}
		mut w := &Window{
			app: app
			title: config.title
			width: config.width
			height: config.height
			min_width: config.min_width
			min_height: config.min_height
			build: config.build
			window_state: state
		}
		set_window_wake(fn [mut app] (reason RenderReason) {
			for mut window in app.windows { window.backend_invalidate(reason) }
		})
		font_regular, font_bold := font_paths()
		device := C.ui2_embedder_metal_device()
		if device == unsafe { nil } { return error('a main-thread Metal device is required') }
		w.ctx = new_surface_draw_context(gg.Config{
			width: config.width
			height: config.height
			font_path: font_regular
			custom_bold_font_path: font_bold
			bg_color: hex_color(0xf4f6f8)
		}, gfx.Environment{
			defaults: gfx.EnvironmentDefaults{color_format: .bgra8, depth_format: .@none, sample_count: 1}
			metal: gfx.MetalEnvironment{device: device}
		})!
		w.native_window = C.ui2_embedder_create(&C.ui2_embedder_config{
			title: config.title.str
			width: config.width
			height: config.height
			min_width: config.min_width
			min_height: config.min_height
			resizable: true
			visible: false
		}, &C.ui2_embedder_callbacks{
			pump: embedder_pump
			event: embedder_event
			text: embedder_text
			closed: embedder_closed
		}, w)
		if w.native_window == unsafe { nil } {
			w.cleanup_embedder_window()
			return error('could not create the native window on the main thread')
		}
		handle := w.native_window
		w.scheduler.set_presentation_required(false)
		w.scheduler.set_wakeup(fn [handle] () { C.ui2_embedder_wakeup(handle) })
		// The embedder has made NSApp and the window by now, so the host can
		// install the declared menus over the embedder's default ones.
		w.os_window = C.ui2_embedder_native_window(handle)
		w.install_declared_menus()
		C.ui2_embedder_show(handle)
		return w
	}

	fn (mut w Window) finish_embedder_callback() {
		w.callback_depth--
		if w.callback_depth == 0 && w.cleanup_pending {
			w.cleanup_embedder_window()
		}
	}

	fn (mut w Window) cleanup_embedder_window() {
		if w.ctx == unsafe { nil } { return }
		mut drawing := w.ctx
		on_cleanup(mut w)
		drawing.destroy()
		discard_custom_window_state(w.window_state)
		w.composition = TextComposition{}
		w.cleanup_pending = false
		mut app := w.app
		app.forget_window(w)
	}

	fn embedder_closed(data voidptr) {
		mut w := unsafe { &Window(data) }
		previous_state := activate_custom_window_state(w.window_state)
		defer {
			activate_custom_window_state(previous_state)
		}
		w.cancel_touch()
		w.reset_custom_keyboard()
		w.scheduler.close()
		w.cleanup_pending = true
		if w.callback_depth == 0 { w.cleanup_embedder_window() }
	}

	fn embedder_pump(data voidptr) i64 {
		mut w := unsafe { &Window(data) }
		if w.scheduler.is_closed() { return -1 }
		previous_state := activate_custom_window_state(w.window_state)
		w.callback_depth++
		defer {
			w.finish_embedder_callback()
			activate_custom_window_state(previous_state)
		}
		now := renderer_now_ms()
		interval := C.ui2_embedder_frame_interval(w.native_window)
		wake_at := w.scheduler.next_wake(now, w.last_frame, interval)
		if wake_at >= 0 && wake_at <= now {
			dispatch := w.custom_input_dispatch()
			ctx := w.ctx
			w.drain_custom_tasks()
			if w.scheduler.is_closed() { return -1 }
			if !dispatch.valid() || w.ctx != ctx { return 0 }
			if w.surface_retry_at > now { return w.surface_retry_at - now }
			mut metrics := C.ui2_embedder_surface{}
			C.ui2_embedder_metrics(w.native_window, &metrics)
			w.ctx.set_surface(metrics.width, metrics.height, metrics.dpi_scale, gfx.Swapchain{})
			draws := w.scheduler.stats().draws
			on_frame(mut w)
			if w.scheduler.is_closed() { return -1 }
			if custom_frame_current(dispatch, ctx) {
				if w.scheduler.stats().draws != draws {
					w.last_frame = renderer_now_ms()
				}
				w.sync_embedder_text()
			}
		}
		next := w.scheduler.next_wake(renderer_now_ms(), w.last_frame, interval)
		if next < 0 { return -1 }
		if w.surface_retry_at > renderer_now_ms() { return w.surface_retry_at - renderer_now_ms() }
		return if next <= renderer_now_ms() { i64(0) } else { next - renderer_now_ms() }
	}

	fn (mut w Window) acquire_embedder_surface() bool {
		mut surface := C.ui2_embedder_surface{}
		if !C.ui2_embedder_acquire_frame(w.native_window, &surface) {
			w.surface_retry_at = renderer_now_ms() + C.ui2_embedder_frame_interval(w.native_window)
			w.scheduler.invalidate(.surface)
			return false
		}
		w.surface_retry_at = -1
		w.ctx.set_surface(surface.width, surface.height, surface.dpi_scale, gfx.Swapchain{
			width: surface.framebuffer_width
			height: surface.framebuffer_height
			sample_count: 1
			color_format: .bgra8
			depth_format: .@none
			metal: gfx.MetalSwapchain{current_drawable: surface.drawable}
		})
		return true
	}

	fn embedder_event(data voidptr, native &C.ui2_embedder_event) bool {
		mut w := unsafe { &Window(data) }
		if w.scheduler.is_closed() { return false }
		previous_state := activate_custom_window_state(w.window_state)
		w.callback_depth++
		defer {
			w.finish_embedder_callback()
			activate_custom_window_state(previous_state)
		}
		mut event := gg.Event{
			typ: match native.kind {
				1 { .mouse_down } 2 { .mouse_up } 3 { .mouse_move }
				4 { .mouse_enter } 5 { .mouse_leave } 6 { .mouse_scroll }
				7 { .key_down } 8 { .key_up } 9 { .char }
				10 { .resized } 11 { .focused } 12 { .unfocused }
				13 { .iconified } 14 { .restored } 15 { .suspended }
				16 { .resumed } 17 { .files_dropped } else { .invalid }
			}
			key_code: unsafe { gg.KeyCode(native.key_code) }
			mouse_button: unsafe { gg.MouseButton(native.mouse_button) }
			char_code: native.char_code
			modifiers: native.modifiers
			key_repeat: native.repeat
			mouse_x: native.x
			mouse_y: native.y
			scroll_x: native.scroll_x
			scroll_y: native.scroll_y
		}
		dispatch_context := w.custom_input_dispatch()
		if event.typ in [.resized, .restored, .resumed] { w.surface_retry_at = -1 }
		if event.typ == .mouse_down {
			if event.mouse_button == .right {
				w.custom_context_press(f64(event.mouse_x), f64(event.mouse_y))
				if dispatch_context.valid() { w.sync_embedder_text() }
				return false
			}
			dispatch := w.custom_mouse_down(f64(event.mouse_x), f64(event.mouse_y))
			if dispatch.valid() { w.sync_embedder_text() }
			return false
		} else if event.typ == .key_down {
			w.scheduler.invalidate(.build)
			if w.drag_owned_escape(event.key_code) { return true }
			w.tooltip.dismiss()
			dispatch := w.begin_custom_input_dispatch()
			if w.custom_key_down(&event, native.skip_dispatch,
				native.text_input && w.composition.field_id.len > 0, dispatch) {
				if dispatch.valid() { w.sync_embedder_text() }
				return true
			}
			if !dispatch.valid() { return true }
			// Readonly editors still own navigation and selection. The editor
			// handler guards mutations; Cocoa text input remains editable-only.
			if !native.text_input {
				w.handle_key_down(event.key_code, event.modifiers)
			}
			if !dispatch.valid() { return true }
			w.sync_embedder_text()
			return false
		} else if event.typ == .char {
			if w.focused_field.len > 0 && !w.editable_fields[w.focused_field] { return false }
			dispatch := w.custom_character_input(event.char_code)
			if dispatch.valid() { w.sync_embedder_text() }
			return false
		} else if event.typ == .files_dropped {
			if voidptr(w.drop_handler) != unsafe { nil } && native.paths != unsafe { nil } && native.path_count > 0 {
				mut paths := []string{cap: native.path_count}
				for index in 0 .. native.path_count {
					paths << unsafe { cstring_to_vstring(native.paths[index]) }
				}
				w.drop_handler(DropEvent{window: w, paths: paths, x: f64(native.x), y: f64(native.y)})
				if !dispatch_context.valid() { return false }
				w.scheduler.invalidate(.build)
			}
		} else {
			on_event(&event, mut w)
		}
		if dispatch_context.valid() { w.sync_embedder_text() }
		return false
	}

	fn embedder_text(data voidptr, native &C.ui2_embedder_text_event) {
		mut w := unsafe { &Window(data) }
		if w.scheduler.is_closed() { return }
		previous_state := activate_custom_window_state(w.window_state)
		w.callback_depth++
		defer {
			w.finish_embedder_callback()
			activate_custom_window_state(previous_state)
		}
		dispatch := w.begin_custom_input_dispatch()
		id := w.focused_field
		// NSTextInputClient text/IME deliveries have their own provenance and
		// must never inherit a pending Sokol character from a physical key.
		w.keyboard.pending = .invalid
		if id.len == 0 || id !in w.active_fields || !w.editable_fields[id] { return }
		mut editor := w.text_editors[id] or { text_editor((w.text_values[id] or { '' }).clone()) }
		value := if native.text == unsafe { nil } { '' } else { unsafe { cstring_to_vstring(native.text) } }
		if native.kind == 2 {
			w.composition.update(id, editor, value, native.selection_start, native.selection_length,
				native.replacement_start, native.replacement_length)
			w.scheduler.invalidate(.paint)
		} else {
			if native.kind == 3 {
				if w.composition.field_id != id { return }
				w.composition.finish(mut editor)
			} else {
				w.composition.commit(mut editor, value, native.replacement_start, native.replacement_length)
			}
			w.replace_text_value(id, editor.text)
			w.replace_text_editor(id, editor)
			w.fire_field_change(id)
			if !dispatch.valid() { return }
			w.scheduler.invalidate(.build)
		}
		if dispatch.valid() { w.sync_embedder_text() }
	}

	fn (mut w Window) custom_composition_editor(id string, editor TextEditor) TextEditor {
		if w.composition.field_id != id { return editor }
		return w.composition.display(editor)
	}

	fn (mut w Window) sync_embedder_text() {
		id := w.focused_field
		editor := w.text_editors[id] or { TextEditor{} }
		display := w.custom_composition_editor(id, editor)
		start, end := display.selection.ordered()
		marked := w.composition.field_id == id && id.len > 0 && w.composition.mark_length > 0
		caret := w.text_caret
		C.ui2_embedder_sync_text(w.native_window, id.len > 0 && id in w.active_fields && w.editable_fields[id],
			display.text.str, rune_offset_to_utf16(display.text, start),
			rune_offset_to_utf16(display.text, end) - rune_offset_to_utf16(display.text, start),
			if marked { rune_offset_to_utf16(display.text, w.composition.start + w.composition.mark_start) } else { -1 },
			if marked { rune_offset_to_utf16(w.composition.text, w.composition.mark_start + w.composition.mark_length)
				- rune_offset_to_utf16(w.composition.text, w.composition.mark_start) } else { 0 },
			caret.x, caret.y, caret.width, caret.height)
	}
}
