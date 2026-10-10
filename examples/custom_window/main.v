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
mut:
	window_ready bool
}

const custom_window_state = &CustomWindowDemo{}

fn (mut app CustomWindowDemo) prepare_window() {
	if !app.window_ready {
		app.window_ready = configure_custom_window()
		if !app.window_ready {
			ui2.request_refresh()
		}
	}
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
		'increment':   fn (_event ui2.ElementEvent) {
			mut state := unsafe { custom_window_state }
			state.add_completed()
			ui2.refresh()
		}
		'decrement':   fn (_event ui2.ElementEvent) {
			mut state := unsafe { custom_window_state }
			state.remove_completed()
			ui2.refresh()
		}
		'reset':       fn (_event ui2.ElementEvent) {
			mut state := unsafe { custom_window_state }
			state.reset()
			ui2.refresh()
		}
		'close':       fn (_event ui2.ElementEvent) {
			ui2.quit()
			ui2.refresh()
		}
		'window_drag': fn (event ui2.ElementEvent) {
			if event.kind == .pointer_down { drag_custom_window() }
			ui2.refresh()
		}
	}
}

fn main() {
	ui2.run_compiled_vml[CustomWindowDemo](
		build:  build_custom_window
		model:  custom_window_state
		title:  'ui2 custom window'
		width:  custom_window_width
		height: custom_window_height
		update: update_custom_window
	) or { panic(err) }
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
