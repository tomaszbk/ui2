// vtest vflags: -d ui2_custom_rendering -d ui2_embedder
// vfmt off
@[has_globals]
module ui2

import gg
import math
import os
import sokol.gfx
import sokol.sgl

$if macos && ui2_custom_rendering ? && ui2_embedder ? && !ui2_headless ? {
	#include "@VMODROOT/tests/render_scheduler/draw_commands.h"
	fn C.ui2_test_command_count(context sgl.Context) int
	fn C.ui2_test_vertex_count(context sgl.Context) int
	fn C.ui2_test_watch_drawable(window voidptr)
	fn C.ui2_test_drawable_release_count() int
	fn C.ui2_test_has_drawable(window voidptr) bool
	fn C.ui2_test_pump(data voidptr, pump fn (voidptr) i64) i64

	__global motion_followup_mode int
	__global motion_followup_progress f64
	__global motion_followup_built_progress f64
	__global motion_followup_events = []MotionEvent{}
	__global motion_followup_acted bool
	__global motion_followup_started bool
	__global motion_followup_now = f64(0)
	__global motion_followup_handle = &MotionHandle{}

	fn motion_followup_clock() f64 {
		return motion_followup_now
	}

	// The tile's timeline moves it 100 units right over 1000 s, or there and
	// back in a loop in mode 1. Only the timeline's events drive the model.
	fn motion_followup_motion() MotionConfig {
		timeline := if motion_followup_mode == 1 {
			motion_keyframes(1000, MotionKeyframe{ at: 0.5, style: MotionStyle{ translate_x: 100 } },
				MotionKeyframe{ at: 1, style: MotionStyle{ translate_x: 0 } }).looped()
		} else {
			MotionTimeline{ ...motion_keyframes(1000, MotionKeyframe{ at: 1, style: MotionStyle{ translate_x: 100 } }), hold: true }
		}
		return MotionConfig{
			enter: MotionStyle{}
			exit: MotionStyle{}
			transition: MotionTransition{ duration: 0 }
			timeline: timeline
			handle: motion_followup_handle
			clock: motion_followup_clock
			on_motion: motion_followup_event
		}
	}

	fn motion_followup_badge(value string) Element {
		return Element{kind: .label, id: 'badge', text: value, frame: rect(20, 100, 240, 30)}
	}

	fn motion_followup_build(mut _ Window) Element {
		motion_followup_built_progress = motion_followup_progress
		return screen(0xffffff, [
			if motion_followup_started {
				with_motion(view('tile', rect(20, 20, 30, 30), BoxStyle{bg: 0x3366cc}, []), motion_followup_motion())
			} else {
				view('tile', rect(20, 20, 30, 30), BoxStyle{bg: 0x3366cc}, [])
			},
			Element{kind: .label, id: 'progress', text: '${motion_followup_progress}', frame: rect(20, 60, 240, 30)},
			motion_followup_badge('declared'),
		])
	}

	fn motion_followup_event(event MotionEvent) {
		mut w := event.window
		if event.source != .timeline { return }
		motion_followup_events << event
		if event.kind != .progress { return }
		motion_followup_progress = event.progress
		if motion_followup_acted { return }
		motion_followup_acted = true
		assert !C.ui2_test_has_drawable(w.native_window), 'motion callbacks precede drawable acquisition'
		match motion_followup_mode {
			2 { w.refresh_element('badge', motion_followup_badge('newer')); w.request_refresh() }
			3 { w.ctx = new_surface_draw_context(gg.Config{width: 320, height: 180}, g_draw_device_environment) or { panic(err) } }
			4 { w.scheduler = new_frame_coordinator() }
			5 { w.quit() }
			6 { on_event(&gg.Event{typ: .suspended}, mut w) }
			7 { w.refresh_element('badge', motion_followup_badge('patched')) }
			8 { motion_followup_handle.cancel() }
			else {}
		}
	}

	// The fixture's clock moves the timeline far from boundaries, so geometry
	// has an independent linear oracle. elapsed is in milliseconds.
	fn motion_followup_sample(mut w Window, elapsed i64) {
		motion_followup_now = f64(elapsed) / 1000
		w.request_refresh()
	}

	fn motion_followup_draw(mut w Window) {
		ctx := w.ctx
		before := w.scheduler.stats()
		frames := ctx.inner.frame
		gpu_frame := gfx.query_frame_stats().frame_index
		C.ui2_test_watch_drawable(w.native_window)
		wake := C.ui2_test_pump(w, embedder_pump)
		after := w.scheduler.stats()
		eprintln('motion follow-up mode=${motion_followup_mode} draws=${before.draws}->${after.draws} frames=${frames}->${ctx.inner.frame} progress=${motion_followup_progress} pending=${after.pending_reasons} wake=${wake}')
		assert after.draws == before.draws + 1, 'ordinary motion events must submit the current progress frame'
		assert ctx.inner.frame == frames + 1 && gfx.query_frame_stats().num_draw > 0
		assert gfx.query_frame_stats().frame_index == gpu_frame + 1
		assert !after.in_flight && after.finished_generation >= before.generation
		assert after.pending && after.generation > after.finished_generation, 'callback model work belongs to the next frame'
		assert C.ui2_test_drawable_release_count() == 1 && !C.ui2_test_has_drawable(w.native_window)
		assert C.ui2_test_command_count(ctx.gl_context) == 0 && C.ui2_test_vertex_count(ctx.gl_context) == 0
		expected := if motion_followup_mode == 1 {
			if motion_followup_progress < 0.5 { 20 + 200 * motion_followup_progress } else { 220 - 200 * motion_followup_progress }
		} else { 20 + 100 * motion_followup_progress }
		node := w.navigation.node('tile') or { panic('missing painted tile') }
		assert math.abs(node.frame.x - expected) < 0.001
	}

	fn test_owned_motion_events_draw_progress_and_preserve_cancellation() {
		mode_arg := os.args.filter(it.starts_with('--motion-followup-mode='))
		if mode_arg.len == 0 {
			mut failures := []int{}
			for mode in 0 .. 9 {
				result := os.execute('${os.quoted_path(os.executable())} --motion-followup-mode=${mode}')
				eprintln(result.output)
				if result.exit_code != 0 || !result.output.contains('owned motion follow-up mode=${mode} passed') { failures << mode }
			}
			assert failures.len == 0, 'motion frame failures: ${failures}'
			return
		}
		motion_followup_mode = mode_arg[0].all_after('=').int()
		mut app := new_app()
		mut w := app.new_window(title: 'Motion callback frame ownership', width: 320, height: 180, build: motion_followup_build)!
		defer { w.quit() }
		assert C.ui2_test_pump(w, embedder_pump) == -1
		gfx.enable_frame_stats()
		motion_followup_now = 0
		motion_followup_started = true
		w.request_refresh()
		motion_followup_sample(mut w, 125_000)
		if motion_followup_mode == 2 {
			w.refresh_element('badge', motion_followup_badge('incoming'))
			w.request_refresh()
		}
		if motion_followup_mode in [0, 1, 7] {
			motion_followup_draw(mut w)
			assert motion_followup_built_progress == 0, 'current frame uses the pre-callback model snapshot'
			progress := motion_followup_progress
			if motion_followup_mode == 7 {
				badge := w.navigation.node('badge') or { panic('missing badge') }
				assert badge.el.text == 'declared' && w.layout_patches.len == 1
			}
			motion_followup_sample(mut w, 375_000)
			motion_followup_draw(mut w)
			assert motion_followup_built_progress == progress
			if motion_followup_mode == 7 {
				badge := w.navigation.node('badge') or { panic('missing badge') }
				assert badge.el.text == 'patched' && w.layout_patches.len == 0
			}
			if motion_followup_mode == 1 {
				for elapsed in [i64(1_125_000), 1_375_000] {
					motion_followup_sample(mut w, elapsed)
					motion_followup_draw(mut w)
				}
				assert motion_followup_events.filter(it.kind == .complete).len == 0
				motion_followup_handle.finish()
				w.request_refresh()
			} else {
				// The timeline began with the first frame after the start, at 125 s.
				motion_followup_sample(mut w, 1_125_001)
				motion_followup_draw(mut w)
			}
			assert motion_followup_events.filter(it.kind == .start).len == 1
			assert motion_followup_events.filter(it.kind == .complete).len == 1
			assert C.ui2_test_pump(w, embedder_pump) == -1
			assert !w.scheduler.stats().motion_active && !w.scheduler.stats().pending
			assert motion_followup_built_progress == motion_followup_progress
			idle_draws := w.scheduler.stats().draws
			assert C.ui2_test_pump(w, embedder_pump) == -1
			assert w.scheduler.stats().draws == idle_draws
		} else {
			mut ctx := w.ctx
			scheduler := w.scheduler
			draws := scheduler.stats().draws
			frames := ctx.inner.frame
			C.ui2_test_watch_drawable(w.native_window)
			C.ui2_test_pump(w, embedder_pump)
			assert motion_followup_acted && motion_followup_events.filter(it.kind == .progress).len == 1
			assert scheduler.stats().draws == draws && !scheduler.stats().in_flight
			assert ctx.inner.frame == frames && C.ui2_test_drawable_release_count() == 0
			assert !C.ui2_test_has_drawable(w.native_window)
			if motion_followup_mode == 2 {
				assert w.layout_patches.len == 2
				assert w.layout_patches[0].element.text == 'incoming'
				assert w.layout_patches[1].element.text == 'newer'
			}
			if motion_followup_mode == 5 {
				assert scheduler.stats().closed && ctx.destroyed && w.ctx == unsafe { nil }
			} else {
				assert C.ui2_test_command_count(ctx.gl_context) == 0
				if motion_followup_mode == 3 { ctx.destroy() }
				motion_followup_handle.cancel()
				if motion_followup_mode == 6 { on_event(&gg.Event{typ: .resumed}, mut w) }
				w.request_refresh()
				assert C.ui2_test_pump(w, embedder_pump) == -1
				assert w.scheduler.stats().draws == if motion_followup_mode == 4 { u64(1) } else { draws + 1 }
				if motion_followup_mode == 2 {
					badge := w.navigation.node('badge') or { panic('missing recovered badge') }
					assert badge.el.text == 'newer' && w.layout_patches.len == 0
				}
			}
		}
		eprintln('owned motion follow-up mode=${motion_followup_mode} passed events=${motion_followup_events.len} draws=${w.scheduler.stats().draws}')
	}
}
