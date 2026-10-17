module ui2

// Element key routing. An element lists the keys it handles in Element.keys;
// while it or a descendant has focus, a press of one of them reaches its
// on_event as a key_down event, before the application's key handlers and
// focus navigation see it. Each backend calls element_key from its key path.

// key_event_name is the normalized name of a key press: the held modifiers in
// the order cmd, ctrl, alt and shift, then KeyCode.name(), joined with `+`,
// for example `shift+tab` or `cmd+s`. A modifier pressed alone has no name.
pub fn key_event_name(event KeyEvent) string {
	if event.code in [.left_shift, .left_control, .left_alt, .left_super, .right_shift, .right_control,
		.right_alt, .right_super] {
		return ''
	}
	name := event.code.name()
	if name.len == 0 {
		return ''
	}
	mut parts := []string{cap: 5}
	if event.cmd {
		parts << 'cmd'
	}
	if event.ctrl {
		parts << 'ctrl'
	}
	if event.alt {
		parts << 'alt'
	}
	if event.shift {
		parts << 'shift'
	}
	parts << name
	return parts.join('+')
}

// element_key delivers a key press to the nearest element, from the focused
// one up through its ancestors, whose keys list the key, and reports whether
// one took it. The event's target is the focused element. A text field or
// text area keeps its caret keys: it passes a key to its ancestors only when
// it lists the key itself. A repeated Enter or Space is claimed again but not
// delivered, so holding it activates once.
fn element_key(event KeyEvent, repeated bool) bool {
	name := key_event_name(event)
	if name.len == 0 {
		return false
	}
	manager := focus_manager()
	focused := manager.node(focused_id()) or { return false }
	editor := focused.el.kind in [.text_field, .text_area]
	mut node := focused
	for {
		if name in node.el.keys && node.enabled && !node.hidden
			&& voidptr(node.el.on_event) != unsafe { nil } {
			if repeated && name in ['enter', 'space'] {
				return true
			}
			node.el.on_event(ElementEvent{
				kind:   .key_down
				id:     node.el.id
				key:    name
				target: focused.el.id
			})
			return true
		}
		if editor || node.parent.len == 0 {
			return false
		}
		node = manager.path_node(node.parent) or { return false }
	}
	return false
}
