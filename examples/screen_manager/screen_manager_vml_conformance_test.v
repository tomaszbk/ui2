// vtest vflags: -d vml_interpreter -d ui2_headless
// vtest build: vml_conformance?
module main

import ui2

// The interpreted screen_manager.vml equals the compiled one: the same tree, events
// and model state (ui2.vml_conformance).
fn test_screen_manager_interpreted_vml_matches_compiled() {
	mut app := ScreenManagerDemo{}
	report := ui2.vml_conformance[ScreenManagerDemo](
		path:     @DIR + '/screen_manager.vml'
		frame:    ui2.rect(0, 0, screen_manager_width, screen_manager_height)
		model:    &app
		reset:    fn (mut app ScreenManagerDemo) {
			app = ScreenManagerDemo{}
		}
		compiled: screen_manager_tree
	) or { panic(err) }
	println(report)
	assert report.equal(), report.str()
}
