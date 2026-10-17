// vtest vflags: -d vml_interpreter -d ui2_headless
// vtest build: vml_conformance?
module main

import ui2

// The interpreted accent_color.vml equals the compiled one: the same tree, events
// and model state (ui2.vml_conformance).
fn test_accent_color_interpreted_vml_matches_compiled() {
	callbacks := accent_color_callbacks()
	report := ui2.vml_conformance[AccentColorDemo](
		path:      @DIR + '/accent_color.vml'
		frame:     ui2.rect(0, 0, accent_color_width, accent_color_height)
		model:     accent_color_state
		reset:     fn (mut app AccentColorDemo) {
			app = accent_color_demo()
		}
		compiled:  accent_color_tree
		callbacks: {
			'callback_reset':        callbacks['reset'] or { panic('missing reset callback') }
			'callback_track_red':    callbacks['track_red'] or { panic('missing track_red callback') }
			'callback_track_green':  callbacks['track_green'] or { panic('missing track_green callback') }
			'callback_track_blue':   callbacks['track_blue'] or { panic('missing track_blue callback') }
			'callback_subscribe':    callbacks['subscribe'] or { panic('missing subscribe callback') }
			'callback_sample_input': callbacks['sample_input'] or { panic('missing sample_input callback') }
		}
	) or { panic(err) }
	println(report)
	assert report.equal(), report.str()
}
