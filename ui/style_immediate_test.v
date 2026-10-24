// vtest vflags: -d ui2_custom_rendering
@[has_globals]
module ui2

$if (android || linux || ((ios || macos || windows) && ui2_custom_rendering ?)) && !ui2_headless ? {
	fn style_backend_measure(text string, _ TextStyle, width f64) !LayoutSize {
		return LayoutSize{ width: if width < 0 { f64(text.runes().len * 8) } else { width }, height: 30 }
	}

	// Text focus owned by a split-process input backend is window state, not an
	// Element property: the renderer paints its focus style from the window.
	fn test_backend_text_focus_is_window_state_that_paints_focus_style() {
		mut w := &Window{}
		w.focused_field = ''
		w.tooltip.pointer_in = false
		w.touch = TouchState{}
		field := Element{
			kind:              .text_field
			id:                'remote'
			frame:             rect(0, 0, 120, 30)
			box:               BoxStyle{ bg: 0x111111 }
			interaction_style: InteractionStyle{ focus: BoxStylePatch{ bg: 0x222222 } }
		}
		area := rect(0, 0, 120, 30)
		viewport := rect(0, 0, 400, 300)
		assert w.resolve_custom_visual_style(field, area, viewport, ContentTransform{}).box.bg == 0x111111
		w.set_backend_text_focus(BackendTextFocus{ id: 'remote', selection: TextSelection{ anchor: 1, caret: 3 } })
		start, end := w.backend_text_focus().selection.ordered()
		assert start == 1 && end == 3
		assert w.resolve_custom_visual_style(field, area, viewport, ContentTransform{}).box.bg == 0x222222
		w.set_backend_text_focus(BackendTextFocus{})
		assert w.resolve_custom_visual_style(field, area, viewport, ContentTransform{}).box.bg == 0x111111
	}

	fn test_theme_style_patch_preserves_live_edit_state_and_uses_paint_invalidation() ! {
		mut w := &Window{}
		mut owner := new_vml_document('theme editor')!
		defer { owner.dispose() or { panic(err) } }
		owner.prepare_theme_tokens(['color:surface'])!
		mut root := owner.element(Element{ kind: .screen, id: 'root', frame: rect(0, 0, 300, 200) })!
		mut field := owner.element(Element{ kind: .text_field, id: 'edit', text: 'declarado', frame: rect(8, 8, 200, 30) })!
		field.style(fn [mut owner] () !StylePatch {
			return style_background(owner.color_token('surface')!)
		})!
		root.set_children([field])!
		w.declared_root = root.element()
		initial := w.scheduler.begin_frame(0) or { panic('missing initial frame') }
		_ = w.resolve_custom_layout(initial, style_backend_measure, w.take_custom_layout_patches())!
		w.scheduler.finish_frame(initial)
		root.mount()!
		identity := w.layout_tree.identity('edit') or { panic('missing editor') }
		w.replace_text_prop('edit', 'declarado')
		w.replace_text_value('edit', 'ñ café🙂')
		w.replace_text_editor('edit', TextEditor{ text: 'ñ café🙂', selection: TextSelection{ anchor: 1, caret: 4 } })
		w.focused_field = 'edit'
		w.composition = TextComposition{ field_id: 'edit', text: 'á' }
		w.layout_tree.reset_stats()
		owner.set_theme(Theme{
			colors: {
				'surface': u32(0)
			}
		})!
		work := w.scheduler.begin_frame(1) or { panic('missing style paint') }
		assert !work.build
		resolved := w.resolve_custom_layout(work, style_backend_measure, w.take_custom_layout_patches())!
		w.scheduler.finish_frame(work)
		assert resolved.children[0].box.bg == 0
		assert w.layout_tree.identity('edit')? == identity
		assert w.text('edit') == 'ñ café🙂'
		assert w.text_editors['edit'].selection == TextSelection{ anchor: 1, caret: 4 }
		assert w.focused_field == 'edit'
		assert w.composition == TextComposition{ field_id: 'edit', text: 'á' }
		assert w.layout_tree.stats().builds == 0
		assert w.layout_tree.stats().measure_visits == 0
		assert w.layout_tree.stats().layout_visits == 0
	}
}
