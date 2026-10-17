// vtest vflags: -d vml_interpreter -d ui2_headless
// vtest build: vml_conformance?
module main

import ui2

// The interpreted stack_layout.vml equals the compiled one: the same tree, events
// and model state (ui2.vml_conformance).
fn test_stack_layout_interpreted_vml_matches_compiled() {
	mut app := StackLayoutDemo{}
	report := ui2.vml_conformance[StackLayoutDemo](
		path:     @DIR + '/stack_layout.vml'
		frame:    ui2.rect(0, 0, stack_width, stack_height)
		model:    &app
		reset:    fn (mut app StackLayoutDemo) {
			app = StackLayoutDemo{}
		}
		compiled: stack_layout_tree
	) or { panic(err) }
	println(report)
	assert report.equal(), report.str()
}
