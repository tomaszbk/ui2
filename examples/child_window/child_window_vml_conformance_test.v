// vtest vflags: -d vml_interpreter -d ui2_headless
// vtest build: vml_conformance?
module main

import ui2

// The interpreted child_window.vml equals the compiled one: the same tree, events
// and model state (ui2.vml_conformance).
fn test_child_window_interpreted_vml_matches_compiled() {
	callbacks := child_window_callbacks()
	report := ui2.vml_conformance[ChildWindowDemo](
		path:      @DIR + '/child_window.vml'
		frame:     ui2.rect(0, 0, child_window_width, child_window_height)
		model:     child_window_state
		reset:     fn (mut app ChildWindowDemo) {
			app = ChildWindowDemo{}
		}
		compiled:  child_window_tree
		callbacks: {
			'callback_create':         callbacks['create'] or { panic('missing create callback') }
			'callback_parent_input':   callbacks['parent_input'] or { panic('missing parent_input callback') }
			'callback_child_titlebar': callbacks['child_titlebar'] or { panic('missing child_titlebar callback') }
			'callback_close':          callbacks['close'] or { panic('missing close callback') }
			'callback_child_name':     callbacks['child_name'] or { panic('missing child_name callback') }
			'callback_genre':          callbacks['genre'] or { panic('missing genre callback') }
			'callback_greet':          callbacks['greet'] or { panic('missing greet callback') }
		}
	) or { panic(err) }
	println(report)
	assert report.equal(), report.str()
}
