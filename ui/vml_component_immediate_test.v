// vtest vflags: -d ui2_custom_rendering
@[has_globals]
module ui2

$if (android || linux || ((ios || macos || windows) && ui2_custom_rendering ?)) && !ui2_headless ? {
	fn vml_retained_measure(text string, _style TextStyle, width f64) !LayoutSize {
		return LayoutSize{ width: if width < 0 { f64(text.runes().len * 8) } else { width }, height: 30 }
	}

	fn test_compiled_effect_and_keyed_reorder_preserve_live_utf8_edit_selection_focus_scroll_ime() ! {
		mut w := &Window{}
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
			fn (mut owner CompiledVmlComponent, item &Signal[string]) ![]&CompiledVmlNode {
				return [owner.element(Element{ kind: .text_area, id: 'edit', text: 'declarado', frame: rect(0, 0, 200, 40) })!]
			})!
		rows.update(['a', 'b'])!
		root.set_children([container, caption])!
		w.declared_root = root.element()
		initial := w.scheduler.begin_frame(0) or { panic('missing initial frame') }
		_ = w.resolve_custom_layout(initial, vml_retained_measure, w.take_custom_layout_patches())!
		w.scheduler.finish_frame(initial)
		root.mount()!
		editor := rows.nodes()[0].element().id
		identity := w.layout_tree.identity(editor) or { panic('missing mounted editor') }
		w.replace_text_prop(editor, 'declarado')
		w.replace_text_value(editor, 'ñ café🙂')
		w.replace_text_editor(editor, TextEditor{ text: 'ñ café🙂'.clone(), selection: TextSelection{ anchor: 1, caret: 4 } })
		w.focused_field = editor
		w.scroll_offsets[named_scroll_state_id(editor)] = 42
		w.composition = TextComposition{ field_id: editor, text: 'á' }
		w.layout_tree.reset_stats()
		value.set('after')!
		rows.update(['b', 'a'])!
		work := w.scheduler.begin_frame(1) or { panic('missing retained patch frame') }
		assert !work.build && work.reasons == RenderReason.layout
		resolved := w.resolve_custom_layout(work, vml_retained_measure, w.take_custom_layout_patches())!
		w.scheduler.finish_frame(work)
		assert resolved.children[1].text == 'after'
		assert resolved.children[0].children[1].id == editor
		assert w.layout_tree.identity(editor) or { panic('editor identity retired') } == identity
		assert w.text(editor) == 'ñ café🙂'
		assert w.text_editors[editor].selection == TextSelection{ anchor: 1, caret: 4 }
		assert w.focused_field == editor
		assert w.scroll_offset(editor) == 42
		assert w.composition == TextComposition{ field_id: editor, text: 'á' }
		assert w.layout_tree.stats().builds == 0
		assert !w.scheduler.stats().pending
	}
}
