module main

import ui2

const child_window_width = 640
const child_window_height = 440
const child_window_vml_source = $embed_file('child_window.vml').to_string()
const child_card_root_x = 16.0
const child_card_root_y = 16.0
const child_panel_width = 320.0
const child_panel_height = 232.0
const child_cascade_step = 26.0

// ui2 owns a single native window, so the child window the original example
// opens becomes a movable panel inside it: same controls, same greeting, and
// the same independence from the field in the parent card.
@[heap]
pub struct ChildWindowDemo {
pub mut:
	open        bool
	panel_x     f64 = 40
	panel_y     f64 = 96
	name        string
	woman       bool
	opened      int
	title       string = 'Child window 1'
	status      string = 'Create a window, type a name, then greet yourself.'
	parent_text string
mut:
	grab_x f64
	grab_y f64
}

const child_window_state = &ChildWindowDemo{}

pub fn greeting(name string, woman bool) string {
	genre := if woman { 'miss' } else { 'mister' }
	trimmed := name.trim_space()
	who := if trimmed.len > 0 { trimmed } else { 'anonymous' }
	return 'Hello, ${genre} ${who}!'
}

pub fn (mut app ChildWindowDemo) create_window() {
	app.opened++
	app.open = true
	app.title = 'Child window ${app.opened}'
	// Cascade the panel the way a window manager does, wrapping before it walks
	// off the card.
	step := f64((app.opened - 1) % 5) * child_cascade_step
	app.panel_x = 40 + step
	app.panel_y = 96 + step
	app.status = '${app.title} opened. Drag its title bar to move it.'
}

pub fn (mut app ChildWindowDemo) close_window() {
	app.open = false
	app.status = 'Child window closed; the parent field kept its own text.'
}

pub fn (mut app ChildWindowDemo) set_name(name string) {
	app.name = name
}

pub fn (mut app ChildWindowDemo) toggle_woman() {
	app.woman = !app.woman
}

pub fn (mut app ChildWindowDemo) greet() {
	message := greeting(app.name, app.woman)
	app.status = message
	ui2.alert('Greeting', message)
}

pub fn (mut app ChildWindowDemo) grab_panel(x f64, y f64) {
	app.grab_x = x - child_card_root_x - app.panel_x
	app.grab_y = y - child_card_root_y - app.panel_y
}

pub fn (mut app ChildWindowDemo) drag_panel(x f64, y f64, card_width f64, card_height f64) {
	app.panel_x = clamp_panel(x - child_card_root_x - app.grab_x, 12, card_width - child_panel_width - 12)
	app.panel_y = clamp_panel(y - child_card_root_y - app.grab_y, 12, card_height - child_panel_height - 12)
}

fn clamp_panel(value f64, low f64, high f64) f64 {
	if high < low {
		return low
	}
	if value < low {
		return low
	}
	return if value > high { high } else { value }
}

fn child_card_size(frame ui2.Rect) (f64, f64) {
	return frame.width - 32.0, frame.height - 32.0
}

fn child_window_callbacks() map[string]ui2.ElementCallback {
	return {
		'create':         fn (_event ui2.ElementEvent) {
			mut state := unsafe { child_window_state }
			state.create_window()
			ui2.refresh()
		}
		'close':          fn (_event ui2.ElementEvent) {
			mut state := unsafe { child_window_state }
			state.close_window()
			ui2.refresh()
		}
		'greet':          fn (_event ui2.ElementEvent) {
			mut state := unsafe { child_window_state }
			state.greet()
			ui2.refresh()
		}
		'child_name':     fn (event ui2.ElementEvent) {
			mut state := unsafe { child_window_state }
			state.set_name(event.text)
			ui2.refresh()
		}
		'genre':          fn (event ui2.ElementEvent) {
			mut state := unsafe { child_window_state }
			state.woman = event.checked
			ui2.refresh()
		}
		'parent_input':   fn (event ui2.ElementEvent) {
			mut state := unsafe { child_window_state }
			state.parent_text = event.text
			ui2.refresh()
		}
		'child_titlebar': fn (event ui2.ElementEvent) {
			mut state := unsafe { child_window_state }
			card_width, card_height := child_card_size(ui2.bounds())
			match event.kind {
				.pointer_down { state.grab_panel(event.x, event.y) }
				.pointer_drag, .pointer_up {
					state.drag_panel(event.x, event.y, card_width, card_height)
				}
				else {}
			}
			ui2.refresh()
		}
	}
}

fn build_child_window_screen() ui2.Element {
	state := unsafe { child_window_state }
	return ui2.element_from_vml_model_with_callbacks(child_window_vml_source, *state, ui2.bounds(), child_window_callbacks()) or {
		eprintln('child-window VML failed: ${err}')
		ui2.screen(0xf1f5f9, [])
	}
}

fn main() {
	ui2.run_window('Child Window', child_window_width, child_window_height, build_child_window_screen)
}
