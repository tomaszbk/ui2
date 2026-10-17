// vtest vflags: -d vml_interpreter -d ui2_headless
// vtest build: vml_conformance?
module main

import ui2

// The interpreted anchor_layout.vml equals the compiled one: the same tree, events
// and model state (ui2.vml_conformance).
fn test_anchor_layout_interpreted_vml_matches_compiled() {
	mut app := AnchorLayoutDemo{}
	report := ui2.vml_conformance[AnchorLayoutDemo](
		path:     @DIR + '/anchor_layout.vml'
		frame:    ui2.rect(0, 0, anchor_width, anchor_height)
		model:    &app
		reset:    fn (mut app AnchorLayoutDemo) {
			app = AnchorLayoutDemo{}
		}
		compiled: anchor_layout_tree
	) or { panic(err) }
	println(report)
	assert report.equal(), report.str()
}
