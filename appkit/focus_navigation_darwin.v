module ui2

$if !ui2_custom_rendering ? {
	import macos

	fn C.ui2_macos_window_send_event(window voidptr, event voidptr)

	fn focus_manager() &FocusManager { return state().navigation }

	fn appkit_focus_offsets(el Element, path string, native_path string, mut offsets map[string]f64) {
		mut st := state()
		st.navigation_paths[path] = native_path
		if el.kind == .scroll {
			if view := st.nodes[native_path] {
				offsets[path] = macos.msg_rect(view, 'documentVisibleRect').y
			}
		}
		child_parent := if el.kind == .scroll { native_path + '/document' } else { native_path }
		for i, child in el.children {
			appkit_focus_offsets(child, reconciliation_child_key(path, i, child), reconciliation_child_key(child_parent, i, child), mut offsets)
		}
	}

	fn sync_focus_navigation() {
		mut st := state()
		mut offsets := map[string]f64{}
		st.navigation_paths.clear()
		appkit_focus_offsets(st.navigation.root, 'root', '', mut offsets)
		st.navigation.update(st.navigation.root, offsets)
	}

	fn reconcile_appkit_focus(root Element, previous string) {
		mut st := state()
		st.navigation.root = root
		st.navigation.current = previous
		sync_focus_navigation()
		if st.navigation.current.len > 0 {
			if focused_id() != st.navigation.current { focus(st.navigation.current) }
		} else if previous.len > 0 {
			native_end_window_editing(st.window)
		}
		for id in st.focus_selections.keys() {
			if _ := st.navigation.node(id) {} else { st.focus_selections.delete(id) }
		}
	}

	fn reveal_appkit_focus(id string) {
		st := state()
		for request in st.navigation.reveals(id) {
			key := st.navigation_paths[request.path] or { continue }
			pane_view := st.nodes[key] or { continue }
			doc := macos.msg_id(pane_view, 'documentView')
			macos.msg_void_rect(doc, 'scrollRectToVisible:', appkit_rect(element_rect(request.rect)))
		}
		sync_focus_navigation()
	}

	fn activate_semantic_control(id string, action SemanticAction) bool {
		st := state()
		node := st.navigation.node(id) or { return false }
		if node.hidden || !node.enabled || !st.navigation.in_scope(node) { return false }
		native := st.views[id] or { return false }
		if action in [.increment, .decrement] && node.el.kind == .slider {
			spec := slider_spec(node.el)
			before := macos.msg_f64(native, 'doubleValue')
			value := semantic_slider_step(before, spec, action)
			macos.msg_void_f64(native, 'setDoubleValue:', value)
			if value != before {
				appkit_emit_callback(appkit_binding(node.el, .change), ElementEvent{ kind: .change, value: value })
			}
			return true
		}
		if action != .activate || !semantic_activatable(node.el) { return false }
		if node.el.kind == .view {
			return appkit_emit_callback(appkit_binding(node.el, .tap), ElementEvent{ kind: .tap })
		}
		if node.el.kind == .dropdown {
			macos.msg_void1(native, 'performClick:', native_nil_view())
			return true
		}
		macos.msg_void1(native, 'performClick:', native_nil_view())
		return true
	}

	fn live_semantic_nodes(nodes []SemanticNode) []SemanticNode {
		st := state()
		mut result := []SemanticNode{cap: nodes.len}
		for node in nodes {
			el := st.navigation.node(node.id) or {
				result << node
				continue
			}
			native := st.views[node.id] or {
				result << node
				continue
			}
			mut value := node.value
			mut checked := node.state.checked
			if el.el.kind in [.text_field, .text_area, .dropdown] && !el.el.secure && el.el.accessibility_value.len == 0 {
				value = text(node.id)
			}
			if el.el.kind == .slider && el.el.accessibility_value.len == 0 { value = slider_value(node.id).str() }
			if el.el.kind in [.checkbox, .switch_control, .toggle_button] {
				checked = macos.msg_i64(native, 'state') != 0
				if el.el.accessibility_value.len == 0 { value = if checked { 'checked' } else { 'unchecked' } }
			}
			result << SemanticNode{
				...node
				value: value
				state: SemanticState{
					...node.state
					checked:  checked
					selected: el.el.kind == .toggle_button && checked
				}
			}
		}
		return result
	}

	// Intercept before NSControl and the shared field editor dispatch. Tab cannot
	// be handled a second time by AppKit, and a semantic button consumes repeats.
	fn appkit_navigation_key(event macos.Id) bool {
		if macos.msg_u64(event, 'type') != 10 { return false }
		key := appkit_key_event(event)
		if key.ctrl || key.cmd || key.alt { return false }
		manager := focus_manager()
		mut candidate := key.code == .tab
		if node := manager.node(focused_id()) {
			candidate = candidate || (semantic_activatable(node.el) && !key.shift && key.code in [
				.space,
				.enter,
				.kp_enter,
			])
				|| (automatic_direction(node.el) && !key.shift && key.code in [.left, .right, .up,
					.down])
		}
		if !candidate { return false }
		if dispatch_typed_key_event(event) { return true }
		mut st := state()
		if st.key_handler != unsafe { nil } {
			st.key_consumed = false
			mut name := key_event_string(event)
			if node := manager.node(focused_id()) {
				if node.el.kind == .text_area { name = 'text:${node.el.id}:${name}' }
			}
			st.key_handler(name)
			consumed := st.key_consumed || st.text_key_consumed
			st.key_consumed = false
			st.text_key_consumed = false
			if consumed { return true }
		}
		return handle_focus_key(key, macos.msg_bool(event, 'isARepeat'))
	}

	@[export: 'ui2_window_send_event']
	fn ui2_window_send_event(self voidptr, _cmd voidptr, event voidptr) {
		if appkit_navigation_key(macos.Id(event)) { return }
		previous := focused_id()
		mut st := state()
		if native := st.views[previous] {
			if (st.view_kinds[previous] or { Kind.view }) == .text_field && native_control_is_editing(native) {
				st.focus_selections[previous] = native_control_selected_range(native)
			}
		}
		C.ui2_macos_window_send_event(self, event)
		if st.navigation.scopes.len > 0 && !st.navigation.can_focus(focused_id()) {
			destination := if st.navigation.can_focus(previous) {
				previous
			} else {
				st.navigation.first(false)
			}
			if destination.len > 0 { focus(destination) }
		}
	}

	fn ui2_focus_accepts_first_responder(self voidptr, _cmd voidptr) bool {
		st := state()
		for id, native in st.views {
			if native == self { return st.navigation.can_focus(id) }
		}
		if id := st.textview_ids[u64(self)] { return st.navigation.can_focus(id) }
		return true // A freshly created control is registered later in reconciliation.
	}
}
