// vtest vflags: -d vml_interpreter -d ui2_headless
// vtest build: vml_conformance?
module main

import ui2

// The interpreted cells.vml equals the compiled one: the same tree, events
// and model state (ui2.vml_conformance).
fn test_cells_interpreted_vml_matches_compiled() {
	mut app := initial_cells()
	report := ui2.vml_conformance[CellsDemo](
		path:     @DIR + '/cells.vml'
		frame:    ui2.rect(0, 0, cells_width, cells_height)
		model:    &app
		reset:    fn (mut app CellsDemo) {
			app = initial_cells()
		}
		compiled: cells_tree
	) or { panic(err) }
	println(report)
	assert report.equal(), report.str()
}
