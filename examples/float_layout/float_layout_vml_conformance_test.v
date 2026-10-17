// vtest vflags: -d vml_interpreter -d ui2_headless
// vtest build: vml_conformance?
module main

import ui2

// The interpreted float_layout.vml equals the compiled one: the same tree, events
// and model state (ui2.vml_conformance).
fn test_float_layout_interpreted_vml_matches_compiled() {
	mut app := FloatLayoutDemo{}
	report := ui2.vml_conformance[FloatLayoutDemo](
		path:     @DIR + '/float_layout.vml'
		frame:    ui2.rect(0, 0, float_width, float_height)
		model:    &app
		reset:    fn (mut app FloatLayoutDemo) {
			app = FloatLayoutDemo{}
		}
		compiled: float_layout_tree
	) or { panic(err) }
	println(report)
	assert report.equal(), report.str()
}
