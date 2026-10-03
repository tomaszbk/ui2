// vfmt off
@[has_globals]
module ui2

$if macos && ui2_embedder ? && ui2_custom_rendering ? && !ui2_headless ? {
	import gg
	import sokol.gfx

	// Capture the dispatcher while creating the window. Its lifetime never
	// changes when another window becomes active, and workers only use post.
	pub struct CustomWindow {
		app &GgApp = unsafe { nil }
	}

	// Native userData is an opaque pointer outside the V collector's roots.
	// A shown window owns its app even if callers retain only its dispatcher.
	__global g_embedder_live_apps = []&GgApp{}

	pub fn open_window(title string, width int, height int, build BuildFn, event EventFn) !CustomWindow {
		return open_embedder_window(title, width, height, 0, 0, build, event)
	}

	pub fn run_windows() {
		C.ui2_embedder_run()
	}

	pub fn (window CustomWindow) dispatcher() UiDispatcher {
		if window.app == unsafe { nil } { return UiDispatcher{} }
		return UiDispatcher{coordinator: window.app.scheduler}
	}

	// Main-thread operations can be directed at a window from another window's
	// handler. Activation is scoped, including nested callbacks during close.
	pub fn (window CustomWindow) update(task fn ()) bool {
		if !C.ui2_embedder_is_main_thread() { return false }
		if window.app == unsafe { nil } || window.app.scheduler.is_closed() { return false }
		mut app := window.app
		previous_app := g_gg_app
		previous_state := activate_custom_window_state(window.app.window_state)
		g_gg_app = window.app
		app.callback_depth++
		defer {
			finish_embedder_callback(window.app)
			activate_custom_window_state(previous_state)
			g_gg_app = previous_app
		}
		task()
		window.app.scheduler.invalidate(.build)
		return true
	}

	pub fn (window CustomWindow) close() {
		if window.app != unsafe { nil } && !window.app.scheduler.is_closed() {
			C.ui2_embedder_close(window.app.native_window)
		}
	}

	// The borrowed NSWindow is for main-thread platform integrations only.
	pub fn (window CustomWindow) native_handle() voidptr {
		if !C.ui2_embedder_is_main_thread() { return unsafe { nil } }
		if window.app == unsafe { nil } || window.app.scheduler.is_closed() { return unsafe { nil } }
		return C.ui2_embedder_native_window(window.app.native_window)
	}

	fn open_embedder_window(title string, width int, height int, min_width int, min_height int,
		build BuildFn, event EventFn) !CustomWindow {
		if !C.ui2_embedder_is_main_thread() { return error('windows must be created on the main thread') }
		if width <= 0 || height <= 0 { return error('window dimensions must be positive') }
		previous_app := g_gg_app
		first := g_active_custom_window_state == unsafe { nil }
		state := if first { adopt_custom_window_state() } else { new_custom_window_state() }
		previous_state := activate_custom_window_state(state)
		mut app := if first { g_gg_app } else { &GgApp{
			scheduler: new_frame_coordinator(g_gg_app.scheduler.policy)
		} }
		app.window_state = state
		g_gg_app = app
		defer {
			activate_custom_window_state(previous_state)
			g_gg_app = previous_app
		}
		g_build_screen = build
		g_event_handler = event
		configure_animation_driver(request_refresh, false)
		publish_menu_context(event, title, unsafe { nil })
		font_regular, font_bold := font_paths()
		device := C.ui2_embedder_metal_device()
		if device == unsafe { nil } { return error('a main-thread Metal device is required') }
		app.ctx = new_surface_draw_context(gg.Config{
			width: width
			height: height
			font_path: font_regular
			custom_bold_font_path: font_bold
			bg_color: hex_color(0xf4f6f8)
		}, gfx.Environment{
			defaults: gfx.EnvironmentDefaults{color_format: .bgra8, depth_format: .@none, sample_count: 1}
			metal: gfx.MetalEnvironment{device: device}
		})!
		g_embedder_live_apps << app
		app.native_window = C.ui2_embedder_create(&C.ui2_embedder_config{
			title: title.str
			width: width
			height: height
			min_width: min_width
			min_height: min_height
			resizable: true
			visible: false
		}, &C.ui2_embedder_callbacks{
			pump: embedder_pump
			event: embedder_event
			text: embedder_text
			closed: embedder_closed
		}, app)
		if app.native_window == unsafe { nil } {
			cleanup_embedder_app(app)
			return error('could not create the native window on the main thread')
		}
		handle := app.native_window
		app.scheduler.set_presentation_required(false)
		app.scheduler.set_wakeup(fn [handle] () { C.ui2_embedder_wakeup(handle) })
		C.ui2_embedder_show(handle)
		return CustomWindow{app: app}
	}

	fn finish_embedder_callback(app &GgApp) {
		mut current := unsafe { app }
		current.callback_depth--
		if current.callback_depth == 0 && current.cleanup_pending {
			cleanup_embedder_app(current)
		}
	}

	fn cleanup_embedder_app(app &GgApp) {
		mut current := unsafe { app }
		if current.ctx == unsafe { nil } { return }
		mut drawing := current.ctx
		on_cleanup(current)
		drawing.destroy()
		discard_custom_window_state(current.window_state)
		current.composition = TextComposition{}
		current.cleanup_pending = false
		for index, live in g_embedder_live_apps {
			if live == app {
				g_embedder_live_apps.delete(index)
				break
			}
		}
	}

	fn embedder_closed(data voidptr) {
		mut app := unsafe { &GgApp(data) }
		previous_app := g_gg_app
		previous_state := activate_custom_window_state(app.window_state)
		g_gg_app = app
		defer {
			activate_custom_window_state(previous_state)
			g_gg_app = previous_app
		}
		app.scheduler.close()
		app.cleanup_pending = true
		if app.callback_depth == 0 { cleanup_embedder_app(app) }
	}

	fn embedder_pump(data voidptr) i64 {
		mut app := unsafe { &GgApp(data) }
		if app.scheduler.is_closed() { return -1 }
		previous_app := g_gg_app
		previous_state := activate_custom_window_state(app.window_state)
		g_gg_app = app
		app.callback_depth++
		defer {
			finish_embedder_callback(app)
			activate_custom_window_state(previous_state)
			g_gg_app = previous_app
		}
		now := renderer_now_ms()
		interval := C.ui2_embedder_frame_interval(app.native_window)
		wake_at := app.scheduler.next_wake(now, app.last_frame, interval)
		if wake_at >= 0 && wake_at <= now {
			drain_custom_tasks(mut app)
			if app.scheduler.is_closed() { return -1 }
			if app.surface_retry_at > now { return app.surface_retry_at - now }
			mut metrics := C.ui2_embedder_surface{}
			C.ui2_embedder_metrics(app.native_window, &metrics)
			app.ctx.set_surface(metrics.width, metrics.height, metrics.dpi_scale, gfx.Swapchain{})
			draws := app.scheduler.stats().draws
			on_frame(mut app)
			if app.scheduler.is_closed() { return -1 }
			if app.scheduler.stats().draws != draws {
				app.last_frame = renderer_now_ms()
			}
			sync_embedder_text(app)
		}
		next := app.scheduler.next_wake(renderer_now_ms(), app.last_frame, interval)
		if next < 0 { return -1 }
		if app.surface_retry_at > renderer_now_ms() { return app.surface_retry_at - renderer_now_ms() }
		return if next <= renderer_now_ms() { i64(0) } else { next - renderer_now_ms() }
	}

	fn acquire_embedder_surface(mut app GgApp) bool {
		mut surface := C.ui2_embedder_surface{}
		if !C.ui2_embedder_acquire_frame(app.native_window, &surface) {
			app.surface_retry_at = renderer_now_ms() + C.ui2_embedder_frame_interval(app.native_window)
			app.scheduler.invalidate(.surface)
			return false
		}
		app.surface_retry_at = -1
		app.ctx.set_surface(surface.width, surface.height, surface.dpi_scale, gfx.Swapchain{
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
		mut app := unsafe { &GgApp(data) }
		if app.scheduler.is_closed() { return false }
		previous_app := g_gg_app
		previous_state := activate_custom_window_state(app.window_state)
		g_gg_app = app
		app.callback_depth++
		defer {
			finish_embedder_callback(app)
			activate_custom_window_state(previous_state)
			g_gg_app = previous_app
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
		if event.typ in [.resized, .restored, .resumed] { app.surface_retry_at = -1 }
		if event.typ == .key_down {
			app.scheduler.invalidate(.build)
			g_tooltip.dismiss()
			if !native.skip_dispatch {
				if menu_bar_handle_key(&event) { return true }
				if g_open_dropdown.len > 0 && handle_dropdown_key(event.key_code) { return true }
				if dispatch_key_event(&event) { return true }
			}
			if !native.text_input && (g_focused_field.len == 0 || app.editable_fields[g_focused_field]) {
				handle_key_down(event.key_code, event.modifiers)
			}
		} else if event.typ == .char && g_focused_field.len > 0 && !app.editable_fields[g_focused_field] {
			return false
		} else if event.typ == .files_dropped {
			if voidptr(g_drop_handler) != unsafe { nil } && native.paths != unsafe { nil } && native.path_count > 0 {
				mut paths := []string{cap: native.path_count}
				for index in 0 .. native.path_count {
					paths << unsafe { cstring_to_vstring(native.paths[index]) }
				}
				g_drop_handler(DropEvent{paths: paths, x: f64(native.x), y: f64(native.y)})
				app.scheduler.invalidate(.build)
			}
		} else {
			on_event(&event, app)
		}
		if !app.scheduler.is_closed() { sync_embedder_text(app) }
		return false
	}

	fn embedder_text(data voidptr, native &C.ui2_embedder_text_event) {
		mut app := unsafe { &GgApp(data) }
		if app.scheduler.is_closed() { return }
		previous_app := g_gg_app
		previous_state := activate_custom_window_state(app.window_state)
		g_gg_app = app
		app.callback_depth++
		defer {
			finish_embedder_callback(app)
			activate_custom_window_state(previous_state)
			g_gg_app = previous_app
		}
		id := g_focused_field
		if id.len == 0 || id !in g_active_fields || !app.editable_fields[id] { return }
		mut editor := g_text_editors[id] or { text_editor((g_text_values[id] or { '' }).clone()) }
		value := if native.text == unsafe { nil } { '' } else { unsafe { cstring_to_vstring(native.text) } }
		if native.kind == 2 {
			app.composition.update(id, editor, value, native.selection_start, native.selection_length,
				native.replacement_start, native.replacement_length)
			app.scheduler.invalidate(.paint)
		} else {
			if native.kind == 3 {
				if app.composition.field_id != id { return }
				app.composition.finish(mut editor)
			} else {
				app.composition.commit(mut editor, value, native.replacement_start, native.replacement_length)
			}
			replace_text_value(id, editor.text)
			replace_text_editor(id, editor)
			fire_field_change(id)
			app.scheduler.invalidate(.build)
		}
		if !app.scheduler.is_closed() { sync_embedder_text(app) }
	}

	fn custom_composition_editor(id string, editor TextEditor) TextEditor {
		if g_gg_app.composition.field_id != id { return editor }
		return g_gg_app.composition.display(editor)
	}

	fn sync_embedder_text(app &GgApp) {
		id := g_focused_field
		editor := g_text_editors[id] or { TextEditor{} }
		display := custom_composition_editor(id, editor)
		start, end := display.selection.ordered()
		marked := app.composition.field_id == id && id.len > 0 && app.composition.mark_length > 0
		caret := app.text_caret
		C.ui2_embedder_sync_text(app.native_window, id.len > 0 && id in g_active_fields && app.editable_fields[id],
			display.text.str, rune_offset_to_utf16(display.text, start),
			rune_offset_to_utf16(display.text, end) - rune_offset_to_utf16(display.text, start),
			if marked { rune_offset_to_utf16(display.text, app.composition.start + app.composition.mark_start) } else { -1 },
			if marked { rune_offset_to_utf16(app.composition.text, app.composition.mark_start + app.composition.mark_length)
				- rune_offset_to_utf16(app.composition.text, app.composition.mark_start) } else { 0 },
			caret.x, caret.y, caret.width, caret.height)
	}
}
