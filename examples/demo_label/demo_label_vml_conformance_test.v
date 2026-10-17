// vtest vflags: -d vml_interpreter -d ui2_headless
// vtest build: vml_conformance?
module main

import ui2

// The interpreted demo_label.vml equals the compiled one: the same tree, events
// and model state (ui2.vml_conformance).
fn test_demo_label_interpreted_vml_matches_compiled() {
	mut app := DemoLabel{}
	report := ui2.vml_conformance[DemoLabel](
		path:     @DIR + '/demo_label.vml'
		frame:    ui2.rect(0, 0, demo_label_width, demo_label_height)
		model:    &app
		reset:    fn (mut app DemoLabel) {
			app = DemoLabel{}
		}
		compiled: demo_label_tree
	) or { panic(err) }
	println(report)
	assert report.equal(), report.str()
}
