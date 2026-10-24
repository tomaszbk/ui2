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
	__global frame_cancel_replacement = &Window(unsafe { nil })
	__global frame_cancel_gpu_frame u32
	__global frame_cancel_queued int

	fn frame_cancel_guard_root(mut _ Window) Element {
		return screen(0xffffff, [Element{kind: .label, id: 'survivor', text: 'Shared context café ñ', frame: rect(0, 0, 220, 40)}])
	}

	fn frame_cancel_scrolled(event ElementEvent) {
		mut w := event.window
		if event.kind != .scroll { return }
		frame_cancel_events << event.value
		if frame_cancel_phase != 1 { return }
		eprintln('owned cancel notification mode=${frame_cancel_mode} value=${event.value} focused=${w.focused_id()} drawable=${C.ui2_test_has_drawable(w.native_window)} queued=${C.ui2_test_command_count(w.ctx.gl_context)}')
		assert event.value == 196
		assert C.ui2_test_has_drawable(w.native_window)
		frame_cancel_queued = C.ui2_test_command_count(w.ctx.gl_context)
		assert frame_cancel_queued > 0 && C.ui2_test_vertex_count(w.ctx.gl_context) > 0
		frame_cancel_gpu_frame = gfx.query_frame_stats().frame_index
		frame_cancel_phase = 2
		match frame_cancel_mode {
			0 { w.request_refresh() }
			1 {
				mut app := w.app
				frame_cancel_replacement = app.new_window(title: 'Replacement after canceled Metal frame', width: 320, height: 240, build: frame_cancel_guard_root) or { panic(err) }
				w.quit()
			}
			2 { w.quit() }
			3 {
				w.ctx = new_surface_draw_context(gg.Config{width: 320, height: 240}, g_draw_device_environment) or { panic(err) }
				w.scheduler.invalidate(.paint)
			}
			4 { w.set_visual_transform('pane', VisualTransform{rotation: 17}) or { panic(err) } }
			else { panic('unknown cancellation mode') }
		}
	}

	fn frame_cancel_root(mut _ Window) Element {
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
			for mode in 0 .. 5 {
				result := os.execute('${os.quoted_path(os.executable())} --frame-cancel-mode=${mode}')
				eprintln(result.output)
				assert result.exit_code == 0
				assert result.output.contains('owned frame cancellation mode=${mode} passed')
			}
			return
		}
		frame_cancel_mode = mode_arg[0].all_after('=').int()
		mut app := new_app()
		mut guard := app.new_window(title: 'Surviving Metal window', width: 320, height: 240, build: frame_cancel_guard_root)!
		defer { guard.quit() }
		assert C.ui2_test_pump(guard, embedder_pump) == -1
		guard_images := guard.ctx.text_renderer.atlas_images()
		shared_sampler := C.ui2_test_shared_sampler()
		mut w := app.new_window(title: 'Canceled Metal paint callback', width: 320, height: 240, build: frame_cancel_root)!
		defer { w.quit() }
		assert C.ui2_test_pump(w, embedder_pump) == -1
		mut ctx := w.ctx
		handle := w.native_window
		scheduler := w.scheduler
		w.focus('restore')
		assert w.scroll_offset('pane') == 430
		assert frame_cancel_events == [f64(430)]
		w.focus('edit')
		w.text_area_set_selection('edit', 1, 2)
		assert w.text_area_caret('edit') == 3 && w.text_area_selection_length('edit') == 2
		embedder_text(w, &C.ui2_embedder_text_event{kind: 2, text: 'ñ'.str, replacement_start: -1, selection_start: 1})
		assert w.composition.field_id == 'edit'
		frame_cancel_events.clear()
		frame_cancel_phase = 1
		w.request_refresh()
		composition := w.composition
		presented := w.visual_geometries.clone()
		draws := scheduler.stats().draws
		frames := ctx.inner.frame
		C.ui2_test_watch_drawable(handle)
		wake := C.ui2_test_pump(w, embedder_pump)
		assert frame_cancel_phase == 2 && frame_cancel_events == [f64(196)]
		assert frame_cancel_queued > 0
		assert !scheduler.stats().in_flight
		assert scheduler.stats().draws == draws
		assert ctx.inner.frame == frames
		assert w.visual_geometries == presented
		assert gfx.query_frame_stats().frame_index == frame_cancel_gpu_frame
		assert C.ui2_test_drawable_release_count() == 1
		assert !C.ui2_test_has_drawable(handle)
		assert gfx.is_valid() && gfx.query_sampler_state(shared_sampler) == .valid
		for image in guard_images {
			assert gfx.query_image_state(image.simg) == .valid
			assert gfx.query_sampler_state(image.ssmp) == .valid
		}
		if frame_cancel_mode in [1, 2] {
			assert wake == -1 && scheduler.stats().closed
			assert ctx.destroyed && w.ctx == unsafe { nil }
			assert C.ui2_embedder_native_window(handle) == unsafe { nil }
			assert !w.dispatcher().post(fn () {})
			if frame_cancel_mode == 1 {
				mut replacement := frame_cancel_replacement
				assert C.ui2_test_pump(replacement, embedder_pump) == -1
				assert replacement.scheduler.stats().draws == 1
				replacement.quit()
			}
		} else {
			assert wake == 0 && scheduler.stats().pending
			assert C.ui2_test_command_count(ctx.gl_context) == 0
			assert C.ui2_test_vertex_count(ctx.gl_context) == 0
			assert w.composition == composition
			if frame_cancel_mode == 3 { ctx.destroy() }
			assert C.ui2_test_pump(w, embedder_pump) == -1
			assert scheduler.stats().draws == draws + 1
			assert !scheduler.stats().pending && !scheduler.stats().in_flight
			assert w.composition == composition
			assert w.focused_id() == 'edit' && w.scroll_offset('pane') == 196
			assert w.text('edit') == 'café ñ'
			assert w.text_area_caret('edit') == 3 && w.text_area_selection_length('edit') == 2
			assert w.text_caret.width > 0
			w.request_refresh()
			assert C.ui2_test_pump(w, embedder_pump) == -1
		}
		guard.request_refresh()
		assert C.ui2_test_pump(guard, embedder_pump) == -1
		assert guard.scheduler.stats().draws == 2
		assert gfx.query_frame_stats().num_draw > 0
		eprintln('owned frame cancellation mode=${frame_cancel_mode} passed queues=${frame_cancel_queued} release=1 survivor_draws=2')
	}
}
