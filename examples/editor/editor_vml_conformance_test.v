// vtest vflags: -d vml_interpreter -d ui2_headless
// vtest build: vml_conformance?
module main

import os
import ui2

// The interpreted editor.vml equals the compiled one: the same tree, events
// and model state (ui2.vml_conformance).
fn test_editor_interpreted_vml_matches_compiled() {
	mut app := editor_at(os.getwd())
	report := ui2.vml_conformance[EditorDemo](
		path:     @DIR + '/editor.vml'
		frame:    ui2.rect(0, 0, editor_width, editor_height)
		model:    &app
		reset:    fn (mut app EditorDemo) {
			app = editor_at(os.getwd())
		}
		compiled: editor_tree
	) or { panic(err) }
	println(report)
	assert report.equal(), report.str()
}
