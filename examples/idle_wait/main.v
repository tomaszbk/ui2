@[has_globals]
module main

import time
import ui2

__global g_idle_example_message = 'Hover here, then load a result'

fn main() {
	ui2.run_window('Idle wait', 520, 220, build)
}

fn build() ui2.Element {
	style := ui2.TextStyle{ size: 16, color: 0x172033 }
	box := ui2.BoxStyle{ bg: 0xdbeafe, radius: 6 }
	return ui2.screen(0xf8fafc, [
		ui2.with_tooltip(ui2.label('status', g_idle_example_message, ui2.rect(20, 20, 480, 36), style),
			'This deadline also works with a stationary pointer.'),
		ui2.with_event(ui2.button('load', 'Load result', ui2.rect(20, 70, 140, 36), box, style), load),
		ui2.text_input(
			id:         'draft'
			text:       'Hello / Hola, año'
			frame:      ui2.rect(20, 130, 480, 36)
			box:        box
			text_style: style
		) or { panic(err) },
	])
}

fn load(event ui2.ElementEvent) {
	if event.kind != .tap { return }
	$if linux || ( macos && ui2_custom_rendering ?) || ( windows && ui2_custom_rendering ?) {
		// Capture on UI; the worker only computes and posts. Local editing and
		// selection survive the unrelated status rebuild.
		dispatcher := ui2.ui_dispatcher()
		spawn load_worker(dispatcher)
	} $else {
		g_idle_example_message = 'Run with -d ui2_custom_rendering for the dispatcher example'
		ui2.refresh()
	}
}

fn load_worker(dispatcher ui2.UiDispatcher) {
	time.sleep(750 * time.millisecond)
	dispatcher.post(fn () { g_idle_example_message = 'Worker result / Resultado recibido' })
}
