// vtest vflags: -d vml_interpreter -d ui2_headless
// vtest build: vml_conformance?
module main

import ui2

// The interpreted spinner.vml equals the compiled one: the same tree, events
// and model state (ui2.vml_conformance).
fn test_spinner_interpreted_vml_matches_compiled() {
	mut app := SpinnerDemo{}
	report := ui2.vml_conformance[SpinnerDemo](
		path:     @DIR + '/spinner.vml'
		frame:    ui2.rect(0, 0, spinner_width, spinner_height)
		model:    &app
		reset:    fn (mut app SpinnerDemo) {
			app = SpinnerDemo{}
		}
		compiled: spinner_tree
	) or { panic(err) }
	println(report)
	assert report.equal(), report.str()
}
