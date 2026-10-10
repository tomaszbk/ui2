// ui2 profiles: custom (custom font family)
module main

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
		'clear':         fn (_event ui2.ElementEvent) {
			mut state := unsafe { demo_event_state }
			state.clear_events()
			ui2.refresh()
		}
		'sample_button': fn (_event ui2.ElementEvent) {
			mut state := unsafe { demo_event_state }
			state.last_event = 'Native button tapped.'
			state.append_history(state.last_event)
			ui2.refresh()
		}
		'event_surface': fn (event ui2.ElementEvent) {
			mut state := unsafe { demo_event_state }
			state.record_pointer(event)
			ui2.refresh()
		}
	}
}

fn handle_demo_key(key string) {
	mut state := unsafe { demo_event_state }
	state.record_key(key)
	ui2.refresh()
}

fn main() {
	ui2.on_key(handle_demo_key)
	ui2.run_compiled_vml[DemoEvent](
		build:  build_demo_event
		model:  demo_event_state
		title:  'Event Inspector'
		width:  demo_event_width
		height: demo_event_height
	) or { panic(err) }
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
	callbacks := demo_event_callbacks()
	callback_sample_button := callbacks['sample_button'] or { panic('missing sample_button callback') }
	callback_clear := callbacks['clear'] or { panic('missing clear callback') }
	callback_event_surface := callbacks['event_surface'] or { panic('missing event_surface callback') }
	return $vml('demo_event.vml')
}

fn demo_event_tree(mut app DemoEvent, frame ui2.Rect) ui2.Element {
	callbacks := demo_event_callbacks()
	callback_sample_button := callbacks['sample_button'] or { panic('missing sample_button callback') }
	callback_clear := callbacks['clear'] or { panic('missing clear callback') }
	callback_event_surface := callbacks['event_surface'] or { panic('missing event_surface callback') }
	return $vml('demo_event.vml', frame)
}
