// vtest vflags: -d vml_interpreter -d ui2_headless
// vtest build: vml_conformance?
module main

import ui2

// The interpreted nested_scrollview.vml equals the compiled one: the same tree, events
// and model state (ui2.vml_conformance).
fn test_nested_scrollview_interpreted_vml_matches_compiled() {
	mut app := initial_nested_scrollview()
	report := ui2.vml_conformance[NestedScrollviewDemo](
		path:     @DIR + '/nested_scrollview.vml'
		frame:    ui2.rect(0, 0, nested_scrollview_width, nested_scrollview_height)
		model:    &app
		reset:    fn (mut app NestedScrollviewDemo) {
			app = initial_nested_scrollview()
		}
		compiled: nested_scrollview_tree
	) or { panic(err) }
	println(report)
	assert report.equal(), report.str()
}
