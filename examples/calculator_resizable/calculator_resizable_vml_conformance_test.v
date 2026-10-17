// vtest vflags: -d vml_interpreter -d ui2_headless
// vtest build: vml_conformance?
module main

import ui2

// The interpreted calculator_resizable.vml equals the compiled one: the same tree, events
// and model state (ui2.vml_conformance).
fn test_calculator_resizable_interpreted_vml_matches_compiled() {
	mut app := resizable_calculator()
	report := ui2.vml_conformance[ResizableCalculator](
		path:     @DIR + '/calculator_resizable.vml'
		frame:    ui2.rect(0, 0, resizable_calc_width, resizable_calc_height)
		model:    &app
		reset:    fn (mut app ResizableCalculator) {
			app = resizable_calculator()
		}
		compiled: calculator_resizable_tree
	) or { panic(err) }
	println(report)
	assert report.equal(), report.str()
}
