// vtest vflags: -d ui2_custom_rendering
@[has_globals]
module ui2

$if (android || linux || ((ios || macos || windows) && ui2_custom_rendering ?)) && !ui2_headless ? {
	import gg

	fn incremental_runtime_measure(text string, _style TextStyle, width f64) !LayoutSize {
		return LayoutSize{ width: if width < 0 { f64(text.runes().len * 8) } else { width }, height: 20 }
	}

	fn test_subtree_runtime_preserves_local_utf8_editor_ime_focus_scroll_and_queued_generation() {
		mut w := &Window{}
		field := text_input(TextInputConfig{ id: 'editor', text: 'declarado', frame: rect(0, 0, 100, 30) })!
		label := label('label', 'hola', Rect{}, TextStyle{})
		w.declared_root = flex(FlexConfig{
			id:          'root'
			frame:       rect(0, 0, 200, 100)
			orientation: .vertical
			children:    [FlexChild{ element: label }, FlexChild{ element: field }]
		})!
		first := w.scheduler.begin_frame(0) or { panic('no initial frame') }
		_ = w.resolve_custom_layout(first, incremental_runtime_measure, w.take_custom_layout_patches())!
		w.scheduler.finish_frame(first)
		w.replace_text_prop('editor', 'declarado')
		w.replace_text_value('editor', 'ñ café🙂')
		w.replace_text_editor('editor', TextEditor{ text: 'ñ café🙂'.clone(), selection: TextSelection{ anchor: 1, caret: 4 } })
		w.focused_field = 'editor'
		w.scroll_offsets[named_scroll_state_id('editor')] = 42
		w.composition = TextComposition{ field_id: 'editor', text: 'á' }
		w.layout_tree.reset_stats()
		w.refresh_element('label', Element{ ...label, text_style: TextStyle{ color: 0xff0000 } })
		work := w.scheduler.begin_frame(1) or { panic('no patch') }
		assert !work.build && work.reasons == RenderReason.layout
		_ = w.resolve_custom_layout(work, incremental_runtime_measure, w.take_custom_layout_patches())!
		assert w.layout_stats().text_measurements == 0
		assert w.layout_stats().layout_visits == 0
		w.refresh_element('label', Element{ ...label, text: 'cambia' })
		w.scheduler.finish_frame(work)
		assert w.scheduler.stats().pending
		next := w.scheduler.begin_frame(2) or { panic('lost next generation') }
		root := w.resolve_custom_layout(next, incremental_runtime_measure, w.take_custom_layout_patches())!
		w.scheduler.finish_frame(next)
		assert root.children[0].text == 'cambia'
		assert root.children[1].text == 'declarado'
		assert w.text('editor') == 'ñ café🙂'
		assert w.text_editors['editor'].selection == TextSelection{ anchor: 1, caret: 4 }
		assert w.focused_field == 'editor'
		assert w.scroll_offset('editor') == 42
		assert w.composition.text == 'á'
		assert w.layout_tree.stats().builds == 0
	}

	fn test_hover_and_scroll_request_paint_without_a_screen_build() {
		mut w := &Window{}
		initial := w.scheduler.begin_frame(0) or { panic('no frame') }
		w.scheduler.finish_frame(initial)
		on_event(&gg.Event{ typ: .mouse_move, mouse_x: -100, mouse_y: -100 }, mut w)
		work := w.scheduler.begin_frame(1) or { panic('no paint') }
		assert !work.build && work.reasons == RenderReason.paint
		w.scheduler.finish_frame(work)
	}
}
