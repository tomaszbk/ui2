// vtest vflags: -d vml_interpreter -d ui2_headless
// vtest build: vml_conformance?
module main

import ui2

// The interpreted box_layout_with_textbox.vml equals the compiled one: the same tree, events
// and model state (ui2.vml_conformance).
fn test_box_layout_with_textbox_interpreted_vml_matches_compiled() {
	mut app := initial_box_layout_textbox()
	report := ui2.vml_conformance[BoxLayoutTextboxDemo](
		path:     @DIR + '/box_layout_with_textbox.vml'
		frame:    ui2.rect(0, 0, box_textbox_width, box_textbox_height)
		model:    &app
		reset:    fn (mut app BoxLayoutTextboxDemo) {
			app = initial_box_layout_textbox()
		}
		compiled: box_layout_with_textbox_tree
	) or { panic(err) }
	println(report)
	assert report.equal(), report.str()
}
