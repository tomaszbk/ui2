// vtest vflags: -d vml_interpreter -d ui2_headless
// vtest build: vml_conformance?
module main

import ui2

// The interpreted relative_layout.vml equals the compiled one: the same tree, events
// and model state (ui2.vml_conformance).
fn test_relative_layout_interpreted_vml_matches_compiled() {
	mut app := RelativeLayoutDemo{}
	report := ui2.vml_conformance[RelativeLayoutDemo](
		path:     @DIR + '/relative_layout.vml'
		frame:    ui2.rect(0, 0, relative_width, relative_height)
		model:    &app
		reset:    fn (mut app RelativeLayoutDemo) {
			app = RelativeLayoutDemo{}
		}
		compiled: relative_layout_tree
	) or { panic(err) }
	println(report)
	assert report.equal(), report.str()
}
