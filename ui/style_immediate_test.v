// vtest vflags: -d ui2_custom_rendering
@[has_globals]
module ui2

$if (android || linux || ((macos || windows) && ui2_custom_rendering ?)) && !ui2_headless ? {
	fn style_backend_measure(text string, _ TextStyle, width f64) !LayoutSize {
		return LayoutSize{ width: if width < 0 { f64(text.runes().len * 8) } else { width }, height: 30 }
	}

	fn test_theme_style_patch_preserves_live_edit_state_and_uses_paint_invalidation() ! {
		previous_app := g_gg_app
		previous_state := capture_custom_window_state()
		defer {
			g_gg_app = previous_app
			previous_state.restore()
		}
		mut app := &GgApp{ scheduler: new_frame_coordinator() }
		g_gg_app = app
		mut owner := new_vml_document('theme editor')!
		defer { owner.dispose() or { panic(err) } }
		owner.prepare_theme_tokens(['color:surface'])!
		mut root := owner.element(Element{ kind: .screen, id: 'root', frame: rect(0, 0, 300, 200) })!
		mut field := owner.element(Element{ kind: .text_field, id: 'edit', text: 'declarado', frame: rect(8, 8, 200, 30) })!
		field.style(fn [mut owner] () !StylePatch {
			return style_background(owner.color_token('surface')!)
		})!
		root.set_children([field])!
		app.declared_root = root.element()
		initial := app.scheduler.begin_frame(0) or { panic('missing initial frame') }
		_ = resolve_custom_layout(mut app, initial, style_backend_measure, take_custom_layout_patches(mut app))!
		app.scheduler.finish_frame(initial)
		root.mount()!
		identity := app.layout_tree.identity('edit') or { panic('missing editor') }
		replace_text_prop('edit', 'declarado')
		replace_text_value('edit', 'ñ café🙂')
		replace_text_editor('edit', TextEditor{ text: 'ñ café🙂', selection: TextSelection{ anchor: 1, caret: 4 } })
		g_focused_field = 'edit'
		app.composition = TextComposition{ field_id: 'edit', text: 'á' }
		app.layout_tree.reset_stats()
		owner.set_theme(Theme{
			colors: {
				'surface': u32(0)
			}
		})!
		work := app.scheduler.begin_frame(1) or { panic('missing style paint') }
		assert !work.build
		resolved := resolve_custom_layout(mut app, work, style_backend_measure, take_custom_layout_patches(mut app))!
		app.scheduler.finish_frame(work)
		assert resolved.children[0].box.bg == 0
		assert app.layout_tree.identity('edit')? == identity
		assert text('edit') == 'ñ café🙂'
		assert g_text_editors['edit'].selection == TextSelection{ anchor: 1, caret: 4 }
		assert g_focused_field == 'edit'
		assert app.composition == TextComposition{ field_id: 'edit', text: 'á' }
		assert app.layout_tree.stats().builds == 0
		assert app.layout_tree.stats().measure_visits == 0
		assert app.layout_tree.stats().layout_visits == 0
	}
}
