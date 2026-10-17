@[has_globals]
module ui2

$if (android || ios || linux || macos || windows) && !ui2_headless ? {
	import gg

	fn incremental_runtime_measure(text string, _style TextStyle, width f64) !LayoutSize {
		return LayoutSize{ width: if width < 0 { f64(text.runes().len * 8) } else { width }, height: 20 }
	}

	fn test_subtree_runtime_preserves_local_utf8_editor_ime_focus_scroll_and_queued_generation() {
		previous_app := g_gg_app
		previous_window := capture_custom_window_state()
		defer {
			g_gg_app = previous_app
			previous_window.restore()
		}
		mut app := &GgApp{ scheduler: new_frame_coordinator() }
		g_gg_app = app
		field := text_input(TextInputConfig{ id: 'editor', text: 'declarado', frame: rect(0, 0, 100, 30) })!
		label := label('label', 'hola', Rect{}, TextStyle{})
		app.declared_root = flex(FlexConfig{
			id:          'root'
			frame:       rect(0, 0, 200, 100)
			orientation: .vertical
			children:    [FlexChild{ element: label }, FlexChild{ element: field }]
		})!
		first := app.scheduler.begin_frame(0) or { panic('no initial frame') }
		_ = resolve_custom_layout(mut app, first, incremental_runtime_measure, take_custom_layout_patches(mut app))!
		app.scheduler.finish_frame(first)
		replace_text_prop('editor', 'declarado')
		replace_text_value('editor', 'ñ café🙂')
		replace_text_editor('editor', TextEditor{ text: 'ñ café🙂'.clone(), selection: TextSelection{ anchor: 1, caret: 4 } })
		g_focused_field = 'editor'
		g_scroll_offsets[named_scroll_state_id('editor')] = 42
		app.composition = TextComposition{ field_id: 'editor', text: 'á' }
		app.layout_tree.reset_stats()
		refresh_element('label', Element{ ...label, text_style: TextStyle{ color: 0xff0000 } })
		work := app.scheduler.begin_frame(1) or { panic('no patch') }
		assert !work.build && work.reasons == RenderReason.layout
		_ = resolve_custom_layout(mut app, work, incremental_runtime_measure, take_custom_layout_patches(mut app))!
		assert layout_stats().text_measurements == 0
		assert layout_stats().layout_visits == 0
		refresh_element('label', Element{ ...label, text: 'cambia' })
		app.scheduler.finish_frame(work)
		assert app.scheduler.stats().pending
		next := app.scheduler.begin_frame(2) or { panic('lost next generation') }
		root := resolve_custom_layout(mut app, next, incremental_runtime_measure, take_custom_layout_patches(mut app))!
		app.scheduler.finish_frame(next)
		assert root.children[0].text == 'cambia'
		assert root.children[1].text == 'declarado'
		assert text('editor') == 'ñ café🙂'
		assert g_text_editors['editor'].selection == TextSelection{ anchor: 1, caret: 4 }
		assert g_focused_field == 'editor'
		assert scroll_offset('editor') == 42
		assert app.composition.text == 'á'
		assert app.layout_tree.stats().builds == 0
	}

	fn test_hover_and_scroll_request_paint_without_a_screen_build() {
		previous := g_gg_app
		defer { g_gg_app = previous }
		mut app := &GgApp{ scheduler: new_frame_coordinator() }
		g_gg_app = app
		initial := app.scheduler.begin_frame(0) or { panic('no frame') }
		app.scheduler.finish_frame(initial)
		on_event(&gg.Event{ typ: .mouse_move, mouse_x: -100, mouse_y: -100 }, app)
		work := app.scheduler.begin_frame(1) or { panic('no paint') }
		assert !work.build && work.reasons == RenderReason.paint
		app.scheduler.finish_frame(work)
	}
}
