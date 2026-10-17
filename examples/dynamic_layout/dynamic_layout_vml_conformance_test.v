// vtest vflags: -d vml_interpreter -d ui2_headless
// vtest build: vml_conformance?
module main

import ui2

// The interpreted dynamic_layout.vml equals the compiled one: the same tree, events
// and model state (ui2.vml_conformance).
fn test_dynamic_layout_interpreted_vml_matches_compiled() {
	mut app := initial_dynamic_layout()
	report := ui2.vml_conformance[DynamicLayoutDemo](
		path:     @DIR + '/dynamic_layout.vml'
		frame:    ui2.rect(0, 0, dynamic_layout_width, dynamic_layout_height)
		model:    &app
		reset:    fn (mut app DynamicLayoutDemo) {
			app = initial_dynamic_layout()
		}
		compiled: dynamic_layout_tree
	) or { panic(err) }
	println(report)
	assert report.equal(), report.str()
}
