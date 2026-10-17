module main

import ui2

// build_generic is form.vml written by hand in the shape of the generic
// lowering (props nodes through ui2.vml_document/vml_root/vml_child/
// vml_repeat), so both lowerings build the same document.
fn build_generic(mut app Calculator, frame ui2.Rect) ui2.Element {
	return build_generic_document(mut app, frame) or { panic(err) }
}

fn build_generic_document(mut app Calculator, frame ui2.Rect) !ui2.Element {
	mut d := ui2.vml_document(frame)!
	mut owner := d.owner
	mut root := ui2.vml_root(mut owner, ui2.ScreenProps{
		style: ui2.compose_styles([ui2.style_background(0xF1F5F9)])
	}, id: 'root', path: '0')!
	mut outer := ui2.vml_child(mut root, mut owner, ui2.AbsoluteProps{
		style: ui2.compose_styles([ui2.style_transparent(true)])
	}, path: '0.0')!
	mut panel := ui2.vml_child(mut outer, mut owner, ui2.ViewProps{
		x:     12
		y:     12
		style: ui2.compose_styles([ui2.style_background(0x1F2937), ui2.style_radius(12)])
	}, path: '0.0.0')!
	panel.prop('width', fn [root] (mut p ui2.ViewProps) ! {
		p.width = root.geometry()!.width - 24
	})!
	panel.prop('height', fn [root] (mut p ui2.ViewProps) ! {
		p.height = root.geometry()!.height - 24
	})!
	mut inner := ui2.vml_child(mut panel, mut owner, ui2.AbsoluteProps{
		style: ui2.compose_styles([ui2.style_transparent(true)])
	}, path: '0.0.0.0')!
	mut display := ui2.vml_child(mut inner, mut owner, ui2.LabelProps{
		x:      10
		y:      8
		height: 48
		style:  ui2.compose_styles([ui2.style_foreground(0xFFFFFF), ui2.style_font_size(28),
			ui2.style_text_align(.right)])
	}, path: '0.0.0.0.0')!
	display.prop('text', fn [mut app, mut owner] (mut p ui2.LabelProps) ! {
		owner.watch_app()!
		p.text = app.display
	})!
	display.prop('width', fn [root] (mut p ui2.LabelProps) ! {
		p.width = (root.geometry()!.width - 24) - 20
	})!
	ui2.vml_repeat(mut inner, '0_0_0_0_1', fn [mut app, mut owner] () ![]Key {
		owner.watch_app()!
		return app.keys
	}, fn (key Key) string {
		return key.text
	}, fn [root] (mut item_owner ui2.CompiledVmlComponent, mut segment ui2.VmlSegment, item_input &ui2.Signal[Key]) ! {
		mut item := unsafe { item_input }
		item_owner.state('@index', 0)!
		mut button := ui2.vml_child(mut segment, mut item_owner, ui2.ButtonProps{
			height: 44
		}, path: '0.0.0.0.1.0')!
		button.prop('text', fn [mut item] (mut p ui2.ButtonProps) ! {
			p.text = item.get()!.text
		})!
		button.prop('x', fn [mut item, root] (mut p ui2.ButtonProps) ! {
			p.x = 6 + item.get()!.column * ((((root.geometry()!.width - 24) - 30) / 4) + 6)
		})!
		button.prop('y', fn [mut item] (mut p ui2.ButtonProps) ! {
			p.y = 64 + item.get()!.row * 50
		})!
		button.prop('width', fn [root] (mut p ui2.ButtonProps) ! {
			p.width = ((root.geometry()!.width - 24) - 30) / 4
		})!
		button.prop('style', fn [mut item] (mut p ui2.ButtonProps) ! {
			key := item.get()!
			operator := key.role == 'operator'
			p.style = ui2.compose_styles([
				ui2.style_background(if operator { u32(0x3478D4) } else { u32(0xF8FAFC) }),
				ui2.style_foreground(if operator { u32(0xFFFFFF) } else { u32(0x111827) }),
				ui2.style_font_size(18),
				ui2.style_weight(if key.text == '=' { 700 } else { 400 }),
				ui2.style_text_align(.center),
				ui2.style_radius(8),
			])
		})!
	}, source: 'form.vml', line: 23, column: 17)!
	return d.finish()!
}
