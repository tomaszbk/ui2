// vtest vflags: -d vml_interpreter -d ui2_headless
// vtest build: vml_conformance?
module main

import ui2

// The interpreted scrollview.vml equals the compiled one: the same tree, events
// and model state (ui2.vml_conformance).
fn test_scrollview_interpreted_vml_matches_compiled() {
	mut app := initial_scrollview()
	report := ui2.vml_conformance[ScrollviewDemo](
		path:     @DIR + '/scrollview.vml'
		frame:    ui2.rect(0, 0, scrollview_width, scrollview_height)
		model:    &app
		reset:    fn (mut app ScrollviewDemo) {
			app = initial_scrollview()
		}
		compiled: scrollview_tree
	) or { panic(err) }
	println(report)
	assert report.equal(), report.str()
}
