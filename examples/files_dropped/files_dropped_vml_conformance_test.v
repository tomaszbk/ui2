// vtest vflags: -d vml_interpreter -d ui2_headless
// vtest build: vml_conformance?
module main

import ui2

// The interpreted files_dropped.vml equals the compiled one: the same tree, events
// and model state (ui2.vml_conformance).
fn test_files_dropped_interpreted_vml_matches_compiled() {
	report := ui2.vml_conformance[FilesDroppedDemo](
		path:     @DIR + '/files_dropped.vml'
		frame:    ui2.rect(0, 0, files_dropped_width, files_dropped_height)
		model:    files_dropped_state
		reset:    fn (mut app FilesDroppedDemo) {
			app = FilesDroppedDemo{}
		}
		compiled: files_dropped_tree
	) or { panic(err) }
	println(report)
	assert report.equal(), report.str()
}
