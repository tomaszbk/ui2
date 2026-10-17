// vtest vflags: -d vml_interpreter -d ui2_headless
// vtest build: vml_conformance?
module main

import ui2

// The interpreted grid.vml equals the compiled one: the same tree, events
// and model state (ui2.vml_conformance).
fn test_grid_interpreted_vml_matches_compiled() {
	mut app := initial_grid()
	report := ui2.vml_conformance[GridDemo](
		path:     @DIR + '/grid.vml'
		frame:    ui2.rect(0, 0, grid_width, grid_height)
		model:    &app
		reset:    fn (mut app GridDemo) {
			app = initial_grid()
		}
		compiled: grid_tree
	) or { panic(err) }
	println(report)
	assert report.equal(), report.str()
}
