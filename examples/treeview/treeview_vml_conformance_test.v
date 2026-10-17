// vtest vflags: -d vml_interpreter -d ui2_headless
// vtest build: vml_conformance?
module main

import ui2

// The interpreted treeview.vml equals the compiled one: the same tree, events
// and model state (ui2.vml_conformance).
fn test_treeview_interpreted_vml_matches_compiled() {
	mut app := initial_treeview()
	report := ui2.vml_conformance[TreeviewDemo](
		path:     @DIR + '/treeview.vml'
		frame:    ui2.rect(0, 0, treeview_width, treeview_height)
		model:    &app
		reset:    fn (mut app TreeviewDemo) {
			app = initial_treeview()
		}
		compiled: treeview_tree
	) or { panic(err) }
	println(report)
	assert report.equal(), report.str()
}
