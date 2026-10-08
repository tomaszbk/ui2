module ui2

$if macos && ui2_embedder ?&& ui2_custom_rendering ?&& !ui2_headless ? {
	import gg
	import os
	import sokol.gfx
	import sokol.sgl
	import ui2.thirdparty.vglyph

	fn text_gpu_test_environment() gfx.Environment {
		return gfx.Environment{
			defaults: gfx.EnvironmentDefaults{ color_format: .bgra8, depth_format: .@none, sample_count: 1 }
			metal:    gfx.MetalEnvironment{ device: C.ui2_embedder_metal_device() }
		}
	}

	fn text_gpu_test_surface(mut ctx DrawContext, window voidptr) {
		mut surface := C.ui2_embedder_surface{}
		assert C.ui2_embedder_acquire_frame(window, &surface)
		ctx.set_surface(surface.width, surface.height, surface.dpi_scale, gfx.Swapchain{
			width:        surface.framebuffer_width
			height:       surface.framebuffer_height
			sample_count: 1
			color_format: .bgra8
			depth_format: .@none
			metal:        gfx.MetalSwapchain{ current_drawable: surface.drawable }
		})
	}
}

// Keep the test functions present on other backends: the V test compiler cannot
// currently compile a file whose every test is removed by a platform guard.
fn test_owned_draw_resources_keep_other_window_text_and_device_alive() {
	$if macos && ui2_embedder ?&& ui2_custom_rendering ?&& !ui2_headless ? {
		config := gg.Config{ width: 320, height: 240 }
		environment := text_gpu_test_environment()
		mut first := new_surface_draw_context(config, environment)!
		defer { first.destroy() }
		mut second := new_surface_draw_context(config, environment)!
		defer { second.destroy() }
		mut third := new_surface_draw_context(config, environment)!
		defer { third.destroy() }
		mut fourth := new_surface_draw_context(config, environment)!
		defer { fourth.destroy() }
		assert voidptr(first.text) != voidptr(second.text)
		assert voidptr(second.text) != voidptr(third.text)
		assert voidptr(third.text) != voidptr(fourth.text)
		first_images := first.text_renderer.atlas_images()
		second_images := second.text_renderer.atlas_images()
		assert first_images[0].simg != second_images[0].simg
		assert first_images[0].ssmp != second_images[0].ssmp
		assert first.inner.ft == unsafe { nil }
		assert !first.inner.font_inited
		style := TextStyle{
			size:        12
			font_family: os.join_path(@VMODROOT, 'assets', 'fonts', 'Roboto-Regular.ttf')
		}
		value := 'independent window'
		first_width := first.shape_text(value, style, -1, 1, false)!.size.width
		assert first_width > 0
		first.activate()
		sgl.defaults()
		sgl.matrix_mode_projection()
		sgl.ortho(0, 320, 240, 0, -1, 1)
		first.draw_shaped(first.shape_text(value, style, -1, 1, false)!, 5, 5)
		generation := first.text_font_generation
		// A CPU-only context can register a newly requested family after a
		// window already has cached glyphs. The next draw updates that window's
		// font identities without replacing pixels needed by queued quads.
		font_path := '/System/Library/Fonts/Supplemental/Arial.ttf'
		assert os.is_file(font_path)
		mut cpu := new_text_engine(1)!
		defer { cpu.free() }
		cpu.shape('font registered by CPU measurement', TextStyle{
			...style
			font_family: font_path
		}, -1, 1, false)!
		refreshed := first.shape_text(value, style, -1, 1, false)!
		first.draw_shaped(refreshed, 5, 25)
		assert first.text_font_generation > generation
		assert first.text_font_generation == first.text.font_generation
		assert first.text_renderer.atlas_images()[0].simg == first_images[0].simg
		assert gfx.query_sampler_state(first_images[0].ssmp) == .valid
		assert sgl.error() == .no_error
		second.set_surface(320, 240, 2, gfx.Swapchain{})
		assert gfx.query_image_state(second_images[0].simg) != .valid
		assert gfx.query_sampler_state(second_images[0].ssmp) != .valid
		assert second.shape_text(value, style, -1, 1, false)!.size.width == first_width
		larger := TextStyle{ ...style, size: 30 }
		assert second.shape_text(value, larger, -1, 1, false)!.size.width > first_width * 2
		assert first.shape_text(value, style, -1, 1, false)!.size.width == first_width

		first.destroy()
		assert gfx.is_valid()
		assert gfx.query_image_state(first_images[0].simg) != .valid
		assert gfx.query_sampler_state(first_images[0].ssmp) != .valid
		live_second := second.text_renderer.atlas_images()[0]
		assert gfx.query_image_state(live_second.simg) == .valid
		assert gfx.query_sampler_state(live_second.ssmp) == .valid
		assert second.shape_text('the other window remains usable', larger, -1, 1, false)!.size.width > 0
		second.destroy()
		assert gfx.is_valid()
		assert third.shape_text(value, style, -1, 1, false)!.size.width == first_width
		assert fourth.shape_text(value, larger, -1, 1, false)!.size.width > first_width * 2
		third.destroy()
		assert gfx.is_valid()
		fourth.destroy()
		assert !gfx.is_valid()

		// A fresh window recreates the device and atlas after the final close.
		mut reopened := new_surface_draw_context(config, environment)!
		defer { reopened.destroy() }
		assert reopened.shape_text(value, style, -1, 1, false)!.size.width == first_width
		reopened.destroy()
		assert !gfx.is_valid()
	}
}

fn test_text_atlas_uploads_new_glyphs_before_on_demand_submission_and_releases_growth() {
	$if macos && ui2_embedder ?&& ui2_custom_rendering ?&& !ui2_headless ? {
		mut ctx := new_surface_draw_context(gg.Config{ width: 320, height: 240 }, text_gpu_test_environment())!
		defer { ctx.destroy() }
		window := C.ui2_embedder_create(&C.ui2_embedder_config{
			title:   c'UI2 text atlas verification'
			width:   320
			height:  240
			visible: false
		}, &C.ui2_embedder_callbacks{}, unsafe { nil })
		assert window != unsafe { nil }
		defer { C.ui2_embedder_close(window) }
		text_gpu_test_surface(mut ctx, window)
		initial := ctx.text_renderer.atlas_images()[0]
		ctx.text_renderer.free()
		assert gfx.query_image_state(initial.simg) != .valid
		assert gfx.query_sampler_state(initial.ssmp) != .valid
		ctx.text_renderer = vglyph.new_renderer_atlas_size(mut ctx.inner, 64, 32, ctx.scale)
		small := ctx.text_renderer.atlas_images()[0]
		style := TextStyle{
			size:        16
			font_family: os.join_path(@VMODROOT, 'assets', 'fonts', 'Roboto-Regular.ttf')
			color:       0x202020
		}
		shaped := ctx.shape_text('ABCDEFGHIJKLMNOPQRSTUVWXYZ abcdefghijklmnopqrstuvwxyz 0123456789', style, 310, 5, false)!
		ctx.begin()
		ctx.draw_shaped(shaped, 5, 5)
		assert sgl.error() == .no_error
		assert ctx.text_renderer.get_atlas_height() > 32
		assert gfx.query_image_info(small.simg).upd_frame_index > 0
		grown := ctx.text_renderer.atlas_images()[0]
		assert grown.simg != small.simg
		assert grown.ssmp == small.ssmp
		assert gfx.query_image_state(small.simg) == .valid
		assert gfx.query_image_info(grown.simg).upd_frame_index == 0
		ctx.end()
		C.ui2_embedder_frame_done(window)
		// No extra frame is required for text introduced by a worker/tooltip.
		assert gfx.query_image_info(grown.simg).upd_frame_index > 0
		assert ctx.inner.frame == 1
		assert gfx.query_sampler_state(grown.ssmp) == .valid

		text_gpu_test_surface(mut ctx, window)
		ctx.begin()
		next := ctx.shape_text('new glyphs: Ω Ж café', style, -1, 1, false)!
		ctx.draw_shaped(next, 5, 5)
		assert gfx.query_image_state(small.simg) != .valid
		assert gfx.query_sampler_state(grown.ssmp) == .valid
		before := gfx.query_image_info(grown.simg).upd_frame_index
		ctx.end()
		C.ui2_embedder_frame_done(window)
		assert gfx.query_image_info(grown.simg).upd_frame_index > before
		assert ctx.inner.frame == 2

		// Resizing at the same DPI keeps atlas ownership; changing DPI replaces
		// raster resources while preserving the same fractional logical metrics.
		width := ctx.shape_text('DPI stable geometry', style, -1, 1, false)!.size.width
		previous := ctx.text_renderer.atlas_images()[0]
		ctx.set_surface(640, 360, ctx.scale, gfx.Swapchain{})
		assert ctx.text_renderer.atlas_images()[0].simg == previous.simg
		ctx.set_surface(640, 360, 1.25, gfx.Swapchain{})
		assert gfx.query_image_state(previous.simg) != .valid
		assert gfx.query_sampler_state(previous.ssmp) != .valid
		assert ctx.shape_text('DPI stable geometry', style, -1, 1, false)!.size.width == width
		current := ctx.text_renderer.atlas_images()[0]
		ctx.destroy()
		assert !gfx.is_valid()
		assert ctx.text == unsafe { nil }
		assert ctx.text_renderer == unsafe { nil }
		assert current.simg.id != 0
		ctx.destroy()
	}
}

fn test_closing_with_deferred_atlas_images_keeps_another_context_alive() {
	$if macos && ui2_embedder ?&& ui2_custom_rendering ?&& !ui2_headless ? {
		config := gg.Config{ width: 320, height: 240 }
		environment := text_gpu_test_environment()
		mut guard := new_surface_draw_context(config, environment)!
		defer { guard.destroy() }
		guard_image := guard.text_renderer.atlas_images()[0]
		mut transient := new_surface_draw_context(config, environment)!
		defer { transient.destroy() }
		transient.text_renderer.free()
		transient.text_renderer = vglyph.new_renderer_atlas_size(mut transient.inner, 64,
			32, transient.scale)
		first := transient.text_renderer.atlas_images()[0]
		transient.activate()
		sgl.defaults()
		sgl.matrix_mode_projection()
		sgl.ortho(0, 320, 240, 0, -1, 1)
		style := TextStyle{
			size:        16
			font_family: os.join_path(@VMODROOT, 'assets', 'fonts', 'Roboto-Regular.ttf')
			color:       0x202020
		}
		shaped := transient.shape_text('ABCDEFGHIJKLMNOPQRSTUVWXYZ abcdefghijklmnopqrstuvwxyz',
			style, 310, 5, false)!
		transient.draw_shaped(shaped, 5, 5)
		// Four narrow pages consume 4 MiB of texture data. Saturating them with
		// a small bitmap also exercises reuse of a full page before submission,
		// with its previous image retained for already queued glyph quads.
		bitmap := vglyph.Bitmap{
			width:    64
			height:   32
			channels: 4
			data:     []u8{len: 64 * 32 * 4, init: 255}
		}
		mut reused := false
		for _ in 0 .. 550 {
			before := transient.text_renderer.atlas_images()
			transient.text_renderer.debug_insert_bitmap(bitmap, 0, 0)!
			after := transient.text_renderer.atlas_images()
			if before.len == 4 && after.len == 4 {
				for page in 0 .. after.len {
					if before[page].height == 4096 && after[page].height == 4096
						&& before[page].simg != after[page].simg {
						assert before[page].ssmp == after[page].ssmp
						assert gfx.query_image_state(before[page].simg) == .valid
						assert gfx.query_image_info(before[page].simg).upd_frame_index > 0
						assert gfx.query_image_info(after[page].simg).upd_frame_index == 0
						assert gfx.query_sampler_state(after[page].ssmp) == .valid
						reused = true
						break
					}
				}
			}
			if reused { break }
		}
		assert reused
		mut last_id := first.id
		for image in transient.text_renderer.atlas_images() {
			if image.id > last_id { last_id = image.id }
		}
		assert last_id > first.id
		mut allocated := []gg.Image{}
		// No application images are created in this context, so the cache range
		// records each atlas generation while it is waiting for submission.
		for id in first.id .. last_id + 1 {
			allocated << *transient.inner.get_cached_image_by_idx(id)
		}
		assert sgl.error() == .no_error
		transient.destroy()
		assert gfx.is_valid()
		for image in allocated {
			assert gfx.query_image_state(image.simg) != .valid
			assert gfx.query_sampler_state(image.ssmp) != .valid
		}
		assert gfx.query_image_state(guard_image.simg) == .valid
		assert gfx.query_sampler_state(guard_image.ssmp) == .valid
		guard.activate()
		sgl.defaults()
		sgl.matrix_mode_projection()
		sgl.ortho(0, 320, 240, 0, -1, 1)
		long_text := guard.shape_text_area('visible line\n'.repeat(3000), style, 310)!
		guard.draw_shaped_clipped(long_text, 5, 5, rect(5, 5, 310, 200))
		assert sgl.error() == .no_error
		guard.destroy()
		assert !gfx.is_valid()
	}
}

fn test_scaled_composition_gpu_submission_keeps_caret_and_layout_on_resize() {
	$if macos && ui2_embedder ?&& ui2_custom_rendering ?&& !ui2_headless ? {
		previous_app := g_gg_app
		isolated := new_custom_window_state()
		previous_state := activate_custom_window_state(isolated)
		defer {
			discard_custom_window_state(isolated)
			activate_custom_window_state(previous_state)
			g_gg_app = previous_app
		}
		mut ctx := new_surface_draw_context(gg.Config{ width: 640, height: 480 }, text_gpu_test_environment())!
		defer { ctx.destroy() }
		g_gg_app = &GgApp{ ctx: ctx }
		style := TextStyle{ size: 24, font_family: 'Inter' }
		field := text_input(
			id:          'field'
			placeholder: ''
			text:        ''
			frame:       rect(72, 570, 500, 60)
			box:         BoxStyle{ bg: 0xffffff }
			text_style:  style
			keyboard:    keyboard_default
			multiline:   false
		) or { panic(err) }
		rich := rich_label('rich', [
			TextRun{ text: 'Baseline ', style: TextStyle{ ...style, size: 48, weight: 800 } },
			TextRun{ text: 'raised', style: TextStyle{ ...style, size: 26, baseline_offset: 12, color: 0xcc2244 } },
		], rect(72, 290, 400, 45), TextStyle{ ...style, lines: 3 })
		reference := ctx.shape_runs(rich.text_runs, rich.text_style, 400, 3, true)!.size
		for viewport in [rect(0, 0, 640, 480), rect(0, 0, 853, 599)] {
			window := C.ui2_embedder_create(&C.ui2_embedder_config{ title: c'UI2 scaled composition verification', width: int(viewport.width), height: int(viewport.height), visible: false }, &C.ui2_embedder_callbacks{}, unsafe { nil })
			assert window != unsafe { nil }
			text_gpu_test_surface(mut ctx, window)
			g_focused_field = 'field'
			ctx.begin()
			// Independent font advances: this bundled Inter face measures 114.890625
			// logical units. Both paint paths must retain that fractional budget.
			tight_style := TextStyle{ size: 48, font_family: 'Inter', weight: 900, line_height: 59, valign: .top }
			assert !draw_label_text(ctx, '96%', 0, 0, 114.890625, 59, tight_style, viewport)
			assert draw_label_text(ctx, '96%', 0, 0, 114.0, 59, tight_style, viewport)
			tight_rich := rich_label('tight', [TextRun{ text: '96%', style: tight_style }], rect(0, 0, 114.890625, 59), tight_style)
			assert !draw_rich_label_text(ctx, tight_rich, 0, 0, viewport)
			render_element(ctx, scaled_content('slide', viewport, 1280, 720, BoxStyle{ transparent: true }, [
				rich,
				field,
			]), 0, 0, viewport, '', 'root')
			assert sgl.error() == .no_error
			assert ctx.content_transform == ContentTransform{}
			assert ctx.shape_runs(rich.text_runs, rich.text_style, 400, 3, true)!.size == reference
			caret := g_gg_app.text_caret
			if viewport.width == 640 {
				assert caret.x == 42
				assert caret.width == 1
				assert caret.y >= 345 && caret.y + caret.height <= 375
				set_text('field', 'local draft')
				mut editor := g_text_editors['field'] or { panic('editor was not mounted') }
				editor.set_caret(0)
				replace_text_editor('field', editor)
			} else {
				assert caret.x == 56
				assert caret.y > 439 && caret.y + caret.height < 480
				assert text('field') == 'local draft'
				assert (g_text_editors['field'] or { panic('editor lost on resize') }).selection.caret == 0
			}
			ctx.end()
			C.ui2_embedder_frame_done(window)
			C.ui2_embedder_close(window)
		}
	}
}
