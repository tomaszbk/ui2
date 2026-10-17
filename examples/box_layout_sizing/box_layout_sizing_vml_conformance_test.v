// vtest vflags: -d vml_interpreter -d ui2_headless
// vtest build: vml_conformance?
module main

import ui2

// The interpreted box_layout_sizing.vml equals the compiled one: the same tree, events
// and model state (ui2.vml_conformance).
fn test_box_layout_sizing_interpreted_vml_matches_compiled() {
	mut app := BoxLayoutSizingDemo{}
	report := ui2.vml_conformance[BoxLayoutSizingDemo](
		path:     @DIR + '/box_layout_sizing.vml'
		frame:    ui2.rect(0, 0, box_sizing_width, box_sizing_height)
		model:    &app
		reset:    fn (mut app BoxLayoutSizingDemo) {
			app = BoxLayoutSizingDemo{}
		}
		compiled: box_layout_sizing_tree
	) or { panic(err) }
	println(report)
	assert report.equal(), report.str()
}
