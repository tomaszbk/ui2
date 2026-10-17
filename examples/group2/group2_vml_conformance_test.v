// vtest vflags: -d vml_interpreter -d ui2_headless
// vtest build: vml_conformance?
module main

import ui2

// The interpreted group2.vml equals the compiled one: the same tree, events
// and model state (ui2.vml_conformance).
fn test_group2_interpreted_vml_matches_compiled() {
	mut app := Group2Demo{}
	report := ui2.vml_conformance[Group2Demo](
		path:     @DIR + '/group2.vml'
		frame:    ui2.rect(0, 0, group2_width, group2_height)
		model:    &app
		reset:    fn (mut app Group2Demo) {
			app = Group2Demo{}
		}
		compiled: group2_tree
	) or { panic(err) }
	println(report)
	assert report.equal(), report.str()
}
