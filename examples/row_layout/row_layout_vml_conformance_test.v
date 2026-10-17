// vtest vflags: -d vml_interpreter -d ui2_headless
// vtest build: vml_conformance?
module main

import ui2

// The interpreted row_layout.vml equals the compiled one: the same tree, events
// and model state (ui2.vml_conformance).
fn test_row_layout_interpreted_vml_matches_compiled() {
	mut app := RowLayoutDemo{}
	report := ui2.vml_conformance[RowLayoutDemo](
		path:     @DIR + '/row_layout.vml'
		frame:    ui2.rect(0, 0, row_layout_width, row_layout_height)
		model:    &app
		reset:    fn (mut app RowLayoutDemo) {
			app = RowLayoutDemo{}
		}
		compiled: row_layout_tree
	) or { panic(err) }
	println(report)
	assert report.equal(), report.str()
}
