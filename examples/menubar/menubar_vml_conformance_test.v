// vtest vflags: -d vml_interpreter -d ui2_headless
// vtest build: vml_conformance?
module main

import ui2

// The interpreted menubar.vml equals the compiled one: the same tree, events
// and model state (ui2.vml_conformance).
fn test_menubar_interpreted_vml_matches_compiled() {
	callbacks := menubar_callbacks()
	report := ui2.vml_conformance[MenubarDemo](
		path:      @DIR + '/menubar.vml'
		frame:     ui2.rect(0, 0, menubar_width, menubar_height)
		model:     menubar_state
		reset:     fn (mut app MenubarDemo) {
			app = MenubarDemo{}
		}
		compiled:  menubar_tree
		callbacks: {
			'callback_reset': callbacks['reset'] or { panic('missing reset callback') }
		}
	) or { panic(err) }
	println(report)
	assert report.equal(), report.str()
}
