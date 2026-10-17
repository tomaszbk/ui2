// vtest vflags: -d vml_interpreter -d ui2_headless
// vtest build: vml_conformance?
module main

import ui2

fn motion_presence_conformance_tree(mut app MotionApp, _ ui2.Rect) ui2.Element {
	return build_motion(mut app)
}

// The interpreted app.vml (and the motion_card.vml component it imports)
// equals the compiled one: the same tree, events and model state
// (ui2.vml_conformance).
fn test_motion_presence_interpreted_vml_matches_compiled() {
	mut app := MotionApp{}
	report := ui2.vml_conformance[MotionApp](
		path:            @DIR + '/app.vml'
		frame:           ui2.rect(0, 0, 760, 560)
		model:           &app
		reset:           fn (mut app MotionApp) {
			app = MotionApp{}
		}
		compiled:        motion_presence_conformance_tree
		follow_viewport: true
	) or { panic(err) }
	println(report)
	assert report.equal(), report.str()
}
