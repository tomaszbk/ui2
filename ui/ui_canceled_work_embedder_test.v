// vtest vflags: -d ui2_custom_rendering -d ui2_embedder
// vfmt off
@[has_globals]
module ui2

$if macos && ui2_custom_rendering ? && ui2_embedder ? && !ui2_headless ? {
	import os
	import sokol.gfx
	import sokol.sgl

	#include "@VMODROOT/tests/render_scheduler/draw_commands.h"
	fn C.ui2_test_pump(data voidptr, pump fn (voidptr) i64) i64
	fn C.ui2_test_command_count(context sgl.Context) int
	fn C.ui2_test_vertex_count(context sgl.Context) int
	fn C.ui2_test_watch_drawable(window voidptr)
	fn C.ui2_test_drawable_release_count() int
	fn C.ui2_test_has_drawable(window voidptr) bool

	__global canceled_work_other = &Window(unsafe { nil })
	__global canceled_work_builds int
	__global canceled_work_tasks int
	__global canceled_work_cancel bool
	__global canceled_work_mode int

	fn canceled_work_badge(value string) Element {
		return Element{kind: .label, id: 'badge', text: value, frame: rect(10, 10, 220, 30)}
	}
	// The builder runs a business callback that also asks another window to
	// refresh, then cancels its own frame: mode 0 closes the window, mode 1
	// replaces its scheduler and mode 2 asks for another build.
	fn canceled_work_build(mut w Window) Element {
		canceled_work_builds++
		root := screen(0xffffff, [canceled_work_badge('declaration ${canceled_work_builds}')])
		if canceled_work_cancel {
			canceled_work_cancel = false
			canceled_work_tasks++
			mut other := canceled_work_other
			other.request_refresh()
			if canceled_work_mode == 0 { w.quit() }
			if canceled_work_mode == 1 { w.scheduler = new_frame_coordinator() }
			if canceled_work_mode == 2 { w.request_refresh() }
		}
		return root
	}
	fn test_owned_canceled_build_recovers_without_replaying_callbacks() {
		args := os.args.filter(it.starts_with('--canceled-work-mode='))
		if args.len == 0 {
			mut failures := []int{}
			for mode in 0 .. 3 {
				result := os.execute('${os.quoted_path(os.executable())} --canceled-work-mode=${mode}')
				eprintln(result.output)
				if result.exit_code != 0 || !result.output.contains('canceled work mode=${mode} passed') { failures << mode }
			}
			assert failures.len == 0, 'canceled presentation failures: ${failures}'
			return
		}
		canceled_work_mode = args[0].all_after('=').int()
		mut app := new_app()
		canceled_work_other = app.new_window(title: 'Other window', width: 320, height: 180, build: fn (mut _ Window) Element {
			return screen(0xffffff, [Element{kind: .label, id: 'other', text: 'other owner ñ', frame: rect(0, 0, 220, 30)}])
		})!
		mut other := canceled_work_other
		defer { other.quit() }
		assert C.ui2_test_pump(other, embedder_pump) == -1
		other_draws := other.scheduler.stats().draws
		canceled_work_cancel = true
		mut w := app.new_window(title: 'Canceled declaration recovery', width: 320, height: 180, build: canceled_work_build)!
		defer { w.quit() }
		ctx := w.ctx
		scheduler := w.scheduler
		draws := scheduler.stats().draws
		frames := ctx.inner.frame
		gpu_frame := gfx.query_frame_stats().frame_index
		C.ui2_test_watch_drawable(w.native_window)
		wake := C.ui2_test_pump(w, embedder_pump)
		eprintln('canceled work before recovery mode=${canceled_work_mode} wake=${wake} builds=${canceled_work_builds} tasks=${canceled_work_tasks} draws=${scheduler.stats().draws} pending=${scheduler.stats().pending_reasons}')
		assert canceled_work_tasks == 1
		assert scheduler.stats().draws == draws && ctx.inner.frame == frames
		assert gfx.query_frame_stats().frame_index == gpu_frame
		assert !scheduler.stats().in_flight
		assert C.ui2_test_drawable_release_count() == 0 && !C.ui2_test_has_drawable(w.native_window)
		if !ctx.destroyed {
			assert C.ui2_test_command_count(ctx.gl_context) == 0 && C.ui2_test_vertex_count(ctx.gl_context) == 0
		}
		assert other.scheduler.stats().draws == other_draws
		assert other.scheduler.stats().pending
		if canceled_work_mode == 0 {
			assert wake == -1 && scheduler.stats().closed && !w.has_root
			assert ctx.destroyed && w.ctx == unsafe { nil }
		} else if canceled_work_mode == 1 {
			assert w.scheduler != scheduler && !scheduler.stats().pending
			assert !w.has_root, 'old work must not be adopted into a replacement scheduler'
			assert C.ui2_test_pump(w, embedder_pump) == -1
			scheduler.close()
		} else {
			assert wake == 0 && scheduler.stats().pending, 'live canceled work must wake again without a later application invalidation'
			builds := canceled_work_builds
			assert C.ui2_test_pump(w, embedder_pump) == -1
			assert canceled_work_builds == builds + 1
			assert canceled_work_tasks == 1, 'presentation retry must not replay the nested business callback'
			assert scheduler.stats().draws == draws + 1 && ctx.inner.frame == frames + 1
			assert C.ui2_test_drawable_release_count() == 1
			badge := w.navigation.node('badge') or { panic('lost canceled declaration') }
			assert badge.el.text == 'declaration ${canceled_work_builds}'
			assert w.layout_patches.len == 0
			assert !scheduler.stats().pending && !scheduler.stats().in_flight
			assert C.ui2_test_pump(w, embedder_pump) == -1
			assert scheduler.stats().draws == draws + 1 && canceled_work_tasks == 1
		}
		assert C.ui2_test_pump(other, embedder_pump) == -1
		assert other.scheduler.stats().draws == other_draws + 1
		assert !other.scheduler.stats().pending
		eprintln('canceled work mode=${canceled_work_mode} passed builds=${canceled_work_builds} tasks=${canceled_work_tasks} draws=${w.scheduler.stats().draws} other_draws=${other_draws + 1}')
	}
}
