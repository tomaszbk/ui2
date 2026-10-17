// vtest vflags: -d vml_interpreter -d ui2_headless
// vtest build: vml_conformance?
module main

import ui2

// The interpreted page_layout.vml equals the compiled one: the same tree, events
// and model state (ui2.vml_conformance).
fn test_page_layout_interpreted_vml_matches_compiled() {
	mut app := PageLayoutDemo{}
	report := ui2.vml_conformance[PageLayoutDemo](
		path:     @DIR + '/page_layout.vml'
		frame:    ui2.rect(0, 0, page_width, page_height)
		model:    &app
		reset:    fn (mut app PageLayoutDemo) {
			app = PageLayoutDemo{}
		}
		compiled: page_layout_tree
	) or { panic(err) }
	println(report)
	assert report.equal(), report.str()
}
