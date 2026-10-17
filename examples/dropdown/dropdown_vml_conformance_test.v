// vtest vflags: -d vml_interpreter -d ui2_headless
// vtest build: vml_conformance?
module main

import ui2

// The interpreted dropdown.vml equals the compiled one: the same tree, events
// and model state (ui2.vml_conformance).
fn test_dropdown_interpreted_vml_matches_compiled() {
	mut app := DropdownDemo{}
	report := ui2.vml_conformance[DropdownDemo](
		path:     @DIR + '/dropdown.vml'
		frame:    ui2.rect(0, 0, dropdown_width, dropdown_height)
		model:    &app
		reset:    fn (mut app DropdownDemo) {
			app = DropdownDemo{}
		}
		compiled: dropdown_tree
	) or { panic(err) }
	println(report)
	assert report.equal(), report.str()
}
