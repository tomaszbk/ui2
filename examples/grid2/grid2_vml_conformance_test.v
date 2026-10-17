// vtest vflags: -d vml_interpreter -d ui2_headless
// vtest build: vml_conformance?
module main

import ui2

// The interpreted grid2.vml equals the compiled one: the same tree, events
// and model state (ui2.vml_conformance).
fn test_grid2_interpreted_vml_matches_compiled() {
	mut app := grid2_demo()
	report := ui2.vml_conformance[Grid2Demo](
		path:     @DIR + '/grid2.vml'
		frame:    ui2.rect(0, 0, grid2_width, grid2_height)
		model:    &app
		reset:    fn (mut app Grid2Demo) {
			app = grid2_demo()
		}
		compiled: grid2_tree
	) or { panic(err) }
	println(report)
	assert report.equal(), report.str()
}
