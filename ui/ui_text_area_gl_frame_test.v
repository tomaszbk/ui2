// vtest vflags: -d ui2_custom_rendering -d darwin_sokol_glcore33
// vfmt off
@[has_globals]
module ui2

$if macos && ui2_custom_rendering ? && darwin_sokol_glcore33 ? && !ui2_headless ? {
	import gg
	import os
	import sokol.gfx

	__global area_gl_mode int
	__global area_gl_phase int
	__global area_gl_builds int
	__global area_gl_setup_posted bool
	__global area_gl_check_posted bool
	__global area_gl_final_posted bool
	__global area_gl_verified bool
	__global area_gl_events = []f64{}
	__global area_gl_caret Rect
	__global area_gl_gpu u32
	__global area_gl_draws u64
	const area_gl_local = 'local café ñ\n'.repeat(12)

	fn area_gl_scrolled(event ElementEvent) {
		if event.kind != .scroll || area_gl_phase != 1 { return }
		area_gl_phase = 2
		area_gl_events << event.value
		assert event.id == 'edit' && event.value == 0
		assert text('edit') == area_gl_local
		assert text_area_caret('edit') == 3 && text_area_selection_length('edit') == 2
		assert g_tooltip_owners == 1
		area_gl_gpu = gfx.query_frame_stats().frame_index
		area_gl_draws = g_gg_app.scheduler.stats().draws
		match area_gl_mode {
			1 { on_event(&gg.Event{typ: .unfocused}, g_gg_app) }
			2 { quit() }
			3 { update_custom_focus_tree(screen(0xffffff, [Element{kind: .button, id: 'replacement'}])) }
			4 { refresh() }
			5 {
				mut captured := g_gg_app.ctx
				captured.destroy()
				quit()
			}
			else {}
		}
		area_gl_caret = g_gg_app.text_caret
		eprintln('area GL callback mode=${area_gl_mode} offset=${event.value} caret=${area_gl_caret} owners=${g_tooltip_owners}')
	}

	fn area_gl_assert_canceled() {
		assert area_gl_events == [f64(0)]
		assert g_gg_app.text_caret == area_gl_caret
		assert g_tooltip_owners == 0
		assert !g_gg_app.scheduler.stats().in_flight
		assert g_gg_app.scheduler.stats().draws == area_gl_draws
		assert gfx.query_frame_stats().frame_index == area_gl_gpu
		assert text('edit') == area_gl_local
		assert text_area_caret('edit') == 3 && text_area_selection_length('edit') == 2
	}

	fn area_gl_final() {
		// Replacing the mounted root removes focus. After it remounts, use
		// the public API to restore the editor before checking its new caret.
		if area_gl_mode == 3 && focused_id() == '' {
			focus('edit')
			assert ui_dispatcher().post(area_gl_final)
			return
		}
		defer { quit() }
		assert area_gl_events == [f64(0)]
		assert g_gg_app.scheduler.stats().draws > area_gl_draws
		assert g_gg_app.text_caret.width > 0
		assert text('edit') == area_gl_local
		assert text_area_caret('edit') == 3 && text_area_selection_length('edit') == 2
		assert g_tooltip_owners == 0
		assert gfx.query_frame_stats().num_draw > 0
		area_gl_verified = true
		eprintln('area GL mode=${area_gl_mode} passed owners=0 valid_repaint=true')
	}

	fn area_gl_check() {
		area_gl_assert_canceled()
		if area_gl_mode == 3 {
			assert semantic_tree().filter(it.id == 'edit').len == 0
		}
		refresh()
	}

	fn area_gl_setup() {
		set_text('edit', area_gl_local)
		focus('edit')
		text_area_set_selection('edit', 1, 2)
		// Render the local edit at the old range before asking it to scroll.
		area_gl_phase = -1
		refresh()
	}

	fn area_gl_scroll_setup() {
		assert g_gg_app.text_caret.width > 0
		scroll_to_offset('edit', 100)
		assert scroll_offset('edit') == 100
		area_gl_phase = 1
		refresh()
	}

	fn area_gl_cleanup(app &GgApp) {
		if area_gl_mode in [2, 5] {
			area_gl_assert_canceled()
			assert app.scheduler.stats().closed
			area_gl_verified = true
			eprintln('area GL mode=${area_gl_mode} passed owners=0 closed=true')
		}
		on_cleanup(app)
	}

	fn area_gl_root() Element {
		area_gl_builds++
		// The first retained build is mounted; initialization no longer preloads a tree.
		if area_gl_builds == 1 && !area_gl_setup_posted {
			area_gl_setup_posted = true
			gfx.enable_frame_stats()
			g_gg_app.ctx.inner.config = gg.Config{...g_gg_app.ctx.inner.config, cleanup_fn: area_gl_cleanup}
			assert ui_dispatcher().post(area_gl_setup)
		}
		if area_gl_phase == -1 {
			area_gl_phase = 0
			assert ui_dispatcher().post(area_gl_scroll_setup)
		} else if area_gl_phase == 1 && !area_gl_check_posted {
			area_gl_check_posted = true
			assert ui_dispatcher().post(area_gl_check)
		} else if area_gl_phase == 2 && !area_gl_final_posted {
			area_gl_final_posted = true
			assert ui_dispatcher().post(area_gl_final)
		}
		return screen(0xffffff, [Element{kind: .view, id: 'owner', tooltip: 'Parent help', frame: rect(0, 0, 320, 300),
			children: [Element{kind: .text_area, id: 'edit', text: 'declared café ñ', on_event: area_gl_scrolled,
				frame: rect(0, 0, 240, if area_gl_phase > 0 { 290 } else { 60 })}]}])
	}

	fn test_text_area_range_callbacks_abort_captured_gl_text_and_repaint() {
		modes := os.args.filter(it.starts_with('--area-gl-mode='))
		if modes.len == 0 {
			for mode in 0 .. 6 {
				result := os.execute('${os.quoted_path(os.executable())} --area-gl-mode=${mode}')
				eprintln(result.output)
				assert result.exit_code == 0
				assert result.output.contains('area GL mode=${mode} passed')
			}
			return
		}
		area_gl_mode = modes[0].all_after('=').int()
		g_gg_app = &GgApp{}
		activate_custom_window_state(new_custom_window_state())
		// Real Mac GL host and GPU; the callback/event input is synthetic.
		run_window('TextArea callback ownership', 320, 300, area_gl_root)
		assert area_gl_verified
	}
}
