// vtest vflags: -d vml_interpreter -d ui2_headless
// vtest build: vml_conformance?
module main

import ui2

// The interpreted crud.vml equals the compiled one: the same tree, events
// and model state (ui2.vml_conformance).
fn test_crud_interpreted_vml_matches_compiled() {
	mut app := initial_crud()
	report := ui2.vml_conformance[CrudDemo](
		path:     @DIR + '/crud.vml'
		frame:    ui2.rect(0, 0, crud_width, crud_height)
		model:    &app
		reset:    fn (mut app CrudDemo) {
			app = initial_crud()
		}
		compiled: crud_tree
	) or { panic(err) }
	println(report)
	assert report.equal(), report.str()
}
