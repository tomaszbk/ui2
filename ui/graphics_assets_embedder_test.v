// vtest vflags: -d ui2_custom_rendering -d ui2_embedder -d ui2_geometry_capture
// vfmt off
@[has_globals]
module ui2

$if macos && ui2_custom_rendering ? && ui2_embedder ? && ui2_geometry_capture ? && !ui2_headless ? {
	import gg
	import math
	import os
	import sokol.gfx
	import sokol.sgl
	__global graphics_seam_vertices = []PaintVertex{}
	fn graphics_seam_observe(vertices []PaintVertex) { graphics_seam_vertices << vertices }
	fn graphics_seam_env() gfx.Environment {
		return gfx.Environment{defaults:gfx.EnvironmentDefaults{color_format:.bgra8,depth_format:.@none,sample_count:1},
			metal:gfx.MetalEnvironment{device:C.ui2_embedder_metal_device()}}
	}
	fn graphics_seam_surface(mut ctx DrawContext, window voidptr) {
		mut surface := C.ui2_embedder_surface{}
		assert C.ui2_embedder_acquire_frame(window,&surface)
		ctx.set_surface(surface.width,surface.height,surface.dpi_scale,gfx.Swapchain{
			width:surface.framebuffer_width,height:surface.framebuffer_height,sample_count:1,
			color_format:.bgra8,depth_format:.@none,metal:gfx.MetalSwapchain{current_drawable:surface.drawable}})
	}
}

fn test_combined_vector_image_text_exact_clip_rotation_once_and_sibling_scope() {
	$if macos && ui2_custom_rendering ? && ui2_embedder ? && ui2_geometry_capture ? && !ui2_headless ? {
		previous_app := g_gg_app
		previous_state := activate_custom_window_state(new_custom_window_state())
		mut ctx := new_surface_draw_context(gg.Config{width:320,height:240},graphics_seam_env())!
		defer { ctx.destroy(); activate_custom_window_state(previous_state); g_gg_app=previous_app }
		window := C.ui2_embedder_create(&C.ui2_embedder_config{title:c'Graphics combination',width:320,height:240,visible:false},
			&C.ui2_embedder_callbacks{},unsafe { nil })
		assert window != unsafe { nil }
		defer { C.ui2_embedder_close(window) }
		g_gg_app=&GgApp{ctx:ctx,has_root:true}
		ctx.submitted_polygon=graphics_seam_observe
		path := os.join_path(@VMODROOT,'examples','image_assets','assets','pattern.png')
		image_el := Element{...image('image',path,rect(0,0,100,100)),image_style:ImageStyle{fit:.cover,tint:ImageTint{r:17,g:200,b:30}},
			rotation:90,origin_x:50,origin_y:50}
		shape := prepare_vector_shape(vector_polygon([vector_point(-20,-20),vector_point(120,-20),
			vector_point(120,120),vector_point(-20,120)]),VectorStyle{fill:0xaa1122})!
		pane := with_transform(scroll('pane',rect(50,30,100,100),0xffffff,[
			vector_canvas(id:'vector',frame:rect(0,0,100,100),shapes:[shape])!,image_el,
			label('text','año café',rect(-10,20,130,40),TextStyle{color:0x3344ee,size:24}),
		]),VisualTransform{rotation:45,origin_x:50,origin_y:50,scale_x:1.2,scale_y:0.8})
		update_custom_focus_tree(pane)
		graphics_seam_surface(mut ctx,window)
		ctx.images.begin_frame()
		preload_images(mut ctx)
		ctx.begin()
		graphics_seam_vertices.clear()
		render_element(ctx,pane,0,0,rect(0,0,320,240),'','root')
		exact := transformed_clip(pane.frame,pane.visual_transform().matrix(pane.frame)!)
		assert graphics_seam_vertices.any(it.r==170 && it.g==17 && it.b==34)
		assert graphics_seam_vertices.any(it.r==17 && it.g==200 && it.b==30)
		assert graphics_seam_vertices.any(it.r==51 && it.g==68 && it.b==238)
		for vertex in graphics_seam_vertices { assert exact.contains(vertex.x,vertex.y) }
		corner := exact.bounds()
		assert !exact.contains(corner.x+0.1,corner.y+0.1)
		assert ctx.content_transform==ContentTransform{} && !ctx.clip_region.bounded && !ctx.clip_base.bounded
		graphics_seam_vertices.clear()
		render_element(ctx,view('sibling',rect(250,180,30,30),BoxStyle{bg:0xabcdef},[]Element{}),0,0,rect(0,0,320,240),'','sibling')
		assert graphics_seam_vertices.len==4 && graphics_seam_vertices[0].x==250
		// Hand-derived cover/contain local geometry and one R90 after T*S2.
		cover := image_geometry(rect(0,0,100,100),LayoutSize{width:200,height:100},ImageStyle{fit:.cover})!
		contain := image_geometry(rect(0,0,100,100),LayoutSize{width:200,height:100},ImageStyle{})!
		assert cover.source==rect(0.25,0,0.5,1) && contain.bounds==rect(0,25,100,50)
		ctx.content_transform=ContentTransform{xx:2,yy:2,x:10,y:20}.compose(image_el.visual_transform().matrix(rect(0,0,100,100))!)
		graphics_seam_vertices.clear()
		assert ctx.draw_asset_image(image_el,cover)
		assert math.abs(graphics_seam_vertices[0].x-210)<1e-6 && math.abs(graphics_seam_vertices[0].y-20)<1e-6
		ctx.content_transform=ContentTransform{}
		ctx.end()
		C.ui2_embedder_frame_done(window)
		assert sgl.error()==.no_error
		assert ctx.images.stats().decodes==1 && ctx.images.stats().uploads==1
		// Cancellation discards commands without retiring their prepared pages.
		entry := ctx.images.entries[image_entry_key(path,0)] or { panic('image') }
		page := ctx.images.pages[entry.page] or { panic('page') }
		ctx.images.begin_frame()
		ctx.begin()
		ctx.draw_asset_image(image_el,cover)
		ctx.cancel()
		assert !ctx.images.in_frame && gfx.query_image_state(page.image)==.valid
		ctx.images.begin_frame()
		graphics_seam_surface(mut ctx,window)
		ctx.begin()
		assert gfx.query_image_state(page.image)==.valid
		ctx.end()
		C.ui2_embedder_frame_done(window)
		assert ctx.images.stats().entries==0 && gfx.query_image_state(page.image)!=.valid
		println('combined affine vector/image/text Metal submission, rotation-once, restored scope and canceled-page retirement passed')
	}
}
