// vtest vflags: -d vml_interpreter -d ui2_headless
// vtest build: vml_conformance?
module main

import os
import ui2

// The interpreted dirbrowser.vml equals the compiled one: the same tree, events
// and model state (ui2.vml_conformance).
fn test_dirbrowser_interpreted_vml_matches_compiled() {
	mut app := directory_browser_at(os.getwd())
	report := ui2.vml_conformance[DirectoryBrowserDemo](
		path:     @DIR + '/dirbrowser.vml'
		frame:    ui2.rect(0, 0, dirbrowser_width, dirbrowser_height)
		model:    &app
		reset:    fn (mut app DirectoryBrowserDemo) {
			app = directory_browser_at(os.getwd())
		}
		compiled: dirbrowser_tree
	) or { panic(err) }
	println(report)
	assert report.equal(), report.str()
}
