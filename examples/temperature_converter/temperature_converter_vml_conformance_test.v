// vtest vflags: -d vml_interpreter -d ui2_headless
// vtest build: vml_conformance?
module main

import ui2

// The interpreted temperature_converter.vml equals the compiled one: the same tree, events
// and model state (ui2.vml_conformance).
fn test_temperature_converter_interpreted_vml_matches_compiled() {
	mut app := TemperatureConverter{}
	report := ui2.vml_conformance[TemperatureConverter](
		path:     @DIR + '/temperature_converter.vml'
		frame:    ui2.rect(0, 0, temperature_width, temperature_height)
		model:    &app
		reset:    fn (mut app TemperatureConverter) {
			app = TemperatureConverter{}
		}
		compiled: temperature_converter_tree
	) or { panic(err) }
	println(report)
	assert report.equal(), report.str()
}
