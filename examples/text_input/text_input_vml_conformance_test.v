// vtest vflags: -d vml_interpreter -d ui2_headless
// vtest build: vml_conformance?
module main

import ui2

// The interpreted text_input.vml equals the compiled one: the same tree, events
// and model state (ui2.vml_conformance).
fn test_text_input_interpreted_vml_matches_compiled() {
	mut app := TextInputDemo{}
	report := ui2.vml_conformance[TextInputDemo](
		path:     @DIR + '/text_input.vml'
		frame:    ui2.rect(0, 0, text_input_width, text_input_height)
		model:    &app
		reset:    fn (mut app TextInputDemo) {
			app = TextInputDemo{}
		}
		compiled: text_input_tree
	) or { panic(err) }
	println(report)
	assert report.equal(), report.str()
}
