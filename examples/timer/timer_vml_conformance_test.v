// vtest vflags: -d vml_interpreter -d ui2_headless
// vtest build: vml_conformance?
module main

import ui2

// The interpreted timer.vml equals the compiled one: the same tree, events
// and model state (ui2.vml_conformance).
fn test_timer_interpreted_vml_matches_compiled() {
	callbacks := timer_callbacks()
	report := ui2.vml_conformance[TimerDemo](
		path:      @DIR + '/timer.vml'
		frame:     ui2.rect(0, 0, timer_width, timer_height)
		model:     timer_state
		reset:     fn (mut app TimerDemo) {
			app = TimerDemo{}
		}
		compiled:  timer_tree
		callbacks: {
			'callback_duration_slider': callbacks['duration_slider'] or { panic('missing duration_slider callback') }
			'callback_start':           callbacks['start'] or { panic('missing start callback') }
			'callback_pause':           callbacks['pause'] or { panic('missing pause callback') }
		}
	) or { panic(err) }
	println(report)
	assert report.equal(), report.str()
}
