module main

import ui2

const overlays_width = 960
const overlays_height = 680

@[heap]
pub struct OverlayDemo {
pub mut:
	dialog_open    bool = true
	nested_open    bool
	popover_open   bool
	menu_open      bool
	context_open   bool
	tip_open       bool
	reduced_motion bool
	context_point  ?ui2.OverlayPoint
	draft          string = 'Mañana, un café con Sofía.'
	status         string = 'Close the dialog to explore the other surfaces.'
}

pub fn (app &OverlayDemo) surface_motion() ui2.MotionConfig {
	return ui2.MotionConfig{
		enter:            ui2.MotionStyle{ opacity: 0, transform: ui2.VisualTransform{ translate_y: 10, scale_x: 0.98, scale_y: 0.98 } }
		exit:             ui2.MotionStyle{ opacity: 0, transform: ui2.VisualTransform{ translate_y: -6, scale_x: 0.98, scale_y: 0.98 } }
		enter_transition: ui2.MotionTransition{ duration: 0.2, easing: .out_cubic }
		exit_transition:  ui2.MotionTransition{ duration: 0.14, easing: .in_cubic }
		reduced_motion:   app.reduced_motion
	}
}

pub fn (mut app OverlayDemo) open_dialog() { app.dialog_open = true }

pub fn (mut app OverlayDemo) close_dialog() {
	app.nested_open = false
	app.dialog_open = false
	app.status = 'Dialog closed. The draft stays mounted.'
}

pub fn (mut app OverlayDemo) save_draft() {
	app.nested_open = false
	app.dialog_open = false
	app.status = 'Saved: ${app.draft}'
}

pub fn (mut app OverlayDemo) open_nested() { app.nested_open = true }

pub fn (mut app OverlayDemo) close_nested() { app.nested_open = false }

pub fn (mut app OverlayDemo) confirm_nested() {
	app.nested_open = false
	app.status = 'Nested dialog confirmed. Continue editing the same draft.'
}

pub fn (mut app OverlayDemo) toggle_popover() { app.popover_open = !app.popover_open }

pub fn (mut app OverlayDemo) close_popover() { app.popover_open = false }

pub fn (mut app OverlayDemo) toggle_menu() { app.menu_open = !app.menu_open }

pub fn (mut app OverlayDemo) close_menu() { app.menu_open = false }

pub fn (mut app OverlayDemo) show_context() {
	app.context_point = none
	app.context_open = true
}

pub fn (mut app OverlayDemo) open_context(x f64, y f64) {
	app.context_point = ui2.OverlayPoint{ x: x, y: y }
	app.context_open = true
}

pub fn (mut app OverlayDemo) close_context() { app.context_open = false }

pub fn (mut app OverlayDemo) select_action(action string) {
	app.menu_open = false
	app.context_open = false
	app.status = '${action}: ${app.draft}'
}

pub fn (mut app OverlayDemo) show_tip() { app.tip_open = true }

pub fn (mut app OverlayDemo) hide_tip() { app.tip_open = false }

pub fn (mut app OverlayDemo) describe_tip() {
	app.status = 'Keep this button hovered or focused for 0.45 seconds.'
}

pub fn (mut app OverlayDemo) toggle_motion() { app.reduced_motion = !app.reduced_motion }

fn build_overlays(mut app OverlayDemo) ui2.Element { return $vml('overlays.vml') }

fn main() {
	mut app := OverlayDemo{}
	ui2.run_compiled_vml[OverlayDemo](
		build:  build_overlays
		model:  &app
		title:  'Overlay Lab'
		width:  overlays_width
		height: overlays_height
	) or { panic(err) }
}
