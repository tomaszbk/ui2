@[has_globals]
module ui2

$if (android || ios || linux || macos || windows) && !ui2_headless ? && !ui2_document_library ? {
	fn focus_manager() &FocusManager { return g_focus_navigation }

	fn custom_focus_offsets(el Element, path string, mut offsets map[string]f64, mut offsets_x map[string]f64) {
		current_path := if el.overlay_host() { overlay_host_path } else { path }
		if el.kind == .scroll {
			x, y := scroll_mode_offset(el.scroll_mode, scroll_state_offset_x(scroll_view_state_id(el, path)), scroll_state_offset(scroll_view_state_id(el, path)))
			offsets[path] = y
			offsets_x[path] = x
		}
		for i, child in el.children {
			custom_focus_offsets(child, reconciliation_child_key(current_path, i, child), mut offsets, mut offsets_x)
		}
	}

	fn sync_focus_navigation() {
		if g_focus_navigation.geometry_revision != g_focus_navigation.root_revision || g_focus_navigation.geometry_serial == 0 {
			g_gg_app.focus_offsets.clear()
			g_gg_app.focus_offsets_x.clear()
			custom_focus_offsets(g_focus_navigation.root, 'root', mut g_gg_app.focus_offsets, mut g_gg_app.focus_offsets_x)
		} else {
			for node in g_focus_navigation.nodes {
				if node.el.kind == .scroll {
					x, y := scroll_mode_offset(node.el.scroll_mode, scroll_state_offset_x(scroll_view_state_id(node.el, node.path)), scroll_state_offset(scroll_view_state_id(node.el, node.path)))
					g_gg_app.focus_offsets[node.path] = y
					g_gg_app.focus_offsets_x[node.path] = x
				}
			}
		}
		g_focus_navigation.update_mounted_axes(g_focus_navigation.root, g_gg_app.focus_offsets, g_gg_app.focus_offsets_x, bounds(), ContentTransform{ y: menu_bar_height() })
		sync_mounted_scroll_views()
	}

	fn update_custom_focus_tree(root Element) {
		previous := g_focused_field
		previous_scopes := if g_gg_app.overlay_focus.stack.len == 0 && g_gg_app.overlay_tree.focus_layer() != none { g_focus_navigation.scopes.clone() } else { []FocusScopeEntry{} }
		g_focus_navigation.set_root(root)
		g_focus_navigation.current = g_focused_field
		sync_focus_navigation()
		g_gg_app.overlay_focus.sync(mut g_focus_navigation, g_gg_app.overlay_tree, previous, previous_scopes)
		g_focused_field = g_focus_navigation.current
		if g_touch.down && g_touch.pointer_captured {
			captured := g_touch.pointer_target
			if node := g_focus_navigation.node(captured.id) {
				if !node.enabled || node.hidden { cancel_touch() }
			} else if node := g_focus_navigation.path_node(captured.identity) {
				if !node.enabled || node.hidden { cancel_touch() }
			}
		}
		if g_gg_app.composition.field_id.len > 0 && g_gg_app.composition.field_id != g_focused_field {
			g_gg_app.composition = TextComposition{}
		}
		if g_focused_field.len > 0 && g_focused_field != previous { reveal_custom_focus(g_focused_field) }
	}

	fn reveal_custom_focus(id string) {
		dispatch := custom_input_dispatch(g_gg_app)
		ctx := dispatch.app.ctx
		root := g_focus_navigation.root_revision
		if !custom_scroll_dispatch_current(dispatch, ctx, root) { return }
		for request in g_focus_navigation.reveals(id) {
			pane := g_focus_navigation.path_node(request.path) or { continue }
			state_id := scroll_view_state_id(pane.el, pane.path)
			g_pending_scroll.delete(state_id)
			g_pending_scroll_x.delete(state_id)
			before := scroll_state_offset(state_id)
			next := focus_reveal_offset(before, pane.el.frame.height, request.rect)
			set_scroll_offset(state_id, next, scroll_maximum(state_id))
			if !custom_scroll_dispatch_current(dispatch, ctx, root) || g_focused_field != id { return }
			before_x := scroll_state_offset_x(state_id)
			next_x := focus_reveal_offset(before_x, pane.el.frame.width, rect(request.rect.y, request.rect.x, request.rect.height, request.rect.width))
			set_scroll_offset_x(state_id, next_x, scroll_maximum_x(state_id))
			if !custom_scroll_dispatch_current(dispatch, ctx, root) || g_focused_field != id { return }
		}
		sync_focus_navigation()
	}

	fn mounted_menu_options(el Element, path string) []string {
		if node := g_focus_navigation.path_node(path) {
			if node.el.menu == el.menu { return node.menu_options_snapshot() }
		}
		return element_menu_options(el)
	}

	fn custom_focus_target(node FocusNode) HitTarget {
		el := node.el
		options := node.menu_options_snapshot()
		geometry := element_hit_geometry(el,node.local_frame,node.transform,node.clip)
		// The Element accessors take its address, which would move `el` to the heap.
		toggle_group, toggle_allow_no_selection := toggle_selection(el.toggle)
		return HitTarget{
			...geometry
			identity:                  node.path
			pointer_owner_identity:    node.pointer_owner_identity
			id:                        el.id
			kind:                      el.kind
			on_event:                  el.on_event
			clickable: el.clickable
			draggable: el.draggable
			long_press: el.long_press
			swipe_left: el.swipe_left
			drag_source: el.drag_source
			drop_target: el.drop_target
			text_field: el.kind == .text_field
			text_area: el.kind == .text_area
			slider: el.kind == .slider
			slider_frame: node.local_frame
			slider_padding: el.padding
			slider_spec: slider_spec(el)
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

	fn activate_semantic_control(id string, action SemanticAction) bool {
		dispatch := custom_input_dispatch(g_gg_app)
		if !dispatch.valid() { return false }
		node := g_focus_navigation.node(id) or { return false }
		if node.hidden || !node.enabled || !g_focus_navigation.in_scope(node) { return false }
		target := custom_focus_target(node)
		if action in [.increment, .decrement] && node.el.kind == .slider {
			spec := slider_spec(node.el)
			before := g_slider_values[id] or { node.el.value }
			value := semantic_slider_step(before, spec, action)
			g_slider_values[id] = value
			if value != before {
				fire_target_event(target, ElementEvent{ kind: .change, id: id, value: value })
			}
			if dispatch.valid() { invalidate_custom_paint() }
			return true
		}
		if action != .activate || !semantic_activatable(node.el) { return false }
		match node.el.kind {
			.checkbox { commit_checkbox(target) }
			.switch_control { commit_switch(target, !(g_switch_values[id] or { node.el.checked })) }
			.toggle_button { commit_toggle_button(target) }
			.dropdown {
				focus(id)
				if !dispatch.valid() { return true }
				open_dropdown(target)
			}
			else { fire_target_event(target, ElementEvent{ kind: .click, id: id }) }
		}
		if dispatch.valid() { invalidate_custom_paint() }
		return true
	}

	fn live_semantic_nodes(nodes []SemanticNode) []SemanticNode {
		mut result := []SemanticNode{cap: nodes.len}
		for node in nodes {
			el := g_focus_navigation.node(node.id) or {
				result << node
				continue
			}
			mut value := node.value
			mut checked := node.state.checked
			if el.el.kind in [.text_field, .text_area, .dropdown] && !el.el.secure && el.el.accessibility_value.len == 0 {
				value = (g_text_values[node.id] or { value }).clone()
			}
			if el.el.kind == .slider && el.el.accessibility_value.len == 0 { value = (g_slider_values[node.id] or { el.el.value }).str() }
			if el.el.kind == .checkbox { checked = g_checkbox_values[node.id] or { checked } }
			if el.el.kind == .switch_control { checked = g_switch_values[node.id] or { checked } }
			if el.el.kind == .toggle_button { checked = g_toggle_values[node.id] or { checked } }
			if el.el.kind in [.checkbox, .switch_control, .toggle_button] {
				if el.el.accessibility_value.len == 0 { value = if checked { 'checked' } else { 'unchecked' } }
			}
			result << SemanticNode{
				...node
				value: value
				state: SemanticState{
					...node.state
					checked:  checked
					selected: el.el.kind == .toggle_button && checked
					expanded: el.el.kind == .dropdown && g_open_dropdown == node.id
				}
			}
		}
		return result
	}

	// This pass retains every mounted input, including culled subtrees. Editor
	// reconciliation lives here, so scrolling never discards local edits/IME.
	fn reconcile_mounted_focus_controls(root Element) {
		if g_gg_app.controls_initialized && g_gg_app.controls_root == root { return }
		g_gg_app.controls_root = root
		g_gg_app.controls_initialized = true
		g_gg_app.controls_prune_pending = true
		g_active_fields.clear()
		g_gg_app.editable_fields.clear()
		g_active_sliders.clear()
		g_active_switches.clear()
		g_active_checkboxes.clear()
		g_active_toggles.clear()
		g_active_scrolls.clear()
		sync_mounted_focus_controls(root, 'root')
	}

	fn sync_mounted_focus_controls(el Element, path string) {
		sync_mounted_focus_control_subtree(el, if el.overlay_host() { overlay_host_path } else { path }, true)
	}

	fn sync_mounted_focus_control_subtree(el Element, path string, ancestor_enabled bool) {
		enabled := ancestor_enabled && el.presented_enabled() && !el.presented_hidden() && !el.overlay_inert()
		sync_mounted_control(Element{ ...el, enabled: enabled })
		if el.kind == .scroll {
			g_active_scrolls[scroll_view_state_id(el, path)] = true
		}
		for i, child in el.children {
			sync_mounted_focus_control_subtree(child, reconciliation_child_key(path, i, child), enabled)
		}
	}

	fn sync_mounted_control(el Element) {
		kind_changed := el.id in g_text_kinds && (g_text_kinds[el.id] or { el.kind }) != el.kind
		if kind_changed {
			// Remove the old editor before pruning, even when the replacement is
			// not a text control. Its eligible id can still own navigation focus.
			forget_text_state(el.id)
			forget_portable_text_area_selection(el.id)
			g_gg_app.editable_fields.delete(el.id)
			g_active_fields.delete(el.id)
			if g_gg_app.composition.field_id == el.id {
				g_gg_app.composition = TextComposition{}
			}
			if g_open_dropdown == el.id { close_dropdown() }
		}
		if el.kind in [.text_field, .text_area, .dropdown] {
			previous := g_text_props[el.id] or { el.text }
			if kind_changed || el.id !in g_text_values || (el.text != previous && (g_text_values[el.id] or { '' }) != el.text) {
				if g_gg_app.composition.field_id == el.id {
					g_gg_app.composition = TextComposition{}
				}
				replace_text_value(el.id, el.text)
				if el.kind != .dropdown { replace_text_editor(el.id, text_editor(el.text.clone())) }
			}
			if el.id !in g_text_props || el.text != previous { replace_text_prop(el.id, el.text) }
			g_text_kinds[el.id] = el.kind
			g_active_fields[el.id] = true
			if el.kind != .dropdown {
				g_gg_app.editable_fields[el.id] = el.enabled && !el.readonly
				if (!el.enabled || el.readonly) && g_gg_app.composition.field_id == el.id {
					g_gg_app.composition = TextComposition{}
				}
			}
		}
		if el.id.len == 0 { return }
		match el.kind {
			.checkbox {
				if el.id !in g_checkbox_values || (g_checkbox_declared[el.id] or { el.checked }) != el.checked {
					g_checkbox_values[el.id] = el.checked
				}
				g_checkbox_declared[el.id] = el.checked
				g_active_checkboxes[el.id] = true
			}
			.switch_control {
				if el.id !in g_switch_values || (g_switch_declared[el.id] or { el.checked }) != el.checked {
					g_switch_values[el.id] = el.checked
				}
				g_switch_declared[el.id] = el.checked
				g_active_switches[el.id] = true
			}
			.toggle_button {
				g_toggle_groups[el.id] = el.toggle_group()
				g_toggle_allow_no_selection[el.id] = el.toggle_allow_no_selection()
				if el.id !in g_toggle_values || (g_toggle_declared[el.id] or { el.checked }) != el.checked {
					g_toggle_values[el.id] = el.checked
				}
				g_toggle_declared[el.id] = el.checked
				g_active_toggles[el.id] = true
				if g_toggle_values[el.id] or { false } { release_custom_toggle_group(el.id) }
			}
			.slider {
				spec := slider_spec(el)
				if el.id !in g_slider_values || (g_slider_declared[el.id] or { el.value }) != el.value {
					g_slider_values[el.id] = slider_clamped_value(el.value, spec.min, spec.max)
				}
				g_slider_values[el.id] = slider_clamped_value(g_slider_values[el.id] or { el.value }, spec.min, spec.max)
				g_slider_specs[el.id] = spec
				g_slider_declared[el.id] = el.value
				g_active_sliders[el.id] = true
			}
			else {}
		}
	}
}
