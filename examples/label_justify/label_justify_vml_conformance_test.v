// vtest vflags: -d vml_interpreter -d ui2_headless
// vtest build: vml_conformance?
module main

import ui2

// The interpreted label_justify.vml equals the compiled one: the same tree, events
// and model state (ui2.vml_conformance).
fn test_label_justify_interpreted_vml_matches_compiled() {
	mut app := LabelJustifyDemo{}
	report := ui2.vml_conformance[LabelJustifyDemo](
		path:     @DIR + '/label_justify.vml'
		frame:    ui2.rect(0, 0, label_justify_width, label_justify_height)
		model:    &app
		reset:    fn (mut app LabelJustifyDemo) {
			app = LabelJustifyDemo{}
		}
		compiled: label_justify_tree
	) or { panic(err) }
	println(report)
	assert report.equal(), report.str()
}
