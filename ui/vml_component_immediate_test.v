// vtest vflags: -d ui2_custom_rendering
@[has_globals]
module ui2

$if (android || linux || ((macos || windows) && ui2_custom_rendering ?)) && !ui2_headless ? {
	fn vml_retained_measure(text string, _style TextStyle, width f64) !LayoutSize {
		return LayoutSize{ width: if width < 0 { f64(text.runes().len * 8) } else { width }, height: 30 }
	}

	fn test_compiled_effect_and_keyed_reorder_preserve_live_utf8_edit_selection_focus_scroll_ime() ! {
		previous_app := g_gg_app
		previous_window := capture_custom_window_state()
		defer {
			g_gg_app = previous_app
			previous_window.restore()
		}
		mut app := &GgApp{ scheduler: new_frame_coordinator() }
		g_gg_app = app
		mut component := new_vml_component('retained runtime')!
		defer { component.dispose() or { panic(err) } }
		mut root := component.element(Element{ kind: .screen, id: 'root', frame: rect(0, 0, 300, 300) })!
		mut caption := component.element(Element{ kind: .label, id: 'caption', frame: rect(0, 180, 200, 30) })!
		mut value := component.state('value', 'before')!
		caption.effect('text', fn [mut value] (element Element) !Element {
			return Element{ ...element, text: value.get()! }
		})!
		mut container := component.element(flex(FlexConfig{ id: 'items', frame: rect(0, 0, 200, 120), orientation: .vertical })!)!
		mut rows := new_vml_keyed_list(mut container, 'rows', fn (key string) string { return key },
			fn (mut owner CompiledVmlComponent, item &Signal[string]) !&CompiledVmlNode {
				return owner.element(Element{ kind: .text_area, id: 'edit', text: 'declarado', frame: rect(0, 0, 200, 40) })!
			})!
		rows.update(['a', 'b'])!
		root.set_children([container, caption])!
		app.declared_root = root.element()
		initial := app.scheduler.begin_frame(0) or { panic('missing initial frame') }
		_ = resolve_custom_layout(mut app, initial, vml_retained_measure, take_custom_layout_patches(mut app))!
		app.scheduler.finish_frame(initial)
		root.mount()!
		editor := rows.nodes()[0].element().id
		identity := app.layout_tree.identity(editor) or { panic('missing mounted editor') }
		replace_text_prop(editor, 'declarado')
		replace_text_value(editor, 'ñ café🙂')
		replace_text_editor(editor, TextEditor{ text: 'ñ café🙂'.clone(), selection: TextSelection{ anchor: 1, caret: 4 } })
		g_focused_field = editor
		g_scroll_offsets[named_scroll_state_id(editor)] = 42
		app.composition = TextComposition{ field_id: editor, text: 'á' }
		app.layout_tree.reset_stats()
		value.set('after')!
		rows.update(['b', 'a'])!
		work := app.scheduler.begin_frame(1) or { panic('missing retained patch frame') }
		assert !work.build && work.reasons == [.layout]
		resolved := resolve_custom_layout(mut app, work, vml_retained_measure, take_custom_layout_patches(mut app))!
		app.scheduler.finish_frame(work)
		assert resolved.children[1].text == 'after'
		assert resolved.children[0].children[1].id == editor
		assert app.layout_tree.identity(editor) or { panic('editor identity retired') } == identity
		assert text(editor) == 'ñ café🙂'
		assert g_text_editors[editor].selection == TextSelection{ anchor: 1, caret: 4 }
		assert g_focused_field == editor
		assert scroll_offset(editor) == 42
		assert app.composition == TextComposition{ field_id: editor, text: 'á' }
		assert app.layout_tree.stats().builds == 0
		assert !app.scheduler.stats().pending
	}
}
