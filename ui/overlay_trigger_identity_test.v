// vtest vflags: -d ui2_custom_rendering
@[has_globals]
module ui2

$if (linux || ((macos || windows) && ui2_custom_rendering ?)) && !ui2_headless ? {
	__global overlay_trigger_old_requests int
	__global overlay_trigger_new_requests int

	fn overlay_trigger_old_callback(_event ElementEvent) { overlay_trigger_old_requests++ }
	fn overlay_trigger_new_callback(_event ElementEvent) { overlay_trigger_new_requests++ }

	fn overlay_trigger_identity_mount(mut w Window, element Element) ! {
		w.declared_root = screen(0xffffff, [
			button('anchor', 'Anchor', rect(20, 20, 100, 30), BoxStyle{}, TextStyle{}),
			element,
		])
		w.has_root = true
		w.declaration_pending = true
		projected := w.resolve_custom_layout_snapshot(FrameWork{}, measure_layout_text, [], true)!
		w.reconcile_mounted_focus_controls(projected)
		w.update_custom_focus_tree(projected)
	}

	fn overlay_trigger_identity_tip(callback ElementCallback, key string) !Element {
		return with_overlay(Element{ ...view('tip', rect(0, 0, 140, 50), BoxStyle{}, []Element{}), key: key },
			OverlayConfig{ kind: .tooltip, anchor: 'anchor', tooltip_delay: 0.5, on_open: callback })!
	}

	fn test_same_public_id_key_change_preserves_the_retained_tooltip_deadline() ! {
		mut w := &Window{ ctx: &DrawContext{ width: 400, height: 300 } }
		overlay_trigger_old_requests = 0
		overlay_trigger_identity_mount(mut w, overlay_trigger_identity_tip(overlay_trigger_old_callback, 'old-key')!)!
		generation := (w.layout_tree.identity('tip') or { panic('missing tip') }).generation
		w.tooltip.pointer_in = true
		w.tooltip.pointer_x = 30
		w.tooltip.pointer_y = 30
		w.update_overlay_triggers(0)
		assert w.overlay_deadline() == 500
		overlay_trigger_identity_mount(mut w, overlay_trigger_identity_tip(overlay_trigger_old_callback, 'new-key')!)!
		assert (w.layout_tree.identity('tip') or { panic('missing tip') }).generation == generation
		w.update_overlay_triggers(200)
		assert w.overlay_deadline() == 500
		w.update_overlay_triggers(500)
		assert overlay_trigger_old_requests == 1
	}

	fn test_replaced_compiled_tooltip_owner_gets_its_own_request_and_hover_delay() ! {
		mut first := new_vml_document('old-tooltip')!
		mut second := new_vml_document('new-tooltip')!
		defer {
			first.dispose() or { panic(err) }
			second.dispose() or { panic(err) }
		}
		mut w := &Window{ ctx: &DrawContext{ width: 400, height: 300 } }
		overlay_trigger_old_requests = 0
		overlay_trigger_new_requests = 0
		old_node := first.element(overlay_trigger_identity_tip(overlay_trigger_old_callback, 'old-key')!,
			identity: 'tip'
		)!
		first.mount()!
		overlay_trigger_identity_mount(mut w, old_node.element())!
		generation := (w.layout_tree.identity('tip') or { panic('missing tip') }).generation
		w.tooltip.pointer_in = true
		w.tooltip.pointer_x = 30
		w.tooltip.pointer_y = 30
		w.update_overlay_triggers(0)
		w.update_overlay_triggers(500)
		assert overlay_trigger_old_requests == 1
		new_node := second.element(overlay_trigger_identity_tip(overlay_trigger_new_callback, 'new-key')!,
			identity: 'tip'
		)!
		second.mount()!
		overlay_trigger_identity_mount(mut w, new_node.element())!
		first.dispose()!
		assert first.is_disposed() && !second.is_disposed()
		assert old_node != new_node && old_node.identity() != new_node.identity()
		assert (w.layout_tree.identity('tip') or { panic('missing tip') }).generation == generation
		assert w.overlay_tree.layers[w.overlay_tree.layer_index('tip')].element.compiled_node == new_node
		w.update_overlay_triggers(600)
		assert overlay_trigger_new_requests == 0
		assert w.overlay_deadline() == 1100
		w.update_overlay_triggers(1099)
		assert overlay_trigger_new_requests == 0
		w.update_overlay_triggers(1100)
		assert overlay_trigger_old_requests == 1 && overlay_trigger_new_requests == 1
	}

	fn test_tooltip_deadline_is_retired_when_kind_changes_or_open_handler_is_removed() ! {
		for change_kind in [true, false] {
			mut w := &Window{ ctx: &DrawContext{ width: 400, height: 300 } }
			overlay_trigger_old_requests = 0
			original := overlay_trigger_identity_tip(overlay_trigger_old_callback, 'tip')!
			overlay_trigger_identity_mount(mut w, original)!
			w.tooltip.pointer_in = true
			w.tooltip.pointer_x = 30
			w.tooltip.pointer_y = 30
			w.update_overlay_triggers(0)
			assert w.overlay_deadline() == 500
			changed := with_overlay(view('tip', original.frame, original.box, []Element{}), OverlayConfig{
				kind:    if change_kind { .popover } else { .tooltip }
				anchor:  'anchor'
				on_open: if change_kind { overlay_trigger_old_callback } else { unsafe { nil } }
			})!
			overlay_trigger_identity_mount(mut w, changed)!
			w.update_overlay_triggers(200)
			assert w.overlay_deadline() == -1
			assert 'tip' !in w.overlay_triggers
			w.update_overlay_triggers(600)
			assert w.overlay_deadline() == -1 && overlay_trigger_old_requests == 0
		}
	}

	fn test_replaced_compiled_owner_gets_its_own_unavailable_notification() ! {
		mut first := new_vml_document('old-unavailable')!
		mut second := new_vml_document('new-unavailable')!
		defer {
			first.dispose() or { panic(err) }
			second.dispose() or { panic(err) }
		}
		mut w := &Window{ ctx: &DrawContext{ width: 400, height: 300 } }
		overlay_trigger_old_requests = 0
		overlay_trigger_new_requests = 0
		old_node := first.element(with_overlay(view('tip', rect(0, 0, 140, 50), BoxStyle{}, []Element{}),
			OverlayConfig{ kind: .dialog, open: true, owner: 'missing', on_dismiss: overlay_trigger_old_callback })!,
			identity: 'tip'
		)!
		first.mount()!
		overlay_trigger_identity_mount(mut w, old_node.element())!
		w.update_overlay_triggers(0)
		assert overlay_trigger_old_requests == 1
		new_node := second.element(with_overlay(view('tip', rect(0, 0, 140, 50), BoxStyle{}, []Element{}),
			OverlayConfig{ kind: .dialog, open: true, owner: 'missing', on_dismiss: overlay_trigger_new_callback })!,
			identity: 'tip'
		)!
		second.mount()!
		overlay_trigger_identity_mount(mut w, new_node.element())!
		first.dispose()!
		assert first.is_disposed() && old_node != new_node
		w.update_overlay_triggers(1)
		assert overlay_trigger_new_requests == 1
		w.update_overlay_triggers(2)
		assert overlay_trigger_old_requests == 1 && overlay_trigger_new_requests == 1
	}
}
