// vtest vflags: -d vml_interpreter -d ui2_headless
// vtest build: vml_conformance?
module main

// vml: motion_helpers.vml

import ui2

// Conformance of the interpreter with compiled VML (ui2.vml_conformance) for
// motion helper values and Timeline parts: motion_helpers.vml.

@[heap]
pub struct MotionConformanceApp {
pub mut:
	duration f64 = 0.4
	ready    bool
	entering ui2.MotionStyle = ui2.MotionStyle{
		translate_x: -24
	}
}

fn motion_conformance_tree(mut app MotionConformanceApp, frame ui2.Rect) ui2.Element {
	return motion_helpers_vml_framed(mut app, frame)
}

fn motion_conformance_reset(mut app MotionConformanceApp) {
	app = MotionConformanceApp{}
}

fn test_motion_helpers_interpreted_vml_matches_compiled() {
	mut app := MotionConformanceApp{}
	report := ui2.vml_conformance[MotionConformanceApp](
		path:     @DIR + '/motion_helpers.vml'
		frame:    ui2.rect(0, 0, 300, 200)
		model:    &app
		reset:    motion_conformance_reset
		compiled: motion_conformance_tree
	) or { panic(err) }
	println(report)
	assert report.equal(), report.str()
}
