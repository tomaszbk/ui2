// vtest vflags: -d vml_interpreter -d ui2_headless
// vtest build: vml_conformance?
module main

import ui2

// The interpreted rectangles.vml equals the compiled one: the same tree, events
// and model state (ui2.vml_conformance).
fn test_rectangles_interpreted_vml_matches_compiled() {
	mut app := RectanglesDemo{}
	report := ui2.vml_conformance[RectanglesDemo](
		path:     @DIR + '/rectangles.vml'
		frame:    ui2.rect(0, 0, rectangles_width, rectangles_height)
		model:    &app
		reset:    fn (mut app RectanglesDemo) {
			app = RectanglesDemo{}
		}
		compiled: rectangles_tree
	) or { panic(err) }
	println(report)
	assert report.equal(), report.str()
}
