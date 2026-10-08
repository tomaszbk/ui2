// vtest vflags: -d ui2_custom_rendering -d ui2_embedder
// vfmt off
@[has_globals]
module ui2

$if macos && ui2_custom_rendering ? && ui2_embedder ? && !ui2_headless ? {
	import os
	import gg
	import sokol.gfx
	import sokol.sgl

	#include "@VMODROOT/tests/render_scheduler/draw_commands.h"
	fn C.ui2_test_command_count(context sgl.Context) int
	fn C.ui2_test_vertex_count(context sgl.Context) int
	fn C.ui2_test_shared_sampler() gfx.Sampler
	fn C.ui2_test_watch_drawable(window voidptr)
	fn C.ui2_test_drawable_release_count() int
	fn C.ui2_test_has_drawable(window voidptr) bool
	fn C.ui2_test_pump(data voidptr, pump fn (voidptr) i64) i64

	__global area_frame_mode int
	__global area_frame_phase int
	__global area_frame_scroll bool
	__global area_frame_events = []f64{}
	__global area_frame_window = CustomWindow{}
	__global area_frame_guard = CustomWindow{}
	__global area_frame_replacement = CustomWindow{}
	__global area_frame_caret Rect
	__global area_frame_gpu u32
	__global area_frame_queued int
	__global area_frame_offset f64
	const area_frame_local = 'local café ñ\n'.repeat(12)

	fn area_frame_guard_root() Element {
		return screen(0xffffff, [Element{kind: .text_area, id: 'edit', text: 'survivor café ñ', frame: rect(0, 0, 240, 80)}])
	}

	fn area_frame_scrolled(event ElementEvent) {
		if event.kind != .scroll || area_frame_phase != 1 { return }
		area_frame_phase = 2
		area_frame_events << event.value
		area_frame_offset = event.value
		app := g_gg_app
		state := g_active_custom_window_state
		assert event.id == if area_frame_scroll { 'pane' } else { 'edit' }
		assert event.value >= 0 && event.value < 100
		assert g_tooltip_owners == 1
		assert text('edit') == area_frame_local
		assert text_area_caret('edit') == 3 && text_area_selection_length('edit') == 2
		assert C.ui2_test_has_drawable(app.native_window)
		area_frame_queued = C.ui2_test_command_count(app.ctx.gl_context)
		assert area_frame_queued > 0 && C.ui2_test_vertex_count(app.ctx.gl_context) > 0
		area_frame_gpu = gfx.query_frame_stats().frame_index
		match area_frame_mode {
			1 {
				assert area_frame_guard.update(fn () {
					assert g_tooltip_owners == 0
					assert text('edit') == 'survivor local café ñ'
					assert text_area_caret('edit') == 6 && text_area_selection_length('edit') == 3
				})
			}
			2 { area_frame_window.close() }
			3 {
				area_frame_replacement = open_window('Replacement', 320, 300, area_frame_guard_root) or { panic(err) }
				area_frame_window.close()
			}
			4 { refresh() }
			5 { focus('alternate') }
			6 {
				// Internal context lifetime fixture, distinct from public window
				// update/open/close routes above. Free the captured text engine.
				mut captured := app.ctx
				g_gg_app.ctx = new_surface_draw_context(gg.Config{width: 320, height: 300}, g_draw_device_environment) or { panic(err) }
				captured.destroy()
				g_gg_app.scheduler.invalidate(.paint)
			}
			else {}
		}
		// Public window operations restore the caller, including its ownership
		// depth. Do not fabricate a persistent private-state switch as a bug.
		assert g_gg_app == app && g_active_custom_window_state == state
		assert g_tooltip_owners == 1
		area_frame_caret = app.text_caret
		eprintln('area callback kind=${area_frame_scroll} mode=${area_frame_mode} offset=${event.value} caret=${area_frame_caret} owners=${g_tooltip_owners} queued=${area_frame_queued}')
	}

	fn area_frame_root() Element {
		mut children := [Element{kind: .text_area, id: 'edit', text: 'declared café ñ', on_event: area_frame_scrolled,
			frame: rect(0, 0, 240, if area_frame_phase > 0 { 290 } else { 60 })}]
		if area_frame_scroll {
			children[0] = Element{...children[0], frame: rect(0, 0, 240, 60), on_event: ElementCallback(unsafe { nil })}
			children << Element{kind: .scroll, id: 'pane', on_event: area_frame_scrolled, frame: rect(0, 80, 240, 100),
				children: [Element{kind: .button, id: 'content', text: 'Content', frame: rect(0, if area_frame_phase > 0 { 130 } else { 500 }, 140, 30)}]}
		}
		children << Element{kind: .button, id: 'alternate', text: 'Alternate', frame: rect(245, 0, 70, 30)}
		return screen(0xffffff, [Element{kind: .view, id: 'owner', tooltip: 'Parent help', frame: rect(0, 0, 320, 300), children: children}])
	}

	fn test_paint_range_callbacks_keep_text_and_tooltip_continuations_owned() {
		modes := os.args.filter(it.starts_with('--area-frame-mode='))
		if modes.len == 0 {
			for kind in ['text', 'scroll'] {
				for mode in 0 .. 7 {
					result := os.execute('${os.quoted_path(os.executable())} --area-frame-mode=${mode} --area-frame-kind=${kind}')
					eprintln(result.output)
					assert result.exit_code == 0
					assert result.output.contains('area frame kind=${kind} mode=${mode} passed')
				}
			}
			return
		}
		area_frame_mode = modes[0].all_after('=').int()
		area_frame_scroll = os.args.contains('--area-frame-kind=scroll')
		g_gg_app = &GgApp{}
		activate_custom_window_state(new_custom_window_state())
		area_frame_guard = open_window('Surviving editor', 320, 300, area_frame_guard_root)!
		defer { area_frame_guard.close() }
		assert C.ui2_test_pump(area_frame_guard.app, embedder_pump) == -1
		assert area_frame_guard.update(fn () {
			set_text('edit', 'survivor local café ñ')
			focus('edit')
			text_area_set_selection('edit', 3, 3)
			embedder_text(g_gg_app, &C.ui2_embedder_text_event{kind: 2, text: 'ñ'.str, replacement_start: -1, selection_start: 1})
		})
		assert C.ui2_test_pump(area_frame_guard.app, embedder_pump) == -1
		guard_caret := area_frame_guard.app.text_caret
		guard_composition := area_frame_guard.app.composition
		guard_images := area_frame_guard.app.ctx.text_renderer.atlas_images()
		shared_sampler := C.ui2_test_shared_sampler()
		area_frame_window = open_window('Range callback ownership', 320, 300, area_frame_root)!
		defer { area_frame_window.close() }
		assert C.ui2_test_pump(area_frame_window.app, embedder_pump) == -1
		assert area_frame_window.update(fn () {
			set_text('edit', area_frame_local)
			focus('edit')
			text_area_set_selection('edit', 1, 2)
			embedder_text(g_gg_app, &C.ui2_embedder_text_event{kind: 2, text: 'ñ'.str, replacement_start: -1, selection_start: 1})
		})
		assert C.ui2_test_pump(area_frame_window.app, embedder_pump) == -1
		assert area_frame_window.update(fn () {
			scroll_to_offset(if area_frame_scroll { 'pane' } else { 'edit' }, 100)
			assert scroll_offset(if area_frame_scroll { 'pane' } else { 'edit' }) == 100
			area_frame_phase = 1
		})
		ctx := area_frame_window.app.ctx
		scheduler := area_frame_window.app.scheduler
		handle := area_frame_window.app.native_window
		composition := area_frame_window.app.composition
		draws := scheduler.stats().draws
		frames := ctx.inner.frame
		C.ui2_test_watch_drawable(handle)
		wake := C.ui2_test_pump(area_frame_window.app, embedder_pump)
		assert area_frame_phase == 2 && area_frame_events.len == 1
		assert !scheduler.stats().in_flight
		assert C.ui2_test_drawable_release_count() == 1 && !C.ui2_test_has_drawable(handle)
		eprintln('area return kind=${area_frame_scroll} mode=${area_frame_mode} caret=${area_frame_window.app.text_caret} owners=${area_frame_window.app.window_state.tooltip_owners}/${area_frame_guard.app.window_state.tooltip_owners} wake=${wake}')
		assert area_frame_guard.app.window_state.tooltip_owners == 0
		assert area_frame_window.app.window_state.tooltip_owners == 0
		assert area_frame_window.app.text_caret == area_frame_caret,
			'an invalidated TextArea must not publish caret geometry after its callback'
		assert area_frame_guard.app.text_caret == guard_caret
		assert area_frame_guard.app.composition == guard_composition
		// Even the normal callback schedules a build through fire_target_event.
		// Its canceled paint must stop here; the next unclamped frame is the
		// valid continuation control and must produce real text/caret output.
		assert scheduler.stats().draws == draws && ctx.inner.frame == frames
		assert gfx.query_frame_stats().frame_index == area_frame_gpu
		if area_frame_mode in [2, 3] {
			assert wake == -1 && scheduler.stats().closed && ctx.destroyed
			assert area_frame_window.app.ctx == unsafe { nil }
			assert !area_frame_window.dispatcher().post(fn () {})
		} else {
			assert wake == 0
			if area_frame_mode == 6 {
				assert ctx.destroyed && area_frame_window.app.ctx != ctx
			} else {
				assert C.ui2_test_command_count(ctx.gl_context) == 0
				assert C.ui2_test_vertex_count(ctx.gl_context) == 0
			}
			assert area_frame_window.app.composition == composition || area_frame_mode == 5
			assert C.ui2_test_pump(area_frame_window.app, embedder_pump) == -1
			assert scheduler.stats().draws == draws + 1
			if area_frame_mode != 5 { assert area_frame_window.app.text_caret.width > 0 }
		}
		if area_frame_mode !in [2, 3] {
			assert area_frame_window.update(fn () {
				assert g_tooltip_owners == 0
				assert focused_id() == if area_frame_mode == 5 { 'alternate' } else { 'edit' }
				assert text('edit') == area_frame_local
				assert text_area_caret('edit') == 3 && text_area_selection_length('edit') == 2
				assert scroll_offset(if area_frame_scroll { 'pane' } else { 'edit' }) == area_frame_offset
			})
		}
		if area_frame_mode == 3 {
			assert C.ui2_test_pump(area_frame_replacement.app, embedder_pump) == -1
			assert area_frame_replacement.app.window_state.tooltip_owners == 0
			area_frame_replacement.close()
		}
		assert gfx.is_valid() && gfx.query_sampler_state(shared_sampler) == .valid
		for image in guard_images {
			assert gfx.query_image_state(image.simg) == .valid
			assert gfx.query_sampler_state(image.ssmp) == .valid
		}
		assert area_frame_guard.update(fn () {
			assert g_tooltip_owners == 0
			assert text('edit') == 'survivor local café ñ'
			assert text_area_caret('edit') == 6 && text_area_selection_length('edit') == 3
		})
		assert C.ui2_test_pump(area_frame_guard.app, embedder_pump) == -1
		assert gfx.query_frame_stats().num_draw > 0
		kind := if area_frame_scroll { 'scroll' } else { 'text' }
		eprintln('area frame kind=${kind} mode=${area_frame_mode} passed owners=0/0 queued=${area_frame_queued} release=1')
	}
}
