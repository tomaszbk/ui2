// vtest vflags: -d vml_interpreter -d ui2_headless
// vtest build: vml_conformance?
module main

import ui2

// The interpreted tree_view_widget.vml equals the compiled one: the same tree, events
// and model state (ui2.vml_conformance).
fn test_tree_view_widget_interpreted_vml_matches_compiled() {
	mut app := TreeViewWidgetDemo{}
	report := ui2.vml_conformance[TreeViewWidgetDemo](
		path:     @DIR + '/tree_view_widget.vml'
		frame:    ui2.rect(0, 0, tree_view_widget_width, tree_view_widget_height)
		model:    &app
		reset:    fn (mut app TreeViewWidgetDemo) {
			app = TreeViewWidgetDemo{}
		}
		compiled: tree_view_widget_tree
	) or { panic(err) }
	println(report)
	assert report.equal(), report.str()
}
