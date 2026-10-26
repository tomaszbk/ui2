// vtest vflags: -d vml_interpreter -d ui2_headless
// vtest build: vml_conformance?
module main

import ui2

// The interpreted users.vml equals the compiled one: the same tree, events
// and model state (ui2.vml_conformance).
fn test_users_interpreted_vml_matches_compiled() {
	mut app := initial_app()
	report := ui2.vml_conformance[UsersApp](
		path:     @DIR + '/users.vml'
		frame:    ui2.rect(0, 0, window_width, window_height)
		model:    &app
		reset:    fn (mut app UsersApp) {
			app = initial_app()
		}
		compiled: users_tree
	) or { panic(err) }
	println(report)
	assert report.equal(), report.str()
}
