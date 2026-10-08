module main

import os
import ui2

const picker_width = 720
const picker_height = 520

@[heap]
struct PickerDemo {
mut:
	picker    &ui2.FilePicker = unsafe { nil }
	selection string          = 'Choose a mode to open the in-window picker.'
}

const picker_demo = &PickerDemo{}

fn picker_launch(kind ui2.FileDialogKind) ui2.ElementCallback {
	return fn [kind] (_event ui2.ElementEvent) {
		mut state := unsafe { picker_demo }
		state.picker = ui2.new_file_picker(
			id:        'demo_picker'
			dialog:    ui2.FileDialogConfig{
				kind:      kind
				directory: os.getwd()
				filename:  'new_file.txt'
				multiple:  true
			}
			on_result: fn (result ui2.FilePickerResult) {
				mut state := unsafe { picker_demo }
				state.selection = if result.kind == .selected {
					result.paths.join('\n')
				} else {
					'Cancelled.'
				}
				ui2.refresh()
			}
		) or {
			state.selection = 'Cannot open picker: ${err}'
			ui2.refresh()
			return
		}
		state.picker.open() or { state.selection = 'Cannot open picker: ${err}' }
		ui2.refresh()
	}
}

fn build_picker_demo() ui2.Element {
	mut state := unsafe { picker_demo }
	button_box := ui2.BoxStyle{ bg: 0x2563eb, radius: 6 }
	button_text := ui2.TextStyle{ color: 0xffffff }
	mut children := [
		ui2.label('heading', 'Custom file picker', ui2.rect(24, 20, 660, 32), ui2.TextStyle{ size: 22, bold: true }),
		ui2.label('description', 'Browse files inside this window, without desktop dialog helpers.', ui2.rect(24, 58, 660, 24), ui2.TextStyle{ color: 0x475569, size: 13 }),
		ui2.with_event(ui2.button('open', 'Open files', ui2.rect(24, 112, 140, 38), button_box, button_text), picker_launch(.open)),
		ui2.with_event(ui2.button('save', 'Save file', ui2.rect(176, 112, 140, 38), button_box, button_text), picker_launch(.save)),
		ui2.with_event(ui2.button('folder', 'Choose folder', ui2.rect(328, 112, 160, 38), button_box, button_text), picker_launch(.folder)),
		ui2.label('selection', state.selection, ui2.rect(24, 180, 670, 80), ui2.TextStyle{ color: 0x166534, size: 14 }),
	]
	if state.picker != unsafe { nil } {
		children << state.picker.render(ui2.rect(0, 0, picker_width, picker_height))
	}
	return ui2.screen(0xf1f5f9, children)
}

fn main() {
	ui2.run_window('Custom file picker', picker_width, picker_height, build_picker_demo)
}
