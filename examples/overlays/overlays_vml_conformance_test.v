// vtest vflags: -d vml_interpreter -d ui2_headless
// vtest build: vml_conformance?
module main

import ui2

fn overlays_conformance_tree(mut app OverlayDemo, _ ui2.Rect) ui2.Element {
	return build_overlays(mut app)
}

// The interpreted overlays.vml equals the compiled one: the same tree, events
// and model state (ui2.vml_conformance). Like overlays_test.v, it runs with
// reduced motion, so surfaces open and close without a running animation
// driver.
fn test_overlays_interpreted_vml_matches_compiled() {
	mut app := OverlayDemo{
		reduced_motion: true
	}
	report := ui2.vml_conformance[OverlayDemo](
		path:            @DIR + '/overlays.vml'
		frame:           ui2.rect(0, 0, overlays_width, overlays_height)
		model:           &app
		reset:           fn (mut app OverlayDemo) {
			app = OverlayDemo{
				reduced_motion: true
			}
		}
		compiled:        overlays_conformance_tree
		follow_viewport: true
	) or { panic(err) }
	println(report)
	assert report.equal(), report.str()
}
