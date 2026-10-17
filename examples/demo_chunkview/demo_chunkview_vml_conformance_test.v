// vtest vflags: -d vml_interpreter -d ui2_headless
// vtest build: vml_conformance?
module main

import ui2

// The interpreted demo_chunkview.vml equals the compiled one: the same tree, events
// and model state (ui2.vml_conformance).
fn test_demo_chunkview_interpreted_vml_matches_compiled() {
	mut app := ChunkviewDemo{}
	report := ui2.vml_conformance[ChunkviewDemo](
		path:     @DIR + '/demo_chunkview.vml'
		frame:    ui2.rect(0, 0, chunkview_width, chunkview_height)
		model:    &app
		reset:    fn (mut app ChunkviewDemo) {
			app = ChunkviewDemo{}
		}
		compiled: demo_chunkview_tree
	) or { panic(err) }
	println(report)
	assert report.equal(), report.str()
}
