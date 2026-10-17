// vtest vflags: -d vml_interpreter -d ui2_headless
// vtest build: vml_conformance?
module main

import ui2

// The interpreted group.vml equals the compiled one: the same tree, events
// and model state (ui2.vml_conformance).
fn test_group_interpreted_vml_matches_compiled() {
	mut app := GroupDemo{}
	report := ui2.vml_conformance[GroupDemo](
		path:     @DIR + '/group.vml'
		frame:    ui2.rect(0, 0, group_width, group_height)
		model:    &app
		reset:    fn (mut app GroupDemo) {
			app = GroupDemo{}
		}
		compiled: group_tree
	) or { panic(err) }
	println(report)
	assert report.equal(), report.str()
}
