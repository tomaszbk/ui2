// vtest vflags: -d vml_interpreter -d ui2_headless
// vtest build: vml_conformance?
module main

import ui2

// The interpreted tree.vml equals the compiled one: the same tree, events
// and model state (ui2.vml_conformance).
fn test_tree_interpreted_vml_matches_compiled() {
	mut app := TreeDemo{}
	report := ui2.vml_conformance[TreeDemo](
		path:     @DIR + '/tree.vml'
		frame:    ui2.rect(0, 0, tree_width, tree_height)
		model:    &app
		reset:    fn (mut app TreeDemo) {
			app = TreeDemo{}
		}
		compiled: tree_document
	) or { panic(err) }
	println(report)
	assert report.equal(), report.str()
}
