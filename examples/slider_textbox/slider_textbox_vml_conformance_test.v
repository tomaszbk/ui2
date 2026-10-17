// vtest vflags: -d vml_interpreter -d ui2_headless
// vtest build: vml_conformance?
module main

import ui2

// The interpreted slider_textbox.vml equals the compiled one: the same tree, events
// and model state (ui2.vml_conformance).
fn test_slider_textbox_interpreted_vml_matches_compiled() {
	callbacks := slider_textbox_callbacks()
	report := ui2.vml_conformance[SliderTextboxDemo](
		path:      @DIR + '/slider_textbox.vml'
		frame:     ui2.rect(0, 0, slider_textbox_width, slider_textbox_height)
		model:     slider_textbox_state
		reset:     fn (mut app SliderTextboxDemo) {
			app = slider_textbox_demo()
		}
		compiled:  slider_textbox_tree
		callbacks: {
			'callback_reset':             callbacks['reset'] or { panic('missing reset callback') }
			'callback_horizontal_input':  callbacks['horizontal_input'] or { panic('missing horizontal_input callback') }
			'callback_horizontal_slider': callbacks['horizontal_slider'] or { panic('missing horizontal_slider callback') }
			'callback_vertical_input':    callbacks['vertical_input'] or { panic('missing vertical_input callback') }
			'callback_vertical_slider':   callbacks['vertical_slider'] or { panic('missing vertical_slider callback') }
		}
	) or { panic(err) }
	println(report)
	assert report.equal(), report.str()
}
