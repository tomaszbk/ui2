// vtest vflags: -d vml_interpreter -d ui2_headless
// vtest build: vml_conformance?
module main

import ui2

// The interpreted fontchooser.vml equals the compiled one: the same tree, events
// and model state (ui2.vml_conformance).
fn test_fontchooser_interpreted_vml_matches_compiled() {
	mut app := FontChooserDemo{}
	report := ui2.vml_conformance[FontChooserDemo](
		path:     @DIR + '/fontchooser.vml'
		frame:    ui2.rect(0, 0, fontchooser_width, fontchooser_height)
		model:    &app
		reset:    fn (mut app FontChooserDemo) {
			app = FontChooserDemo{}
		}
		compiled: fontchooser_tree
	) or { panic(err) }
	println(report)
	assert report.equal(), report.str()
}
