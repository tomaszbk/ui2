// vtest vflags: -d vml_interpreter -d ui2_headless
// vtest build: vml_conformance?
module main

import ui2

// The interpreted canvas_layout_inside_row.vml equals the compiled one: the same tree, events
// and model state (ui2.vml_conformance).
fn test_canvas_layout_inside_row_interpreted_vml_matches_compiled() {
	callbacks := canvas_layout_inside_row_callbacks()
	report := ui2.vml_conformance[InsideRowDemo](
		path:      @DIR + '/canvas_layout_inside_row.vml'
		frame:     ui2.rect(0, 0, inside_row_width, inside_row_height)
		model:     inside_row_state
		reset:     fn (mut app InsideRowDemo) {
			app = inside_row_demo()
		}
		compiled:  canvas_layout_inside_row_tree
		callbacks: {
			'callback_rotate': callbacks['rotate'] or { panic('missing rotate callback') }
			'callback_return': callbacks['return'] or { panic('missing return callback') }
			'callback_logo':   callbacks['logo'] or { panic('missing logo callback') }
		}
	) or { panic(err) }
	println(report)
	assert report.equal(), report.str()
}
