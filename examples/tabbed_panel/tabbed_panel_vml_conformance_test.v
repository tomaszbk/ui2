// vtest vflags: -d vml_interpreter -d ui2_headless
// vtest build: vml_conformance?
module main

import ui2

// The interpreted tabbed_panel.vml equals the compiled one: the same tree, events
// and model state (ui2.vml_conformance).
fn test_tabbed_panel_interpreted_vml_matches_compiled() {
	mut app := TabbedPanelDemo{}
	report := ui2.vml_conformance[TabbedPanelDemo](
		path:     @DIR + '/tabbed_panel.vml'
		frame:    ui2.rect(0, 0, tabbed_width, tabbed_height)
		model:    &app
		reset:    fn (mut app TabbedPanelDemo) {
			app = TabbedPanelDemo{}
		}
		compiled: tabbed_panel_tree
	) or { panic(err) }
	println(report)
	assert report.equal(), report.str()
}
