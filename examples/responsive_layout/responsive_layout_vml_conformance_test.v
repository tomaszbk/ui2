// vtest vflags: -d vml_interpreter -d ui2_headless
// vtest build: vml_conformance?
module main

import ui2

// The interpreted responsive_layout.vml equals the compiled one: the same tree, events
// and model state (ui2.vml_conformance).
fn test_responsive_layout_interpreted_vml_matches_compiled() {
	mut app := ResponsiveApp{}
	report := ui2.vml_conformance[ResponsiveApp](
		path:     @DIR + '/responsive_layout.vml'
		frame:    ui2.rect(0, 0, 1000, 780)
		model:    &app
		reset:    fn (mut app ResponsiveApp) {
			app = ResponsiveApp{}
		}
		compiled: responsive_layout_tree
	) or { panic(err) }
	println(report)
	assert report.equal(), report.str()
}
