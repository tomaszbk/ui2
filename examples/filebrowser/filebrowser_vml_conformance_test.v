// vtest vflags: -d vml_interpreter -d ui2_headless
// vtest build: vml_conformance?
module main

import os
import ui2

// The interpreted filebrowser.vml equals the compiled one: the same tree, events
// and model state (ui2.vml_conformance).
fn test_filebrowser_interpreted_vml_matches_compiled() {
	mut app := file_browser_at(os.getwd())
	report := ui2.vml_conformance[FileBrowserDemo](
		path:     @DIR + '/filebrowser.vml'
		frame:    ui2.rect(0, 0, filebrowser_width, filebrowser_height)
		model:    &app
		reset:    fn (mut app FileBrowserDemo) {
			app = file_browser_at(os.getwd())
		}
		compiled: filebrowser_tree
	) or { panic(err) }
	println(report)
	assert report.equal(), report.str()
}
