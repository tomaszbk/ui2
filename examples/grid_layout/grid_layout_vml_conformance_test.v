// vtest vflags: -d vml_interpreter -d ui2_headless
// vtest build: vml_conformance?
module main

import ui2

// The interpreted grid_layout.vml equals the compiled one: the same tree, events
// and model state (ui2.vml_conformance).
fn test_grid_layout_interpreted_vml_matches_compiled() {
	mut app := GridLayoutDemo{}
	report := ui2.vml_conformance[GridLayoutDemo](
		path:     @DIR + '/grid_layout.vml'
		frame:    ui2.rect(0, 0, grid_width, grid_height)
		model:    &app
		reset:    fn (mut app GridLayoutDemo) {
			app = GridLayoutDemo{}
		}
		compiled: grid_layout_tree
	) or { panic(err) }
	println(report)
	assert report.equal(), report.str()
}
