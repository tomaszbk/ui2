// vtest vflags: -d vml_interpreter -d ui2_headless
// vtest build: vml_conformance?
module main

import ui2

// The interpreted demo_style_4colors.vml equals the compiled one: the same tree, events
// and model state (ui2.vml_conformance).
fn test_demo_style_4colors_interpreted_vml_matches_compiled() {
	mut app := StyleFourColorsDemo{}
	report := ui2.vml_conformance[StyleFourColorsDemo](
		path:     @DIR + '/demo_style_4colors.vml'
		frame:    ui2.rect(0, 0, style_colors_width, style_colors_height)
		model:    &app
		reset:    fn (mut app StyleFourColorsDemo) {
			app = StyleFourColorsDemo{}
		}
		compiled: demo_style_4colors_tree
	) or { panic(err) }
	println(report)
	assert report.equal(), report.str()
}
