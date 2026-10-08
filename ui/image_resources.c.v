// vfmt off
module ui2

$if (android || linux || ((macos || windows) && ui2_custom_rendering ?)) && !ui2_headless ? {
	import os
	import math
	import stbi
	import sokol.gfx
	import sokol.sgl

	const image_atlas_extent = 512
	const image_atlas_padding = 2

	struct ImageEntry {
		page int
		pixels Rect
		size LayoutSize
		stamp string
	mut:
		seen u64
	}

	@[heap]
	struct ImageAtlasPage {
	mut:
		image gfx.Image
		sampler gfx.Sampler
		width int
		height int
		pixels []u8
		x int
		y int
		row_height int
		live int
		dirty bool
	}

	// One owner per DrawContext. No gg application image cache or global path
	// cache. Slots append for a page's lifetime; no submitted quad is repacked.
	struct ImageResources {
	mut:
		entries map[string]ImageEntry
		pages map[int]&ImageAtlasPage
		next_page int
		frame u64
		in_frame bool
		closed bool
		pipeline sgl.Pipeline
		decodes u64
		cache_hits u64
		uploads u64
		created u64
		destroyed u64
	}

	fn (resources &ImageResources) stats() ImageResourceStats {
		return ImageResourceStats{decodes:resources.decodes, cache_hits:resources.cache_hits,
			uploads:resources.uploads, pages_created:resources.created, pages_destroyed:resources.destroyed,
			entries:resources.entries.len, pages:resources.pages.len, textures:resources.pages.len, samplers:resources.pages.len}
	}

	// Marks describe the complete declared tree, including culled consumers.
	// Pruning occurs only after all draw commands have been submitted.
	fn (mut resources ImageResources) begin_frame() {
		if resources.closed { return }
		resources.frame++
		resources.in_frame = true
	}

	fn image_entry_key(path string, revision u64) string {
		return '${os.abs_path(path)}:${revision}'
	}

	fn (mut resources ImageResources) acquire(path string, revision u64) !ImageEntry {
		if resources.closed || !gfx.is_valid() { return error('image context is closed or GPU is unavailable') }
		if resources.pipeline.id == 0 {
			mut desc := gfx.PipelineDesc{}
			desc.colors[0] = gfx.ColorTargetState{blend:gfx.BlendState{enabled:true,src_factor_rgb:.src_alpha,dst_factor_rgb:.one_minus_src_alpha,src_factor_alpha:.one,dst_factor_alpha:.one_minus_src_alpha}}
			resources.pipeline = sgl.make_pipeline(&desc)
			if resources.pipeline.id == 0 { return error('could not allocate image blend pipeline') }
		}
		key := image_entry_key(path, revision)
		stat := os.stat(path) or {
			resources.forget(key)
			return error('could not read image `${path}`: ${err}')
		}
		stamp := '${stat.size}:${stat.mtime}'
		if mut entry := resources.entries[key] {
			if entry.stamp == stamp {
				entry.seen = resources.frame
				resources.entries[key] = entry
				resources.cache_hits++
				return entry
			}
			resources.forget(key)
		}
		bytes := os.read_bytes(path)!
		decoded := stbi.load_from_memory(bytes.data, bytes.len)!
		defer { decoded.free() }
		resources.decodes++
		if decoded.width <= 0 || decoded.height <= 0 { return error('empty image `${path}`') }
		page_id, x, y := resources.allocate(decoded.width, decoded.height)!
		mut page := resources.pages[page_id] or { return error('image atlas page disappeared') }
		// Extrude two full edge texels, including corners and alpha. Linear
		// filtering at any rotation/scale cannot sample a neighboring asset.
		for dy in -image_atlas_padding .. decoded.height + image_atlas_padding {
			sy := math.max(0, math.min(decoded.height - 1, dy))
			for dx in -image_atlas_padding .. decoded.width + image_atlas_padding {
				sx := math.max(0, math.min(decoded.width - 1, dx))
				from := (sy * decoded.width + sx) * 4
				to := ((y + dy) * page.width + x + dx) * 4
				for channel in 0 .. 4 { page.pixels[to + channel] = unsafe { decoded.data[from + channel] } }
			}
		}
		page.live++
		page.dirty = true
		entry := ImageEntry{page:page_id, pixels:rect(x,y,decoded.width,decoded.height),
			size:LayoutSize{width:decoded.width,height:decoded.height},stamp:stamp,seen:resources.frame}
		resources.entries[key] = entry
		return entry
	}

	fn (mut resources ImageResources) allocate(width int, height int) !(int, int, int) {
		w, h := width + image_atlas_padding * 2, height + image_atlas_padding * 2
		// Stable ordering makes allocation and public fixtures deterministic.
		mut ids := resources.pages.keys()
		ids.sort()
		for id in ids {
			mut page := resources.pages[id] or { continue }
			if page.width != image_atlas_extent || page.height != image_atlas_extent { continue }
			mut x, mut y, mut row := page.x, page.y, page.row_height
			if x + w > page.width { x = 0; y += row; row = 0 }
			if y + h > page.height || w > page.width { continue }
			page.x = x + w; page.y = y; page.row_height = math.max(row,h)
			return id, x + image_atlas_padding, y + image_atlas_padding
		}
		page_width, page_height := math.max(image_atlas_extent,w), math.max(image_atlas_extent,h)
		limits := gfx.query_limits()
		if page_width > limits.max_image_size_2d || page_height > limits.max_image_size_2d {
			return error('image exceeds GPU texture size limit')
		}
		texture := gfx.make_image(&gfx.ImageDesc{width:page_width,height:page_height,pixel_format:.rgba8,usage:.stream})
		sampler := gfx.make_sampler(&gfx.SamplerDesc{min_filter:.linear,mag_filter:.linear,wrap_u:.clamp_to_edge,wrap_v:.clamp_to_edge})
		if gfx.query_image_state(texture) != .valid || gfx.query_sampler_state(sampler) != .valid {
			gfx.destroy_image(texture); gfx.destroy_sampler(sampler)
			return error('could not allocate image atlas GPU resources')
		}
		resources.next_page++
		id := resources.next_page
		resources.pages[id] = &ImageAtlasPage{image:texture,sampler:sampler,width:page_width,height:page_height,
			pixels:[]u8{len:page_width*page_height*4},x:w,row_height:h}
		resources.created++
		return id, image_atlas_padding, image_atlas_padding
	}

	fn (mut resources ImageResources) forget(key string) {
		entry := resources.entries[key] or { return }
		if mut page := resources.pages[entry.page] { page.live-- }
		resources.entries.delete(key)
	}

	fn (mut resources ImageResources) commit() {
		if resources.closed { return }
		for _, mut page in resources.pages {
			if !page.dirty { continue }
			mut data := gfx.ImageData{}
			data.subimage[0][0] = gfx.Range{ptr:page.pixels.data,size:usize(page.pixels.len)}
			gfx.update_image(page.image,&data)
			page.dirty = false
			resources.uploads++
		}
	}

	fn (mut resources ImageResources) finish_frame() {
		if resources.closed || !resources.in_frame { return }
		for key, entry in resources.entries {
			if entry.seen != resources.frame { resources.forget(key) }
		}
		for id, page in resources.pages {
			if page.live > 0 { continue }
			gfx.destroy_image(page.image); gfx.destroy_sampler(page.sampler)
			resources.pages.delete(id)
			resources.destroyed++
		}
		resources.in_frame = false
	}

	fn (mut resources ImageResources) destroy() {
		if resources.closed { return }
		for _, page in resources.pages {
			gfx.destroy_image(page.image); gfx.destroy_sampler(page.sampler)
			resources.destroyed++
		}
		resources.entries.clear(); resources.pages.clear()
		if resources.pipeline.id != 0 { sgl.destroy_pipeline(resources.pipeline); resources.pipeline = sgl.Pipeline{} }
		resources.in_frame = false; resources.closed = true
	}

	fn validate_image_variant(entry ImageEntry, asset ImageAsset, variant ImageVariant) ! {
		if asset.logical_size.width == 0 { return }
		expected := asset.logical_size
		if math.abs(entry.size.width - expected.width * variant.density) > 1
			|| math.abs(entry.size.height - expected.height * variant.density) > 1 {
			return error('image variant `${variant.path}` dimensions disagree with logical_size and density')
		}
	}

	fn (mut ctx DrawContext) prepare_image(el Element, quality_scale f64) !ImageEntry {
		mut required := quality_scale
		if el.image_asset.logical_size.width > 0 && el.frame.width > 0 && el.frame.height > 0 {
			geometry := image_geometry(el.frame,el.image_asset.logical_size,el.image_style,el.rotation)!
			required *= geometry.density
		}
		variant := select_image_variant(el.image_path,el.image_asset,required)!
		key := image_entry_key(variant.path,el.image_asset.revision)
		previous_seen := (ctx.images.entries[key] or { ImageEntry{} }).seen
		entry := ctx.images.acquire(variant.path,el.image_asset.revision)!
		validate_image_variant(entry,el.image_asset,variant) or {
			// A malformed consumer must not invalidate another consumer's valid
			// decoded resource. Restore its previous mark; unclaimed new entries
			// retire after submission like any other unused entry.
			ctx.images.entries[key] = ImageEntry{...entry,seen:previous_seen}
			return err
		}
		return entry
	}

	fn (ctx &DrawContext) image_geometry_for(el Element, area Rect) !ImageGeometry {
		mut required := f64(ctx.scale) * ctx.content_transform.scale
		if el.image_asset.logical_size.width > 0 {
			required *= image_geometry(area,el.image_asset.logical_size,el.image_style,el.rotation)!.density
		}
		variant := select_image_variant(el.image_path,el.image_asset,required)!
		entry := ctx.images.entries[image_entry_key(variant.path,el.image_asset.revision)] or { return error('image is not prepared') }
		validate_image_variant(entry,el.image_asset,variant)!
		intrinsic := if el.image_asset.logical_size.width > 0 { el.image_asset.logical_size } else { entry.size }
		return image_geometry(area,intrinsic,el.image_style,el.rotation)!
	}

	fn (ctx &DrawContext) draw_asset_image(el Element, geometry ImageGeometry) bool {
		required := f64(ctx.scale) * ctx.content_transform.scale * geometry.density
		variant := select_image_variant(el.image_path,el.image_asset,required) or { return false }
		entry := ctx.images.entries[image_entry_key(variant.path,el.image_asset.revision)] or { return false }
		page := ctx.images.pages[entry.page] or { return false }
		u0, v0 := (entry.pixels.x + geometry.source.x * entry.size.width) / page.width,
			(entry.pixels.y + geometry.source.y * entry.size.height) / page.height
		u1, v1 := u0 + geometry.source.width * entry.size.width / page.width, v0 + geometry.source.height * entry.size.height / page.height
		ctx.activate()
		sgl.load_pipeline(ctx.images.pipeline)
		sgl.enable_texture(); sgl.texture(page.image,page.sampler)
		sgl.begin_quads()
		tint := el.image_style.tint
		sgl.c4b(tint.r,tint.g,tint.b,tint.a)
		uvs := [ImagePoint{u0,v0},ImagePoint{u1,v0},ImagePoint{u1,v1},ImagePoint{u0,v1}]
		for i, point in geometry.points {
			// Consume the shared coordinate projection; device DPI is applied once
			// at submission, never mixed into logical fitting or input geometry.
			p := ctx.content_transform.project(rect(point.x,point.y,0,0))
			sgl.v2f_t2f(f32(p.x*ctx.scale),f32(p.y*ctx.scale),f32(uvs[i].x),f32(uvs[i].y))
		}
		sgl.end(); sgl.disable_texture()
		return true
	}

	pub fn image_resource_stats() ImageResourceStats {
		if g_gg_app.ctx == unsafe { nil } { return ImageResourceStats{} }
		return g_gg_app.ctx.images.stats()
	}
} $else {
	pub fn image_resource_stats() ImageResourceStats { return ImageResourceStats{} }
}
