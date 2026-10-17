// vtest vflags: -d vml_interpreter -d ui2_headless
// vtest build: vml_conformance?
module main

import ui2

// The interpreted textbox.vml equals the compiled one: the same tree, events
// and model state (ui2.vml_conformance).
fn test_textbox_interpreted_vml_matches_compiled() {
	mut app := TextboxDemo{}
	report := ui2.vml_conformance[TextboxDemo](
		path:     @DIR + '/textbox.vml'
		frame:    ui2.rect(0, 0, textbox_width, textbox_height)
		model:    &app
		reset:    fn (mut app TextboxDemo) {
			app = TextboxDemo{}
		}
		compiled: textbox_tree
	) or { panic(err) }
	println(report)
	assert report.equal(), report.str()
}
