// vfmt off
// Custom drawing stays independent of the platform loop. The legacy adapter
// delegates presentation to gg; owned surfaces submit their own Sokol pass.
@[has_globals]
module ui2

$if ( android || linux || ( ( macos || windows ) && ui2_custom_rendering ?) ) && !ui2_headless ? && !ui2_document_library ? {
	import gg
	import math
	import sokol.gfx
	import sokol.sfons
	import sokol.sgl
	$if android {
		import fontstash
		import os
		import os.font
	} $else {
		import ui2.thirdparty.vglyph
	}

	#include "@VMODROOT/ui/draw_commands.h"
	fn C.ui2_sgl_discard_commands(context sgl.Context)

	$if android {
		struct DrawContext {
		mut:
			inner               &gg.Context = unsafe { nil }
			width               int
			height              int
			scale               f32 = 1
			content_transform   ContentTransform
			clip_base           ClipRegion
			clip_region         ClipRegion
			interaction_enabled bool               = true
			submitted_polygon   fn ([]PaintVertex) = unsafe { nil }
			ft                  &gg.FT             = unsafe { nil }
			font_inited         bool
			owns_surface        bool
			gl_context          sgl.Context
			swapchain           gfx.Swapchain
			images              ImageResources
			destroying          bool
			destroyed           bool
		}
	} $else {
		struct DrawContext {
		mut:
			inner                &gg.Context = unsafe { nil }
			width                int
			height               int
			scale                f32 = 1
			content_transform    ContentTransform
			clip_base            ClipRegion
			clip_region          ClipRegion
			interaction_enabled  bool               = true
			submitted_polygon    fn ([]PaintVertex) = unsafe { nil }
			text                 &TextEngine        = unsafe { nil }
			text_renderer        &vglyph.Renderer   = unsafe { nil }
			text_font_generation int                = -1
			font_inited          bool
			owns_surface         bool
			gl_context           sgl.Context
			swapchain            gfx.Swapchain
			images               ImageResources
			destroying           bool
			destroyed            bool
		}
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

	// Read live logical dimensions without synchronizing drawing resources or
	// waiting for paint. Owned hosts publish these directly on their context.
	fn (ctx &DrawContext) logical_viewport(host_window voidptr) Rect {
		$if macos && ui2_embedder ? {
			if ctx.owns_surface && host_window != unsafe { nil } {
				mut metrics := C.ui2_embedder_surface{}
				C.ui2_embedder_metrics(host_window, &metrics)
				return rect(0, 0, f64(metrics.width), f64(metrics.height))
			}
		}
		if !ctx.owns_surface && ctx.inner != unsafe { nil } {
			live := ctx.inner.window_size()
			if live.width > 0 && live.height > 0 {
				return rect(0, 0, f64(live.width), f64(live.height))
			}
			return rect(0, 0, f64(ctx.inner.width), f64(ctx.inner.height))
		}
		return rect(0, 0, f64(ctx.width), f64(ctx.height))
	}

	fn (mut ctx DrawContext) sync_gg() {
		if ctx.inner == unsafe { nil } || ctx.owns_surface || ctx.destroyed { return }
		ctx.width = ctx.inner.width
		ctx.height = ctx.inner.height
		ctx.scale = ctx.inner.scale
		$if android {
			ctx.ft = ctx.inner.ft
			ctx.font_inited = ctx.inner.font_inited
		} $else {
			// gg currently creates Fontstash unconditionally during init. Release
			// that unused atlas as soon as the GPU is available; all UI2 desktop
			// text uses the per-context vglyph renderer from this point onward.
			if gfx.is_valid() {
				if ctx.inner.ft != unsafe { nil } && ctx.inner.ft.fons != unsafe { nil } {
					sfons.destroy(ctx.inner.ft.fons)
					// gg's resize handler writes ft.scale unconditionally. Retain an
					// inert FT shell, with no atlas or legacy font drawing enabled.
					ctx.inner.ft = &gg.FT{scale: ctx.scale}
				}
				ctx.inner.font_inited = false
				ctx.ensure_text_resources() or { panic('ui2: ${err}') }
			}
		}
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
			// has a default pipeline and its own alpha/additive pipelines. Size
			// the shared device for the SGL pools instead
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
		$if android {
			ctx.ft = new_draw_fonts(config) or {
				ctx.destroy()
				return err
			}
			ctx.font_inited = true
			inner.ft = ctx.ft
			inner.font_inited = true
		} $else {
			ctx.ensure_text_resources() or {
				ctx.destroy()
				return err
			}
		}
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

	$if android {
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
	}

	$if !android {
		fn (mut ctx DrawContext) ensure_text_resources() ! {
			if ctx.destroyed { return error('drawing context is closed') }
			if ctx.text != unsafe { nil } && ctx.text.scale == ctx.scale { return }
			ctx.activate()
			if ctx.text_renderer != unsafe { nil } { ctx.text_renderer.free() }
			if ctx.text != unsafe { nil } { ctx.text.free() }
			ctx.text = unsafe { nil }
			ctx.text_renderer = unsafe { nil }
			ctx.font_inited = false
			ctx.text = new_text_engine(ctx.scale)!
			ctx.text_renderer = vglyph.new_renderer(mut ctx.inner, ctx.scale)
			ctx.font_inited = true
		}

		fn (ctx &DrawContext) shape_text(text string, style TextStyle, width f64,
			lines int, ellipsize bool) !ShapedText {
			if ctx.destroyed || ctx.text == unsafe { nil } { return error('text context is closed') }
			mut engine := ctx.text
			return engine.shape(text, style, width, lines, ellipsize)
		}

		fn (ctx &DrawContext) shape_runs(runs []TextRun, style TextStyle, width f64, lines int, ellipsize bool) !ShapedText {
			if ctx.destroyed || ctx.text == unsafe { nil } { return error('text context is closed') }
			mut engine := ctx.text
			return engine.shape_runs(runs, style, width, lines, ellipsize)
		}

		fn (ctx &DrawContext) shape_text_area(text string, style TextStyle, width f64) !ShapedText {
			if ctx.destroyed || ctx.text == unsafe { nil } { return error('text context is closed') }
			mut engine := ctx.text
			return engine.shape_area(text, style, width)
		}

		fn (ctx &DrawContext) draw_shaped(shaped ShapedText, x f64, y f64) {
			if ctx.destroyed || ctx.text_renderer == unsafe { nil } { return }
			ctx.prepare_text_draw()
			mut renderer := ctx.text_renderer
			ctx.draw_transformed_layout(mut renderer, shaped.layout, x, y)
		}

		fn (ctx &DrawContext) draw_shaped_clipped(shaped ShapedText, x f64, y f64, clip Rect) {
			if ctx.destroyed || ctx.text_renderer == unsafe { nil } || clip.height <= 0 { return }
			mut visible := shaped.layout
			visible.items = shaped.layout.items.filter(
				y + it.y + it.descent > clip.y && y + it.y - it.ascent < clip.y + clip.height)
			ctx.prepare_text_draw()
			mut renderer := ctx.text_renderer
			ctx.draw_transformed_layout(mut renderer, visible, x, y)
		}

		fn (ctx &DrawContext) draw_transformed_layout(mut renderer vglyph.Renderer, layout vglyph.Layout, x f64, y f64) {
			t := ctx.content_transform
			origin := t.point(x, y)
			renderer.quad_sink = draw_glyph_quad
			renderer.quad_userdata = voidptr(ctx)
			renderer.draw_layout_transformed(layout, f32(origin.x), f32(origin.y),
				vglyph.AffineTransform{ xx: f32(t.xx), xy: f32(t.xy), yx: f32(t.yx), yy: f32(t.yy) })
			renderer.quad_sink = unsafe { nil }
			renderer.quad_userdata = unsafe { nil }
		}

		fn draw_glyph_quad(userdata voidptr, quad []vglyph.QuadVertex) {
			ctx := unsafe { &DrawContext(userdata) }
			mut vertices := []PaintVertex{cap: 4}
			for v in quad {
				vertices << PaintVertex{ x: f64(v.x), y: f64(v.y), u: f64(v.u), v: f64(v.v), r: f64(v.color.r), g: f64(v.color.g), b: f64(v.color.b), a: f64(v.color.a) }
			}
			// vglyph uses a logical projection; do not apply device DPI a second time.
			ctx.emit_window_polygon(vertices, 1)
		}

		fn (ctx &DrawContext) prepare_text_draw() {
			ctx.activate()
			if ctx.text_font_generation != ctx.text.font_generation {
				// Pango may recycle FT face addresses after registering a new font.
				// Discard identities, preserving atlas pixels referenced by quads.
				mut renderer := ctx.text_renderer
				renderer.clear_glyph_cache()
				unsafe { ctx.text_font_generation = ctx.text.font_generation }
			}
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
		$if android {
			if ctx.ft != unsafe { nil } { ctx.ft.scale = ctx.scale }
		} $else {
			ctx.ensure_text_resources() or { panic('ui2: ${err}') }
		}
		ctx.activate()
	}

	fn (ctx &DrawContext) begin() {
		if !ctx.owns_surface {
			ctx.inner.begin()
			return
		}
		ctx.activate()
		$if android {
			if ctx.font_inited { ctx.ft.flush() }
		}
		sgl.defaults()
		sgl.matrix_mode_projection()
		sgl.ortho(0, f32(ctx.swapchain.width), f32(ctx.swapchain.height), 0, -1, 1)
	}

	fn (ctx &DrawContext) end() {
		unsafe { mut images := &ctx.images; images.commit() }
		$if !android {
			if !ctx.destroyed && ctx.text_renderer != unsafe { nil } {
				mut renderer := ctx.text_renderer
				// Atlas uploads precede this frame's GPU submission so new worker
				// text and tooltips are visible in a single on-demand frame.
				renderer.commit()
			}
		}
		if !ctx.owns_surface {
			ctx.inner.end()
			unsafe { mut images := &ctx.images; images.finish_frame() }
			return
		}
		ctx.activate()
		gfx.begin_pass(gfx.Pass{ action: ctx.inner.clear_pass, swapchain: ctx.swapchain })
		sgl.draw()
		gfx.end_pass()
		gfx.commit()
		unsafe { ctx.inner.frame++
			mut images := &ctx.images; images.finish_frame() }
	}

	// begin records commands; the GPU pass starts only in end. An invalidated
	// frame must discard those commands without submitting to its old surface.
	fn (ctx &DrawContext) cancel() {
		if ctx.destroyed || !gfx.is_valid() { return }
		context := if ctx.owns_surface { ctx.gl_context } else { sgl.default_context() }
		C.ui2_sgl_discard_commands(context)
		unsafe { mut images := &ctx.images; images.cancel_frame() }
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
		if ctx.destroyed || ctx.destroying { return }
		ctx.destroying=true
		if g_gg_app.ctx==&ctx { cancel_touch() }
		ctx.activate()
		$if !android {
			if ctx.text_renderer != unsafe { nil } { ctx.text_renderer.free() }
			if ctx.text != unsafe { nil } { ctx.text.free() }
			ctx.text_renderer = unsafe { nil }
			ctx.text = unsafe { nil }
		}
		ctx.font_inited = false
		ctx.images.destroy()
		if !ctx.owns_surface {
			ctx.destroyed = true
			return
		}
		$if android {
			if ctx.ft != unsafe { nil } { sfons.destroy(ctx.ft.fons) }
			ctx.ft = unsafe { nil }
		}
		ctx.inner.ft = unsafe { nil }
		ctx.inner.font_inited = false
		sgl.destroy_pipeline(ctx.inner.pipeline.alpha)
		sgl.destroy_pipeline(ctx.inner.pipeline.add)
		sgl.destroy_context(ctx.gl_context)
		ctx.destroyed = true
		release_draw_device()
	}

	fn color_vertex(p Point, c gg.Color) PaintVertex {
		return PaintVertex{ x: p.x, y: p.y, r: f64(c.r), g: f64(c.g), b: f64(c.b), a: f64(c.a) }
	}
	fn (ctx &DrawContext) emit_window_polygon(vertices []PaintVertex, dpi f64) {
		clipped := ctx.clip_region.clip_polygon(vertices)
		if clipped.len < 3 { return }
		$if ui2_geometry_capture ? {
			if voidptr(ctx.submitted_polygon) != unsafe { nil } { ctx.submitted_polygon(clipped) }
		}
		sgl.begin_triangles()
		for i in 1 .. clipped.len - 1 {
			for v in [clipped[0], clipped[i], clipped[i + 1]] {
				sgl.c4b(u8(math.clamp(v.r, 0.0, 255.0)), u8(math.clamp(v.g, 0.0, 255.0)), u8(math.clamp(v.b, 0.0, 255.0)), u8(math.clamp(v.a, 0.0, 255.0)))
				sgl.v2f_t2f(f32(v.x * dpi), f32(v.y * dpi), f32(v.u), f32(v.v))
			}
		}
		sgl.end()
	}
	fn (ctx &DrawContext) draw_local_polygon(points []Point, c gg.Color) {
		ctx.activate()
		sgl.load_pipeline(ctx.inner.pipeline.alpha)
		sgl.disable_texture()
		vertices := points.map(color_vertex(ctx.content_transform.point(it.x, it.y), c))
		ctx.emit_window_polygon(vertices, f64(ctx.scale))
	}
	fn (ctx &DrawContext) draw_rect_filled(x f32, y f32, w f32, h f32, c gg.Color) {
		if w <= 0 || h <= 0 { return }
		area := ctx.content_transform.rounded_local_rect(rect(f64(x), f64(y), f64(w), f64(h)), f64(ctx.scale))
		ctx.draw_local_polygon(ContentTransform{}.quad(area), c)
	}
	fn (ctx &DrawContext) draw_rect_empty(x f32, y f32, w f32, h f32, c gg.Color) {
		ctx.draw_rounded_rect_empty(x, y, w, h, 0, c)
	}
	fn (ctx &DrawContext) draw_rounded_rect_filled(x f32, y f32, w f32, h f32, radius f32, c gg.Color) {
		if w <= 0 || h <= 0 { return }
		if radius <= 0 {
			ctx.draw_rect_filled(x, y, w, h, c)
			return
		}
		area := ctx.content_transform.rounded_local_rect(rect(f64(x), f64(y), f64(w), f64(h)), f64(ctx.scale))
		r := math.max(0.0, math.min(f64(radius), math.min(area.width, area.height) / 2))
		mut points := []Point{}
		for corner in 0 .. 4 {
			for index in 0 .. 17 {
				p := border_corner_point(area, corner, r, r, 180 + f64(corner) * 90 + f64(index) * 90 / 16)
				points << Point{p.x, p.y}
			}
		}
		ctx.draw_local_polygon(points, c)
	}
	fn (ctx &DrawContext) draw_rounded_rect_empty(x f32, y f32, w f32, h f32, radius f32, c gg.Color) {
		area := ctx.content_transform.rounded_local_rect(rect(f64(x), f64(y), f64(w), f64(h)), f64(ctx.scale))
		box_ := BoxStyle{ radius: f64(radius), border_left: 1, border_top: 1, border_right: 1, border_bottom: 1 }
		for triangle in box_border_triangles(area, box_) {
			ctx.draw_local_polygon([Point{triangle.a.x, triangle.a.y},
				Point{triangle.b.x, triangle.b.y}, Point{triangle.c.x, triangle.c.y}], c)
		}
	}
	fn (ctx &DrawContext) draw_triangle_filled(x f32, y f32, x2 f32, y2 f32, x3 f32, y3 f32, c gg.Color) {
		ctx.draw_local_polygon([Point{f64(x), f64(y)}, Point{f64(x2), f64(y2)}, Point{f64(x3), f64(y3)}], c)
	}
	fn (ctx &DrawContext) draw_line_with_config(x f32, y f32, x2 f32, y2 f32, config gg.PenConfig) {
		dx := f64(x2 - x)
		dy := f64(y2 - y)
		length := math.sqrt(dx * dx + dy * dy)
		if length <= 0 || config.thickness <= 0 { return }
		nx := -dy / length * f64(config.thickness) / 2
		ny := dx / length * f64(config.thickness) / 2
		ctx.draw_local_polygon([Point{f64(x) + nx, f64(y) + ny}, Point{f64(x2) + nx, f64(y2) + ny},
			Point{f64(x2) - nx, f64(y2) - ny}, Point{f64(x) - nx, f64(y) - ny}], config.color)
	}
	fn (ctx &DrawContext) scissor_rect(x f64, y f64, w f64, h f64) {
		region := ctx.clip_base.intersect(transformed_clip(rect(x, y, w, h), ctx.content_transform))
		unsafe { ctx.clip_region = region }
		ctx.sync_scissor()
	}
	fn (ctx &DrawContext) sync_scissor() {
		// Scissor only accelerates the exact polygon clipper, never defines the clip.
		// Restoring a paint scope must also restore this backend state, including
		// an unbounded parent, before another primitive is submitted.
		area := if ctx.clip_region.bounded { ctx.clip_region.bounds() } else { rect(0, 0, f64(ctx.width), f64(ctx.height)) }
		ctx.activate()
		left := math.floor(area.x * ctx.scale)
		top := math.floor(area.y * ctx.scale)
		right := math.ceil((area.x + area.width) * ctx.scale)
		bottom := math.ceil((area.y + area.height) * ctx.scale)
		sgl.scissor_rect(int(left), int(top), int(right - left), int(bottom - top), true)
	}

	$if android {
		fn (ctx &DrawContext) set_text_cfg(config gg.TextCfg) {
			ctx.activate()
			ctx.inner.set_text_cfg(config)
		}
		fn (ctx &DrawContext) text_width(text string) int {
			ctx.activate()
			return ctx.inner.text_width(text)
		}
		fn (ctx &DrawContext) text_width_f(text string) f32 {
			ctx.activate()
			return ctx.inner.text_width_f(text)
		}
		fn (ctx &DrawContext) draw_text(x int, y int, text string, config gg.TextCfg) {
			area := ctx.content_transform.project(rect(f64(x), f64(y), 0, 0))
			ctx.activate()
			ctx.inner.draw_text(int(area.x), int(area.y), text, gg.TextCfg{ ...config, size: int(f64(config.size) * ctx.content_transform.footprint_scale() + 0.5), max_width: int(f64(config.max_width) * ctx.content_transform.footprint_scale()) })
		}
	}
}
