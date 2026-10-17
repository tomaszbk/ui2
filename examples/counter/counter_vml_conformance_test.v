// vtest vflags: -d vml_interpreter -d ui2_headless
// vtest build: vml_conformance?
module main

import ui2

// The interpreted app.vml equals the compiled one: the same tree, events
// and model state (ui2.vml_conformance).
fn test_counter_interpreted_vml_matches_compiled() {
	mut app := CounterApp{}
	report := ui2.vml_conformance[CounterApp](
		path:     @DIR + '/app.vml'
		frame:    ui2.rect(0, 0, counter_width, counter_height)
		model:    &app
		reset:    fn (mut app CounterApp) {
			app = CounterApp{}
		}
		compiled: counter_tree
	) or { panic(err) }
	println(report)
	assert report.equal(), report.str()
}
