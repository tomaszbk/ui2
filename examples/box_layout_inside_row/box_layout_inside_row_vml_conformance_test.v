// vtest vflags: -d vml_interpreter -d ui2_headless
// vtest build: vml_conformance?
module main

import ui2

// The interpreted box_layout_inside_row.vml equals the compiled one: the same tree, events
// and model state (ui2.vml_conformance).
fn test_box_layout_inside_row_interpreted_vml_matches_compiled() {
	mut app := initial_box_layout_inside_row()
	report := ui2.vml_conformance[BoxLayoutInsideRowDemo](
		path:     @DIR + '/box_layout_inside_row.vml'
		frame:    ui2.rect(0, 0, box_row_width, box_row_height)
		model:    &app
		reset:    fn (mut app BoxLayoutInsideRowDemo) {
			app = initial_box_layout_inside_row()
		}
		compiled: box_layout_inside_row_tree
	) or { panic(err) }
	println(report)
	assert report.equal(), report.str()
}
