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

	__global animation_followup_mode int
	__global animation_followup_progress f64
	__global animation_followup_built_progress f64
	__global animation_followup_events = []AnimationEvent{}
	__global animation_followup_acted bool

	fn animation_followup_badge(value string) Element {
		return Element{kind: .label, id: 'badge', text: value, frame: rect(20, 100, 240, 30)}
	}

	fn animation_followup_build() Element {
		animation_followup_built_progress = animation_followup_progress
		return screen(0xffffff, [
			view('tile', rect(20, 20, 30, 30), BoxStyle{bg: 0x3366cc}, []),
			Element{kind: .label, id: 'progress', text: '${animation_followup_progress}', frame: rect(20, 60, 240, 30)},
			animation_followup_badge('declared'),
		])
	}

	fn animation_followup_event(event AnimationEvent) {
		animation_followup_events << event
		if event.kind != .progress { return }
		animation_followup_progress = event.progress
		if animation_followup_acted { return }
		animation_followup_acted = true
		assert !C.ui2_test_has_drawable(g_gg_app.native_window), 'animation callbacks precede drawable acquisition'
		match animation_followup_mode {
			2 { refresh_element('badge', animation_followup_badge('newer')); refresh() }
			3 { g_gg_app.ctx = new_surface_draw_context(gg.Config{width: 320, height: 180}, g_draw_device_environment) or { panic(err) } }
			4 { g_gg_app.scheduler = new_frame_coordinator() }
			5 {
				temporary := new_custom_window_state()
				previous := activate_custom_window_state(temporary)
				activate_custom_window_state(previous)
				discard_custom_window_state(temporary)
			}
			6 { quit() }
			7 { on_event(&gg.Event{typ: .suspended}, g_gg_app) }
			8 { refresh_element('badge', animation_followup_badge('patched')) }
			9 { clear_animation('tile') }
			else {}
		}
	}

	// Keep the production monotonic clock and driver. Move only the fixture's
	// timeline far from boundaries, so geometry has an independent linear oracle.
	fn animation_followup_sample(window CustomWindow, elapsed i64) {
		assert window.update(fn [elapsed] () {
			mut runtime := g_animation_runtime
			runtime.mutex.lock()
			run := runtime.runs['tile'] or { panic('missing animation') }
			runtime.runs['tile'] = AnimationRun{...run, started_at: animation_now_ms() - elapsed}
			runtime.mutex.unlock()
		})
	}

	fn animation_followup_draw(window CustomWindow) {
		ctx := window.app.ctx
		before := window.app.scheduler.stats()
		frames := ctx.inner.frame
		gpu_frame := gfx.query_frame_stats().frame_index
		C.ui2_test_watch_drawable(window.app.native_window)
		wake := C.ui2_test_pump(window.app, embedder_pump)
		after := window.app.scheduler.stats()
		eprintln('animation follow-up mode=${animation_followup_mode} draws=${before.draws}->${after.draws} frames=${frames}->${ctx.inner.frame} progress=${animation_followup_progress} pending=${after.pending_reasons} wake=${wake}')
		assert after.draws == before.draws + 1, 'ordinary animation events must submit the current progress frame'
		assert ctx.inner.frame == frames + 1 && gfx.query_frame_stats().num_draw > 0
		assert gfx.query_frame_stats().frame_index == gpu_frame + 1
		assert !after.in_flight && after.finished_generation >= before.generation
		assert after.pending && after.generation > after.finished_generation, 'callback model work belongs to the next frame'
		assert C.ui2_test_drawable_release_count() == 1 && !C.ui2_test_has_drawable(window.app.native_window)
		assert C.ui2_test_command_count(ctx.gl_context) == 0 && C.ui2_test_vertex_count(ctx.gl_context) == 0
		expected := if animation_followup_mode == 1 {
			if animation_followup_progress < 0.5 { 20 + 200 * animation_followup_progress } else { 220 - 200 * animation_followup_progress }
		} else { 20 + 100 * animation_followup_progress }
		node := window.app.window_state.navigation.node('tile') or { panic('missing painted tile') }
		assert math.abs(node.frame.x - expected) < 0.001
	}

	fn test_owned_animation_events_draw_progress_and_preserve_cancellation() {
		mode_arg := os.args.filter(it.starts_with('--animation-followup-mode='))
		if mode_arg.len == 0 {
			mut failures := []int{}
			for mode in 0 .. 10 {
				result := os.execute('${os.quoted_path(os.executable())} --animation-followup-mode=${mode}')
				eprintln(result.output)
				if result.exit_code != 0 || !result.output.contains('owned animation follow-up mode=${mode} passed') { failures << mode }
			}
			assert failures.len == 0, 'animation frame failures: ${failures}'
			return
		}
		animation_followup_mode = mode_arg[0].all_after('=').int()
		g_gg_app = &GgApp{}
		activate_custom_window_state(new_custom_window_state())
		window := open_window('Animation callback frame ownership', 320, 180, animation_followup_build)!
		defer { window.close() }
		assert C.ui2_test_pump(window.app, embedder_pump) == -1
		gfx.enable_frame_stats()
		assert window.update(fn () {
			definition := if animation_followup_mode == 1 {
				sequence(animation(duration: 500, x: 120), animation(duration: 500, x: 20)).repeating().with_event_handler(animation_followup_event)
			} else { animation(duration: 1000, x: 120, on_event: animation_followup_event) }
			definition.start('tile')
		})
		animation_followup_sample(window, 125_000)
		if animation_followup_mode == 2 {
			assert window.update(fn () { refresh_element('badge', animation_followup_badge('incoming')) })
		}
		if animation_followup_mode in [0, 1, 8] {
			animation_followup_draw(window)
			assert animation_followup_built_progress == 0, 'current frame uses the pre-callback model snapshot'
			progress := animation_followup_progress
			if animation_followup_mode == 8 {
				badge := window.app.window_state.navigation.node('badge') or { panic('missing badge') }
				assert badge.el.text == 'declared' && window.app.layout_patches.len == 1
			}
			animation_followup_sample(window, 375_000)
			animation_followup_draw(window)
			assert animation_followup_built_progress == progress
			if animation_followup_mode == 8 {
				badge := window.app.window_state.navigation.node('badge') or { panic('missing badge') }
				assert badge.el.text == 'patched' && window.app.layout_patches.len == 0
			}
			if animation_followup_mode == 1 {
				for elapsed in [i64(1_125_000), 1_375_000] {
					animation_followup_sample(window, elapsed)
					animation_followup_draw(window)
				}
				assert animation_followup_events.filter(it.kind == .complete).len == 0
				assert window.update(fn () { stop_animation('tile') })
			} else {
				animation_followup_sample(window, 1_000_001)
				animation_followup_draw(window)
			}
			assert animation_followup_events.filter(it.kind == .start).len == 1
			assert animation_followup_events.filter(it.kind == .complete).len == 1
			assert C.ui2_test_pump(window.app, embedder_pump) == -1
			assert !window.app.scheduler.stats().animation_active && !window.app.scheduler.stats().pending
			assert animation_followup_built_progress == animation_followup_progress
			idle_draws := window.app.scheduler.stats().draws
			assert C.ui2_test_pump(window.app, embedder_pump) == -1
			assert window.app.scheduler.stats().draws == idle_draws
		} else {
			mut ctx := window.app.ctx
			scheduler := window.app.scheduler
			draws := scheduler.stats().draws
			frames := ctx.inner.frame
			C.ui2_test_watch_drawable(window.app.native_window)
			C.ui2_test_pump(window.app, embedder_pump)
			assert animation_followup_acted && animation_followup_events.filter(it.kind == .progress).len == 1
			assert scheduler.stats().draws == draws && !scheduler.stats().in_flight
			assert ctx.inner.frame == frames && C.ui2_test_drawable_release_count() == 0
			assert !C.ui2_test_has_drawable(window.app.native_window)
			if animation_followup_mode == 2 {
				assert window.app.layout_patches.len == 2
				assert window.app.layout_patches[0].element.text == 'incoming'
				assert window.app.layout_patches[1].element.text == 'newer'
			}
			if animation_followup_mode == 6 {
				assert scheduler.stats().closed && ctx.destroyed && window.app.ctx == unsafe { nil }
			} else {
				assert C.ui2_test_command_count(ctx.gl_context) == 0
				if animation_followup_mode == 3 { ctx.destroy() }
				assert window.update(fn () {
					clear_animation('tile')
					if animation_followup_mode == 7 { on_event(&gg.Event{typ: .resumed}, g_gg_app) }
				})
				assert C.ui2_test_pump(window.app, embedder_pump) == -1
				assert window.app.scheduler.stats().draws == if animation_followup_mode == 4 { u64(1) } else { draws + 1 }
				if animation_followup_mode == 2 {
					badge := window.app.window_state.navigation.node('badge') or { panic('missing recovered badge') }
					assert badge.el.text == 'newer' && window.app.layout_patches.len == 0
				}
			}
		}
		eprintln('owned animation follow-up mode=${animation_followup_mode} passed events=${animation_followup_events.len} draws=${window.app.scheduler.stats().draws}')
	}
}
