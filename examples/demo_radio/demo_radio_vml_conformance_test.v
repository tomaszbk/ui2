// vtest vflags: -d vml_interpreter -d ui2_headless
// vtest build: vml_conformance?
module main

import ui2

// The interpreted demo_radio.vml equals the compiled one: the same tree, events
// and model state (ui2.vml_conformance).
fn test_demo_radio_interpreted_vml_matches_compiled() {
	mut app := initial_radio_demo()
	report := ui2.vml_conformance[RadioDemo](
		path:     @DIR + '/demo_radio.vml'
		frame:    ui2.rect(0, 0, radio_width, radio_height)
		model:    &app
		reset:    fn (mut app RadioDemo) {
			app = initial_radio_demo()
		}
		compiled: demo_radio_tree
	) or { panic(err) }
	println(report)
	assert report.equal(), report.str()
}
