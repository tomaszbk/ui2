// vtest vflags: -d vml_interpreter -d ui2_headless
// vtest build: vml_conformance?
module main

import ui2

// The interpreted demo_event.vml equals the compiled one: the same tree, events
// and model state (ui2.vml_conformance).
fn test_demo_event_interpreted_vml_matches_compiled() {
	callbacks := demo_event_callbacks()
	report := ui2.vml_conformance[DemoEvent](
		path:      @DIR + '/demo_event.vml'
		frame:     ui2.rect(0, 0, demo_event_width, demo_event_height)
		model:     demo_event_state
		reset:     fn (mut app DemoEvent) {
			app = DemoEvent{}
		}
		compiled:  demo_event_tree
		callbacks: {
			'callback_sample_button': callbacks['sample_button'] or { panic('missing sample_button callback') }
			'callback_clear':         callbacks['clear'] or { panic('missing clear callback') }
			'callback_event_surface': callbacks['event_surface'] or { panic('missing event_surface callback') }
		}
	) or { panic(err) }
	println(report)
	assert report.equal(), report.str()
}
