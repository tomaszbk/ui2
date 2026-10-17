// vtest vflags: -d vml_interpreter -d ui2_headless
// vtest build: vml_conformance?
module main

import ui2

// The interpreted carousel.vml equals the compiled one: the same tree, events
// and model state (ui2.vml_conformance).
fn test_carousel_interpreted_vml_matches_compiled() {
	mut app := CarouselDemo{}
	report := ui2.vml_conformance[CarouselDemo](
		path:     @DIR + '/carousel.vml'
		frame:    ui2.rect(0, 0, carousel_width, carousel_height)
		model:    &app
		reset:    fn (mut app CarouselDemo) {
			app = CarouselDemo{}
		}
		compiled: carousel_tree
	) or { panic(err) }
	println(report)
	assert report.equal(), report.str()
}
