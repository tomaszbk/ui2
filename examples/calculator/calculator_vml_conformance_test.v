// vtest vflags: -d vml_interpreter -d ui2_headless
// vtest build: vml_conformance?
module main

import ui2

// The interpreted calculator.vml equals the compiled one: the same tree, events
// and model state (ui2.vml_conformance).
fn test_calculator_interpreted_vml_matches_compiled() {
	mut app := initial_calculator()
	report := ui2.vml_conformance[Calculator](
		path:     @DIR + '/calculator.vml'
		frame:    ui2.rect(0, 0, window_width, window_height)
		model:    &app
		reset:    fn (mut app Calculator) {
			app = initial_calculator()
		}
		compiled: calculator_tree
	) or { panic(err) }
	println(report)
	assert report.equal(), report.str()
}
