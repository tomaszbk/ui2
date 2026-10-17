// vtest vflags: -d vml_interpreter -d ui2_headless
// vtest build: vml_conformance?
module main

import ui2

// The interpreted resizable_menu_window.vml equals the compiled one: the same tree, events
// and model state (ui2.vml_conformance).
fn test_resizable_menu_window_interpreted_vml_matches_compiled() {
	mut app := ResizableMenuDemo{}
	report := ui2.vml_conformance[ResizableMenuDemo](
		path:     @DIR + '/resizable_menu_window.vml'
		frame:    ui2.rect(0, 0, menu_window_width, menu_window_height)
		model:    &app
		reset:    fn (mut app ResizableMenuDemo) {
			app = ResizableMenuDemo{}
		}
		compiled: resizable_menu_window_tree
	) or { panic(err) }
	println(report)
	assert report.equal(), report.str()
}
