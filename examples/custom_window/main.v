module main

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
		'increment':   fn (event ui2.ElementEvent) {
			mut state := unsafe { custom_window_state }
			state.add_completed()
			event.window.request_refresh()
		}
		'decrement':   fn (event ui2.ElementEvent) {
			mut state := unsafe { custom_window_state }
			state.remove_completed()
			event.window.request_refresh()
		}
		'reset':       fn (event ui2.ElementEvent) {
			mut state := unsafe { custom_window_state }
			state.reset()
			event.window.request_refresh()
		}
		'close':       fn (event ui2.ElementEvent) {
			event.window.quit()
		}
		'window_drag': fn (event ui2.ElementEvent) {
			if event.kind == .pointer_down { event.window.start_move() }
		}
	}
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
	callbacks := custom_window_callbacks()
	callback_window_drag := callbacks['window_drag'] or { panic('missing window_drag callback') }
	callback_close := callbacks['close'] or { panic('missing close callback') }
	callback_decrement := callbacks['decrement'] or { panic('missing decrement callback') }
	callback_reset := callbacks['reset'] or { panic('missing reset callback') }
	callback_increment := callbacks['increment'] or { panic('missing increment callback') }
	return $vml('custom_window.vml')
}

fn custom_window_tree(mut app CustomWindowDemo, frame ui2.Rect) ui2.Element {
	callbacks := custom_window_callbacks()
	callback_window_drag := callbacks['window_drag'] or { panic('missing window_drag callback') }
	callback_close := callbacks['close'] or { panic('missing close callback') }
	callback_decrement := callbacks['decrement'] or { panic('missing decrement callback') }
	callback_reset := callbacks['reset'] or { panic('missing reset callback') }
	callback_increment := callbacks['increment'] or { panic('missing increment callback') }
	return $vml('custom_window.vml', frame)
}

fn update_custom_window(mut app CustomWindowDemo) { app.prepare_window() }
