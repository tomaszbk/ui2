// vtest vflags: -d vml_interpreter -d ui2_headless
// vtest build: vml_conformance?
module main

import ui2

// The interpreted gradient_texture.vml equals the compiled one: the same tree, events
// and model state (ui2.vml_conformance).
fn test_gradient_texture_interpreted_vml_matches_compiled() {
	mut app := gradient_demo(0)
	report := ui2.vml_conformance[GradientTextureDemo](
		path:     @DIR + '/gradient_texture.vml'
		frame:    ui2.rect(0, 0, gradient_texture_width, gradient_texture_height)
		model:    &app
		reset:    fn (mut app GradientTextureDemo) {
			app = gradient_demo(0)
		}
		compiled: gradient_texture_tree
	) or { panic(err) }
	println(report)
	assert report.equal(), report.str()
}
