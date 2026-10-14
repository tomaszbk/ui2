// vtest vflags: -d ui2_headless
module ui2

fn overlay_focus_refresh(mut manager FocusManager, mut state OverlayFocusState,
	mut tree OverlayTree, root Element, viewport Rect) !Element {
	previous := manager.current
	previous_scopes := manager.scopes.clone()
	projected := tree.resolve(root, map[string]f64{}, viewport, 0)!
	manager.update_mounted(projected, map[string]f64{}, viewport, ContentTransform{})
	state.sync(mut manager, tree, previous, previous_scopes)
	return projected
}

fn overlay_focus_nested_root(dialog_open bool, menu_open bool, launcher_exists bool) !Element {
	menu := with_overlay(view('choices', rect(0, 0, 100, 80), BoxStyle{}, [
		button('first_choice', 'First', rect(8, 8, 80, 24), BoxStyle{}, TextStyle{}),
		button('last_choice', 'Last', rect(8, 40, 80, 24), BoxStyle{}, TextStyle{}),
	]), OverlayConfig{ kind: .menu, anchor: 'menu_anchor', open: menu_open })!
	dialog := with_overlay(view('dialog', rect(0, 0, 240, 160), BoxStyle{}, [
		Element{ kind: .text_field, id: 'draft', text: 'España ñ', frame: rect(20, 20, 180, 30) },
		button('menu_anchor', 'Choices', rect(20, 80, 60, 24), BoxStyle{}, TextStyle{}),
		menu,
	]), OverlayConfig{ kind: .dialog, open: dialog_open, initial_focus: 'draft' })!
	mut children := []Element{}
	if launcher_exists {
		children << button('launcher', 'Open', rect(20, 20, 80, 30), BoxStyle{}, TextStyle{})
	}
	children << button('fallback', 'Fallback', rect(120, 20, 80, 30), BoxStyle{}, TextStyle{})
	children << dialog
	return Element{ ...view('workspace', rect(0, 0, 400, 300), BoxStyle{}, children), focus_scope: true }
}

fn test_overlay_nested_menu_traps_traversal_and_restores_dialog_then_outer_scope() ! {
	viewport := rect(0, 0, 400, 300)
	mut manager := FocusManager{}
	mut state := OverlayFocusState{}
	mut tree := OverlayTree{}
	_ = overlay_focus_refresh(mut manager, mut state, mut tree, overlay_focus_nested_root(false, false, true)!, viewport)!
	assert manager.enter_scope('workspace')
	assert manager.set_focus('launcher')
	_ = overlay_focus_refresh(mut manager, mut state, mut tree, overlay_focus_nested_root(true, false, true)!, viewport)!
	assert manager.current == 'draft'
	assert manager.scopes.map(it.id) == ['dialog']
	assert !manager.can_focus('launcher')
	assert manager.set_focus('menu_anchor')
	_ = overlay_focus_refresh(mut manager, mut state, mut tree, overlay_focus_nested_root(true, true, true)!, viewport)!
	assert manager.current == 'first_choice'
	assert manager.scopes.map(it.id) == ['choices']
	assert manager.order() == ['first_choice', 'last_choice']
	assert manager.traverse(true) && manager.current == 'last_choice'
	assert manager.traverse(false) && manager.current == 'first_choice'
	assert !manager.can_focus('draft') && !manager.can_focus('launcher')
	assert (manager.node('choices') or { panic('missing menu') }).frame == rect(100, 180, 100, 80)
	_ = overlay_focus_refresh(mut manager, mut state, mut tree, overlay_focus_nested_root(true, false, true)!, viewport)!
	assert manager.current == 'menu_anchor'
	assert manager.scopes.map(it.id) == ['dialog']
	_ = overlay_focus_refresh(mut manager, mut state, mut tree, overlay_focus_nested_root(false, false, true)!, viewport)!
	assert manager.current == 'launcher'
	assert manager.scopes.map(it.id) == ['workspace']
	assert state.stack.len == 0
}

fn test_overlay_restore_uses_surviving_outer_scope_when_saved_control_disappears() ! {
	viewport := rect(0, 0, 400, 300)
	mut manager := FocusManager{}
	mut state := OverlayFocusState{}
	mut tree := OverlayTree{}
	_ = overlay_focus_refresh(mut manager, mut state, mut tree, overlay_focus_nested_root(false, false, true)!, viewport)!
	assert manager.enter_scope('workspace')
	assert manager.set_focus('launcher')
	_ = overlay_focus_refresh(mut manager, mut state, mut tree, overlay_focus_nested_root(true, true, true)!, viewport)!
	assert manager.current == 'first_choice'
	_ = overlay_focus_refresh(mut manager, mut state, mut tree, overlay_focus_nested_root(false, false, false)!, viewport)!
	assert manager.current == 'fallback'
	assert manager.scopes.map(it.id) == ['workspace']
	assert state.stack.len == 0
}

fn test_popover_explicit_initial_focus_reaches_its_child_and_restores_launcher() ! {
	viewport := rect(0, 0, 400, 300)
	mut manager := FocusManager{}
	mut state := OverlayFocusState{}
	mut tree := OverlayTree{}
	for index, open in [false, true, false] {
		popover := with_overlay(view('popover', rect(0, 0, 160, 80), BoxStyle{}, [
			Element{ kind: .text_field, id: 'entry', frame: rect(8, 8, 140, 30) },
		]), OverlayConfig{ anchor: 'launcher', open: open, initial_focus: 'entry' })!
		root := screen(0xffffff, [
			button('launcher', 'Open', rect(20, 20, 80, 30), BoxStyle{}, TextStyle{}),
			popover,
		])
		_ = overlay_focus_refresh(mut manager, mut state, mut tree, root, viewport)!
		if index == 0 {
			assert manager.set_focus('launcher')
		}
		if index == 1 {
			assert manager.current == 'entry'
		}
		if index == 2 {
			assert manager.current == 'launcher' && state.stack.len == 0
		}
	}
}

fn test_portal_anchor_uses_dialog_geometry_when_declared_before_its_owner_surface() ! {
	viewport := rect(0, 0, 400, 300)
	popover := with_overlay(view('popover', rect(0, 0, 100, 60), BoxStyle{}, []Element{}),
		OverlayConfig{ anchor: 'dialog_anchor', open: true })!
	dialog := with_overlay(view('dialog', rect(0, 0, 240, 160), BoxStyle{}, [
		button('dialog_anchor', 'Anchor', rect(20, 20, 60, 24), BoxStyle{}, TextStyle{}),
	]), OverlayConfig{ kind: .dialog, open: true })!
	mut tree := OverlayTree{}
	mut manager := FocusManager{}
	manager.update_mounted(tree.resolve(screen(0xffffff, [popover, dialog]), map[string]f64{}, viewport, 0)!,
		map[string]f64{}, viewport, ContentTransform{})
	presented := manager.node('popover') or { panic('missing portal') }
	assert !presented.hidden && presented.enabled
	assert presented.scopes == ['dialog']
	assert presented.frame == rect(100, 120, 100, 60)
}

fn test_overlay_owner_dependency_cycle_is_diagnosed() ! {
	first := with_overlay(view('first', rect(0, 0, 160, 80), BoxStyle{}, []Element{}),
		OverlayConfig{ kind: .dialog, owner: 'second', open: true })!
	second := with_overlay(view('second', rect(0, 0, 160, 80), BoxStyle{}, []Element{}),
		OverlayConfig{ kind: .dialog, owner: 'first', open: true })!
	mut tree := OverlayTree{}
	if _ := tree.resolve(screen(0xffffff, [first, second]), map[string]f64{}, rect(0, 0, 400, 300), 0) {
		assert false, 'overlay ownership cycles must be rejected before presentation'
	} else {
		assert err.msg().contains('cycle')
	}
}

fn test_portal_placement_waits_for_distinct_explicit_owner_and_anchor_surface() ! {
	viewport := rect(0, 0, 400, 300)
	owner := with_overlay(view('owner', rect(0, 0, 100, 80), BoxStyle{}, []Element{}),
		OverlayConfig{ point: OverlayPoint{ x: 30, y: 100 }, gap: 0, open: true })!
	anchor_surface := with_overlay(view('anchor_surface', rect(0, 0, 100, 80), BoxStyle{}, [
		button('late_anchor', 'Anchor', rect(20, 20, 60, 24), BoxStyle{}, TextStyle{}),
	]), OverlayConfig{ point: OverlayPoint{ x: 200, y: 30 }, gap: 0, open: true })!
	floating := with_overlay(view('floating', rect(0, 0, 100, 60), BoxStyle{}, []Element{}),
		OverlayConfig{ owner: 'owner', anchor: 'late_anchor', open: true })!
	root := view('root', viewport, BoxStyle{}, [owner, floating, anchor_surface])
	mut tree := OverlayTree{}
	mut manager := FocusManager{}
	manager.update_mounted(tree.resolve(root, map[string]f64{}, viewport, 0)!,
		map[string]f64{}, viewport, ContentTransform{})
	presented := manager.node('floating') or { panic('missing floating surface') }
	assert !presented.hidden && presented.enabled
	assert presented.frame == rect(220, 80, 100, 60)
}
