// vtest vflags: -d ui2_custom_rendering -d ui2_embedder
module ui2

$if macos && ui2_embedder ?&& ui2_custom_rendering ?&& !ui2_headless ? {
	import gg
	import os
	import sokol.gfx
	import sokol.sgl

	fn image_gpu_environment() gfx.Environment {
		return gfx.Environment{
			defaults: gfx.EnvironmentDefaults{ color_format: .bgra8, depth_format: .@none, sample_count: 1 }
			metal:    gfx.MetalEnvironment{ device: C.ui2_embedder_metal_device() }
		}
	}

	fn image_gpu_surface(mut ctx DrawContext, window voidptr, scale f32) {
		mut surface := C.ui2_embedder_surface{}
		assert C.ui2_embedder_acquire_frame(window, &surface)
		ctx.set_surface(surface.width, surface.height, scale, gfx.Swapchain{
			width:        surface.framebuffer_width
			height:       surface.framebuffer_height
			sample_count: 1
			color_format: .bgra8
			depth_format: .@none
			metal:        gfx.MetalSwapchain{ current_drawable: surface.drawable }
		})
	}

	fn image_gpu_path(name string) string {
		return os.join_path(@VMODROOT, 'examples', 'image_assets', 'assets', name)
	}
}

fn test_image_gpu_atlas_context_isolation_shared_release_resize_and_recreation() {
	$if macos && ui2_embedder ?&& ui2_custom_rendering ?&& !ui2_headless ? {
		environment := image_gpu_environment()
		mut first := new_surface_draw_context(gg.Config{ width: 320, height: 240 }, environment)!
		defer { first.destroy() }
		mut second := new_surface_draw_context(gg.Config{ width: 320, height: 240 }, environment)!
		defer { second.destroy() }
		first.images.begin_frame()
		red := first.images.acquire(image_gpu_path('red.png'), 0)!
		shared_entry := first.images.acquire(image_gpu_path('red.png'), 0)!
		green := first.images.acquire(image_gpu_path('green.png'), 0)!
		alpha := first.images.acquire(image_gpu_path('alpha.png'), 0)!
		assert red == shared_entry
		assert red.page == green.page && green.page == alpha.page
		assert first.images.stats().decodes == 3
		assert first.images.stats().cache_hits == 1
		second.images.begin_frame()
		guard := second.images.acquire(image_gpu_path('red.png'), 0)!
		page := first.images.pages[red.page] or { panic('page lost') }
		guard_page := second.images.pages[guard.page] or { panic('guard page lost') }
		assert page.image != guard_page.image && page.sampler != guard_page.sampler
		// The full extruded boundary and corners are red, including alpha.
		for y in int(red.pixels.y) - 2 .. int(red.pixels.y + red.pixels.height) + 2 {
			for x in int(red.pixels.x) - 2 .. int(red.pixels.x + red.pixels.width) + 2 {
				offset := (y * page.width + x) * 4
				assert page.pixels[offset..offset + 4] == [u8(255), 0, 0, 255]
			}
		}
		alpha_offset := (int(alpha.pixels.y) * page.width + int(alpha.pixels.x)) * 4
		assert page.pixels[alpha_offset..alpha_offset + 4] == [u8(255), 255, 255, 0]
		window := C.ui2_embedder_create(&C.ui2_embedder_config{ title: c'Image resources verification', width: 320, height: 240, visible: false }, &C.ui2_embedder_callbacks{}, unsafe { nil })
		assert window != unsafe { nil }
		defer { C.ui2_embedder_close(window) }
		image_gpu_surface(mut first, window, 1)
		first.begin()
		el := image('red', image_gpu_path('red.png'), rect(0.25, 0.75, 80, 80))
		first.draw_asset_image(el, first.image_geometry_for(el, el.frame)!)
		first.end()
		C.ui2_embedder_frame_done(window)
		assert sgl.error() == .no_error
		assert first.images.stats().uploads == 1
		// Removing one of two consumers still marks the one shared entry.
		first.images.begin_frame()
		first.images.acquire(image_gpu_path('red.png'), 0)!
		image_gpu_surface(mut first, window, 1.5)
		first.begin()
		first.draw_asset_image(el, first.image_geometry_for(el, el.frame)!)
		first.end()
		C.ui2_embedder_frame_done(window)
		assert first.images.stats().entries == 1
		assert gfx.query_image_state(page.image) == .valid
		assert first.images.stats().decodes == 3
		// Last consumer gone: release only after a real GPU submission.
		first.images.begin_frame()
		image_gpu_surface(mut first, window, 2)
		first.begin()
		first.end()
		C.ui2_embedder_frame_done(window)
		assert first.images.stats().pages == 0
		assert gfx.query_image_state(page.image) != .valid
		assert gfx.query_sampler_state(page.sampler) != .valid
		assert gfx.query_image_state(guard_page.image) == .valid
		// Device/DPI changes select a different asset but never change geometry.
		asset_el := Element{
			...image('v', image_gpu_path('variant1.png'), rect(0.25, 0.75, 32, 16))
			image_asset: ImageAsset{
				logical_size: LayoutSize{ width: 32, height: 16 }
				variants:     [
					ImageVariant{ path: image_gpu_path('variant2.png'), density: 2 },
					ImageVariant{ path: image_gpu_path('variant3.png'), density: 3 },
				]
			}
		}
		mut last_geometry := ImageGeometry{}
		for scale in [f32(1), 1.25, 1.5, 2, 3] {
			image_gpu_surface(mut first, window, scale)
			first.images.begin_frame()
			entry := first.prepare_image(asset_el, f64(scale))!
			assert entry.size.width == if scale <= 1 {
				32
			} else if scale <= 2 {
				64
			} else {
				96
			}
			geometry := first.image_geometry_for(asset_el, asset_el.frame)!
			if last_geometry.bounds.width > 0 {
				assert geometry == last_geometry
			}
			last_geometry = geometry
			first.begin()
			assert first.draw_asset_image(asset_el, geometry)
			first.end()
			C.ui2_embedder_frame_done(window)
			assert first.images.stats().entries == 1
		}
		assert first.images.stats().decodes == 6
		assert first.images.stats().uploads == 4
		mut handles := []gfx.Image{}
		mut samplers := []gfx.Sampler{}
		for _, p in first.images.pages {
			handles << p.image
			samplers << p.sampler
		}
		first.destroy()
		first.destroy()
		assert first.images.stats().pages == 0
		assert first.images.stats().pages_created == first.images.stats().pages_destroyed
		for handle in handles {
			assert gfx.query_image_state(handle) != .valid
		}
		for sampler in samplers {
			assert gfx.query_sampler_state(sampler) != .valid
		}
		assert gfx.query_image_state(guard_page.image) == .valid
		mut recreated := new_surface_draw_context(gg.Config{ width: 320, height: 240 }, environment)!
		recreated.images.begin_frame()
		r := recreated.images.acquire(image_gpu_path('red.png'), 0)!
		rp := recreated.images.pages[r.page] or { panic('recreated page lost') }
		for handle in handles {
			assert rp.image != handle
		}
		recreated.destroy()
		second.destroy()
		assert !gfx.is_valid()
	}
}
