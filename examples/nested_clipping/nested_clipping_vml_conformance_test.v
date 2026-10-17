// vtest vflags: -d vml_interpreter -d ui2_headless
// vtest build: vml_conformance?
module main

import ui2

// The interpreted nested_clipping.vml equals the compiled one: the same tree, events
// and model state (ui2.vml_conformance).
fn test_nested_clipping_interpreted_vml_matches_compiled() {
	mut app := nested_clipping_demo()
	report := ui2.vml_conformance[NestedClippingDemo](
		path:     @DIR + '/nested_clipping.vml'
		frame:    ui2.rect(0, 0, nested_clipping_width, nested_clipping_height)
		model:    &app
		reset:    fn (mut app NestedClippingDemo) {
			app = nested_clipping_demo()
		}
		compiled: nested_clipping_tree
	) or { panic(err) }
	println(report)
	assert report.equal(), report.str()
}
