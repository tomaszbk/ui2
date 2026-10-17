// vtest vflags: -d vml_interpreter -d ui2_headless
// vtest build: vml_conformance?
module main

import ui2

// The interpreted rasterview.vml equals the compiled one: the same tree, events
// and model state (ui2.vml_conformance).
fn test_rasterview_interpreted_vml_matches_compiled() {
	mut app := initial_rasterview()
	report := ui2.vml_conformance[RasterviewDemo](
		path:     @DIR + '/rasterview.vml'
		frame:    ui2.rect(0, 0, rasterview_width, rasterview_height)
		model:    &app
		reset:    fn (mut app RasterviewDemo) {
			app = initial_rasterview()
		}
		compiled: rasterview_tree
	) or { panic(err) }
	println(report)
	assert report.equal(), report.str()
}
