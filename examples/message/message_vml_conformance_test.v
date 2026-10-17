// vtest vflags: -d vml_interpreter -d ui2_headless
// vtest build: vml_conformance?
module main

import ui2

// The interpreted message.vml equals the compiled one: the same tree, events
// and model state (ui2.vml_conformance).
fn test_message_interpreted_vml_matches_compiled() {
	mut app := MessageDemo{}
	report := ui2.vml_conformance[MessageDemo](
		path:     @DIR + '/message.vml'
		frame:    ui2.rect(0, 0, message_width, message_height)
		model:    &app
		reset:    fn (mut app MessageDemo) {
			app = MessageDemo{}
		}
		compiled: message_tree
	) or { panic(err) }
	println(report)
	assert report.equal(), report.str()
}
