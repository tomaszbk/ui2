// vtest vflags: -d vml_interpreter -d ui2_headless
// vtest build: vml_conformance?
module main

import ui2

// The interpreted circle_drawer.vml equals the compiled one: the same tree, events
// and model state (ui2.vml_conformance).
fn test_circle_drawer_interpreted_vml_matches_compiled() {
	callbacks := circle_drawer_callbacks()
	report := ui2.vml_conformance[CircleDrawerDemo](
		path:      @DIR + '/circle_drawer.vml'
		frame:     ui2.rect(0, 0, circle_drawer_width, circle_drawer_height)
		model:     circle_drawer_state
		reset:     fn (mut app CircleDrawerDemo) {
			app = CircleDrawerDemo{}
		}
		compiled:  circle_drawer_tree
		callbacks: {
			'callback_undo':          callbacks['undo'] or { panic('missing undo callback') }
			'callback_redo':          callbacks['redo'] or { panic('missing redo callback') }
			'callback_radius_less':   callbacks['radius_less'] or { panic('missing radius_less callback') }
			'callback_radius_more':   callbacks['radius_more'] or { panic('missing radius_more callback') }
			'callback_circle_canvas': callbacks['circle_canvas'] or { panic('missing circle_canvas callback') }
		}
	) or { panic(err) }
	println(report)
	assert report.equal(), report.str()
}
