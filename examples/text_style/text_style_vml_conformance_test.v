// vtest vflags: -d vml_interpreter -d ui2_headless
// vtest build: vml_conformance?
module main

import ui2

// The interpreted text_style.vml equals the compiled one: the same tree, events
// and model state (ui2.vml_conformance).
fn test_text_style_interpreted_vml_matches_compiled() {
	mut app := text_style_demo()
	report := ui2.vml_conformance[TextStyleDemo](
		path:     @DIR + '/text_style.vml'
		frame:    ui2.rect(0, 0, text_style_width, text_style_height)
		model:    &app
		reset:    fn (mut app TextStyleDemo) {
			app = text_style_demo()
		}
		compiled: text_style_tree
	) or { panic(err) }
	println(report)
	assert report.equal(), report.str()
}
