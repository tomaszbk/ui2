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

	__global canceled_work_other = CustomWindow{}
	__global canceled_work_builds int
	__global canceled_work_tasks int
	__global canceled_work_switch bool
	__global canceled_work_mode int

	fn canceled_work_badge(value string) Element {
		return Element{kind: .label, id: 'badge', text: value, frame: rect(10, 10, 220, 30)}
	}
	fn canceled_work_build() Element {
		canceled_work_builds++
		root := screen(0xffffff, [canceled_work_badge('declaration ${canceled_work_builds}')])
		if canceled_work_switch {
			if canceled_work_mode != 2 { canceled_work_switch = false }
			assert canceled_work_other.update(fn () { canceled_work_tasks++ })
			if canceled_work_mode == 3 { refresh_element('badge', canceled_work_badge('newer')) }
			if canceled_work_mode == 4 { quit() }
			if canceled_work_mode == 5 { g_gg_app.scheduler = new_frame_coordinator() }
			if canceled_work_mode == 6 { refresh() }
		}
		return root
	}
	fn test_owned_canceled_build_recovers_without_replaying_callbacks() {
		args := os.args.filter(it.starts_with('--canceled-work-mode='))
		if args.len == 0 {
			mut failures := []int{}
			for mode in 0 .. 7 {
				result := os.execute('${os.quoted_path(os.executable())} --canceled-work-mode=${mode}')
				eprintln(result.output)
				if result.exit_code != 0 || !result.output.contains('canceled work mode=${mode} passed') { failures << mode }
			}
			assert failures.len == 0, 'canceled presentation failures: ${failures}'
			return
		}
		canceled_work_mode = args[0].all_after('=').int()
		g_gg_app = &GgApp{}
		activate_custom_window_state(new_custom_window_state())
		canceled_work_other = open_window('Nested update owner', 320, 180, fn () Element {
			return screen(0xffffff, [Element{kind: .label, id: 'other', text: 'other owner ñ', frame: rect(0, 0, 220, 30)}])
		})!
		defer { canceled_work_other.close() }
		assert C.ui2_test_pump(canceled_work_other.app, embedder_pump) == -1
		other_draws := canceled_work_other.app.scheduler.stats().draws
		canceled_work_switch = canceled_work_mode != 1 && canceled_work_mode != 3
		window := open_window('Canceled declaration recovery', 320, 180, canceled_work_build)!
		defer { window.close() }
		if canceled_work_mode in [1, 3] {
			assert C.ui2_test_pump(window.app, embedder_pump) == -1
			assert window.update(fn () {
				canceled_work_switch = true
				if canceled_work_mode == 3 { refresh_element('badge', canceled_work_badge('incoming')) }
			})
		}
		ctx := window.app.ctx
		scheduler := window.app.scheduler
		draws := scheduler.stats().draws
		frames := ctx.inner.frame
		gpu_frame := gfx.query_frame_stats().frame_index
		C.ui2_test_watch_drawable(window.app.native_window)
		wake := C.ui2_test_pump(window.app, embedder_pump)
		eprintln('canceled work before recovery mode=${canceled_work_mode} wake=${wake} builds=${canceled_work_builds} tasks=${canceled_work_tasks} draws=${scheduler.stats().draws} pending=${scheduler.stats().pending_reasons}')
		assert canceled_work_tasks == 1
		assert scheduler.stats().draws == draws && ctx.inner.frame == frames
		assert gfx.query_frame_stats().frame_index == gpu_frame
		assert !scheduler.stats().in_flight
		assert C.ui2_test_drawable_release_count() == 0 && !C.ui2_test_has_drawable(window.app.native_window)
		if !ctx.destroyed {
			assert C.ui2_test_command_count(ctx.gl_context) == 0 && C.ui2_test_vertex_count(ctx.gl_context) == 0
		}
		assert canceled_work_other.app.scheduler.stats().draws == other_draws
		assert canceled_work_other.app.scheduler.stats().pending
		if canceled_work_mode == 4 {
			assert wake == -1 && scheduler.stats().closed && !window.app.has_root
			assert ctx.destroyed && window.app.ctx == unsafe { nil }
		} else if canceled_work_mode == 5 {
			assert window.app.scheduler != scheduler && !scheduler.stats().pending
			assert !window.app.has_root, 'old work must not be adopted into a replacement scheduler'
			assert C.ui2_test_pump(window.app, embedder_pump) == -1
			scheduler.close()
		} else {
			assert wake == 0 && scheduler.stats().pending, 'live canceled work must wake again without a later application invalidation'
			if canceled_work_mode == 3 {
				assert window.app.layout_patches.len == 2
				assert window.app.layout_patches[0].element.text == 'incoming'
				assert window.app.layout_patches[1].element.text == 'newer'
			}
			builds := canceled_work_builds
			assert C.ui2_test_pump(window.app, embedder_pump) == -1
			assert canceled_work_builds == builds + if canceled_work_mode == 6 { 1 } else { 0 }
			assert canceled_work_tasks == 1, 'presentation retry must not replay the nested business callback'
			assert scheduler.stats().draws == draws + 1 && ctx.inner.frame == frames + 1
			assert C.ui2_test_drawable_release_count() == 1
			badge := window.app.window_state.navigation.node('badge') or { panic('lost canceled declaration') }
			assert badge.el.text == if canceled_work_mode == 3 { 'newer' } else { 'declaration ${canceled_work_builds}' }
			assert window.app.layout_patches.len == 0
			assert !scheduler.stats().pending && !scheduler.stats().in_flight
			assert C.ui2_test_pump(window.app, embedder_pump) == -1
			assert scheduler.stats().draws == draws + 1 && canceled_work_tasks == 1
		}
		assert C.ui2_test_pump(canceled_work_other.app, embedder_pump) == -1
		assert canceled_work_other.app.scheduler.stats().draws == other_draws + 1
		assert !canceled_work_other.app.scheduler.stats().pending
		eprintln('canceled work mode=${canceled_work_mode} passed builds=${canceled_work_builds} tasks=${canceled_work_tasks} draws=${window.app.scheduler.stats().draws} other_draws=${other_draws + 1}')
	}
}
