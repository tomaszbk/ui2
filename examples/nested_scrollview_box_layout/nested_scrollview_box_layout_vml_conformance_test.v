// vtest vflags: -d vml_interpreter -d ui2_headless
// vtest build: vml_conformance?
module main

import ui2

// The interpreted nested_scrollview_box_layout.vml equals the compiled one: the same tree, events
// and model state (ui2.vml_conformance).
fn test_nested_scrollview_box_layout_interpreted_vml_matches_compiled() {
	mut app := initial_nested_scroll_box_layout()
	report := ui2.vml_conformance[NestedScrollBoxLayoutDemo](
		path:     @DIR + '/nested_scrollview_box_layout.vml'
		frame:    ui2.rect(0, 0, nested_box_width, nested_box_height)
		model:    &app
		reset:    fn (mut app NestedScrollBoxLayoutDemo) {
			app = initial_nested_scroll_box_layout()
		}
		compiled: nested_scrollview_box_layout_tree
	) or { panic(err) }
	println(report)
	assert report.equal(), report.str()
}
