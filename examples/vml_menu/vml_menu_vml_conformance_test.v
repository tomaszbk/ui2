// vtest vflags: -d vml_interpreter -d ui2_headless
// vtest build: vml_conformance?
module main

import ui2

// The interpreted menus.vml declares the same application menus as the
// compiled one.
fn test_vml_menu_interpreted_vml_matches_compiled() {
	callbacks := menu_callbacks()
	mut named := map[string]ui2.ElementCallback{}
	for name, callback in callbacks {
		named['callback_${name}'] = callback
	}
	report := ui2.vml_conformance_menu_document(@DIR + '/menus.vml', build_menus(), named) or {
		panic(err)
	}
	println(report)
	assert report.equal(), report.str()
}
