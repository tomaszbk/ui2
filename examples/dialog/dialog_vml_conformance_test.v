// vtest vflags: -d vml_interpreter -d ui2_headless
// vtest build: vml_conformance?
module main

import ui2

// The interpreted dialog.vml equals the compiled one: the same tree, events
// and model state (ui2.vml_conformance).
fn test_dialog_interpreted_vml_matches_compiled() {
	mut app := DialogDemo{}
	report := ui2.vml_conformance[DialogDemo](
		path:     @DIR + '/dialog.vml'
		frame:    ui2.rect(0, 0, dialog_width, dialog_height)
		model:    &app
		reset:    fn (mut app DialogDemo) {
			app = DialogDemo{}
		}
		compiled: dialog_tree
	) or { panic(err) }
	println(report)
	assert report.equal(), report.str()
}
