// vtest vflags: -d vml_interpreter -d ui2_headless
// vtest build: vml_conformance?
module main

import ui2

// The interpreted accordion_widget.vml equals the compiled one: the same tree, events
// and model state (ui2.vml_conformance).
fn test_accordion_widget_interpreted_vml_matches_compiled() {
	mut app := AccordionDemo{}
	report := ui2.vml_conformance[AccordionDemo](
		path:     @DIR + '/accordion_widget.vml'
		frame:    ui2.rect(0, 0, accordion_width, accordion_height)
		model:    &app
		reset:    fn (mut app AccordionDemo) {
			app = AccordionDemo{}
		}
		compiled: accordion_widget_tree
	) or { panic(err) }
	println(report)
	assert report.equal(), report.str()
}
