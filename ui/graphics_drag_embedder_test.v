// vtest vflags: -d ui2_custom_rendering -d ui2_embedder -d ui2_geometry_capture
// vfmt off
@[has_globals]
module ui2

$if macos && ui2_custom_rendering ? && ui2_embedder ? && ui2_geometry_capture ? && !ui2_headless ? {
	import gg
	import os
	import sokol.gfx
	import sokol.sgl
	__global drag_seam_vertices = []PaintVertex{}
	__global drag_seam_events = []ElementEventKind{}
	__global drag_seam_teardown = false
	fn drag_seam_observe(vertices []PaintVertex) { drag_seam_vertices << vertices }
	fn drag_seam_record(event ElementEvent) {
		drag_seam_events << event.kind
		if event.kind==.drag_cancel && drag_seam_teardown {
			assert !g_gg_app.ctx.images.closed && g_gg_app.ctx.destroying
			handle_touch_down(40,40)
			assert !g_touch.down // a context being destroyed cannot regain capture
		}
	}
	fn drag_seam_environment() gfx.Environment {
		return gfx.Environment{defaults:gfx.EnvironmentDefaults{color_format:.bgra8,depth_format:.@none,sample_count:1},
			metal:gfx.MetalEnvironment{device:C.ui2_embedder_metal_device()}}
	}
	fn drag_seam_acquire(mut ctx DrawContext, window voidptr) {
		mut surface:=C.ui2_embedder_surface{}
		assert C.ui2_embedder_acquire_frame(window,&surface)
		ctx.set_surface(surface.width,surface.height,surface.dpi_scale,gfx.Swapchain{
			width:surface.framebuffer_width,height:surface.framebuffer_height,sample_count:1,
			color_format:.bgra8,depth_format:.@none,metal:gfx.MetalSwapchain{current_drawable:surface.drawable}})
	}
	fn drag_seam_tree(path string, asset ImageAsset, child bool) Element {
		image_el:=Element{...image('content',path,rect(0,0,32,16)),image_asset:asset,image_style:ImageStyle{tint:ImageTint{r:47,g:57,b:67}}}
		source:=with_transform(with_event(with_drag_source(view('preview-source',rect(10,10,40,30),BoxStyle{transparent:true},
			if child { [image_el] } else { []Element{} }),DragSource{preview:DragPreview{image_path:path,image_asset:asset,
			image_style:image_el.image_style,width:32,height:16,offset_x:0,offset_y:0,box:BoxStyle{transparent:true}}}),drag_seam_record),
			VisualTransform{rotation:30,scale_x:2,scale_y:2,origin_x:20,origin_y:15})
		return scroll('source-pane',rect(20,20,120,60),0xffffff,[source,view('extent',rect(0,240,10,10),BoxStyle{transparent:true},[])])
	}
	fn drag_seam_mount(root Element) {
		g_gg_app.declared_root=root
		g_gg_app.declaration_pending=true
		g_gg_app.has_root=true
		assert sync_custom_input_geometry(custom_input_dispatch(g_gg_app))
	}
	fn test_preview_common_affine_window_clip_resources_last_consumer_and_context_teardown() {
		previous_app:=g_gg_app
		previous_state:=activate_custom_window_state(new_custom_window_state())
		mut ctx:=new_surface_draw_context(gg.Config{width:320,height:240},drag_seam_environment())!
		defer { ctx.destroy(); activate_custom_window_state(previous_state); g_gg_app=previous_app }
		window:=C.ui2_embedder_create(&C.ui2_embedder_config{title:c'Drag combination',width:320,height:240,visible:false},
			&C.ui2_embedder_callbacks{},unsafe { nil })
		assert window!=unsafe { nil }
		defer { C.ui2_embedder_close(window) }
		g_gg_app=&GgApp{ctx:ctx}
		g_build_screen=unsafe { nil }
		drag_seam_events=[]ElementEventKind{}
		drag_seam_teardown=false
		ctx.submitted_polygon=drag_seam_observe
		folder:=os.join_path(@VMODROOT,'examples','image_assets','assets')
		path:=os.join_path(folder,'variant1.png')
		asset:=ImageAsset{logical_size:LayoutSize{width:32,height:16},revision:7,
			variants:[ImageVariant{path:os.join_path(folder,'variant2.png'),density:2},ImageVariant{path:os.join_path(folder,'variant3.png'),density:3}]}
		root:=drag_seam_tree(path,asset,true)
		drag_seam_mount(root)
		source:=g_drag_registry.owners['id:preview-source']
		point:=source.content_transform.point(source.local_frame.x+10,source.local_frame.y+10)
		handle_touch_down(point.x,point.y)
		handle_touch_move(300,215)
		assert drag_active() && g_touch.pointer_captured
		drag_seam_acquire(mut ctx,window)
		ctx.images.begin_frame()
		preload_images(mut ctx)
		preload_drag_preview(mut ctx)
		assert ctx.images.stats().decodes==1 && ctx.images.entries.len==1
		variant:=select_image_variant(path,asset,f64(ctx.scale)*source.content_transform.footprint_scale())!
		entry:=ctx.images.entries[image_entry_key(variant.path,7)] or { panic('shared variant/revision') }
		page:=ctx.images.pages[entry.page] or { panic('page') }
		ctx.begin()
		render_element(ctx,root,0,0,rect(0,0,320,240),'','root')
		outer:=ContentTransform{xx:1.2,yy:0.8,x:7,y:9}
		clip:=transformed_clip(rect(10,10,60,60),VisualTransform{rotation:35,origin_x:30,origin_y:30}.matrix(rect(10,10,60,60))!)
		ctx.content_transform=outer; ctx.clip_base=clip; ctx.clip_region=clip; ctx.sync_scissor()
		hits:=g_hit_targets.len
		tooltips:=g_tooltip_targets.len
		owners:=g_drag_registry.owners.len
		drag_seam_vertices.clear()
		draw_drag_preview(ctx)
		assert drag_seam_vertices.len>=3 && drag_seam_vertices.any(!clip.contains(it.x,it.y))
		for vertex in drag_seam_vertices {
			assert vertex.x>=0 && vertex.x<=320 && vertex.y>=0 && vertex.y<=240
			assert vertex.r==47 && vertex.g==57 && vertex.b==67
		}
		assert ctx.content_transform==outer && ctx.clip_base==clip && ctx.clip_region==clip
		assert g_hit_targets.len==hits && g_tooltip_targets.len==tooltips && g_drag_registry.owners.len==owners
		drag_seam_vertices.clear()
		ctx.draw_local_polygon([Point{0,0},Point{100,0},Point{100,100},Point{0,100}],gg.Color{r:3,g:4,b:5})
		assert drag_seam_vertices.len>=3
		for vertex in drag_seam_vertices { assert clip.contains(vertex.x,vertex.y) }
		ctx.content_transform=ContentTransform{}; ctx.clip_base=ClipRegion{}; ctx.clip_region=ClipRegion{}
		ctx.end(); C.ui2_embedder_frame_done(window)
		assert sgl.error()==.no_error && ctx.images.stats().uploads==1
		// Source remains mounted offscreen. Remove its content image: preview is
		// now the last image consumer and still marks the same resource owner.
		g_scroll_offsets[named_scroll_state_id('source-pane')]=100
		drag_seam_mount(drag_seam_tree(path,asset,false))
		assert g_drag_registry.owners['id:preview-source'].h==0 && drag_active()
		drag_seam_acquire(mut ctx,window)
		ctx.images.begin_frame(); preload_images(mut ctx); preload_drag_preview(mut ctx)
		assert ctx.images.stats().decodes==1 && ctx.images.entries.len==1
		ctx.begin(); draw_drag_preview(ctx); ctx.end(); C.ui2_embedder_frame_done(window)
		assert gfx.query_image_state(page.image)==.valid && ctx.images.stats().uploads==1
		cancel_drag()
		assert !g_touch.down && drag_seam_events.filter(it==.drag_cancel).len==1
		drag_seam_acquire(mut ctx,window)
		ctx.images.begin_frame(); preload_images(mut ctx); preload_drag_preview(mut ctx)
		ctx.begin()
		assert gfx.query_image_state(page.image)==.valid
		ctx.end(); C.ui2_embedder_frame_done(window)
		assert ctx.images.entries.len==0 && gfx.query_image_state(page.image)!=.valid
		// Capture must retire before resources are destroyed/recreated.
		g_scroll_offsets[named_scroll_state_id('source-pane')]=0
		drag_seam_mount(drag_seam_tree(path,asset,false))
		handle_touch_down(point.x,point.y); handle_touch_move(200,180)
		assert drag_active()
		drag_seam_teardown=true
		ctx.destroy()
		assert ctx.destroyed && ctx.images.closed && !g_touch.down && !g_touch.pointer_captured
		assert drag_seam_events.filter(it==.drag_cancel).len==2
		mut replacement:=new_surface_draw_context(gg.Config{width:320,height:240},drag_seam_environment())!
		g_gg_app.ctx=replacement
		handle_touch_up(200,180)
		assert !g_touch.down && replacement.images.entries.len==0 && !replacement.images.closed
		replacement.destroy()
		println('owned Metal submission: shared revision/DPI resource, window-clipped affine preview, scope restore, offscreen/last consumer and teardown cancellation passed; no pixel capture or OS input')
	}
	fn drag_seam_accept(_ DragOffer) DragOperation { return .move }
	fn test_bitmap_dimensions_and_revision_use_image_resources_before_current_release() {
		previous_app:=g_gg_app
		previous_state:=activate_custom_window_state(new_custom_window_state())
		mut ctx:=new_surface_draw_context(gg.Config{width:320,height:240},drag_seam_environment())!
		defer { ctx.destroy(); activate_custom_window_state(previous_state); g_gg_app=previous_app }
		g_gg_app=&GgApp{ctx:ctx}
		g_build_screen=unsafe { nil }
		drag_seam_events=[]ElementEventKind{}
		drag_seam_teardown=false
		folder:=os.join_path(@VMODROOT,'examples','image_assets','assets')
		source:=with_event(with_drag_source(view('source',rect(10,20,40,40),BoxStyle{},[]),DragSource{}),drag_seam_record)
		square:=with_event(with_drop_target(Element{...image('target',os.join_path(folder,'alpha.png'),rect(100,20,100,100)),
			image_asset:ImageAsset{revision:1}},DropTarget{accept:drag_seam_accept}),drag_seam_record)
		drag_seam_mount(screen(0xffffff,[source,square]))
		handle_touch_down(20,30); handle_touch_move(120,30)
		assert drag_active() && drag_destination(120,30).id=='target'
		rectangular:=Element{...square,image_path:os.join_path(folder,'variant1.png')}
		drag_seam_mount(screen(0xffffff,[source,rectangular]))
		assert g_drag_registry.owners['id:target'].image_geometry.bounds==rect(100,45,100,50)
		handle_touch_up(120,30)
		assert drag_seam_events.filter(it==.drop).len==0 && drag_seam_events.filter(it==.drag_cancel).len==1
		assert ctx.images.stats().decodes==2 && g_gg_app.scheduler.stats().draws==0
		drag_seam_mount(screen(0xffffff,[source,Element{...rectangular,image_asset:ImageAsset{revision:2}}]))
		handle_touch_down(20,30); handle_touch_move(120,60)
		drag_seam_mount(screen(0xffffff,[source,Element{...rectangular,image_asset:ImageAsset{revision:3}}]))
		handle_touch_up(120,60)
		assert drag_seam_events.filter(it==.drop).len==1 && drag_seam_events.filter(it==.drag_end).len==1
		assert image_entry_key(rectangular.image_path,3) in ctx.images.entries
		assert ctx.images.stats().decodes==4 && !g_touch.pointer_captured && !g_touch.down
		println('base bitmap dimensions/revision prepared by the same resource owner before current release passed (GPU preparation + synthetic input)')
	}

}
