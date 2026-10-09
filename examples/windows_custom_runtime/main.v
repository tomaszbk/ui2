module main

import ui2

struct RuntimeDemo {
mut:
	updates int
}

const runtime_demo = &RuntimeDemo{}

fn notes() string {
	mut lines := ['Mañana: café, lápiz y acción. Select text, then press Delete.']
	for index in 1 .. 40 {
		lines << '${index:02} — Editable notes: ñ, á, é, í, ó, ú.'
	}
	return lines.join('\n')
}

fn update_counter() {
	mut state := unsafe { runtime_demo }
	state.updates++
	ui2.request_refresh()
}

fn handle_key(event ui2.KeyEvent) {
	if event.code == .f6 {
		update_counter()
		ui2.consume_text_key()
	} else if event.code == .f7 {
		ui2.set_text('notes', notes())
		ui2.consume_text_key()
	}
}

fn handle_button(event ui2.ElementEvent) {
	if event.kind == .tap {
		update_counter()
	}
}

fn build() ui2.Element {
	b := ui2.bounds()
	style := ui2.TextStyle{ size: 16, color: 0x172554 }
	return ui2.screen(0xf1f5f9, [
		ui2.label('heading', 'Editable text and retained updates', ui2.rect(24, 20, b.width - 48, 32), ui2.TextStyle{ size: 22, bold: true, color: 0x172554 }),
		ui2.label('help', 'F6 updates the counter while you edit. F7 replaces the notes.', ui2.rect(24, 60, b.width - 48, 28), style),
		ui2.text_input(
			id:         'title'
			text:       'Mañana: café y acción'
			multiline:  false
			frame:      ui2.rect(24, 104, b.width - 48, 38)
			box:        ui2.BoxStyle{ bg: 0xffffff, radius: 4 }
			text_style: style
		) or { panic(err) },
		ui2.text_input(
			id:         'notes'
			text:       notes()
			frame:      ui2.rect(24, 160, b.width - 48, b.height - 244)
			box:        ui2.BoxStyle{ bg: 0xffffff, radius: 4 }
			text_style: style
		) or { panic(err) },
		ui2.label('counter', 'Unrelated updates: ${runtime_demo.updates}', ui2.rect(24, b.height - 64, 280, 40), style),
		ui2.with_event(ui2.button('update', 'Update counter', ui2.rect(b.width - 208, b.height - 64, 184, 40), ui2.BoxStyle{ bg: 0xdbeafe, radius: 4 }, style), handle_button),
	])
}

fn main() {
	ui2.on_key_event(handle_key)
	ui2.run_window('Windows custom runtime', 760, 560, build)
}
