// vtest vflags: -d vml_interpreter -d ui2_headless
// vtest build: vml_conformance?
module main

import ui2

// The interpreted toggle_button.vml equals the compiled one: the same tree, events
// and model state (ui2.vml_conformance).
fn test_toggle_button_interpreted_vml_matches_compiled() {
	mut app := ToggleButtonDemo{}
	report := ui2.vml_conformance[ToggleButtonDemo](
		path:     @DIR + '/toggle_button.vml'
		frame:    ui2.rect(0, 0, toggle_width, toggle_height)
		model:    &app
		reset:    fn (mut app ToggleButtonDemo) {
			app = ToggleButtonDemo{}
		}
		compiled: toggle_button_tree
	) or { panic(err) }
	println(report)
	assert report.equal(), report.str()
}
