// vtest vflags: -d vml_interpreter -d ui2_headless
// vtest build: vml_conformance?
module main

import ui2

// The interpreted users_box_layout.vml equals the compiled one: the same tree, events
// and model state (ui2.vml_conformance).
fn test_users_box_layout_interpreted_vml_matches_compiled() {
	mut app := users_box_demo()
	report := ui2.vml_conformance[UsersBoxLayoutDemo](
		path:     @DIR + '/users_box_layout.vml'
		frame:    ui2.rect(0, 0, users_box_width, users_box_height)
		model:    &app
		reset:    fn (mut app UsersBoxLayoutDemo) {
			app = users_box_demo()
		}
		compiled: users_box_layout_tree
	) or { panic(err) }
	println(report)
	assert report.equal(), report.str()
}
