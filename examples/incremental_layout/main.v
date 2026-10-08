module main

import ui2
import os
import json2

// The compiled runner and V builders share retained layout. The compiler's
// grammar migration is a separate roadmap item; this is its typed builder API.
pub struct LayoutDemo {
pub mut:
	long_text bool
	blue      bool
}

fn message(model LayoutDemo) ui2.Element {
	return ui2.label('message', if model.long_text {
		'El texto cambia de tamaño. Ñ, acentos y edición permanecen intactos. Los hermanos de esta columna se desplazan según el ancho asignado.'
	} else {
		'Un texto breve con ñ y acentos.'
	}, ui2.Rect{}, ui2.TextStyle{
		size:  20
		lines: 20
		color: if model.blue {
			u32(0x2563eb)
		} else {
			u32(0x172033)
		}
	})
}

pub fn (mut model LayoutDemo) change_text() {
	model.long_text = !model.long_text
	ui2.refresh_element('message', message(model))
}

pub fn (mut model LayoutDemo) change_color() {
	model.blue = !model.blue
	ui2.refresh_element('message', message(model))
}

fn control(mut model LayoutDemo, id string, title string, action string) ui2.Element {
	return ui2.Element{
		...ui2.button(id, title, ui2.rect(0, 0, 145, 38), ui2.BoxStyle{ bg: 0xe8edf5, radius: 6 }, ui2.TextStyle{})
		on_event: ui2.compiled_vml_callback(mut model, ui2.CompiledVmlCallbackConfig{ action_name: action })
	}
}

fn build(mut model LayoutDemo) ui2.Element {
	bounds := ui2.bounds()
	return build_at(mut model, if bounds.width > 100 { bounds.width - 48 } else { 52.0 })
}

fn build_at(mut model LayoutDemo, width f64) ui2.Element {
	toolbar := ui2.flex(ui2.FlexConfig{
		id:       'toolbar'
		frame:    ui2.rect(0, 0, width, 40)
		gap:      12
		children: [
			ui2.FlexChild{ element: control(mut model, 'color', 'Cambiar color', 'change_color') },
			ui2.FlexChild{ element: control(mut model, 'text', 'Cambiar texto', 'change_text') },
		]
	}) or { panic(err) }
	content := ui2.flex(ui2.FlexConfig{
		id:          'content'
		frame:       ui2.rect(24, 24, width, 300)
		orientation: .vertical
		gap:         16
		align:       .stretch
		children:    [
			ui2.FlexChild{ element: ui2.label('title', 'Layout incremental', ui2.rect(0, 0, 0, 32), ui2.TextStyle{ size: 26, weight: 700 }) },
			ui2.FlexChild{ element: toolbar, shrink: 0 },
			ui2.FlexChild{ element: message(model), shrink: 0 },
			ui2.FlexChild{ element: ui2.text_input(ui2.TextInputConfig{ id: 'editor', text: 'Escribe aquí: ñ, café', frame: ui2.rect(0, 0, 0, 38), box: ui2.BoxStyle{ bg: 0x202833 }, text_style: ui2.TextStyle{ color: 0xffffff }, multiline: false }) or { panic(err) }, shrink: 0 },
		]
	}) or { panic(err) }
	return ui2.screen(0xf5f7fb, [content])
}

// Compare identical declarations/configuration with an explicitly uncached
// reconstruction reference. Counts describe actual work, not a speed claim.
fn measurements() {
	for scenario in ['color', 'text'] {
		for policy in ['reconstruct', 'retained_build', 'subtree_patch'] {
			mut model := LayoutDemo{}
			mut tree := ui2.LayoutTree{}
			tree.replace(build_at(mut model, 612)) or { panic(err) }
			_ = tree.resolve(ui2.LayoutConstraints{}, ui2.measure_layout_text, ui2.LayoutEnvironment{}) or { panic(err) }
			tree.reset_stats()
			for i in 0 .. 20 {
				if scenario == 'color' {
					model.blue = i % 2 == 0
				} else {
					model.long_text = i % 2 == 0
				}
				if policy == 'reconstruct' { tree.clear() }
				if policy == 'subtree_patch' {
					tree.patch('message', message(model)) or { panic(err) }
				} else {
					tree.replace(build_at(mut model, 612)) or { panic(err) }
				}
				_ = tree.resolve(ui2.LayoutConstraints{}, ui2.measure_layout_text, ui2.LayoutEnvironment{}) or { panic(err) }
			}
			println('${scenario} ${policy} ${json2.encode(tree.stats())}')
		}
	}
}

fn main() {
	if '--measure' in os.args {
		measurements()
		return
	}
	ui2.run_compiled_vml[LayoutDemo](
		model:  LayoutDemo{ long_text: '--long' in os.args }
		build:  build
		title:  'Incremental layout'
		width:  660
		height: 380
	) or { panic(err) }
}
