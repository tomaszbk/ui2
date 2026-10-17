// vtest vflags: -d vml_interpreter -d ui2_headless
// vtest build: vml_conformance?
module main

import ui2

// The interpreted rectangles_resizable.vml equals the compiled one: the same tree, events
// and model state (ui2.vml_conformance).
fn test_rectangles_resizable_interpreted_vml_matches_compiled() {
	mut app := initial_resizable_rectangles()
	report := ui2.vml_conformance[ResizableRectanglesDemo](
		path:     @DIR + '/rectangles_resizable.vml'
		frame:    ui2.rect(0, 0, resizable_rectangles_width, resizable_rectangles_height)
		model:    &app
		reset:    fn (mut app ResizableRectanglesDemo) {
			app = initial_resizable_rectangles()
		}
		compiled: rectangles_resizable_tree
	) or { panic(err) }
	println(report)
	assert report.equal(), report.str()
}
