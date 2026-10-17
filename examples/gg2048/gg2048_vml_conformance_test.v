// vtest vflags: -d vml_interpreter -d ui2_headless
// vtest build: vml_conformance?
module main

import ui2

// The interpreted gg2048.vml equals the compiled one: the same tree, events
// and model state (ui2.vml_conformance).
fn test_gg2048_interpreted_vml_matches_compiled() {
	mut app := initial_2048()
	report := ui2.vml_conformance[Game2048](
		path:     @DIR + '/gg2048.vml'
		frame:    ui2.rect(0, 0, game_2048_width, game_2048_height)
		model:    &app
		reset:    fn (mut app Game2048) {
			app = initial_2048()
		}
		compiled: gg2048_tree
	) or { panic(err) }
	println(report)
	assert report.equal(), report.str()
}
