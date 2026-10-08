// vtest vflags: -d ui2_custom_rendering
@[has_globals]
module ui2

$if ( linux || ( ( macos || windows ) && ui2_custom_rendering ?) ) && !ui2_headless ? {
	// Check every retained string before releasing the source. On a regression
	// this fails while the source is still valid, without reading freed bytes.
	fn assert_shape_excludes_source_storage(shaped ShapedText, source string) {
		start := usize(source.str)
		end := start + usize(source.len)
		mut retained := [shaped.text, shaped.layout.text]
		for line in shaped.lines { retained << line.text }
		for item in shaped.layout.items {
			if item.run_text.len > 0 { retained << item.run_text }
		}
		for text in retained {
			address := usize(text.str)
			assert address < start || address > end, 'shaped text must outlive the source allocation'
		}
	}

	fn check_editor_shape_ownership(id string, value string, multiline bool) ! {
		previous := activate_custom_window_state(new_custom_window_state())
		mut engine := new_text_engine(1)!
		defer {
			forget_text_state(id)
			activate_custom_window_state(previous)
			engine.free()
		}
		style := TextStyle{ size: 16, font_family: 'Roboto Mono' }
		g_text_kinds[id] = if multiline { Kind.text_area } else { Kind.text_field }
		replace_text_editor(id, text_editor(value.clone()))
		editor := g_text_editors[id] or { panic('missing editor') }
		// Allocate the equal-content query before the real replacement frees
		// editor.text; neither query nor expected value borrows that allocation.
		query := editor.text.clone()
		cold := if multiline {
			engine.shape_area(editor.text, style, 400)!
		} else {
			engine.shape(editor.text, style, 400, 1, false)!
		}
		assert_shape_excludes_source_storage(cold, editor.text)
		assert engine.shape_builds == 1 && engine.shape_hits == 0
		positions := cold.layout.get_valid_cursor_positions()
		indices := [0, 4, 6, 7, value.runes().len]
		cursors := indices.map(cold.cursor(it))
		selection := cold.selection(0, 4)
		assert positions.contains(5) && positions.contains(8)
		if !multiline {
			assert positions.contains(12)
		}
		assert cursors[1].x > cursors[0].x
		assert selection.len == 1 && selection[0].width > 0
		replace_text_editor(id, text_editor('reemplazo á'.clone()))
		hit := if multiline {
			engine.shape_area(query, style, 400)!
		} else {
			engine.shape(query, style, 400, 1, false)!
		}
		assert engine.shape_builds == 1 && engine.shape_hits == 1
		assert hit.text.str == cold.text.str, 'a hit reuses the owned cache text'
		assert hit.layout.text.str == cold.layout.text.str
		for shaped in [cold, hit] {
			assert shaped.text == value && shaped.layout.text == value
			assert shaped.layout.get_valid_cursor_positions() == positions
			for i, index in indices {
				assert shaped.cursor(index) == cursors[i]
			}
			assert shaped.selection(0, 4) == selection
			space := shaped.layout.get_char_rect(5) or { panic('missing space geometry') }
			emoji := shaped.layout.get_char_rect(8) or { panic('missing emoji geometry') }
			assert shaped.hit_test(space.x + space.width / 2, space.y + space.height / 2) == 4
			assert shaped.hit_test(emoji.x + emoji.width / 2, emoji.y + emoji.height / 2) == 6
		}
		if multiline {
			assert cold.lines.map(it.text) == ['café ñ🙂', 'área', '']
			assert cold.lines.map(it.start) == [0, 9, 14]
			assert cold.lines.map(it.end) == [7, 13, 14]
			// Remember from an old shape only after the editor has been replaced.
			for shaped in [cold, hit] {
				remember_shaped_text_area(id, shaped, 400, style)
				assert g_text_area_layouts[id].text == value
				assert g_text_area_layouts[id].lines == ['café ñ🙂', 'área', '']
			}
		} else {
			assert cold.lines.len == 1 && cold.lines[0].text == value
			assert hit.hit_test(hit.size.width + 10, 0) == 7
		}
	}

	fn test_field_cold_and_cached_shapes_survive_real_editor_replacement() {
		check_editor_shape_ownership('owned-field', 'café ñ🙂', false)!
	}

	fn test_area_cold_and_cached_shapes_survive_real_editor_replacement() {
		check_editor_shape_ownership('owned-area', 'café ñ🙂\r\nárea\n', true)!
	}

	fn test_cached_and_uncached_shapes_own_short_lived_external_text() {
		mut engine := new_text_engine(1)!
		defer { engine.free() }
		value := 'café ñ🙂'
		source := value.clone()
		query := source.clone()
		style := TextStyle{ size: 16 }
		g_text_font_mutex.lock()
		direct := engine.build_shape_locked(source, [], style, 400, 1, false, false) or {
			g_text_font_mutex.unlock()
			panic(err)
		}
		g_text_font_mutex.unlock()
		cold := engine.shape(source, style, 400, 1, false)!
		assert_shape_excludes_source_storage(direct, source)
		assert_shape_excludes_source_storage(cold, source)
		free_owned_string(source)
		hit := engine.shape(query, style, 400, 1, false)!
		assert engine.shape_builds == 2 && engine.shape_hits == 1
		assert hit.text.str == cold.text.str
		// Returned shapes also keep their text after their cache entry retires.
		engine.shape_cache.clear()
		for shaped in [direct, cold, hit] {
			assert shaped.text == value && shaped.layout.text == value
			assert shaped.lines[0].text == value
			assert shaped.layout.get_valid_cursor_positions().contains(12)
			assert shaped.cursor(7).x > shaped.cursor(4).x
			assert shaped.selection(0, 4).len == 1
			assert shaped.hit_test(shaped.size.width + 10, 0) == 7
			$if debug {
				assert shaped.layout.items.map(it.run_text).join('') == value
			}
		}
	}

	fn test_rich_shapes_outlive_short_lived_runs_and_keep_paint_owners() {
		mut engine := new_text_engine(1)!
		defer { engine.free() }
		first := 'café ñ'.clone()
		second := '\nárea'.clone()
		base := TextStyle{ size: 16 }
		runs := [TextRun{ text: first, style: TextStyle{ ...base, color: 0xff0000 } },
			TextRun{ text: second, style: TextStyle{ ...base, color: 0x0000ff } }]
		cold := engine.shape_runs(runs, base, 400, 2, false)!
		assert_shape_excludes_source_storage(cold, first)
		assert_shape_excludes_source_storage(cold, second)
		free_owned_string(first)
		free_owned_string(second)
		fresh_runs := [
			TextRun{ text: 'café ñ', style: TextStyle{ ...base, color: 0x00ff00 } },
			TextRun{ text: '\nárea', style: TextStyle{ ...base, color: 0xff00ff } },
		]
		hit := engine.shape_runs(fresh_runs, base, 400, 2, false)!
		assert engine.shape_builds == 1 && engine.shape_hits == 1
		assert hit.text.str == cold.text.str
		for i, shaped in [cold, hit] {
			assert shaped.text == 'café ñ\nárea' && shaped.layout.text == shaped.text
			assert shaped.lines.map(it.text) == ['café ñ', 'área']
			assert shaped.cursor(7).y > shaped.cursor(0).y
			assert shaped.selection(0, 4).len == 1
			caret := shaped.cursor(7)
			assert shaped.hit_test(-10, caret.y + caret.height / 2) == 7
			for item in shaped.layout.items {
				color := if item.start_index < 8 { u32(0xff0000) } else { u32(0x0000ff) }
				paint := if item.start_index < 8 { u32(0x00ff00) } else { u32(0xff00ff) }
				assert item.color == hex_color(if i == 0 { color } else { paint })
			}
		}
	}
}
