module ui2

struct OverlayTriggerOwner {
	mounted_generation u64
	compiled_node      &CompiledVmlNode = unsafe { nil }
}

struct OverlayTrigger {
mut:
	owner     OverlayTriggerOwner
	inside    bool
	requested bool
	deadline  i64 = -1
	pointer_x f64
	pointer_y f64
}

struct OverlayFocusEntry {
	id      string
	restore string
}

struct OverlayFocusState {
mut:
	stack        []OverlayFocusEntry
	outer_scopes []FocusScopeEntry
}

fn (tree &OverlayTree) focus_layer() ?OverlayLayer {
	for i := tree.layers.len - 1; i >= 0; i-- {
		layer := tree.layers[i]
		if layer.active && !layer.element.overlay_inert()
			&& (layer.config.kind in [.dialog, .menu, .context_menu] || layer.config.initial_focus.len > 0)
			&& (tree.modal.len == 0 || layer.element.id == tree.modal || tree.modal in layer.scopes) {
			return layer
		}
	}
	return none
}

fn (mut state OverlayFocusState) sync(mut manager FocusManager, tree &OverlayTree,
	previous string, previous_scopes []FocusScopeEntry) {
	layer := tree.focus_layer()
	desired := if active := layer { active.element.id } else { '' }
	current := if state.stack.len > 0 { state.stack.last().id } else { '' }
	if desired == current { return }
	mut restore := previous
	mut found := -1
	for i, entry in state.stack { if entry.id == desired { found = i } }
	if desired.len == 0 || found >= 0 {
		limit := if found >= 0 { found + 1 } else { 0 }
		for state.stack.len > limit { restore = state.stack.pop().restore }
	}
	if active := layer {
		if found < 0 {
			if state.stack.len == 0 { state.outer_scopes = previous_scopes.clone() }
			state.stack << OverlayFocusEntry{ id: desired, restore: previous }
		}
		manager.scopes.clear()
		if active.element.focus_scope {
			manager.scopes << FocusScopeEntry{ id: desired, restore: state.stack.last().restore }
		}
		if found >= 0 && manager.can_focus(restore) {
			manager.current = restore
			return
		}
		if node := manager.node(active.config.initial_focus) {
			if manager.can_focus(node.el.id) && (node.el.id == desired || desired in node.scopes) {
				manager.current = node.el.id
				return
			}
		}
		manager.current = manager.first(false)
		if manager.current.len == 0 && manager.can_focus(desired) { manager.current = desired }
	} else {
		manager.scopes.clear()
		for entry in state.outer_scopes {
			if node := manager.node(entry.id) {
				if node.el.focus_scope && !node.hidden && node.enabled { manager.scopes << entry }
			}
		}
		state.outer_scopes.clear()
		manager.current = if manager.can_focus(restore) { restore } else { manager.first(false) }
	}
}
