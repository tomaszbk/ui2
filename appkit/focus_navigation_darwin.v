module ui2

$if !ui2_custom_rendering ? && !ui2_document_library ? {
	import macos

	fn C.ui2_macos_window_send_event(window voidptr, event voidptr)
	fn C.ui2_macos_window_lifecycle(window voidptr, selector voidptr)

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
		st.navigation.update_mounted(st.navigation.root, offsets, bounds(), ContentTransform{})
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
		window := st.window
		root_view := st.root_view
		manager := st.navigation
		root := manager.root
		tree := st.layout_tree
		revision := tree.revision
		lifecycle := st.keyboard_generation
		target := st.views[id] or { return }
		if focused_id() != id || manager.current != id { return }
		for request in st.navigation.reveals(id) {
			key := st.navigation_paths[request.path] or { continue }
			pane_view := st.nodes[key] or { continue }
			doc := macos.msg_id(pane_view, 'documentView')
			macos.msg_void_rect(doc, 'scrollRectToVisible:', appkit_rect(element_rect(request.rect)))
			// Bounds notifications synchronously run application callbacks. A
			// redirected focus or remount owns its own reveal, including outer panes.
			if state() != st || st.window != window || st.root_view != root_view
				|| st.keyboard_generation != lifecycle || st.navigation != manager
				|| manager.root != root || st.layout_tree != tree || tree.revision != revision
				|| (st.views[id] or { native_nil_view() }) != target
				|| (st.nodes[key] or { native_nil_view() }) != pane_view
				|| manager.current != id || focused_id() != id { return }
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
			el := st.navigation.path_node(node.path) or {
				result << node
				continue
			}
			key := st.navigation_paths[node.path] or {
				result << node
				continue
			}
			native := st.nodes[key] or {
				result << node
				continue
			}
			mut value := node.value
			mut checked := node.state.checked
			if el.el.kind in [.text_field, .text_area, .dropdown] && !el.el.secure && el.el.accessibility_value.len == 0 {
				value = match el.el.kind {
					.text_area { macos.utf8_string(macos.msg_id(text_area_text_view(native, el.el.disable_scroll), 'string')) }
					.dropdown { native_dropdown_text(native) }
					else { native_text(native) }
				}
			}
			if el.el.kind == .slider && el.el.accessibility_value.len == 0 { value = native_snap_slider_value(native, slider_spec(el.el)).str() }
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

	fn appkit_text_client_has_marked_text() bool {
		st := state()
		responder := macos.msg_id(st.window, 'firstResponder')
		if macos.responds_to(responder, 'hasMarkedText') {
			return macos.msg_bool(responder, 'hasMarkedText')
		}
		// NSTextField itself is not the NSTextInputClient. Its current shared
		// field editor owns composition when AppKit reports the control here.
		if native := st.views[focused_id()] {
			if macos.responds_to(native, 'currentEditor') {
				editor := macos.msg_id(native, 'currentEditor')
				return macos.responds_to(editor, 'hasMarkedText') && macos.msg_bool(editor, 'hasMarkedText')
			}
		}
		return false
	}

	// Intercept before NSControl and the shared field editor dispatch. Tab cannot
	// be handled a second time by AppKit, and a semantic button consumes repeats.
	fn appkit_navigation_key(event macos.Id) bool {
		mut st := state()
		event_type := macos.msg_u64(event, 'type')
		if event_type !in [u64(10), u64(11)] { return false }
		physical := macos.msg_u64(event, 'keyCode')
		if event_type == 11 {
			if st.activation_keys[physical] or { false } { st.keyboard_generation++ }
			st.activation_keys.delete(physical)
			return false
		}
		key := appkit_key_event(event)
		repeated := macos.msg_bool(event, 'isARepeat')
		owned := repeated && (st.activation_keys[physical] or { false })
		if !repeated { st.activation_keys.delete(physical) }
		if !owned && (key.ctrl || key.cmd || key.alt) { return false }
		// Explicit application handling still precedes the native input context.
		// Already consumed activation repeats remain owned during composition.
		composing := !owned && appkit_text_client_has_marked_text()
		manager := focus_manager()
		mut candidate := owned || key.code == .tab
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
		if st.key_handler != unsafe { nil } {
			generation := st.keyboard_generation
			st.key_consumed = false
			mut name := key_event_string(event)
			if node := manager.node(focused_id()) {
				if node.el.kind == .text_area { name = 'text:${node.el.id}:${name}' }
			}
			st.navigation_key_dispatched = true
			st.key_handler(name)
			consumed := st.key_consumed || st.text_key_consumed
			st.key_consumed = false
			st.text_key_consumed = false
			if consumed || st.keyboard_generation != generation { return true }
		}
		if owned { return true }
		if composing { return false } // AppKit owns default composition commands.
		// Claim before the synchronous callback: it may focus/remove a control,
		// refresh, resign or close the window. Never re-latch after that callback.
		if !repeated && !key.shift && key.code in [.space, .enter, .kp_enter] {
			if node := manager.node(focused_id()) {
				if manager.can_focus(node.el.id) && semantic_activatable(node.el) {
					st.activation_keys[physical] = true
				}
			}
		}
		return handle_focus_key(key, repeated)
	}

	fn ui2_window_release_activation(self voidptr, selector voidptr) {
		mut st := state()
		if self == st.window {
			st.activation_keys.clear()
			st.keyboard_generation++
		}
		C.ui2_macos_window_lifecycle(self, selector)
	}

	fn ui2_app_release_activation(_self voidptr, _selector voidptr, _notification voidptr) {
		mut st := state()
		st.activation_keys.clear()
		st.keyboard_generation++
	}

	@[export: 'ui2_window_send_event']
	fn ui2_window_send_event(self voidptr, _cmd voidptr, event voidptr) {
		if self != state().window {
			C.ui2_macos_window_send_event(self, event)
			return
		}
		mut st := state()
		previous_dispatch := st.navigation_key_dispatched
		st.navigation_key_dispatched = false
		defer { st.navigation_key_dispatched = previous_dispatch }
		// Native editors can bypass window keyDown:. Observe each key-down here;
		// performKeyEquivalent/keyDown share the event/timestamp deduplication.
		if macos.msg_u64(event, 'type') == 10 {
			generation := state().keyboard_generation
			if dispatch_typed_key_event(event) || state().keyboard_generation != generation { return }
		}
		composing := macos.msg_u64(event, 'type') == 10 && appkit_text_client_has_marked_text()
		if appkit_navigation_key(macos.Id(event)) { return }
		previous := focused_id()
		if native := st.views[previous] {
			if (st.view_kinds[previous] or { Kind.view }) == .text_field && native_control_is_editing(native) {
				st.focus_selections[previous] = native_control_selected_range(native)
			}
		}
		C.ui2_macos_window_send_event(self, event)
		if !composing && st.navigation.scopes.len > 0 && !st.navigation.can_focus(focused_id()) {
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
