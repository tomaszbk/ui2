// vtest vflags: -d vml_interpreter -d ui2_headless
// vtest build: vml_conformance?
module main

import ui2

// The interpreted file_dialog.vml equals the compiled one: the same tree, events
// and model state (ui2.vml_conformance).
fn test_file_dialog_interpreted_vml_matches_compiled() {
	mut app := FileDialogDemo{}
	report := ui2.vml_conformance[FileDialogDemo](
		path:     @DIR + '/file_dialog.vml'
		frame:    ui2.rect(0, 0, file_dialog_width, file_dialog_height)
		model:    &app
		reset:    fn (mut app FileDialogDemo) {
			app = FileDialogDemo{}
		}
		compiled: file_dialog_tree
	) or { panic(err) }
	println(report)
	assert report.equal(), report.str()
}
