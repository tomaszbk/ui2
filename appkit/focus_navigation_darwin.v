module ui2

$if macos && !ui2_custom_rendering ? && !ui2_headless ? && !ui2_document_library ? {
	import macos

	fn C.ui2_macos_window_send_event(window voidptr, event voidptr)
	fn C.ui2_macos_window_lifecycle(window voidptr, selector voidptr)

	fn (mut w Window) focus_manager() &FocusManager { return w.navigation }

	fn (mut w Window) appkit_focus_offsets(el Element, path string, native_path string, mut offsets map[string]f64, mut offsets_x map[string]f64) {
		w.navigation_paths[path] = native_path
		if el.kind == .scroll {
			if view := w.nodes[native_path] {
				visible := macos.msg_rect(view, 'documentVisibleRect')
				offsets[path] = visible.y
				offsets_x[path] = visible.x
			}
		}
		child_parent := if el.kind == .scroll { native_path + '/document' } else { native_path }
		for i, child in el.children {
			w.appkit_focus_offsets(child, reconciliation_child_key(path, i, child), reconciliation_child_key(child_parent, i, child), mut offsets, mut offsets_x)
		}
	}

	fn (mut w Window) sync_focus_navigation() {
		mut offsets := map[string]f64{}
		mut offsets_x := map[string]f64{}
		w.navigation_paths.clear()
		w.appkit_focus_offsets(w.navigation.root, 'root', '', mut offsets, mut offsets_x)
		w.navigation.update_mounted_axes(w.navigation.root, offsets, offsets_x, w.bounds(), ContentTransform{})
	}

	fn (mut w Window) reconcile_appkit_focus(root Element, previous string) {
		w.navigation.set_root(root)
		w.navigation.current = previous
		w.sync_focus_navigation()
		if w.navigation.current.len > 0 {
			if w.focused_id() != w.navigation.current { w.focus(w.navigation.current) }
		} else if previous.len > 0 {
			native_end_window_editing(w.window)
		}
		for id in w.focus_selections.keys() {
			if _ := w.navigation.node(id) {} else { w.focus_selections.delete(id) }
		}
	}

	fn (mut w Window) reveal_appkit_focus(id string) {
		window := w.window
		root_view := w.root_view
		manager := w.navigation
		root := manager.root
		tree := w.layout_tree
		revision := tree.revision
		lifecycle := w.keyboard_generation
		target := w.views[id] or { return }
		if w.focused_id() != id || manager.current != id { return }
		for request in w.navigation.reveals(id) {
			key := w.navigation_paths[request.path] or { continue }
			pane_view := w.nodes[key] or { continue }
			doc := macos.msg_id(pane_view, 'documentView')
			macos.msg_void_rect(doc, 'scrollRectToVisible:', appkit_rect(element_rect(request.rect)))
			// Bounds notifications synchronously run application callbacks. A
			// redirected focus or remount owns its own reveal, including outer panes.
			if !appkit_window_open(w) || w.window != window || w.root_view != root_view
				|| w.keyboard_generation != lifecycle || w.navigation != manager
				|| manager.root != root || w.layout_tree != tree || tree.revision != revision
				|| (w.views[id] or { native_nil_view() }) != target
				|| (w.nodes[key] or { native_nil_view() }) != pane_view
				|| manager.current != id || w.focused_id() != id { return }
		}
		w.sync_focus_navigation()
	}

	fn (mut w Window) activate_semantic_control(id string, action SemanticAction) bool {
		node := w.navigation.node(id) or { return false }
		if node.hidden || !node.enabled || !w.navigation.in_scope(node) { return false }
		native := w.views[id] or { return false }
		if action in [.increment, .decrement] && node.el.kind == .slider {
			spec := slider_spec(node.el)
			before := macos.msg_f64(native, 'doubleValue')
			value := semantic_slider_step(before, spec, action)
			macos.msg_void_f64(native, 'setDoubleValue:', value)
			if value != before {
				w.appkit_emit_callback(appkit_binding(node.el, .change), ElementEvent{ kind: .change, value: value })
			}
			return true
		}
		if action != .activate || !semantic_activatable(node.el) { return false }
		if node.el.kind == .view {
			return w.appkit_emit_callback(appkit_binding(node.el, .click), ElementEvent{ kind: .click })
		}
		if node.el.kind == .dropdown {
			macos.msg_void1(native, 'performClick:', native_nil_view())
			return true
		}
		macos.msg_void1(native, 'performClick:', native_nil_view())
		return true
	}

	fn (mut w Window) live_semantic_nodes(nodes []SemanticNode) []SemanticNode {
		mut result := []SemanticNode{cap: nodes.len}
		for node in nodes {
			el := w.navigation.path_node(node.path) or {
				result << node
				continue
			}
			key := w.navigation_paths[node.path] or {
				result << node
				continue
			}
			native := w.nodes[key] or {
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

	fn (mut w Window) appkit_text_client_has_marked_text() bool {
		responder := macos.msg_id(w.window, 'firstResponder')
		if macos.responds_to(responder, 'hasMarkedText') {
			return macos.msg_bool(responder, 'hasMarkedText')
		}
		// NSTextField itself is not the NSTextInputClient. Its current shared
		// field editor owns composition when AppKit reports the control here.
		if native := w.views[w.focused_id()] {
			if macos.responds_to(native, 'currentEditor') {
				editor := macos.msg_id(native, 'currentEditor')
				return macos.responds_to(editor, 'hasMarkedText') && macos.msg_bool(editor, 'hasMarkedText')
			}
		}
		return false
	}

	// Intercept before NSControl and the shared field editor dispatch. Tab cannot
	// be handled a second time by AppKit, and a semantic button consumes repeats.
	fn (mut w Window) appkit_navigation_key(event macos.Id) bool {
		event_type := macos.msg_u64(event, 'type')
		if event_type !in [u64(10), u64(11)] { return false }
		physical := macos.msg_u64(event, 'keyCode')
		if event_type == 11 {
			if w.activation_keys[physical] or { false } { w.keyboard_generation++ }
			w.activation_keys.delete(physical)
			return false
		}
		key := appkit_key_event(event)
		repeated := macos.msg_bool(event, 'isARepeat')
		owned := repeated && (w.activation_keys[physical] or { false })
		if !repeated { w.activation_keys.delete(physical) }
		if !owned && (key.ctrl || key.cmd || key.alt) { return false }
		// Explicit application handling still precedes the native input context.
		// Already consumed activation repeats remain owned during composition.
		composing := !owned && w.appkit_text_client_has_marked_text()
		manager := w.focus_manager()
		mut candidate := owned || key.code == .tab
		if node := manager.node(w.focused_id()) {
			candidate = candidate || (semantic_activatable(node.el) && !key.shift && key.code in [
				.space,
				.enter,
				.kp_enter,
			])
				|| (automatic_direction(node.el) && !key.shift && key.code in [.left, .right, .up,
					.down])
		}
		if !candidate { return false }
		if w.key_handler != unsafe { nil } {
			generation := w.keyboard_generation
			w.key_consumed = false
			mut name := key_event_string(event)
			if node := manager.node(w.focused_id()) {
				if node.el.kind == .text_area { name = 'text:${node.el.id}:${name}' }
			}
			w.navigation_key_dispatched = true
			w.key_handler(mut w, name)
			consumed := w.key_consumed || w.text_key_consumed
			w.key_consumed = false
			w.text_key_consumed = false
			if consumed || w.keyboard_generation != generation { return true }
		}
		if owned { return true }
		if composing { return false } // AppKit owns default composition commands.
		// Claim before the synchronous callback: it may focus/remove a control,
		// refresh, resign or close the window. Never re-latch after that callback.
		if !repeated && !key.shift && key.code in [.space, .enter, .kp_enter] {
			if node := manager.node(w.focused_id()) {
				if manager.can_focus(node.el.id) && semantic_activatable(node.el) {
					w.activation_keys[physical] = true
				}
			}
		}
		return w.handle_focus_key(KeyEvent{ ...key, window: w }, repeated)
	}

	fn ui2_window_release_activation(self voidptr, selector voidptr) {
		if mut w := appkit_host().windows[u64(self)] {
			w.activation_keys.clear()
			w.keyboard_generation++
		}
		C.ui2_macos_window_lifecycle(self, selector)
	}

	fn ui2_app_release_activation(_self voidptr, _selector voidptr, _notification voidptr) {
		mut host := appkit_host()
		for _, mut w in host.windows {
			w.activation_keys.clear()
			w.keyboard_generation++
		}
	}

	@[export: 'ui2_window_send_event']
	fn ui2_window_send_event(self voidptr, _cmd voidptr, event voidptr) {
		mut w := appkit_host().windows[u64(self)] or {
			C.ui2_macos_window_send_event(self, event)
			return
		}
		previous_dispatch := w.navigation_key_dispatched
		w.navigation_key_dispatched = false
		defer { w.navigation_key_dispatched = previous_dispatch }
		// Native editors can bypass window keyDown:. Observe each key-down here;
		// performKeyEquivalent/keyDown share the event/timestamp deduplication.
		if macos.msg_u64(event, 'type') == 10 {
			generation := w.keyboard_generation
			if w.dispatch_typed_key_event(event) || w.keyboard_generation != generation { return }
		}
		composing := macos.msg_u64(event, 'type') == 10 && w.appkit_text_client_has_marked_text()
		if w.appkit_navigation_key(macos.Id(event)) { return }
		previous := w.focused_id()
		if native := w.views[previous] {
			if (w.view_kinds[previous] or { Kind.view }) == .text_field && native_control_is_editing(native) {
				w.focus_selections[previous] = native_control_selected_range(native)
			}
		}
		C.ui2_macos_window_send_event(self, event)
		if !composing && w.navigation.scopes.len > 0 && !w.navigation.can_focus(w.focused_id()) {
			destination := if w.navigation.can_focus(previous) {
				previous
			} else {
				w.navigation.first(false)
			}
			if destination.len > 0 { w.focus(destination) }
		}
	}

	fn ui2_focus_accepts_first_responder(self voidptr, _cmd voidptr) bool {
		// A view that is not in a window yet has nothing to be refused by.
		w := appkit_window_for(self) or { return true }
		for id, native in w.views {
			if native == self { return w.navigation.can_focus(id) }
		}
		if id := w.textview_ids[u64(self)] { return w.navigation.can_focus(id) }
		return true // A freshly created control is registered later in reconciliation.
	}
}
