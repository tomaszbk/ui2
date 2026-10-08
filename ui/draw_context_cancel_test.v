// vtest vflags: -d ui2_custom_rendering -d ui2_embedder
module ui2

$if macos && ui2_embedder ? && ui2_custom_rendering ? && !ui2_headless ? {
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
	fn C.ui2_test_pool_begin() voidptr
	fn C.ui2_test_pool_end(pool voidptr)

	fn cancel_test_surface(mut ctx DrawContext, window voidptr) {
		mut surface := C.ui2_embedder_surface{}
		assert C.ui2_embedder_acquire_frame(window, &surface)
		ctx.set_surface(surface.width, surface.height, surface.dpi_scale, gfx.Swapchain{
			width: surface.framebuffer_width
			height: surface.framebuffer_height
			sample_count: 1
			color_format: .bgra8
			depth_format: .@none
			metal: gfx.MetalSwapchain{current_drawable: surface.drawable}
		})
	}
}

fn test_cancel_discards_only_its_cpu_commands_without_submitting_a_metal_frame() {
	$if macos && ui2_embedder ? && ui2_custom_rendering ? && !ui2_headless ? {
		environment := gfx.Environment{
			defaults: gfx.EnvironmentDefaults{color_format: .bgra8, depth_format: .@none, sample_count: 1}
			metal: gfx.MetalEnvironment{device: C.ui2_embedder_metal_device()}
		}
		mut first := new_surface_draw_context(gg.Config{width: 320, height: 240}, environment)!
		mut other := new_surface_draw_context(gg.Config{width: 320, height: 240}, environment)!
		defer { first.destroy(); other.destroy() }
		window := C.ui2_embedder_create(&C.ui2_embedder_config{title: c'Owned Metal cancellation queues', width: 320, height: 240}, &C.ui2_embedder_callbacks{}, unsafe { nil })
		assert window != unsafe { nil }
		defer { C.ui2_embedder_close(window) }
		gfx.enable_frame_stats()
		shared_sampler := C.ui2_test_shared_sampler()
		first_context := first.gl_context
		style := TextStyle{size: 18, font_family: 'Inter'}
		mut pool := C.ui2_test_pool_begin()
		cancel_test_surface(mut first, window)
		first_images := first.text_renderer.atlas_images()
		first_text := first.text
		first_renderer := first.text_renderer
		C.ui2_test_watch_drawable(window)
		first.begin()
		before := gfx.query_frame_stats().frame_index
		first.cancel() // No commands and no started Metal pass.
		assert gfx.query_frame_stats().frame_index == before
		assert first.inner.frame == 0
		assert C.ui2_test_command_count(first.gl_context) == 0
		assert C.ui2_test_has_drawable(window)
		C.ui2_embedder_frame_done(window)
		assert C.ui2_test_drawable_release_count() == 1
		assert !C.ui2_test_has_drawable(window)
		C.ui2_test_pool_end(pool)

		pool = C.ui2_test_pool_begin()
		cancel_test_surface(mut first, window)
		C.ui2_test_watch_drawable(window)
		first.begin()
		first.scissor_rect(0, 0, 200, 100)
		first.draw_rect_filled(0, 0, 100, 30, gg.red)
		first.draw_shaped(first.shape_text('discarded café ñ', style, -1, 1, false)!, 5, 50)
		assert C.ui2_test_command_count(first.gl_context) > 0
		assert C.ui2_test_vertex_count(first.gl_context) > 0
		cancel_test_surface(mut other, window)
		other_images := other.text_renderer.atlas_images()
		other.begin()
		other.draw_rect_filled(0, 0, 80, 30, gg.blue)
		other.draw_shaped(other.shape_text('other window', style, -1, 1, false)!, 5, 50)
		other_commands := C.ui2_test_command_count(other.gl_context)
		other_vertices := C.ui2_test_vertex_count(other.gl_context)
		assert other_commands > 0 && other_vertices > 0
		active := sgl.get_context()
		first.cancel() // Cancel the captured context, even if another is active.
		assert sgl.get_context() == active
		assert C.ui2_test_command_count(first.gl_context) == 0
		assert C.ui2_test_vertex_count(first.gl_context) == 0
		assert C.ui2_test_command_count(other.gl_context) == other_commands
		assert C.ui2_test_vertex_count(other.gl_context) == other_vertices
		assert gfx.query_frame_stats().frame_index == before
		assert first.text == first_text && first.text_renderer == first_renderer
		assert first.gl_context == first_context
		assert gfx.query_sampler_state(shared_sampler) == .valid
		for image in first_images {
			assert gfx.query_image_state(image.simg) == .valid
			assert gfx.query_sampler_state(image.ssmp) == .valid
		}
		C.ui2_embedder_frame_done(window)
		assert C.ui2_test_drawable_release_count() == 1
		assert !C.ui2_test_has_drawable(window)
		C.ui2_test_pool_end(pool)

		// The other queued frame remains drawable, including its text resources.
		pool = C.ui2_test_pool_begin()
		cancel_test_surface(mut other, window)
		other.end()
		assert gfx.query_frame_stats().num_draw > 0
		C.ui2_embedder_frame_done(window)
		C.ui2_test_pool_end(pool)
		// An empty valid repaint on the canceled context must draw no stale quads.
		pool = C.ui2_test_pool_begin()
		cancel_test_surface(mut first, window)
		first.begin()
		first.end()
		assert gfx.query_frame_stats().num_passes == 1
		assert gfx.query_frame_stats().num_draw == 0
		C.ui2_embedder_frame_done(window)
		C.ui2_test_pool_end(pool)
		// The discarded glyphs can still be painted on a subsequent current frame.
		pool = C.ui2_test_pool_begin()
		cancel_test_surface(mut first, window)
		first.begin()
		first.draw_shaped(first.shape_text('discarded café ñ', style, -1, 1, false)!, 5, 50)
		first.end()
		assert gfx.query_frame_stats().num_draw > 0
		C.ui2_embedder_frame_done(window)
		C.ui2_test_pool_end(pool)
		first.destroy()
		first.cancel() // Late cancellation cannot touch the surviving device.
		assert gfx.is_valid()
		assert gfx.query_sampler_state(shared_sampler) == .valid
		for image in other_images {
			assert gfx.query_image_state(image.simg) == .valid
			assert gfx.query_sampler_state(image.ssmp) == .valid
		}
		pool = C.ui2_test_pool_begin()
		cancel_test_surface(mut other, window)
		other.begin()
		other.draw_shaped(other.shape_text('surviving context', style, -1, 1, false)!, 5, 50)
		other.end()
		assert gfx.query_frame_stats().num_draw > 0
		C.ui2_embedder_frame_done(window)
		C.ui2_test_pool_end(pool)
		eprintln('owned cancellation queues and shared resources passed')
	}
}
