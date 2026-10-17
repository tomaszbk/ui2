// vtest vflags: -d vml_interpreter -d ui2_headless
// vtest build: vml_conformance?
module main

import ui2

// The interpreted canvas_layout.vml equals the compiled one: the same tree, events
// and model state (ui2.vml_conformance).
fn test_canvas_layout_interpreted_vml_matches_compiled() {
	callbacks := canvas_layout_callbacks()
	report := ui2.vml_conformance[CanvasLayoutDemo](
		path:      @DIR + '/canvas_layout.vml'
		frame:     ui2.rect(0, 0, canvas_layout_width, canvas_layout_height)
		model:     canvas_layout_state
		reset:     fn (mut app CanvasLayoutDemo) {
			app = CanvasLayoutDemo{}
		}
		compiled:  canvas_layout_tree
		callbacks: {
			'callback_theme_dropdown': callbacks['theme_dropdown'] or { panic('missing theme_dropdown callback') }
			'callback_about':          callbacks['about'] or { panic('missing about callback') }
			'callback_clear_notes':    callbacks['clear_notes'] or { panic('missing clear_notes callback') }
			'callback_add_note':       callbacks['add_note'] or { panic('missing add_note callback') }
			'callback_reset_tile':     callbacks['reset_tile'] or { panic('missing reset_tile callback') }
			'callback_toggle_menu':    callbacks['toggle_menu'] or { panic('missing toggle_menu callback') }
			'callback_canvas_sheet':   callbacks['canvas_sheet'] or { panic('missing canvas_sheet callback') }
			'callback_menu_delete':    callbacks['menu_delete'] or { panic('missing menu_delete callback') }
			'callback_menu_export':    callbacks['menu_export'] or { panic('missing menu_export callback') }
			'callback_menu_exit':      callbacks['menu_exit'] or { panic('missing menu_exit callback') }
			'callback_canvas_tile':    callbacks['canvas_tile'] or { panic('missing canvas_tile callback') }
		}
	) or { panic(err) }
	println(report)
	assert report.equal(), report.str()
}
