module main

// vml: app.vml

import ui2

pub struct MotionRow {
pub:
	id    string
	title string
}

pub struct MotionApp {
pub mut:
	shown   bool = true
	moved   bool
	reduced bool
	rows    []MotionRow = [MotionRow{ id: 'one', title: 'First card' },
		MotionRow{ id: 'two', title: 'Second card' }]
	cleaned int
}

pub fn (app &MotionApp) panel_motion() ui2.MotionConfig {
	return ui2.MotionConfig{
		enter:            ui2.MotionStyle{ opacity: 0, translate_y: 18, scale_x: 0.96, scale_y: 0.96 }
		exit:             ui2.MotionStyle{ opacity: 0, translate_y: -18, scale_x: 0.96, scale_y: 0.96 }
		enter_transition: ui2.MotionTransition{ duration: 0.25, easing: .out_cubic }
		exit_transition:  ui2.MotionTransition{ duration: 0.2, easing: .in_cubic }
		transition:       ui2.MotionTransition{ duration: 0.35, easing: .in_out_cubic }
		reduced_motion:   app.reduced
	}
}

pub fn (mut app MotionApp) toggle_panel() { app.shown = !app.shown }

pub fn (mut app MotionApp) toggle_transform() { app.moved = !app.moved }

pub fn (app &MotionApp) panel_x() f64 { return if app.moved { 32.0 } else { 0.0 } }

pub fn (app &MotionApp) panel_rotation() f64 { return if app.moved { 3.0 } else { 0.0 } }

pub fn (mut app MotionApp) toggle_reduced() { app.reduced = !app.reduced }

pub fn (mut app MotionApp) toggle_cards() {
	app.rows = if app.rows.len == 0 {
		[MotionRow{ id: 'one', title: 'First card' }, MotionRow{ id: 'two', title: 'Second card' }]
	} else {
		[]MotionRow{}
	}
}

pub fn (mut app MotionApp) card_cleaned() { app.cleaned++ }

fn build_motion(mut app MotionApp) ui2.Element {
	return app_vml(mut app)
}

fn main() {
	mut app := MotionApp{}
	ui2.run_compiled_vml[MotionApp](
		build:  build_motion
		model:  &app
		title:  'Retained motion and presence'
		width:  760
		height: 560
	) or { panic(err) }
}
