// vtest vflags: -d ui2_headless
module ui2

fn test_overlay_portals_escape_scroll_clip_and_follow_projected_anchor() ! {
	anchor := Element{ kind: .button, id: 'anchor', frame: rect(10, 120, 70, 24) }
	popup := with_overlay(view('popup', rect(0, 0, 140, 80), BoxStyle{}, [
		Element{ kind: .button, id: 'choice', frame: rect(8, 8, 120, 28) },
	]), OverlayConfig{ open: true, anchor: 'anchor' })!
	pane := Element{
		kind:     .scroll
		id:       'pane'
		frame:    rect(30, 20, 200, 100)
		children: [
			anchor,
			popup,
		]
	}
	root := screen(0xffffff, [pane])
	mut source_geometry := FocusManager{}
	source_geometry.update_mounted(root, map[string]f64{}, rect(0, 0, 400, 300), ContentTransform{})
	path := (source_geometry.node('pane') or { panic('pane') }).path
	mut tree := OverlayTree{}
	projected := tree.resolve(root, {
		path: 60.0
	}, rect(0, 0, 400, 300), 0)!
	mut focus := FocusManager{}
	focus.update_mounted(projected, {
		path: 60.0
	}, rect(0, 0, 400, 300), ContentTransform{})
	surface := focus.node('popup') or { panic('portal missing') }
	assert surface.frame == rect(40, 110, 140, 80)
	choice := focus.node('choice') or { panic('choice missing') }
	assert choice.clip.bounds() == rect(40, 110, 140, 80)
	assert choice.frame == rect(48, 118, 120, 28)
	assert projected.children[0].children[0].children.len == 1
	assert tree.resolve(root, {
		path: 60.0
	}, rect(0, 0, 400, 300), 0)! == projected
}

fn test_overlay_dialog_inerts_background_and_keeps_closed_editor_mounted() ! {
	dialog := with_overlay(view('dialog', rect(0, 0, 180, 100), BoxStyle{}, [
		Element{ kind: .text_field, id: 'draft', frame: rect(8, 8, 160, 28), text: 'España ñ' },
	]), OverlayConfig{ kind: .dialog, open: true })!
	root := screen(0xffffff, [Element{ kind: .button, id: 'outside' }, dialog])
	mut tree := OverlayTree{}
	mut focus := FocusManager{}
	focus.update(tree.resolve(root, map[string]f64{}, rect(0, 0, 400, 300), 0)!, map[string]f64{})
	assert !focus.can_focus('outside')
	assert focus.can_focus('draft')
	assert !focus.can_focus('dialog__backdrop')
	closed := with_overlay(view('dialog', dialog.frame, dialog.box, dialog.children), OverlayConfig{ kind: .dialog })!
	focus.update(tree.resolve(screen(0xffffff, [
		Element{ kind: .button, id: 'outside' },
		closed,
	]), map[string]f64{}, rect(0, 0, 400, 300), 0)!, map[string]f64{})
	assert focus.can_focus('outside')
	assert !focus.can_focus('draft')
	assert (focus.node('draft') or { panic('closed editor was unmounted') }).el.text == 'España ñ'
}

fn test_overlay_disappearing_anchor_blocks_input_without_retiring_owner() ! {
	popup := with_overlay(view('popup', rect(0, 0, 140, 80), BoxStyle{}, [Element{ kind: .button, id: 'choice', frame: rect(0, 0, 120, 28) }]), OverlayConfig{ anchor: 'removed', open: true })!
	mut tree := OverlayTree{}
	mut focus := FocusManager{}
	focus.update(tree.resolve(screen(0xffffff, [popup]), map[string]f64{}, rect(0, 0, 400, 300), 0)!, map[string]f64{})
	assert !focus.can_focus('choice')
	assert tree.top_active() == none
	assert focus.node('choice') != none
}

fn test_overlay_reserves_backdrop_identity_and_rejects_collisions() ! {
	dialog := with_overlay(view('dialog', rect(0, 0, 100, 80), BoxStyle{}, []), OverlayConfig{ kind: .dialog })!
	mut tree := OverlayTree{}
	tree.resolve(screen(0xffffff, [dialog, Element{ kind: .button, id: 'dialog__backdrop' }]),
		map[string]f64{}, rect(0, 0, 400, 300), 0) or {
		assert err.msg().contains('collides')
		return
	}
	assert false, 'colliding generated backdrop id accepted'
}
