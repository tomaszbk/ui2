// vfmt off
// Custom drawing stays independent of the platform loop. The legacy adapter
// delegates presentation to gg; owned surfaces submit their own Sokol pass.
@[has_globals]
module ui2

$if (android || linux || ((macos || windows) && ui2_custom_rendering ?)) && !ui2_headless ? {
	import fontstash
	import gg
	import os
	import os.font
	import sokol.gfx
	import sokol.sfons
	import sokol.sgl

	struct DrawContext {
	mut:
		inner &gg.Context = unsafe { nil }
		width int
		height int
		scale f32 = 1
		ft &gg.FT = unsafe { nil }
		font_inited bool
		owns_surface bool
		gl_context sgl.Context
		swapchain gfx.Swapchain
		image_ids map[int]bool
		destroyed bool
	}

	__global g_draw_device_users = 0
	__global g_draw_device_environment = gfx.Environment{}
	const draw_context_pool_size = 64
	const draw_pipeline_pool_size = draw_context_pool_size * 4

	fn gg_draw_context(inner &gg.Context) &DrawContext {
		mut ctx := &DrawContext{inner: inner}
		ctx.sync_gg()
		return ctx
	}

	fn (mut ctx DrawContext) sync_gg() {
		if ctx.inner == unsafe { nil } || ctx.owns_surface { return }
		ctx.width = ctx.inner.width
		ctx.height = ctx.inner.height
		ctx.scale = ctx.inner.scale
		ctx.ft = ctx.inner.ft
		ctx.font_inited = ctx.inner.font_inited
	}

	// The GFX device is shared, while command buffers, atlases and images belong
	// to a window. Device lifetime is independent of the order windows close in.
	fn new_surface_draw_context(config gg.Config, environment gfx.Environment) !&DrawContext {
		$if macos && ui2_embedder ? {
			if environment.metal.device == unsafe { nil } {
				return error('the owned Metal renderer needs a device created on the main thread')
			}
		}
		if g_draw_device_users == 0 {
			if gfx.is_valid() {
				return error('the owned renderer cannot share a running gg/Sokol app device')
			}
			// Every SGL pipeline creates five GFX primitive pipelines. A window
			// has a default, alpha, additive and font pipeline, plus one shader
			// for its font atlas. Size the shared device for the SGL pools instead
			// of GFX's single-window defaults, which failed on the third window.
			gfx.setup(&gfx.Desc{
				buffer_pool_size: draw_context_pool_size
				image_pool_size: draw_context_pool_size * 16
				sampler_pool_size: draw_context_pool_size * 16
				shader_pool_size: draw_context_pool_size
				pipeline_pool_size: draw_pipeline_pool_size * 5
				environment: environment
			})
			if !gfx.is_valid() { return error('could not initialize the renderer device') }
			sgl.setup(&sgl.Desc{
				context_pool_size: draw_context_pool_size
				pipeline_pool_size: draw_pipeline_pool_size
				color_format: environment.defaults.color_format
				depth_format: environment.defaults.depth_format
				sample_count: environment.defaults.sample_count
			})
			g_draw_device_environment = environment
		} else if environment.metal.device != g_draw_device_environment.metal.device
			|| environment.d3d11.device != g_draw_device_environment.d3d11.device
			|| environment.d3d11.device_context != g_draw_device_environment.d3d11.device_context
			|| environment.wgpu.device != g_draw_device_environment.wgpu.device
			|| environment.defaults.color_format != g_draw_device_environment.defaults.color_format
			|| environment.defaults.depth_format != g_draw_device_environment.defaults.depth_format
			|| environment.defaults.sample_count != g_draw_device_environment.defaults.sample_count {
			return error('windows must share the renderer device and attachment formats')
		}
		g_draw_device_users++
		gl_context := sgl.make_context(&sgl.ContextDesc{
			color_format: environment.defaults.color_format
			depth_format: environment.defaults.depth_format
			sample_count: environment.defaults.sample_count
		})
		if gl_context.id == 0 {
			release_draw_device()
			return error('could not allocate a window drawing context')
		}
		sgl.set_context(gl_context)
		mut inner := &gg.Context{
			config: config
			width: config.width
			height: config.height
			scale: 1
			has_started: true
			bg_color: config.bg_color
			clear_pass: gfx.create_clear_pass_action(f32(config.bg_color.r) / 255,
				f32(config.bg_color.g) / 255, f32(config.bg_color.b) / 255,
				f32(config.bg_color.a) / 255)
			pipeline: &gg.PipelineContainer{}
		}
		inner.pipeline.alpha = draw_blend_pipeline(.one_minus_src_alpha)
		inner.pipeline.add = draw_blend_pipeline(.one)
		mut ctx := &DrawContext{
			inner: inner
			width: config.width
			height: config.height
			owns_surface: true
			gl_context: gl_context
		}
		ctx.ft = new_draw_fonts(config) or {
			ctx.destroy()
			return err
		}
		ctx.font_inited = true
		inner.ft = ctx.ft
		inner.font_inited = true
		return ctx
	}

	fn draw_blend_pipeline(destination gfx.BlendFactor) sgl.Pipeline {
		mut desc := gfx.PipelineDesc{}
		desc.colors[0] = gfx.ColorTargetState{
			blend: gfx.BlendState{
				enabled: true
				src_factor_rgb: .src_alpha
				dst_factor_rgb: destination
			}
		}
		return sgl.make_pipeline(&desc)
	}

	fn new_draw_fonts(config gg.Config) !&gg.FT {
		normal_path := if config.font_path.len > 0 { config.font_path } else { font.default() }
		normal := if config.font_bytes_normal.len > 0 {
			config.font_bytes_normal.clone()
		} else {
			os.read_bytes(normal_path)!
		}
		bold_path := if config.custom_bold_font_path.len > 0 {
			config.custom_bold_font_path
		} else { font.get_path_variant(normal_path, .bold) }
		bold := if config.font_bytes_bold.len > 0 {
			config.font_bytes_bold.clone()
		} else { os.read_bytes(bold_path) or { normal.clone() } }
		mono := if config.font_bytes_mono.len > 0 {
			config.font_bytes_mono.clone()
		} else { os.read_bytes(font.get_path_variant(normal_path, .mono)) or { normal.clone() } }
		italic := if config.font_bytes_italic.len > 0 {
			config.font_bytes_italic.clone()
		} else { os.read_bytes(font.get_path_variant(normal_path, .italic)) or { normal.clone() } }
		fons := sfons.create(2048, 2048, 1)
		if fons == unsafe { nil } { return error('could not create the window font atlas') }
		fons.set_error_callback(expand_draw_atlas, fons)
		normal_id := fons.add_font_mem('normal', normal, true)
		if normal_id == fontstash.invalid {
			sfons.destroy(fons)
			return error('could not load the window font')
		}
		bold_id := fons.add_font_mem('bold', bold, true)
		mono_id := fons.add_font_mem('mono', mono, true)
		italic_id := fons.add_font_mem('italic', italic, true)
		return &gg.FT{
			fons: fons
			font_normal: normal_id
			font_bold: if bold_id != fontstash.invalid { bold_id } else { normal_id }
			font_mono: if mono_id != fontstash.invalid { mono_id } else { normal_id }
			font_italic: if italic_id != fontstash.invalid { italic_id } else { normal_id }
			scale: 1
		}
	}

	fn expand_draw_atlas(pointer voidptr, error_code i32, _value i32) {
		if error_code != C.FONS_ATLAS_FULL { return }
		fons := unsafe { &fontstash.Context(pointer) }
		width, height := fons.get_atlas_size()
		next_width := if width < 8192 { width * 2 } else { width }
		next_height := if height < 8192 { height * 2 } else { height }
		if next_width != width || next_height != height {
			fons.expand_atlas(next_width, next_height)
		}
	}

	fn (ctx &DrawContext) activate() {
		if ctx.owns_surface && !ctx.destroyed { sgl.set_context(ctx.gl_context) }
	}

	fn (mut ctx DrawContext) set_surface(width int, height int, scale f32, swapchain gfx.Swapchain) {
		ctx.width = width
		ctx.height = height
		ctx.scale = if scale > 0 { scale } else { f32(1) }
		ctx.swapchain = swapchain
		ctx.inner.width = width
		ctx.inner.height = height
		ctx.inner.scale = ctx.scale
		if ctx.ft != unsafe { nil } { ctx.ft.scale = ctx.scale }
		ctx.activate()
	}

	fn (ctx &DrawContext) begin() {
		if !ctx.owns_surface { ctx.inner.begin(); return }
		ctx.activate()
		if ctx.font_inited { ctx.ft.flush() }
		sgl.defaults()
		sgl.matrix_mode_projection()
		sgl.ortho(0, f32(ctx.swapchain.width), f32(ctx.swapchain.height), 0, -1, 1)
	}

	fn (ctx &DrawContext) end() {
		if !ctx.owns_surface { ctx.inner.end(); return }
		ctx.activate()
		gfx.begin_pass(gfx.Pass{action: ctx.inner.clear_pass, swapchain: ctx.swapchain})
		sgl.draw()
		gfx.end_pass()
		gfx.commit()
	}

	fn release_draw_device() {
		g_draw_device_users--
		if g_draw_device_users == 0 {
			sgl.shutdown()
			gfx.shutdown()
			g_draw_device_environment = gfx.Environment{}
		}
	}

	fn (mut ctx DrawContext) destroy() {
		if !ctx.owns_surface || ctx.destroyed { return }
		ctx.activate()
		for id, _ in ctx.image_ids { ctx.inner.remove_cached_image_by_idx(id) }
		ctx.image_ids.clear()
		if ctx.ft != unsafe { nil } { sfons.destroy(ctx.ft.fons) }
		ctx.ft = unsafe { nil }
		ctx.font_inited = false
		ctx.inner.ft = unsafe { nil }
		ctx.inner.font_inited = false
		sgl.destroy_pipeline(ctx.inner.pipeline.alpha)
		sgl.destroy_pipeline(ctx.inner.pipeline.add)
		sgl.destroy_context(ctx.gl_context)
		ctx.destroyed = true
		release_draw_device()
	}

	fn (ctx &DrawContext) draw_rect_filled(x f32, y f32, w f32, h f32, c gg.Color) {
		ctx.activate(); ctx.inner.draw_rect_filled(x, y, w, h, c)
	}
	fn (ctx &DrawContext) draw_rect_empty(x f32, y f32, w f32, h f32, c gg.Color) {
		ctx.activate(); ctx.inner.draw_rect_empty(x, y, w, h, c)
	}
	fn (ctx &DrawContext) draw_rounded_rect_filled(x f32, y f32, w f32, h f32, radius f32, c gg.Color) {
		ctx.activate(); ctx.inner.draw_rounded_rect_filled(x, y, w, h, radius, c)
	}
	fn (ctx &DrawContext) draw_rounded_rect_empty(x f32, y f32, w f32, h f32, radius f32, c gg.Color) {
		ctx.activate(); ctx.inner.draw_rounded_rect_empty(x, y, w, h, radius, c)
	}
	fn (ctx &DrawContext) draw_triangle_filled(x f32, y f32, x2 f32, y2 f32, x3 f32, y3 f32, c gg.Color) {
		ctx.activate(); ctx.inner.draw_triangle_filled(x, y, x2, y2, x3, y3, c)
	}
	fn (ctx &DrawContext) draw_line_with_config(x f32, y f32, x2 f32, y2 f32, config gg.PenConfig) {
		ctx.activate(); ctx.inner.draw_line_with_config(x, y, x2, y2, config)
	}
	fn (ctx &DrawContext) scissor_rect(x int, y int, w int, h int) {
		ctx.activate(); ctx.inner.scissor_rect(x, y, w, h)
	}
	fn (ctx &DrawContext) set_text_cfg(config gg.TextCfg) {
		ctx.activate(); ctx.inner.set_text_cfg(config)
	}
	fn (ctx &DrawContext) text_width(text string) int {
		ctx.activate(); return ctx.inner.text_width(text)
	}
	fn (ctx &DrawContext) text_width_f(text string) f32 {
		ctx.activate(); return ctx.inner.text_width_f(text)
	}
	fn (ctx &DrawContext) draw_text(x int, y int, text string, config gg.TextCfg) {
		ctx.activate(); ctx.inner.draw_text(x, y, text, config)
	}
	fn (ctx &DrawContext) draw_image_with_config(config gg.DrawImageConfig) {
		ctx.activate(); ctx.inner.draw_image_with_config(config)
	}
	fn (mut ctx DrawContext) create_image_from_byte_array(bytes []u8, config gg.ImageConfig) !gg.Image {
		ctx.activate()
		loaded := ctx.inner.create_image_from_byte_array(bytes, config)!
		if ctx.owns_surface {
			if gfx.query_image_state(loaded.simg) != .valid || gfx.query_sampler_state(loaded.ssmp) != .valid {
				ctx.inner.remove_cached_image_by_idx(loaded.id)
				return error('could not allocate the image GPU resources')
			}
			ctx.image_ids[loaded.id] = true
		}
		return loaded
	}
	fn (mut ctx DrawContext) get_cached_image_by_idx(id int) &gg.Image {
		return ctx.inner.get_cached_image_by_idx(id)
	}
	fn (mut ctx DrawContext) remove_cached_image_by_idx(id int) {
		ctx.activate()
		ctx.inner.remove_cached_image_by_idx(id)
		ctx.image_ids.delete(id)
	}
}
