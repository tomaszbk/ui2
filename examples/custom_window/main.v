module main

// vml: custom_window.vml

import ui2

const custom_window_width = 440
const custom_window_height = 210

@[heap]
pub struct CustomWindowDemo {
pub mut:
	completed          int
	completed_label    string = 'Nothing completed yet'
	platform_note      string
	transparent_screen bool
	screen_background  u32 = u32(0x0f172a)
}

const custom_window_state = &CustomWindowDemo{}

fn (mut app CustomWindowDemo) prepare_window() {
	app.transparent_screen = custom_window_uses_transparent_screen()
	app.screen_background = custom_window_screen_background()
	app.platform_note = custom_window_platform_note()
}

pub fn (mut app CustomWindowDemo) add_completed() {
	app.completed++
	app.update_completed_label()
}

pub fn (mut app CustomWindowDemo) remove_completed() {
	if app.completed > 0 {
		app.completed--
	}
	app.update_completed_label()
}

pub fn (mut app CustomWindowDemo) reset() {
	app.completed = 0
	app.update_completed_label()
}

fn (mut app CustomWindowDemo) update_completed_label() {
	app.completed_label = match app.completed {
		0 { 'Nothing completed yet' }
		1 { '1 focus session completed' }
		else { '${app.completed} focus sessions completed' }
	}
}

fn custom_window_callbacks() map[string]ui2.ElementCallback {
	return {
		'increment':   callback_increment
		'decrement':   callback_decrement
		'reset':       callback_reset
		'close':       callback_close
		'window_drag': callback_window_drag
	}
}

fn callback_increment(event ui2.ElementEvent) {
	mut state := unsafe { custom_window_state }
	state.add_completed()
	event.window.request_refresh()
}

fn callback_decrement(event ui2.ElementEvent) {
	mut state := unsafe { custom_window_state }
	state.remove_completed()
	event.window.request_refresh()
}

fn callback_reset(event ui2.ElementEvent) {
	mut state := unsafe { custom_window_state }
	state.reset()
	event.window.request_refresh()
}

fn callback_close(event ui2.ElementEvent) {
	event.window.quit()
}

fn callback_window_drag(event ui2.ElementEvent) {
	if event.kind == .pointer_down { event.window.start_move() }
}

fn main() {
	mut app := ui2.new_app()
	mut window := ui2.open_compiled_vml[CustomWindowDemo](mut app,
		build:  build_custom_window
		model:  custom_window_state
		title:  'ui2 custom window'
		width:  custom_window_width
		height: custom_window_height
		update: update_custom_window
	) or { panic(err) }
	// Timers run on the window's first frame, once its native window exists.
	window.after(0, fn [mut window] () {
		configure_custom_window(mut window)
	})
	app.run()
}

fn build_custom_window(mut app CustomWindowDemo) ui2.Element {
	return custom_window_vml(mut app)
}

fn custom_window_tree(mut app CustomWindowDemo, frame ui2.Rect) ui2.Element {
	return custom_window_vml_framed(mut app, frame)
}

fn update_custom_window(mut app CustomWindowDemo) { app.prepare_window() }
