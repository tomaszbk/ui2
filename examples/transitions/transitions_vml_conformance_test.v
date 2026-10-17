// vtest vflags: -d vml_interpreter -d ui2_headless
// vtest build: vml_conformance?
module main

import ui2

// The interpreted transitions.vml equals the compiled one: the same tree, events
// and model state (ui2.vml_conformance).
fn test_transitions_interpreted_vml_matches_compiled() {
	callbacks := transitions_callbacks()
	report := ui2.vml_conformance[TransitionsDemo](
		path:      @DIR + '/transitions.vml'
		frame:     ui2.rect(0, 0, transitions_width, transitions_height)
		model:     transitions_state
		reset:     fn (mut app TransitionsDemo) {
			app = TransitionsDemo{}
		}
		compiled:  transitions_tree
		callbacks: {
			'callback_slide': callbacks['slide'] or { panic('missing slide callback') }
		}
	) or { panic(err) }
	println(report)
	assert report.equal(), report.str()
}
