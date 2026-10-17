// vtest vflags: -d vml_interpreter -d ui2_headless
// vtest build: vml_conformance?
module main

import ui2

// The interpreted box_layout.vml equals the compiled one: the same tree, events
// and model state (ui2.vml_conformance).
fn test_box_layout_interpreted_vml_matches_compiled() {
	mut app := BoxLayoutDemo{}
	report := ui2.vml_conformance[BoxLayoutDemo](
		path:     @DIR + '/box_layout.vml'
		frame:    ui2.rect(0, 0, box_layout_width, box_layout_height)
		model:    &app
		reset:    fn (mut app BoxLayoutDemo) {
			app = BoxLayoutDemo{}
		}
		compiled: box_layout_tree
	) or { panic(err) }
	println(report)
	assert report.equal(), report.str()
}
