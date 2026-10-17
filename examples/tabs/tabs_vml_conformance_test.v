// vtest vflags: -d vml_interpreter -d ui2_headless
// vtest build: vml_conformance?
module main

import ui2

// The interpreted tabs.vml equals the compiled one: the same tree, events
// and model state (ui2.vml_conformance).
fn test_tabs_interpreted_vml_matches_compiled() {
	mut app := TabsDemo{}
	report := ui2.vml_conformance[TabsDemo](
		path:     @DIR + '/tabs.vml'
		frame:    ui2.rect(0, 0, tabs_width, tabs_height)
		model:    &app
		reset:    fn (mut app TabsDemo) {
			app = TabsDemo{}
		}
		compiled: tabs_tree
	) or { panic(err) }
	println(report)
	assert report.equal(), report.str()
}
