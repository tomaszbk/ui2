// vtest vflags: -d vml_interpreter -d ui2_headless
// vtest build: vml_conformance?
module main

import ui2

// The interpreted switch.vml equals the compiled one: the same tree, events
// and model state (ui2.vml_conformance).
fn test_switch_interpreted_vml_matches_compiled() {
	mut app := SwitchDemo{}
	report := ui2.vml_conformance[SwitchDemo](
		path:     @DIR + '/switch.vml'
		frame:    ui2.rect(0, 0, switch_width, switch_height)
		model:    &app
		reset:    fn (mut app SwitchDemo) {
			app = SwitchDemo{}
		}
		compiled: switch_tree
	) or { panic(err) }
	println(report)
	assert report.equal(), report.str()
}
