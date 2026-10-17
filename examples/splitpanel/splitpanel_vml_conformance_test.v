// vtest vflags: -d vml_interpreter -d ui2_headless
// vtest build: vml_conformance?
module main

import ui2

// The interpreted splitpanel.vml equals the compiled one: the same tree, events
// and model state (ui2.vml_conformance).
fn test_splitpanel_interpreted_vml_matches_compiled() {
	mut app := initial_splitpanel()
	report := ui2.vml_conformance[SplitPanelDemo](
		path:     @DIR + '/splitpanel.vml'
		frame:    ui2.rect(0, 0, splitpanel_width, splitpanel_height)
		model:    &app
		reset:    fn (mut app SplitPanelDemo) {
			app = initial_splitpanel()
		}
		compiled: splitpanel_tree
	) or { panic(err) }
	println(report)
	assert report.equal(), report.str()
}
