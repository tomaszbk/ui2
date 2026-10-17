// vtest vflags: -d vml_interpreter -d ui2_headless
// vtest build: vml_conformance?
module main

import ui2

// The interpreted custom_window.vml equals the compiled one: the same tree, events
// and model state (ui2.vml_conformance).
fn test_custom_window_interpreted_vml_matches_compiled() {
	callbacks := custom_window_callbacks()
	report := ui2.vml_conformance[CustomWindowDemo](
		path:      @DIR + '/custom_window.vml'
		frame:     ui2.rect(0, 0, custom_window_width, custom_window_height)
		model:     custom_window_state
		reset:     fn (mut app CustomWindowDemo) {
			app = CustomWindowDemo{}
		}
		compiled:  custom_window_tree
		callbacks: {
			'callback_window_drag': callbacks['window_drag'] or { panic('missing window_drag callback') }
			'callback_close':       callbacks['close'] or { panic('missing close callback') }
			'callback_decrement':   callbacks['decrement'] or { panic('missing decrement callback') }
			'callback_reset':       callbacks['reset'] or { panic('missing reset callback') }
			'callback_increment':   callbacks['increment'] or { panic('missing increment callback') }
		}
	) or { panic(err) }
	println(report)
	assert report.equal(), report.str()
}
