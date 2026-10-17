// vtest vflags: -d vml_interpreter -d ui2_headless
// vtest build: vml_conformance?
module main

import ui2

// The interpreted logview.vml equals the compiled one: the same tree, events
// and model state (ui2.vml_conformance).
fn test_logview_interpreted_vml_matches_compiled() {
	mut app := LogviewDemo{}
	report := ui2.vml_conformance[LogviewDemo](
		path:     @DIR + '/logview.vml'
		frame:    ui2.rect(0, 0, logview_width, logview_height)
		model:    &app
		reset:    fn (mut app LogviewDemo) {
			app = LogviewDemo{}
		}
		compiled: logview_tree
	) or { panic(err) }
	println(report)
	assert report.equal(), report.str()
}
