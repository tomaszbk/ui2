// vtest vflags: -d ui2_custom_rendering -d ui2_embedder
// vfmt off
@[has_globals]
module ui2

$if macos && ui2_custom_rendering ? && ui2_embedder ? && !ui2_headless ? {
	import gg
	import os
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

	__global frame_cancel_mode int
	__global frame_cancel_phase int
	__global frame_cancel_events = []f64{}
	__global frame_cancel_replacement = CustomWindow{}
	__global frame_cancel_gpu_frame u32
	__global frame_cancel_queued int

	fn frame_cancel_guard_root() Element {
		return screen(0xffffff, [Element{kind: .label, id: 'survivor', text: 'Shared context café ñ', frame: rect(0, 0, 220, 40)}])
	}

	fn frame_cancel_scrolled(event ElementEvent) {
		if event.kind != .scroll { return }
		frame_cancel_events << event.value
		if frame_cancel_phase != 1 { return }
		eprintln('owned cancel notification mode=${frame_cancel_mode} value=${event.value} focused=${focused_id()} drawable=${C.ui2_test_has_drawable(g_gg_app.native_window)} queued=${C.ui2_test_command_count(g_gg_app.ctx.gl_context)}')
		assert event.value == 196
		assert C.ui2_test_has_drawable(g_gg_app.native_window)
		frame_cancel_queued = C.ui2_test_command_count(g_gg_app.ctx.gl_context)
		assert frame_cancel_queued > 0 && C.ui2_test_vertex_count(g_gg_app.ctx.gl_context) > 0
		frame_cancel_gpu_frame = gfx.query_frame_stats().frame_index
		frame_cancel_phase = 2
		match frame_cancel_mode {
			0 { refresh() }
			1 {
				temporary := new_custom_window_state()
				previous := activate_custom_window_state(temporary)
				activate_custom_window_state(previous)
				discard_custom_window_state(temporary)
				g_gg_app.scheduler.invalidate(.paint)
			}
			2 {
				frame_cancel_replacement = open_window('Replacement after canceled Metal frame', 320, 240, frame_cancel_guard_root) or { panic(err) }
				quit()
			}
			3 { quit() }
			4 {
				g_gg_app.ctx = new_surface_draw_context(gg.Config{width: 320, height: 240}, g_draw_device_environment) or { panic(err) }
				g_gg_app.scheduler.invalidate(.paint)
			}
			5 { set_visual_transform('pane', VisualTransform{rotation: 17}) or { panic(err) } }
			else { panic('unknown cancellation mode') }
		}
	}

	fn frame_cancel_root() Element {
		return screen(0xffffff, [
			Element{kind: .label, id: 'queued', text: 'Queued old surface text café ñ', frame: rect(0, 0, 250, 30)},
			Element{kind: .text_area, id: 'edit', text: 'café ñ', frame: rect(0, 35, 220, 40)},
			Element{kind: .scroll, id: 'pane', frame: rect(0, 100, 160, 100), on_event: frame_cancel_scrolled,
				children: [Element{kind: .button, id: 'restore', text: 'Restore', frame: rect(0, if frame_cancel_phase > 0 { 250 } else { 500 }, 140, 30)}]},
		])
	}

	fn test_owned_paint_callback_cancellation_keeps_frame_and_window_lifetimes() {
		mode_arg := os.args.filter(it.starts_with('--frame-cancel-mode='))
		if mode_arg.len == 0 {
			for mode in 0 .. 6 {
				result := os.execute('${os.quoted_path(os.executable())} --frame-cancel-mode=${mode}')
				eprintln(result.output)
				assert result.exit_code == 0
				assert result.output.contains('owned frame cancellation mode=${mode} passed')
			}
			return
		}
		frame_cancel_mode = mode_arg[0].all_after('=').int()
		g_gg_app = &GgApp{}
		activate_custom_window_state(new_custom_window_state())
		guard := open_window('Surviving Metal window', 320, 240, frame_cancel_guard_root)!
		defer { guard.close() }
		assert C.ui2_test_pump(guard.app, embedder_pump) == -1
		guard_images := guard.app.ctx.text_renderer.atlas_images()
		shared_sampler := C.ui2_test_shared_sampler()
		window := open_window('Canceled Metal paint callback', 320, 240, frame_cancel_root)!
		defer { window.close() }
		assert C.ui2_test_pump(window.app, embedder_pump) == -1
		mut ctx := window.app.ctx
		handle := window.app.native_window
		scheduler := window.app.scheduler
		assert window.update(fn () {
			focus('restore')
			assert scroll_offset('pane') == 430
			assert frame_cancel_events == [f64(430)]
			focus('edit')
			text_area_set_selection('edit', 1, 2)
			assert text_area_caret('edit') == 3 && text_area_selection_length('edit') == 2
			embedder_text(g_gg_app, &C.ui2_embedder_text_event{kind: 2, text: 'ñ'.str, replacement_start: -1, selection_start: 1})
			assert g_gg_app.composition.field_id == 'edit'
			frame_cancel_events.clear()
			frame_cancel_phase = 1
		})
		composition := window.app.composition
		presented := window.app.visual_geometries.clone()
		draws := scheduler.stats().draws
		frames := ctx.inner.frame
		C.ui2_test_watch_drawable(handle)
		wake := C.ui2_test_pump(window.app, embedder_pump)
		assert frame_cancel_phase == 2 && frame_cancel_events == [f64(196)]
		assert frame_cancel_queued > 0
		assert !scheduler.stats().in_flight
		assert scheduler.stats().draws == draws
		assert ctx.inner.frame == frames
		assert window.app.visual_geometries == presented
		assert gfx.query_frame_stats().frame_index == frame_cancel_gpu_frame
		assert C.ui2_test_drawable_release_count() == 1
		assert !C.ui2_test_has_drawable(handle)
		assert gfx.is_valid() && gfx.query_sampler_state(shared_sampler) == .valid
		for image in guard_images {
			assert gfx.query_image_state(image.simg) == .valid
			assert gfx.query_sampler_state(image.ssmp) == .valid
		}
		if frame_cancel_mode in [2, 3] {
			assert wake == -1 && scheduler.stats().closed
			assert ctx.destroyed && window.app.ctx == unsafe { nil }
			assert C.ui2_embedder_native_window(handle) == unsafe { nil }
			assert !window.dispatcher().post(fn () {})
			if frame_cancel_mode == 2 {
				assert C.ui2_test_pump(frame_cancel_replacement.app, embedder_pump) == -1
				assert frame_cancel_replacement.app.scheduler.stats().draws == 1
				frame_cancel_replacement.close()
			}
		} else {
			assert wake == 0 && scheduler.stats().pending
			assert C.ui2_test_command_count(ctx.gl_context) == 0
			assert C.ui2_test_vertex_count(ctx.gl_context) == 0
			assert window.app.composition == composition
			if frame_cancel_mode == 4 { ctx.destroy() }
			assert C.ui2_test_pump(window.app, embedder_pump) == -1
			assert scheduler.stats().draws == draws + 1
			assert !scheduler.stats().pending && !scheduler.stats().in_flight
			assert window.app.composition == composition
			assert window.update(fn () {
				assert focused_id() == 'edit' && scroll_offset('pane') == 196
				assert text('edit') == 'café ñ'
				assert text_area_caret('edit') == 3 && text_area_selection_length('edit') == 2
				assert g_gg_app.text_caret.width > 0
			})
			assert C.ui2_test_pump(window.app, embedder_pump) == -1
		}
		assert guard.update(fn () { refresh() })
		assert C.ui2_test_pump(guard.app, embedder_pump) == -1
		assert guard.app.scheduler.stats().draws == 2
		assert gfx.query_frame_stats().num_draw > 0
		eprintln('owned frame cancellation mode=${frame_cancel_mode} passed queues=${frame_cancel_queued} release=1 survivor_draws=2')
	}
}
