// vtest vflags: -d vml_interpreter -d ui2_headless
// vtest build: vml_conformance?
module main

import ui2

// The interpreted rgb_color.vml equals the compiled one: the same tree, events
// and model state (ui2.vml_conformance).
fn test_rgb_color_interpreted_vml_matches_compiled() {
	mut app := RgbColorDemo{}
	report := ui2.vml_conformance[RgbColorDemo](
		path:     @DIR + '/rgb_color.vml'
		frame:    ui2.rect(0, 0, rgb_color_width, rgb_color_height)
		model:    &app
		reset:    fn (mut app RgbColorDemo) {
			app = RgbColorDemo{}
		}
		compiled: rgb_color_tree
	) or { panic(err) }
	println(report)
	assert report.equal(), report.str()
}
