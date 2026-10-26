module main

// vml: transitions.vml

import math
import ui2

const transitions_width = 640
const transitions_height = 500
const transition_logo_size = 82.0

@[heap]
pub struct TransitionsDemo {
pub mut:
	progress     f64
	moving       bool
	target_label string = 'Top left'
	status       string = 'Press Slide to move through the canvas.'
	target_x     f64    = 24
	target_y     f64    = 24
mut:
	target_index int
}

const transitions_state = &TransitionsDemo{}

fn transition_target(index int, width f64, height f64) (f64, f64, string) {
	max_x := math.max(24.0, width - transition_logo_size - 24.0)
	max_y := math.max(24.0, height - transition_logo_size - 24.0)
	return match index {
		1 { max_x, max_y, 'Bottom right' }
		2 { max_x, 24.0, 'Top right' }
		3 { 24.0, max_y, 'Bottom left' }
		4 { (width - transition_logo_size) / 2.0, (height - transition_logo_size) / 2.0, 'Center' }
		else { 24.0, 24.0, 'Top left' }
	}
}

fn (mut app TransitionsDemo) select_target(stage_width f64, stage_height f64) {
	app.target_index = (app.target_index + 1) % 5
	app.target_x, app.target_y, app.target_label = transition_target(app.target_index, stage_width, stage_height)
	app.progress = 0
	app.moving = true
	app.status = 'Moving to ${app.target_label.to_lower()}…'
}

// tile_motion slides the tile from where it is shown to each new target: the
// tile is laid out at the target at once, and its layout transition moves it
// there over 0.75 seconds. A new target while it moves starts from where it is.
fn (app &TransitionsDemo) tile_motion() ui2.MotionConfig {
	return ui2.compose_motion([
		ui2.motion_layout(.position),
		ui2.motion_transition(0.75),
		ui2.motion_easing(.in_out_cubic),
		ui2.motion_on(transition_motion_event),
	])
}

fn transition_motion_event(event ui2.MotionEvent) {
	if event.source != .layout {
		return
	}
	mut state := unsafe { transitions_state }
	match event.kind {
		.progress {
			state.progress = event.progress
		}
		.complete {
			state.progress = 1
			state.moving = false
			state.status = 'Arrived at ${state.target_label.to_lower()}.'
		}
		else {}
	}
}

fn transition_stage_size(frame ui2.Rect) (f64, f64) {
	return frame.width - 68.0, frame.height - 178.0
}

fn transitions_callbacks() map[string]ui2.ElementCallback {
	return {
		'slide': callback_slide
	}
}

fn callback_slide(event ui2.ElementEvent) {
	handle_transitions_event(mut event.window, 'slide')
}

fn handle_transitions_event(mut w ui2.Window, event string) {
	if event != 'slide' {
		return
	}
	frame := w.bounds()
	stage_width, stage_height := transition_stage_size(frame)
	mut state := unsafe { transitions_state }
	state.select_target(stage_width, stage_height)
	w.request_refresh()
}

fn main() {
	ui2.run_compiled_vml[TransitionsDemo](
		build:  build_transitions
		model:  transitions_state
		title:  'Transitions'
		width:  transitions_width
		height: transitions_height
	) or { panic(err) }
}

fn build_transitions(mut app TransitionsDemo) ui2.Element {
	return transitions_vml(mut app)
}

fn transitions_tree(mut app TransitionsDemo, frame ui2.Rect) ui2.Element {
	return transitions_vml_framed(mut app, frame)
}
