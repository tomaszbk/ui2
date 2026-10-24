module main

// vml: demo_event.vml

import ui2

const demo_event_width = 680
const demo_event_height = 500

@[heap]
pub struct DemoEvent {
pub mut:
	last_event     string = 'Interact with the blue surface or press a key.'
	history        string
	pointer_events int
	key_events     int
}

const demo_event_state = &DemoEvent{}

fn (mut app DemoEvent) append_history(line string) {
	mut lines := if app.history.len == 0 { []string{} } else { app.history.split_into_lines() }
	lines.insert(0, line)
	if lines.len > 10 {
		lines = lines[..10].clone()
	}
	app.history = lines.join('\n')
}

fn (mut app DemoEvent) record_key(key string) {
	app.last_event = 'Key: ${key}'
	app.key_events++
	app.append_history(app.last_event)
}

fn demo_event_callbacks() map[string]ui2.ElementCallback {
	return {
		'clear':         callback_clear
		'sample_button': callback_sample_button
		'event_surface': callback_event_surface
	}
}

fn callback_clear(event ui2.ElementEvent) {
	mut state := unsafe { demo_event_state }
	state.clear_events()
	event.window.request_refresh()
}

fn callback_sample_button(event ui2.ElementEvent) {
	mut state := unsafe { demo_event_state }
	state.last_event = 'Native button tapped.'
	state.append_history(state.last_event)
	event.window.request_refresh()
}

fn callback_event_surface(event ui2.ElementEvent) {
	mut state := unsafe { demo_event_state }
	state.record_pointer(event)
	event.window.request_refresh()
}

fn handle_demo_key(mut w ui2.Window, key string) {
	mut state := unsafe { demo_event_state }
	state.record_key(key)
	w.request_refresh()
}

fn main() {
	mut app := ui2.new_app()
	mut window := ui2.open_compiled_vml[DemoEvent](mut app,
		build:  build_demo_event
		model:  demo_event_state
		title:  'Event Inspector'
		width:  demo_event_width
		height: demo_event_height
	) or { panic(err) }
	window.on_key(handle_demo_key)
	app.run()
}

fn (mut app DemoEvent) clear_events() {
	app.last_event = 'Event log cleared.'
	app.history = ''
	app.pointer_events = 0
	app.key_events = 0
}

fn (mut app DemoEvent) record_pointer(event ui2.ElementEvent) {
	if event.kind !in [.pointer_down, .pointer_drag, .pointer_up] { return }
	phase := match event.kind {
		.pointer_down { 'down' }
		.pointer_drag { 'drag' }
		else { 'up' }
	}
	app.last_event = 'Pointer ${phase} at (${event.x:g}, ${event.y:g}).'
	app.pointer_events++
	app.append_history(app.last_event)
}

fn build_demo_event(mut app DemoEvent) ui2.Element {
	return demo_event_vml(mut app)
}

fn demo_event_tree(mut app DemoEvent, frame ui2.Rect) ui2.Element {
	return demo_event_vml_framed(mut app, frame)
}
