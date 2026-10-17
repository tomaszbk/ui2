@[has_globals]
module ui2

$if (linux || macos || windows) && !ui2_headless ? {
	__global overlay_trigger_old_requests int
	__global overlay_trigger_new_requests int

	fn overlay_trigger_old_callback(_event ElementEvent) { overlay_trigger_old_requests++ }
	fn overlay_trigger_new_callback(_event ElementEvent) { overlay_trigger_new_requests++ }

	fn overlay_trigger_identity_mount(mut app GgApp, element Element) ! {
		app.declared_root = screen(0xffffff, [
			button('anchor', 'Anchor', rect(20, 20, 100, 30), BoxStyle{}, TextStyle{}),
			element,
		])
		app.has_root = true
		app.declaration_pending = true
		projected := resolve_custom_layout_snapshot(mut app, FrameWork{}, measure_layout_text, [], true)!
		reconcile_mounted_focus_controls(projected)
		update_custom_focus_tree(projected)
	}

	fn overlay_trigger_identity_tip(callback ElementCallback, key string) !Element {
		return with_overlay(Element{ ...view('tip', rect(0, 0, 140, 50), BoxStyle{}, []Element{}), key: key },
			OverlayConfig{ kind: .tooltip, anchor: 'anchor', tooltip_delay: 0.5, on_open: callback })!
	}

	fn test_same_public_id_key_change_preserves_the_retained_tooltip_deadline() ! {
		previous_app := g_gg_app
		previous_build := g_build_screen
		previous := activate_custom_window_state(new_custom_window_state())
		defer {
			activate_custom_window_state(previous)
			g_gg_app = previous_app
			g_build_screen = previous_build
		}
		g_build_screen = unsafe { nil }
		mut app := &GgApp{ ctx: &DrawContext{ width: 400, height: 300 } }
		g_gg_app = app
		overlay_trigger_old_requests = 0
		overlay_trigger_identity_mount(mut app, overlay_trigger_identity_tip(overlay_trigger_old_callback, 'old-key')!)!
		generation := (app.layout_tree.identity('tip') or { panic('missing tip') }).generation
		g_tooltip.pointer_in = true
		g_tooltip.pointer_x = 30
		g_tooltip.pointer_y = 30
		update_overlay_triggers(0)
		assert overlay_deadline() == 500
		overlay_trigger_identity_mount(mut app, overlay_trigger_identity_tip(overlay_trigger_old_callback, 'new-key')!)!
		assert (app.layout_tree.identity('tip') or { panic('missing tip') }).generation == generation
		update_overlay_triggers(200)
		assert overlay_deadline() == 500
		update_overlay_triggers(500)
		assert overlay_trigger_old_requests == 1
	}

	fn test_replaced_compiled_tooltip_owner_gets_its_own_request_and_hover_delay() ! {
		previous_app := g_gg_app
		previous_build := g_build_screen
		previous := activate_custom_window_state(new_custom_window_state())
		mut first := new_vml_document('old-tooltip')!
		mut second := new_vml_document('new-tooltip')!
		defer {
			first.dispose() or { panic(err) }
			second.dispose() or { panic(err) }
			activate_custom_window_state(previous)
			g_gg_app = previous_app
			g_build_screen = previous_build
		}
		g_build_screen = unsafe { nil }
		mut app := &GgApp{ ctx: &DrawContext{ width: 400, height: 300 } }
		g_gg_app = app
		overlay_trigger_old_requests = 0
		overlay_trigger_new_requests = 0
		old_node := first.element(overlay_trigger_identity_tip(overlay_trigger_old_callback, 'old-key')!,
			identity: 'tip'
		)!
		first.mount()!
		overlay_trigger_identity_mount(mut app, old_node.element())!
		generation := (app.layout_tree.identity('tip') or { panic('missing tip') }).generation
		g_tooltip.pointer_in = true
		g_tooltip.pointer_x = 30
		g_tooltip.pointer_y = 30
		update_overlay_triggers(0)
		update_overlay_triggers(500)
		assert overlay_trigger_old_requests == 1
		new_node := second.element(overlay_trigger_identity_tip(overlay_trigger_new_callback, 'new-key')!,
			identity: 'tip'
		)!
		second.mount()!
		overlay_trigger_identity_mount(mut app, new_node.element())!
		first.dispose()!
		assert first.is_disposed() && !second.is_disposed()
		assert old_node != new_node && old_node.identity() != new_node.identity()
		assert (app.layout_tree.identity('tip') or { panic('missing tip') }).generation == generation
		assert app.overlay_tree.layers[app.overlay_tree.layer_index('tip')].element.compiled_node == new_node
		update_overlay_triggers(600)
		assert overlay_trigger_new_requests == 0
		assert overlay_deadline() == 1100
		update_overlay_triggers(1099)
		assert overlay_trigger_new_requests == 0
		update_overlay_triggers(1100)
		assert overlay_trigger_old_requests == 1 && overlay_trigger_new_requests == 1
	}

	fn test_tooltip_deadline_is_retired_when_kind_changes_or_open_handler_is_removed() ! {
		for change_kind in [true, false] {
			previous_app := g_gg_app
			previous_build := g_build_screen
			previous := activate_custom_window_state(new_custom_window_state())
			defer {
				activate_custom_window_state(previous)
				g_gg_app = previous_app
				g_build_screen = previous_build
			}
			g_build_screen = unsafe { nil }
			mut app := &GgApp{ ctx: &DrawContext{ width: 400, height: 300 } }
			g_gg_app = app
			overlay_trigger_old_requests = 0
			original := overlay_trigger_identity_tip(overlay_trigger_old_callback, 'tip')!
			overlay_trigger_identity_mount(mut app, original)!
			g_tooltip.pointer_in = true
			g_tooltip.pointer_x = 30
			g_tooltip.pointer_y = 30
			update_overlay_triggers(0)
			assert overlay_deadline() == 500
			changed := with_overlay(view('tip', original.frame, original.box, []Element{}), OverlayConfig{
				kind:    if change_kind { .popover } else { .tooltip }
				anchor:  'anchor'
				on_open: if change_kind { overlay_trigger_old_callback } else { unsafe { nil } }
			})!
			overlay_trigger_identity_mount(mut app, changed)!
			update_overlay_triggers(200)
			assert overlay_deadline() == -1
			assert 'tip' !in app.overlay_triggers
			update_overlay_triggers(600)
			assert overlay_deadline() == -1 && overlay_trigger_old_requests == 0
		}
	}

	fn test_replaced_compiled_owner_gets_its_own_unavailable_notification() ! {
		previous_app := g_gg_app
		previous_build := g_build_screen
		previous := activate_custom_window_state(new_custom_window_state())
		mut first := new_vml_document('old-unavailable')!
		mut second := new_vml_document('new-unavailable')!
		defer {
			first.dispose() or { panic(err) }
			second.dispose() or { panic(err) }
			activate_custom_window_state(previous)
			g_gg_app = previous_app
			g_build_screen = previous_build
		}
		g_build_screen = unsafe { nil }
		mut app := &GgApp{ ctx: &DrawContext{ width: 400, height: 300 } }
		g_gg_app = app
		overlay_trigger_old_requests = 0
		overlay_trigger_new_requests = 0
		old_node := first.element(with_overlay(view('tip', rect(0, 0, 140, 50), BoxStyle{}, []Element{}),
			OverlayConfig{ kind: .dialog, open: true, owner: 'missing', on_dismiss: overlay_trigger_old_callback })!,
			identity: 'tip'
		)!
		first.mount()!
		overlay_trigger_identity_mount(mut app, old_node.element())!
		update_overlay_triggers(0)
		assert overlay_trigger_old_requests == 1
		new_node := second.element(with_overlay(view('tip', rect(0, 0, 140, 50), BoxStyle{}, []Element{}),
			OverlayConfig{ kind: .dialog, open: true, owner: 'missing', on_dismiss: overlay_trigger_new_callback })!,
			identity: 'tip'
		)!
		second.mount()!
		overlay_trigger_identity_mount(mut app, new_node.element())!
		first.dispose()!
		assert first.is_disposed() && old_node != new_node
		update_overlay_triggers(1)
		assert overlay_trigger_new_requests == 1
		update_overlay_triggers(2)
		assert overlay_trigger_old_requests == 1 && overlay_trigger_new_requests == 1
	}
}
