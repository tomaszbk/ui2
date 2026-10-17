// vtest vflags: -d vml_interpreter -d ui2_headless
// vtest build: vml_conformance?
module main

import ui2

// The interpreted double_listbox.vml equals the compiled one: the same tree, events
// and model state (ui2.vml_conformance).
fn test_double_listbox_interpreted_vml_matches_compiled() {
	mut app := initial_double_listbox()
	report := ui2.vml_conformance[DoubleListboxDemo](
		path:     @DIR + '/double_listbox.vml'
		frame:    ui2.rect(0, 0, double_list_width, double_list_height)
		model:    &app
		reset:    fn (mut app DoubleListboxDemo) {
			app = initial_double_listbox()
		}
		compiled: double_listbox_tree
	) or { panic(err) }
	println(report)
	assert report.equal(), report.str()
}
