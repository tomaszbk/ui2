module ui2

$if macos && !ui2_custom_rendering ?&& !ui2_headless ? {
	import macos

	fn test_native_assigned_width_wrap_height_fits_actual_appkit_cell() {
		pool := macos.autorelease_pool_new()
		defer { macos.release(pool) }
		caption := 'El texto cambia de tamaño. Ñ, acentos y edición permanecen intactos. Los hermanos de esta columna se desplazan según el ancho asignado.'
		style := TextStyle{ size: 20, lines: 20 }
		measured := measure_layout_element(label('caption', caption, Rect{}, style), LayoutConstraints{ min_width: 612, max_width: 612 }, measure_layout_text)!
		control := native_new_label(native_rect(0, 0, measured.width, measured.height), caption, style.color, style.size, false, false, false, 0, style.lines, .top, false)
		defer { macos.release(control) }
		required := native_label_content_height(control, native_rect(0, 0, measured.width, measured.height), style.lines)
		assert measured.height >= required, 'assigned-width measurement must fit the actual AppKit cell: ${measured.height} < ${required}'
	}

	fn test_native_subtree_layout_moves_siblings_without_replacing_editor_or_selection() {
		pool := macos.autorelease_pool_new()
		defer { macos.release(pool) }
		ensure_runtime_classes()
		mut st := state()
		previous := *st
		st.layout_tree = &LayoutTree{}
		st.root_view = native_new_flipped_view(native_rect(0, 0, 120, 300), BoxStyle{})
		defer {
			remove_stale_nodes(map[string]bool{})
			macos.release(st.root_view)
			unsafe { *st = previous }
		}
		caption := label('caption', 'breve', Rect{}, TextStyle{ lines: 20 })
		editor := text_input(TextInputConfig{ id: 'editor', text: 'declarado', disable_scroll: true, frame: rect(0, 0, 0, 60) })!
		column := flex(FlexConfig{
			id:          'column'
			frame:       rect(0, 0, 100, 260)
			orientation: .vertical
			align:       .stretch
			children:    [FlexChild{ element: caption, shrink: 0 },
				FlexChild{ element: editor, shrink: 0 }]
		})!
		render_root(screen(0xffffff, [column]))
		control := st.views['editor'] or { panic('missing editor') }
		macos.msg_void1(control, 'setString:', macos.nsstring('ñ café🙂'))
		macos.msg_void_range(control, 'setSelectedRange:', macos.range(1, 4))
		macos.msg_void_id_range(control, 'setMarkedText:selectedRange:', macos.nsstring('á'), macos.range(1, 0))
		assert macos.msg_bool(control, 'hasMarkedText')
		live_text := macos.utf8_string(macos.msg_id(control, 'string'))
		selection := macos.msg_range(control, 'selectedRange')
		composition := macos.msg_range(control, 'markedRange')
		before := macos.msg_rect(control, 'frame')
		st.layout_tree.reset_stats()
		refresh_element('caption', Element{ ...caption, text_style: TextStyle{ ...caption.text_style, color: 0xff0000 } })
		assert st.layout_tree.stats().measure_visits == 0
		assert st.layout_tree.stats().layout_visits == 0
		refresh_element('caption', Element{ ...caption, text: 'palabra palabra palabra palabra palabra palabra' })
		current := st.views['editor'] or { panic('lost editor') }
		assert current == control
		assert macos.utf8_string(macos.msg_id(current, 'string')) == live_text
		assert macos.msg_range(current, 'selectedRange') == selection
		assert macos.msg_bool(current, 'hasMarkedText')
		assert macos.msg_range(current, 'markedRange') == composition
		assert macos.msg_rect(current, 'frame').y > before.y
		assert st.layout_tree.stats().builds == 0
	}
}
