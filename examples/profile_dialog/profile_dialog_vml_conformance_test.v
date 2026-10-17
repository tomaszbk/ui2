// vtest vflags: -d vml_interpreter -d ui2_headless
// vtest build: vml_conformance?
module main

import ui2

// The interpreted profile_dialog.vml equals the compiled one: the same tree, events
// and model state (ui2.vml_conformance).
fn test_profile_dialog_interpreted_vml_matches_compiled() {
	mut app := ProfileDialogDemo{}
	report := ui2.vml_conformance[ProfileDialogDemo](
		path:     @DIR + '/profile_dialog.vml'
		frame:    ui2.rect(0, 0, profile_dialog_width, profile_dialog_height)
		model:    &app
		reset:    fn (mut app ProfileDialogDemo) {
			app = ProfileDialogDemo{}
		}
		compiled: profile_dialog_tree
	) or { panic(err) }
	println(report)
	assert report.equal(), report.str()
}
