// vtest vflags: -d vml_interpreter -d ui2_headless
// vtest build: vml_conformance?
module main

import ui2

// The interpreted colorbox.vml equals the compiled one: the same tree, events
// and model state (ui2.vml_conformance).
fn test_colorbox_interpreted_vml_matches_compiled() {
	callbacks := colorbox_callbacks()
	report := ui2.vml_conformance[ColorBoxDemo](
		path:      @DIR + '/colorbox.vml'
		frame:     ui2.rect(0, 0, colorbox_width, colorbox_height)
		model:     colorbox_state
		reset:     fn (mut app ColorBoxDemo) {
			app = colorbox_demo()
		}
		compiled:  colorbox_tree
		callbacks: {
			'callback_store':       callbacks['store'] or { panic('missing store callback') }
			'callback_hue_strip':   callbacks['hue_strip'] or { panic('missing hue_strip callback') }
			'callback_sv_square':   callbacks['sv_square'] or { panic('missing sv_square callback') }
			'callback_swatch_grid': callbacks['swatch_grid'] or { panic('missing swatch_grid callback') }
			'callback_red_input':   callbacks['red_input'] or { panic('missing red_input callback') }
			'callback_green_input': callbacks['green_input'] or { panic('missing green_input callback') }
			'callback_blue_input':  callbacks['blue_input'] or { panic('missing blue_input callback') }
		}
	) or { panic(err) }
	println(report)
	assert report.equal(), report.str()
}
