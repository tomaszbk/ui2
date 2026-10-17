// vtest vflags: -d vml_interpreter -d ui2_headless
// vtest build: vml_conformance?
module main

import ui2

// The interpreted tray_icon.vml equals the compiled one: the same tree, events
// and model state (ui2.vml_conformance).
fn test_tray_icon_interpreted_vml_matches_compiled() {
	callbacks := tray_icon_callbacks()
	report := ui2.vml_conformance[TrayDemo](
		path:      @DIR + '/tray_icon.vml'
		frame:     ui2.rect(0, 0, tray_icon_width, tray_icon_height)
		model:     tray_demo_state
		reset:     fn (mut app TrayDemo) {
			app = TrayDemo{}
		}
		compiled:  tray_icon_tree
		callbacks: {
			'callback_tray_show':          callbacks['tray_show'] or { panic('missing tray_show callback') }
			'callback_tray_hide':          callbacks['tray_hide'] or { panic('missing tray_hide callback') }
			'callback_tray_status':        callbacks['tray_status'] or { panic('missing tray_status callback') }
			'callback_tray_notifications': callbacks['tray_notifications'] or { panic('missing tray_notifications callback') }
			'callback_status_available':   callbacks['status_available'] or { panic('missing status_available callback') }
			'callback_status_busy':        callbacks['status_busy'] or { panic('missing status_busy callback') }
			'callback_status_away':        callbacks['status_away'] or { panic('missing status_away callback') }
		}
	) or { panic(err) }
	println(report)
	assert report.equal(), report.str()
}
