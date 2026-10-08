@[has_globals]
module main

import ui2 as ui

__global activations = 0
__global unrelated = 0
__global last_action = 'Use Tab / Shift-Tab, arrows, Enter and Space.'

fn activated(event ui.ElementEvent) {
	activations++
	last_action = '${event.id}: ${event.kind} (${activations})'
	println('activate ${event.id} count=${activations}')
	ui.refresh()
}

fn changed(event ui.ElementEvent) {
	println('edit ${event.id}: ${event.text}')
}

fn enter_panel(_event ui.ElementEvent) {
	ui.enter_focus_scope('panel')
	last_action = 'Panel scope: Tab wraps; Escape restores the previous focus.'
	ui.refresh()
}

fn leave_panel(_event ui.ElementEvent) {
	ui.leave_focus_scope()
	last_action = 'Restored focus: ${ui.focused_id()}'
	ui.refresh()
}

fn key(event ui.KeyEvent) {
	if event.code in [.tab, .enter, .space] { println('key ${event.code} shift=${event.shift}') }
	if event.code == .escape && ui.active_focus_scope().len > 0 {
		leave_panel(ui.ElementEvent{})
		ui.consume_key()
	}
	// F2 updates an unrelated label while editing. F3 replaces text explicitly.
	if event.code == .f2 {
		unrelated++
		println('refresh focus=${ui.focused_id()} text=${ui.text('editor')}')
		ui.refresh()
		ui.consume_key()
	}
	if event.code == .f3 {
		ui.set_text('editor', 'Replaced: ñ / á')
		ui.consume_key()
	}
	// F4 prints the portable hooks and focus; useful in native and custom mode.
	if event.code == .f4 {
		println('focus=${ui.focused_id()} scope=${ui.active_focus_scope()} scroll=${ui.scroll_offset('list')}')
		for node in ui.semantic_tree() {
			if node.id.len > 0 {
				println('semantic ${node.id}: ${node.role} name=${node.name} value=${node.value} focused=${node.state.focused}')
			}
		}
		ui.consume_key()
	}
}

fn navigation_button(id string, title string, x f64, y f64, callback ui.ElementCallback) ui.Element {
	return ui.with_event(ui.button(id, title, ui.rect(x, y, 160, 36),
		ui.BoxStyle{ bg: 0xe2e8f0, radius: 6 }, ui.TextStyle{ size: 14, color: 0x0f172a }), callback)
}

fn build() ui.Element {
	mut rows := []ui.Element{}
	for i in 0 .. 8 {
		rows << navigation_button('row-${i}', 'Mounted row ${i + 1}', 8, f64(i * 48 + 8), activated)
	}
	return ui.screen(0xf8fafc, [
		ui.label('title', 'Focus navigation', ui.rect(20, 16, 680, 36), ui.TextStyle{ size: 24, bold: true }),
		ui.label('help', 'F2: unrelated update   F3: set_text   F4: print semantic hooks', ui.rect(20, 55, 690, 26), ui.TextStyle{ size: 14 }),
		ui.Element{ kind: .text_field, id: 'editor', text: 'Español: ñ, á, café', on_event: changed, frame: ui.rect(20, 92, 360, 34), box: ui.BoxStyle{ bg: 0xffffff }, text_style: ui.TextStyle{ size: 16, color: 0x3478d4 }, accessibility_name: 'Editable Spanish text' },
		navigation_button('first', 'First', 20, 150, activated),
		navigation_button('right', 'Right', 210, 150, activated),
		navigation_button('below', 'Below', 20, 204, activated),
		navigation_button('enter-panel', 'Enter scope', 210, 204, enter_panel),
		ui.Element{ ...navigation_button('disabled', 'Disabled (skip)', 20, 258, activated), enabled: false },
		ui.Element{ ...navigation_button('hidden', 'Hidden (skip)', 210, 258, activated), hidden: true },
		ui.Element{
			kind:        .view
			id:          'panel'
			focus_scope: true
			frame:       ui.rect(420, 92, 260, 160)
			box:         ui.BoxStyle{ bg: 0xeef2ff }
			children:    [
				ui.label('', 'Independent focus scope', ui.rect(12, 8, 236, 26), ui.TextStyle{ size: 14 }),
				navigation_button('panel-a', 'Panel A', 12, 42, activated),
				navigation_button('panel-exit', 'Leave scope', 12, 94, leave_panel),
			]
		},
		ui.scroll('list', ui.rect(420, 280, 260, 150), 0xffffff, rows),
		ui.label('status', '${last_action}\nUnrelated updates: ${unrelated}', ui.rect(20, 330, 380, 80), ui.TextStyle{ size: 14, lines: 3 }),
	])
}

fn main() {
	ui.on_key_event(key)
	ui.run_window('UI2 Focus Navigation', 720, 470, build)
}
