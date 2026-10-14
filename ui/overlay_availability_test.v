// vtest vflags: -d ui2_headless
module ui2

fn overlay_availability_pane() Element {
	return Element{
		kind:     .scroll
		id:       'pane'
		frame:    rect(20, 20, 120, 50)
		children: [button('clipped_anchor', 'Anchor', rect(0, 120, 100, 24), BoxStyle{}, TextStyle{})]
	}
}

fn overlay_availability_outside() Element {
	return button('outside', 'Outside', rect(200, 20, 100, 24), BoxStyle{}, TextStyle{})
}

fn test_clipped_dialog_anchor_does_not_leave_an_invisible_modal_input_gate() ! {
	dialog := with_overlay(view('dialog', rect(0, 0, 160, 100), BoxStyle{}, [
		button('inside', 'Inside', rect(8, 8, 100, 24), BoxStyle{}, TextStyle{}),
	]), OverlayConfig{ kind: .dialog, open: true, anchor: 'clipped_anchor' })!
	root := screen(0xffffff, [overlay_availability_outside(), overlay_availability_pane(), dialog])
	viewport := rect(0, 0, 400, 300)
	mut tree := OverlayTree{}
	mut focus := FocusManager{}
	focus.update_mounted(tree.resolve(root, map[string]f64{}, viewport, 0)!, map[string]f64{}, viewport, ContentTransform{})
	assert tree.modal == ''
	assert tree.top_active() == none
	assert !tree.layers[tree.layer_index('dialog')].available
	assert focus.can_focus('outside')
	assert !focus.can_focus('inside')
	assert (focus.node('dialog') or { panic('dialog was retired') }).hidden
	assert focus.node('inside') != none
}

fn test_unavailable_portal_blocks_authored_owner_explicit_owner_and_anchor_dependents() ! {
	for relation in ['authored', 'owner', 'anchor'] {
		config := match relation {
			'owner' { OverlayConfig{ kind: .dialog, open: true, owner: 'portal' } }
			'anchor' { OverlayConfig{ kind: .dialog, open: true, anchor: 'inner_anchor' } }
			else { OverlayConfig{ kind: .dialog, open: true } }
		}
		dialog := with_overlay(view('dialog', rect(0, 0, 100, 80), BoxStyle{}, [
			button('inside', 'Inside', rect(8, 8, 80, 24), BoxStyle{}, TextStyle{}),
		]), config)!
		mut content := [button('inner_anchor', 'Anchor', rect(8, 8, 100, 24), BoxStyle{}, TextStyle{})]
		if relation == 'authored' { content << dialog }
		portal := with_overlay(view('portal', rect(0, 0, 160, 100), BoxStyle{}, content),
			OverlayConfig{ open: true, anchor: 'clipped_anchor' })!
		mut children := [overlay_availability_outside(), overlay_availability_pane(), portal]
		if relation != 'authored' { children << dialog }
		viewport := rect(0, 0, 400, 300)
		mut tree := OverlayTree{}
		mut focus := FocusManager{}
		focus.update_mounted(tree.resolve(screen(0xffffff, children), map[string]f64{}, viewport, 0)!,
			map[string]f64{}, viewport, ContentTransform{})
		assert !tree.layers[tree.layer_index('portal')].available, relation
		assert !tree.layers[tree.layer_index('dialog')].available, relation
		assert tree.modal == '', relation
		assert tree.top_active() == none, relation
		assert focus.can_focus('outside'), relation
		assert !focus.can_focus('inside'), relation
		assert (focus.node('dialog') or { panic('dependent dialog was retired') }).hidden, relation
	}
}

fn test_exiting_available_dialog_paints_its_backdrop_without_trapping_background() ! {
	base := view('dialog', rect(0, 0, 160, 100), BoxStyle{}, []Element{})
	dialog := with_overlay(Element{ ...base, presence_exiting: true },
		OverlayConfig{ kind: .dialog, open: true })!
	viewport := rect(0, 0, 400, 300)
	mut tree := OverlayTree{}
	projected := tree.resolve(screen(0xffffff, [overlay_availability_outside(), dialog]),
		map[string]f64{}, viewport, 0)!
	mut focus := FocusManager{}
	focus.update_mounted(projected, map[string]f64{}, viewport, ContentTransform{})
	assert tree.layers[tree.layer_index('dialog')].available
	assert !tree.layers[tree.layer_index('dialog')].active
	assert tree.modal == '' && tree.top_active() == none
	assert focus.can_focus('outside')
	assert projected.children.len == 3
	assert projected.children[1].id == 'dialog__backdrop'
	assert !projected.children[1].enabled && !projected.children[1].presented_hidden()
	assert !projected.children[2].presented_hidden()
}
