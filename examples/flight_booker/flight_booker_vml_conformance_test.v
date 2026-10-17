// vtest vflags: -d vml_interpreter -d ui2_headless
// vtest build: vml_conformance?
module main

import ui2

// The interpreted flight_booker.vml equals the compiled one: the same tree, events
// and model state (ui2.vml_conformance).
fn test_flight_booker_interpreted_vml_matches_compiled() {
	mut app := initial_flight_booker()
	report := ui2.vml_conformance[FlightBooker](
		path:     @DIR + '/flight_booker.vml'
		frame:    ui2.rect(0, 0, flight_booker_width, flight_booker_height)
		model:    &app
		reset:    fn (mut app FlightBooker) {
			app = initial_flight_booker()
		}
		compiled: flight_booker_tree
	) or { panic(err) }
	println(report)
	assert report.equal(), report.str()
}
