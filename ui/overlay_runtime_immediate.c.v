// vfmt off
module ui2

$if (linux || macos || windows) && !ui2_headless ? && !ui2_document_library ? {
	fn resolve_custom_overlays(mut app GgApp, declared Element, measure LayoutTextMeasureFn) !Element {
		viewport := if app.ctx != unsafe { nil } {
			rect(0, 0, f64(app.ctx.width), f64(app.ctx.height) - menu_bar_height())
		} else { bounds() }
		root := with_drawn_popup_menu(mut app, declared, viewport)
		mut tree := app.overlay_tree
		if !tree.initialized || tree.source != root {
			tree.has_overlays = element_has_overlays(root)
			if tree.has_overlays {
				app.overlay_offsets.clear()
				app.overlay_offsets_x.clear()
				custom_focus_offsets(root, 'root', mut app.overlay_offsets, mut app.overlay_offsets_x)
			}
		} else if tree.has_overlays {
			for node in tree.geometry.nodes {
				if node.el.kind == .scroll {
					id := scroll_view_state_id(node.el, node.path)
					app.overlay_offsets[node.path] = scroll_state_offset(id)
					app.overlay_offsets_x[node.path] = scroll_state_offset_x(id)
				}
			}
		}
		tree.offsets_x = unsafe { app.overlay_offsets_x }
		tree.measure = measure
		tree.environment = app.layout_environment
		return tree.resolve(root, app.overlay_offsets, viewport, app.presentation_revision)!
	}

	fn request_overlay_dismiss(layer OverlayLayer, reason OverlayDismissReason) {
		callback := layer.config.on_dismiss
		if callback == unsafe { nil } { return }
		dispatch := custom_input_dispatch(g_gg_app)
		if !dispatch.valid() { return }
		index := g_gg_app.overlay_tree.layer_index(layer.element.id)
		if index < 0 { return }
		current := g_gg_app.overlay_tree.layers[index]
		if current.element.compiled_node != layer.element.compiled_node
			|| (layer.element.mounted_generation() > 0 && current.element.mounted_generation() != layer.element.mounted_generation())
			|| voidptr(current.config.on_dismiss) != voidptr(callback) { return }
		revision := g_gg_app.presentation_revision
		callback(ElementEvent{ kind: .dismiss, id: layer.element.id, dismiss_reason: reason })
		if dispatch.valid() && revision == g_gg_app.presentation_revision { request_refresh() }
	}

	fn request_overlay_open(layer OverlayLayer, x f64, y f64) {
		callback := layer.config.on_open
		if callback == unsafe { nil } { return }
		dispatch := custom_input_dispatch(g_gg_app)
		if !dispatch.valid() { return }
		revision := g_gg_app.presentation_revision
		callback(ElementEvent{ kind: .open, id: layer.element.id, x: x, y: y })
		if dispatch.valid() && revision == g_gg_app.presentation_revision { request_refresh() }
	}

	// overlay_context_press offers a secondary press to the overlays first. An
	// open declared context menu moves to it when its owner is under it, the top
	// surface takes a press outside it, and a closed declared context menu opens
	// when its owner is under it. It reports whether an overlay took the press.
	fn overlay_context_press(x f64, y f64) bool {
		dispatch := custom_input_dispatch(g_gg_app)
		app := g_gg_app
		if active := app.overlay_tree.top_active() {
			if active.config.kind == .context_menu && !overlay_contains(active, x, y)
				&& active.config.on_open != unsafe { nil } {
				owner_id := if active.config.anchor.len > 0 { active.config.anchor } else { active.config.owner }
				if owner := g_focus_navigation.node(owner_id) {
					if !owner.hidden && owner.enabled && hit_target_contains(custom_focus_target(owner), x, y) {
						request_overlay_open(active, x, y - menu_bar_height())
						return true
					}
				}
			}
		}
		if overlay_pointer_down(x, y) || !dispatch.valid() { return true }
		for i := app.overlay_tree.layers.len - 1; i >= 0; i-- {
			layer := app.overlay_tree.layers[i]
			if layer.config.kind != .context_menu || !layer.available || layer.config.on_open == unsafe { nil } { continue }
			owner_id := if layer.config.anchor.len > 0 { layer.config.anchor } else { layer.config.owner }
			node := g_focus_navigation.node(owner_id) or { continue }
			if node.hidden || !node.enabled || !hit_target_contains(custom_focus_target(node), x, y) { continue }
			request_overlay_open(layer, x, y - menu_bar_height())
			return true
		}
		return false
	}

	fn overlay_anchor_focused(anchor FocusNode) bool {
		mut current := g_focus_navigation.node(g_focused_field) or { return false }
		for _ in 0 .. g_focus_navigation.nodes.len {
			if current.path == anchor.path { return true }
			current = g_focus_navigation.path_node(current.parent) or { return false }
		}
		return false
	}

	fn update_overlay_triggers(now i64) {
		dispatch := custom_input_dispatch(g_gg_app)
		root := g_focus_navigation.root_revision
		if g_gg_app.overlay_trigger_revision != g_gg_app.overlay_tree.source_revision {
			for id in g_gg_app.overlay_triggers.keys() {
				if g_gg_app.overlay_tree.layer_index(id) < 0 { g_gg_app.overlay_triggers.delete(id) }
			}
			for id in g_gg_app.overlay_unavailable.keys() {
				if g_gg_app.overlay_tree.layer_index(id) < 0 { g_gg_app.overlay_unavailable.delete(id) }
			}
			g_gg_app.overlay_trigger_revision = g_gg_app.overlay_tree.source_revision
		}
		for layer in g_gg_app.overlay_tree.layers {
			id := layer.element.id
			owner := OverlayTriggerOwner{ mounted_generation: layer.element.mounted_generation(), compiled_node: layer.element.compiled_node }
			if layer.config.open && !layer.available {
				requested := if previous := g_gg_app.overlay_unavailable[id] { previous == owner } else { false }
				if !requested {
					g_gg_app.overlay_unavailable[id] = owner
					request_overlay_dismiss(layer, .owner_unavailable)
				}
			} else { g_gg_app.overlay_unavailable.delete(id) }
			if !dispatch.valid() || root != g_focus_navigation.root_revision { return }
			if layer.config.kind != .tooltip || layer.config.on_open == unsafe { nil } {
				g_gg_app.overlay_triggers.delete(id)
				continue
			}
			anchor := g_focus_navigation.node(layer.config.anchor) or {
				g_gg_app.overlay_triggers.delete(id)
				continue
			}
			focused := !anchor.hidden && anchor.enabled && overlay_anchor_focused(anchor)
			hovered := !anchor.hidden && anchor.enabled && g_tooltip.pointer_in
				&& hit_target_contains(custom_focus_target(anchor), g_tooltip.pointer_x, g_tooltip.pointer_y)
			inside := layer.available && (focused || hovered) && !g_touch.down && !menu_bar_open() && !drawn_popup_menu_open() && g_open_dropdown.len == 0
			mut state := g_gg_app.overlay_triggers[id] or { OverlayTrigger{ owner: owner } }
			if state.owner != owner { state = OverlayTrigger{ owner: owner } }
			if inside && !state.inside {
				state.requested = false
				state.deadline = if focused { now } else { now + i64(layer.config.tooltip_delay * 1000) }
			}
			if inside && !state.requested {
				if focused { state.deadline = now }
				else if state.pointer_x != g_tooltip.pointer_x || state.pointer_y != g_tooltip.pointer_y {
					state.deadline = now + i64(layer.config.tooltip_delay * 1000)
				}
			}
			state.pointer_x = g_tooltip.pointer_x
			state.pointer_y = g_tooltip.pointer_y
			if !inside {
				state.deadline = -1
				state.requested = false
			}
			leaving := state.inside && !inside
			state.inside = inside
			ready := inside && !state.requested && now >= state.deadline
			if ready { state.requested = true; state.deadline = -1 }
			g_gg_app.overlay_triggers[id] = state
			if leaving && layer.config.open { request_overlay_dismiss(layer, .pointer_leave) }
			if ready && !layer.config.open { request_overlay_open(layer, anchor.frame.x, anchor.frame.y - menu_bar_height()) }
			if layer.active { g_tooltip.dismiss() }
			if !dispatch.valid() || root != g_focus_navigation.root_revision { return }
		}
	}

	fn overlay_deadline() i64 {
		mut next := i64(-1)
		for _, state in g_gg_app.overlay_triggers {
			if state.deadline >= 0 && (next < 0 || state.deadline < next) { next = state.deadline }
		}
		return next
	}

	fn overlay_contains(layer OverlayLayer, x f64, y f64) bool {
		node := g_focus_navigation.node(layer.element.id) or { return false }
		return hit_target_contains(custom_focus_target(node), x, y)
	}

	// Outside presses belong to the transient surface even when its controlled
	// handler vetoes closing. They never click through into a background control.
	fn overlay_pointer_down(x f64, y f64) bool {
		layer := g_gg_app.overlay_tree.top_active() or { return false }
		if overlay_contains(layer, x, y) { return false }
		if layer.config.dismiss_on_outside { request_overlay_dismiss(layer, .outside_pointer) }
		return true
	}

	fn overlay_key(event KeyEvent, repeated bool) bool {
		layer := g_gg_app.overlay_tree.top_active() or { return false }
		if event.code == .escape && layer.config.dismiss_on_escape {
			if !repeated { request_overlay_dismiss(layer, .escape) }
			return true
		}
		if layer.config.kind !in [.menu, .context_menu] || event.ctrl || event.alt || event.cmd { return false }
		mut manager := focus_manager()
		match event.code {
			.up, .down { focus(if manager.traverse(event.code == .up) { manager.current } else { layer.element.id }); return true }
			.home, .end { destination := manager.first(event.code == .end); if destination.len > 0 { focus(destination) }; return true }
			.tab { if !repeated { request_overlay_dismiss(layer, .escape) }; return true }
			else { return false }
		}
	}

	fn overlay_selection_owner(id string) ?OverlayLayer {
		node := g_focus_navigation.node(id) or { return none }
		for i := g_gg_app.overlay_tree.layers.len - 1; i >= 0; i-- {
			layer := g_gg_app.overlay_tree.layers[i]
			if layer.active && layer.config.kind in [.menu, .context_menu] && layer.element.id in node.scopes { return layer }
		}
		return none
	}
}

$if (android || ios) && !ui2_headless ? && !ui2_document_library ? {
	fn resolve_custom_overlays(mut _app GgApp, root Element, _measure LayoutTextMeasureFn) !Element { return root }
	fn overlay_pointer_down(_x f64, _y f64) bool { return false }
	fn overlay_key(_event KeyEvent, _repeated bool) bool { return false }
	fn overlay_selection_owner(_id string) ?OverlayLayer { return none }
	fn request_overlay_dismiss(_layer OverlayLayer, _reason OverlayDismissReason) {}
	fn overlay_context_press(_x f64, _y f64) bool { return false }
	fn update_overlay_triggers(_now i64) {}
	fn overlay_deadline() i64 { return -1 }
}
