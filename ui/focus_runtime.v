// vfmt off
module ui2

// Runtime calls exist only when the selected platform backend is mounted.
// Native AppKit/Win32 and UIKit remain available with ui2_headless; the
// custom backend excludes it. Pure policy and semantic types stay unguarded.
$if ios || ((macos || windows) && !ui2_custom_rendering ?)
	|| ((android || linux || ((macos || windows) && ui2_custom_rendering ?)) && !ui2_headless ?) {
// Sequential navigation wraps within the active scope, or the whole window.
pub fn focus_next() bool { return traverse_focus(false) }

pub fn focus_previous() bool { return traverse_focus(true) }

fn traverse_focus(backwards bool) bool {
	sync_focus_navigation()
	mut manager := focus_manager()
	manager.current = focused_id()
	if !manager.traverse(backwards) { return false }
	destination := manager.current
	focus(destination)
	manager.current = focused_id()
	return manager.current == destination
}

// Explicit direction calls also work from editors; automatic arrows leave
// editor, dropdown and slider navigation to the existing control backend.
pub fn focus_direction(direction FocusDirection) bool {
	sync_focus_navigation()
	mut manager := focus_manager()
	manager.current = focused_id()
	if !manager.directional(direction) { return false }
	destination := manager.current
	focus(destination)
	manager.current = focused_id()
	return manager.current == destination
}

pub fn enter_focus_scope(id string) bool {
	sync_focus_navigation()
	mut manager := focus_manager()
	manager.current = focused_id()
	if !manager.enter_scope(id) { return false }
	destination := manager.current
	focus(destination)
	manager.current = focused_id()
	if manager.current != destination {
		if manager.scopes.len > 0 && manager.scopes.last().id == id { manager.scopes.delete_last() }
		return false
	}
	return true
}

pub fn leave_focus_scope() bool {
	sync_focus_navigation()
	mut manager := focus_manager()
	if !manager.leave_scope() { return false }
	if manager.current.len == 0 { dismiss_keyboard() } else { focus(manager.current) }
	return true
}

pub fn active_focus_scope() string {
	manager := focus_manager()
	return if manager.scopes.len == 0 { '' } else { manager.scopes.last().id }
}

// Snapshots include current native/custom edit buffers and state. They can be
// queried after reconciliation without waiting for paint.
pub fn semantic_tree() []SemanticNode {
	sync_focus_navigation()
	mut manager := focus_manager()
	manager.current = focused_id()
	return live_semantic_nodes(manager.semantics())
}

pub fn semantic_node(id string) ?SemanticNode {
	for node in semantic_tree() { if node.id == id && id.len > 0 { return node } }
	return none
}

pub fn perform_semantic_action(id string, action SemanticAction) bool {
	node := semantic_node(id) or { return false }
	if action !in node.actions { return false }
	if action == .focus {
		focus(id)
		return focused_id() == id
	}
	return activate_semantic_control(id, action)
}

fn automatic_direction(el Element) bool {
	return el.kind !in [.text_field, .text_area, .dropdown, .slider]
}

// Repetition moves focus once per delivered Tab/arrow event. Semantic
// activation is once per physical press, consuming autorepeat as well.
fn handle_focus_key(event KeyEvent, repeated bool) bool {
	if event.ctrl || event.cmd || event.alt { return false }
	if event.code == .tab {
		traverse_focus(event.shift)
		return true
	}
	manager := focus_manager()
	node := manager.node(focused_id()) or { return false }
	if !manager.can_focus(node.el.id) { return false }
	if event.code in [.enter, .kp_enter, .space] && !event.shift && semantic_activatable(node.el) {
		if !repeated {
			$if (android || linux || ((macos || windows) && ui2_custom_rendering ?)) && !ui2_headless ? {
				// Establish ownership before the action can reenter input. Lifecycle
				// reset clears it; an invalid outer dispatch never re-latches it.
				own_custom_activation(event.code)
			}
			activate_semantic_control(node.el.id, .activate)
		}
		return true
	}
	if !event.shift && node.el.kind == .slider {
		if event.code in [.left, .down] { return activate_semantic_control(node.el.id, .decrement) }
		if event.code in [.right, .up] { return activate_semantic_control(node.el.id, .increment) }
	}
	if !event.shift && automatic_direction(node.el) {
		direction := match event.code {
			.left { FocusDirection.left }
			.right { FocusDirection.right }
			.up { FocusDirection.up }
			.down { FocusDirection.down }
			else { return false }
		}
		focus_direction(direction)
		return true
	}
	return false
}

}
