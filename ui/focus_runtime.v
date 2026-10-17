// vfmt off
module ui2

// Focus and semantic actions run through the backend contract (backend.v).
// Sequential navigation wraps within the active scope, or the whole window.
pub fn (mut w Window) focus_next() bool { return w.traverse_focus(false) }

pub fn (mut w Window) focus_previous() bool { return w.traverse_focus(true) }

fn (mut w Window) traverse_focus(backwards bool) bool {
	dispatch := w.backend_input_dispatch()
	if !dispatch.valid() { return false }
	w.sync_focus_navigation()
	mut manager := w.focus_manager()
	manager.current = w.focused_id()
	if !manager.traverse(backwards) { return false }
	destination := manager.current
	w.focus(destination)
	if !dispatch.valid() { return false }
	manager.current = w.focused_id()
	return manager.current == destination
}

// Explicit direction calls also work from editors; automatic arrows leave
// editor, dropdown and slider navigation to the existing control backend.
pub fn (mut w Window) focus_direction(direction FocusDirection) bool {
	dispatch := w.backend_input_dispatch()
	if !dispatch.valid() { return false }
	w.sync_focus_navigation()
	mut manager := w.focus_manager()
	manager.current = w.focused_id()
	if !manager.directional(direction) { return false }
	destination := manager.current
	w.focus(destination)
	if !dispatch.valid() { return false }
	manager.current = w.focused_id()
	return manager.current == destination
}

pub fn (mut w Window) enter_focus_scope(id string) bool {
	dispatch := w.backend_input_dispatch()
	if !dispatch.valid() { return false }
	w.sync_focus_navigation()
	mut manager := w.focus_manager()
	manager.current = w.focused_id()
	if !manager.enter_scope(id) { return false }
	destination := manager.current
	w.focus(destination)
	if !dispatch.valid() { return false }
	manager.current = w.focused_id()
	if manager.current != destination {
		if manager.scopes.len > 0 && manager.scopes.last().id == id { manager.scopes.delete_last() }
		return false
	}
	return true
}

pub fn (mut w Window) leave_focus_scope() bool {
	dispatch := w.backend_input_dispatch()
	if !dispatch.valid() { return false }
	w.sync_focus_navigation()
	mut manager := w.focus_manager()
	if !manager.leave_scope() { return false }
	if manager.current.len == 0 { w.dismiss_keyboard() } else { w.focus(manager.current) }
	if !dispatch.valid() { return false }
	return true
}

pub fn (mut w Window) active_focus_scope() string {
	manager := w.focus_manager()
	return if manager.scopes.len == 0 { '' } else { manager.scopes.last().id }
}

// Snapshots include current native/custom edit buffers and state. They can be
// queried after reconciliation without waiting for paint.
pub fn (mut w Window) semantic_tree() []SemanticNode {
	w.sync_focus_navigation()
	mut manager := w.focus_manager()
	manager.current = w.focused_id()
	return w.live_semantic_nodes(manager.semantics())
}

pub fn (mut w Window) semantic_node(id string) ?SemanticNode {
	for node in w.semantic_tree() { if node.id == id && id.len > 0 { return node } }
	return none
}

pub fn (mut w Window) perform_semantic_action(id string, action SemanticAction) bool {
	dispatch := w.backend_input_dispatch()
	if !dispatch.valid() { return false }
	node := w.semantic_node(id) or { return false }
	if action !in node.actions { return false }
	if action == .focus {
		w.focus(id)
		if !dispatch.valid() { return false }
		return w.focused_id() == id
	}
	return w.activate_semantic_control(id, action)
}

fn automatic_direction(el Element) bool {
	return el.kind !in [.text_field, .text_area, .dropdown, .slider]
}

// Repetition moves focus once per delivered Tab/arrow event. Semantic
// activation is once per physical press, consuming autorepeat as well.
fn (mut w Window) handle_focus_key(event KeyEvent, repeated bool) bool {
	if event.ctrl || event.cmd || event.alt { return false }
	if event.code == .tab {
		w.traverse_focus(event.shift)
		return true
	}
	manager := w.focus_manager()
	node := manager.node(w.focused_id()) or { return false }
	if !manager.can_focus(node.el.id) { return false }
	if event.code in [.enter, .kp_enter, .space] && !event.shift && semantic_activatable(node.el) {
		if !repeated {
			// Establish ownership before the action can reenter input. Lifecycle
			// reset clears it; an invalid outer dispatch never re-latches it.
			w.backend_own_activation(event.code)
			w.activate_semantic_control(node.el.id, .activate)
		}
		return true
	}
	if !event.shift && node.el.kind == .slider {
		if event.code in [.left, .down] { return w.activate_semantic_control(node.el.id, .decrement) }
		if event.code in [.right, .up] { return w.activate_semantic_control(node.el.id, .increment) }
	}
	if !event.shift && automatic_direction(node.el) {
		direction := match event.code {
			.left { FocusDirection.left }
			.right { FocusDirection.right }
			.up { FocusDirection.up }
			.down { FocusDirection.down }
			else { return false }
		}
		w.focus_direction(direction)
		return true
	}
	return false
}
