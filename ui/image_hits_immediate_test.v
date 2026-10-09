// vtest vflags: -d ui2_custom_rendering
module ui2

fn test_image_visible_quad_hits_share_fractional_scaled_coordinates_and_clip() {
	$if ( android || linux || ( ( macos || windows ) && ui2_custom_rendering ?) ) && !ui2_headless ? {
		previous := g_gg_app.ctx
		previous_hits := g_hit_targets
		transform := ContentTransform{xx:0.5,yy:0.5,x:10.25,y:20.75}.compose(
			VisualTransform{rotation:45,origin_x:50,origin_y:50}.matrix(rect(0,0,100,100))!)
		clip := transformed_clip(rect(0,0,100,60),ContentTransform{xx:0.5,yy:0.5,x:10.25,y:20.75})
		g_gg_app.ctx = &DrawContext{content_transform:transform,clip_base:clip,scale:1.5}
		defer { g_gg_app.ctx=previous; g_hit_targets=previous_hits.clone() }
		g_hit_targets=[]HitTarget{}
		geometry := image_geometry(rect(0,0,100,100),LayoutSize{width:100,height:100},ImageStyle{})!
		add_hit_target(HitTarget{id:'image',w:100,h:100,is_image:true,image_geometry:geometry},rect(-100,-100,300,300))
		assert hit_test(35.25,45.75).id=='image'
		target := g_hit_targets[0]
		tip := TooltipTarget{key:'image',text:'visible quad',frame:rect(target.x,target.y,target.w,target.h),
			local_frame:target.local_frame,content_transform:transform,clip_region:clip,has_geometry:true,
			is_image:true,image_geometry:geometry}
		assert tooltip_target_at([tip],35.25,45.75).text=='visible quad'
		for p in [Point{12.75,23.25},Point{5.25,15.75},Point{35.25,60.75}] {
			assert tooltip_target_at([tip],p.x,p.y).text==''
			assert hit_test(p.x,p.y).id==''
		}
		g_gg_app.ctx.content_transform=ContentTransform{xx:0.5,yy:0.5,x:10.25,y:20.75}
		// A later rectangle still wins in reverse paint order.
		add_hit_target(HitTarget{ id: 'front', x: 40, y: 40, w: 20, h: 20 }, rect(0, 0, 100, 100))
		assert hit_test(35.25, 45.75).id == 'front'
	}
}
