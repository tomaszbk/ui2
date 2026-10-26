// vtest vflags: -gc boehm -d no_gc_thread_local_alloc -d ui2_custom_rendering -d ui2_embedder
module ui2

$if macos && ui2_custom_rendering ? && ui2_embedder ? && !ui2_headless ? {
	import gg
	import sokol.gfx
}

fn test_retained_glyph_clip_and_primitive_submission_allocate_nothing() {
	$if macos && ui2_custom_rendering ? && ui2_embedder ? && !ui2_headless ? {
		environment := gfx.Environment{defaults: gfx.EnvironmentDefaults{color_format: .bgra8, depth_format: .@none, sample_count: 1},
			metal: gfx.MetalEnvironment{device: C.ui2_embedder_metal_device()}}
		mut ctx := new_surface_draw_context(gg.Config{width: 320, height: 240}, environment)!
		defer { ctx.destroy() }
		ctx.set_surface(320, 240, 1, gfx.Swapchain{width: 320, height: 240, color_format: .bgra8, depth_format: .@none, sample_count: 1})
		shaped := ctx.shape_text_area('año café selección\nsegunda línea', TextStyle{size:18, underline:true}, 250)!
		ctx.content_transform = VisualTransform{rotation: 19}.matrix(rect(20, 30, 200, 100))!
		ctx.clip_region = transformed_clip(rect(10, 20, 140, 140), ctx.content_transform)
		for _ in 0 .. 3 {
			ctx.begin()
			ctx.draw_shaped_clipped(shaped, 5, 30, rect(0, 20, 200, 80))
			ctx.draw_rounded_rect_filled(5, 40, 100, 30, 8, gg.blue)
			ctx.draw_rounded_rect_empty(5, 40, 100, 30, 8, gg.red)
			ctx.cancel()
		}
		before := gc_allocation_snapshot()!
		for _ in 0 .. 100 {
			ctx.begin()
			ctx.draw_shaped_clipped(shaped, 5, 30, rect(0, 20, 200, 80))
			ctx.draw_rounded_rect_filled(5, 40, 100, 30, 8, gg.blue)
			ctx.draw_rounded_rect_empty(5, 40, 100, 30, 8, gg.red)
			ctx.cancel()
		}
		after := gc_allocation_snapshot()!.delta_since(before)
		assert ctx.inner.r.error() == .no_error
		assert after.allocated_bytes == 0
		assert after.collections == 0
	}
}

fn test_interaction_text_palettes_and_selection_reuse_owned_shapes() {
	$if macos && ui2_custom_rendering ? && ui2_embedder ? && !ui2_headless ? {
		environment := gfx.Environment{defaults: gfx.EnvironmentDefaults{color_format: .bgra8, depth_format: .@none, sample_count: 1},
			metal: gfx.MetalEnvironment{device: C.ui2_embedder_metal_device()}}
		mut ctx := new_surface_draw_context(gg.Config{width: 320, height: 240}, environment)!
		defer { ctx.destroy() }
		plain := TextStyle{size: 18, color: 0x101010}
		hover := TextStyle{size: 18, color: 0xaa1010}
		text := 'office año café'
		first := ctx.shape_text(text, plain, -1, 1, false)!
		second := ctx.shape_text(text, hover, -1, 1, false)!
		assert first.layout.items[0].color != second.layout.items[0].color
		expected := first.selection(1, 5)
		assert ctx.shaped_selection(first, 1, 5) == expected
		before := gc_allocation_snapshot()!
		mut count := 0
		for i in 0 .. 1000 {
			shaped := ctx.shape_text(text, if i % 2 == 0 { plain } else { hover }, -1, 1, false)!
			count += ctx.shaped_selection(shaped, 1, 5).len
			_ = shaped.cursor(2)
		}
		after := gc_allocation_snapshot()!.delta_since(before)
		assert count >= 1000
		assert after.allocated_bytes == 0
		assert after.collections == 0
		assert ctx.text.shape_builds == 1
		// Further colors may evict a palette, but already returned layouts own
		// their item/color snapshots and remain valid.
		for color in 0 .. 20 { _ = ctx.shape_text(text, TextStyle{size:18, color:u32(color)}, -1, 1, false)! }
		assert first.layout.items[0].color != second.layout.items[0].color
		for bucket in ctx.text.shape_cache.values() {
			for entry in bucket { assert entry.painted.len <= shape_paint_cache_limit }
		}
	}
}
