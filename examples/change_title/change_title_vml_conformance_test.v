// vtest vflags: -d vml_interpreter -d ui2_headless
// vtest build: vml_conformance?
module main

import ui2

// The interpreted change_title.vml equals the compiled one: the same tree, events
// and model state (ui2.vml_conformance).
fn test_change_title_interpreted_vml_matches_compiled() {
	mut app := ChangeTitleDemo{}
	report := ui2.vml_conformance[ChangeTitleDemo](
		path:     @DIR + '/change_title.vml'
		frame:    ui2.rect(0, 0, change_title_width, change_title_height)
		model:    &app
		reset:    fn (mut app ChangeTitleDemo) {
			app = ChangeTitleDemo{}
		}
		compiled: change_title_tree
	) or { panic(err) }
	println(report)
	assert report.equal(), report.str()
}
