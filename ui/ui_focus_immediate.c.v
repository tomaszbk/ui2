module ui2

$if (android || linux || ((ios || macos || windows) && ui2_custom_rendering ?)) && !ui2_headless ? && !ui2_document_library ? {
	fn (mut w Window) focus_manager() &FocusManager { return w.navigation }

	fn (mut w Window) custom_focus_offsets(el Element, path string, mut offsets map[string]f64, mut offsets_x map[string]f64) {
		current_path := if el.overlay_host() { overlay_host_path } else { path }
		if el.kind == .scroll {
			x, y := scroll_mode_offset(el.scroll_mode, w.scroll_state_offset_x(scroll_view_state_id(el, path)), w.scroll_state_offset(scroll_view_state_id(el, path)))
			offsets[path] = y
			offsets_x[path] = x
		}
		for i, child in el.children {
			w.custom_focus_offsets(child, reconciliation_child_key(current_path, i, child), mut offsets, mut offsets_x)
		}
	}

	fn (mut w Window) sync_focus_navigation() {
		if w.navigation.geometry_revision != w.navigation.root_revision || w.navigation.geometry_serial == 0 {
			w.focus_offsets.clear()
			w.focus_offsets_x.clear()
			w.custom_focus_offsets(w.navigation.root, 'root', mut w.focus_offsets, mut w.focus_offsets_x)
		} else {
			for node in w.navigation.nodes {
				if node.el.kind == .scroll {
					x, y := scroll_mode_offset(node.el.scroll_mode, w.scroll_state_offset_x(scroll_view_state_id(node.el, node.path)), w.scroll_state_offset(scroll_view_state_id(node.el, node.path)))
					w.focus_offsets[node.path] = y
					w.focus_offsets_x[node.path] = x
				}
			}
		}
		w.navigation.update_mounted_axes(w.navigation.root, w.focus_offsets, w.focus_offsets_x, w.bounds(), ContentTransform{ y: w.menu_bar_height() })
		w.sync_mounted_scroll_views()
	}

	fn (mut w Window) update_custom_focus_tree(root Element) {
		previous := w.focused_field
		previous_scopes := if w.overlay_focus.stack.len == 0 && w.overlay_tree.focus_layer() != none {
			w.navigation.scopes.clone()
		} else {
			[]FocusScopeEntry{}
		}
		w.navigation.set_root(root)
		w.navigation.current = w.focused_field
		w.sync_focus_navigation()
		w.overlay_focus.sync(mut w.navigation, w.overlay_tree, previous, previous_scopes)
		w.focused_field = w.navigation.current
		if w.touch.down && w.touch.pointer_captured {
			captured := w.touch.pointer_target
			if node := w.navigation.node(captured.id) {
				if !node.enabled || node.hidden { w.cancel_touch() }
			} else if node := w.navigation.path_node(captured.identity) {
				if !node.enabled || node.hidden { w.cancel_touch() }
			}
		}
		if w.composition.field_id.len > 0 && w.composition.field_id != w.focused_field {
			w.composition = TextComposition{}
		}
		if w.focused_field.len > 0 && w.focused_field != previous {
			w.reveal_custom_focus(w.focused_field)
		}
	}

	fn (mut w Window) reveal_custom_focus(id string) {
		dispatch := w.custom_input_dispatch()
		ctx := dispatch.window.ctx
		root := w.navigation.root_revision
		if !w.custom_scroll_dispatch_current(dispatch, ctx, root) { return }
		for request in w.navigation.reveals(id) {
			pane := w.navigation.path_node(request.path) or { continue }
			state_id := scroll_view_state_id(pane.el, pane.path)
			w.pending_scroll.delete(state_id)
			w.pending_scroll_x.delete(state_id)
			before := w.scroll_state_offset(state_id)
			next := focus_reveal_offset(before, pane.el.frame.height, request.rect)
			w.set_scroll_offset(state_id, next, w.scroll_maximum(state_id))
			if !w.custom_scroll_dispatch_current(dispatch, ctx, root) || w.focused_field != id {
				return
			}
			before_x := w.scroll_state_offset_x(state_id)
			next_x := focus_reveal_offset(before_x, pane.el.frame.width, rect(request.rect.y, request.rect.x, request.rect.height, request.rect.width))
			w.set_scroll_offset_x(state_id, next_x, w.scroll_maximum_x(state_id))
			if !w.custom_scroll_dispatch_current(dispatch, ctx, root) || w.focused_field != id {
				return
			}
		}
		w.sync_focus_navigation()
	}

	fn (mut w Window) mounted_menu_options(el Element, path string) []string {
		if node := w.navigation.path_node(path) {
			if node.el.menu == el.menu { return node.menu_options_snapshot() }
		}
		return element_menu_options(el)
	}

	fn (mut w Window) custom_focus_target(node FocusNode) HitTarget {
		el := node.el
		options := node.menu_options_snapshot()
		geometry := w.element_hit_geometry(el, node.local_frame, node.transform, node.clip)
		// The Element accessors take its address, which would move `el` to the heap.
		toggle_group, toggle_allow_no_selection := toggle_selection(el.toggle)
		return HitTarget{
			...geometry
			identity:                  node.path
			pointer_owner_identity:    node.pointer_owner_identity
			id:                        el.id
			kind:                      el.kind
			on_event:                  el.on_event
			clickable:                 el.clickable
			draggable:                 el.draggable
			long_press:                el.long_press
			swipe_left:                el.swipe_left
			drag_source:               el.drag_source
			drop_target:               el.drop_target
			text_field:                el.kind == .text_field
			text_area:                 el.kind == .text_area
			slider:                    el.kind == .slider
			slider_frame:              node.local_frame
			slider_padding:            el.padding
			slider_spec:               slider_spec(el)
			checkbox:                  el.kind == .checkbox
			checkbox_state:            el.checked
			switch_control:            el.kind == .switch_control
			switch_state:              el.checked
			toggle_button:             el.kind == .toggle_button
			toggle_group:              toggle_group
			toggle_allow_no_selection: toggle_allow_no_selection
			dropdown:                  el.kind == .dropdown
			options:                   options
			button_behavior:           el.kind == .view && el.button_behavior
		}
	}

	fn (mut w Window) activate_semantic_control(id string, action SemanticAction) bool {
		dispatch := w.custom_input_dispatch()
		if !dispatch.valid() { return false }
		node := w.navigation.node(id) or { return false }
		if node.hidden || !node.enabled || !w.navigation.in_scope(node) { return false }
		target := w.custom_focus_target(node)
		if action in [.increment, .decrement] && node.el.kind == .slider {
			spec := slider_spec(node.el)
			before := w.slider_values[id] or { node.el.value }
			value := semantic_slider_step(before, spec, action)
			w.slider_values[id] = value
			if value != before {
				w.fire_target_event(target, ElementEvent{ kind: .change, id: id, value: value })
			}
			if dispatch.valid() { w.invalidate_custom_paint() }
			return true
		}
		if action != .activate || !semantic_activatable(node.el) { return false }
		match node.el.kind {
			.checkbox { w.commit_checkbox(target) }
			.switch_control {
				w.commit_switch(target, !(w.switch_values[id] or { node.el.checked }))
			}
			.toggle_button { w.commit_toggle_button(target) }
			.dropdown {
				w.focus(id)
				if !dispatch.valid() { return true }
				w.open_dropdown(target)
			}
			else { w.fire_target_event(target, ElementEvent{ kind: .click, id: id }) }
		}
		if dispatch.valid() { w.invalidate_custom_paint() }
		return true
	}

	fn (mut w Window) live_semantic_nodes(nodes []SemanticNode) []SemanticNode {
		mut result := []SemanticNode{cap: nodes.len}
		for node in nodes {
			el := w.navigation.node(node.id) or {
				result << node
				continue
			}
			mut value := node.value
			mut checked := node.state.checked
			if el.el.kind in [.text_field, .text_area, .dropdown] && !el.el.secure && el.el.accessibility_value.len == 0 {
				value = (w.text_values[node.id] or { value }).clone()
			}
			if el.el.kind == .slider && el.el.accessibility_value.len == 0 {
				value = (w.slider_values[node.id] or { el.el.value }).str()
			}
			if el.el.kind == .checkbox { checked = w.checkbox_values[node.id] or { checked } }
			if el.el.kind == .switch_control { checked = w.switch_values[node.id] or { checked } }
			if el.el.kind == .toggle_button { checked = w.toggle_values[node.id] or { checked } }
			if el.el.kind in [.checkbox, .switch_control, .toggle_button] {
				if el.el.accessibility_value.len == 0 {
					value = if checked { 'checked' } else { 'unchecked' }
				}
			}
			result << SemanticNode{
				...node
				value: value
				state: SemanticState{
					...node.state
					checked:  checked
					selected: el.el.kind == .toggle_button && checked
					expanded: el.el.kind == .dropdown && (w.dropdown_id == node.id || w.popup_menu_owner == node.id)
				}
			}
		}
		return result
	}

	// This pass retains every mounted input, including culled subtrees. Editor
	// reconciliation lives here, so scrolling never discards local edits/IME.
	fn (mut w Window) reconcile_mounted_focus_controls(root Element) {
		if w.controls_initialized && w.controls_root == root { return }
		w.controls_root = root
		w.controls_initialized = true
		w.controls_prune_pending = true
		w.active_fields.clear()
		w.editable_fields.clear()
		w.active_sliders.clear()
		w.active_switches.clear()
		w.active_checkboxes.clear()
		w.active_toggles.clear()
		w.active_scrolls.clear()
		w.sync_mounted_focus_controls(root, 'root')
	}

	fn (mut w Window) sync_mounted_focus_controls(el Element, path string) {
		w.sync_mounted_focus_control_subtree(el, if el.overlay_host() {
			overlay_host_path
		} else {
			path
		}, true)
	}

	fn (mut w Window) sync_mounted_focus_control_subtree(el Element, path string, ancestor_enabled bool) {
		enabled := ancestor_enabled && el.presented_enabled() && !el.presented_hidden() && !el.overlay_inert()
		w.sync_mounted_control(Element{ ...el, enabled: enabled })
		if el.kind == .scroll {
			w.active_scrolls[scroll_view_state_id(el, path)] = true
		}
		for i, child in el.children {
			w.sync_mounted_focus_control_subtree(child, reconciliation_child_key(path, i, child), enabled)
		}
	}

	fn (mut w Window) sync_mounted_control(el Element) {
		kind_changed := el.id in w.text_kinds && (w.text_kinds[el.id] or { el.kind }) != el.kind
		if kind_changed {
			// Remove the old editor before pruning, even when the replacement is
			// not a text control. Its eligible id can still own navigation focus.
			w.forget_text_state(el.id)
			w.text_area_selections.delete(el.id)
			w.editable_fields.delete(el.id)
			w.active_fields.delete(el.id)
			if w.composition.field_id == el.id {
				w.composition = TextComposition{}
			}
			if w.dropdown_id == el.id { w.close_dropdown() }
		}
		if el.kind in [.text_field, .text_area, .dropdown] {
			previous := w.text_props[el.id] or { el.text }
			if kind_changed || el.id !in w.text_values || (el.text != previous && (w.text_values[el.id] or { '' }) != el.text) {
				if w.composition.field_id == el.id {
					w.composition = TextComposition{}
				}
				w.replace_text_value(el.id, el.text)
				if el.kind != .dropdown {
					w.replace_text_editor(el.id, text_editor(el.text.clone()))
				}
			}
			if el.id !in w.text_props || el.text != previous { w.replace_text_prop(el.id, el.text) }
			w.text_kinds[el.id] = el.kind
			w.active_fields[el.id] = true
			if el.kind != .dropdown {
				w.editable_fields[el.id] = el.enabled && !el.readonly
				if (!el.enabled || el.readonly) && w.composition.field_id == el.id {
					w.composition = TextComposition{}
				}
			}
		}
		if el.id.len == 0 { return }
		match el.kind {
			.checkbox {
				if el.id !in w.checkbox_values || (w.checkbox_declared[el.id] or { el.checked }) != el.checked {
					w.checkbox_values[el.id] = el.checked
				}
				w.checkbox_declared[el.id] = el.checked
				w.active_checkboxes[el.id] = true
			}
			.switch_control {
				if el.id !in w.switch_values || (w.switch_declared[el.id] or { el.checked }) != el.checked {
					w.switch_values[el.id] = el.checked
				}
				w.switch_declared[el.id] = el.checked
				w.active_switches[el.id] = true
			}
			.toggle_button {
				w.toggle_groups[el.id] = el.toggle_group()
				w.toggle_allow_no_selection[el.id] = el.toggle_allow_no_selection()
				if el.id !in w.toggle_values || (w.toggle_declared[el.id] or { el.checked }) != el.checked {
					w.toggle_values[el.id] = el.checked
				}
				w.toggle_declared[el.id] = el.checked
				w.active_toggles[el.id] = true
				if w.toggle_values[el.id] or { false } { w.release_custom_toggle_group(el.id) }
			}
			.slider {
				spec := slider_spec(el)
				if el.id !in w.slider_values || (w.slider_declared[el.id] or { el.value }) != el.value {
					w.slider_values[el.id] = slider_clamped_value(el.value, spec.min, spec.max)
				}
				w.slider_values[el.id] = slider_clamped_value(w.slider_values[el.id] or { el.value }, spec.min, spec.max)
				w.slider_specs[el.id] = spec
				w.slider_declared[el.id] = el.value
				w.active_sliders[el.id] = true
			}
			else {}
		}
	}
}
