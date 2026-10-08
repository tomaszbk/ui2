// vtest vflags: -d ui2_custom_rendering
// vfmt off
@[has_globals]
module ui2

$if (android || linux || ((macos || windows) && ui2_custom_rendering ?)) && !ui2_headless ? {
	fn vector_test_shape() VectorShape {
		return prepare_vector_shape(vector_polygon([vector_point(0,0), vector_point(20,0),
			vector_point(20,5), vector_point(5,5), vector_point(5,20), vector_point(0,20)]),
			VectorStyle{fill:0x336699}) or { panic(err) }
	}

	fn test_vector_hits_share_scaled_content_inverse_and_clip() {
		old_app := g_gg_app
		old_targets := g_hit_targets.clone()
		defer { g_gg_app = old_app; g_hit_targets = old_targets.clone() }
		g_gg_app = &GgApp{ctx: &DrawContext{content_transform: ContentTransform{scale:2,x:10,y:20},scale:1}}
		g_hit_targets = []HitTarget{}
		// Frame (3,4)..(23,24), clipped at local x=13. No duplicate coordinate math.
		add_hit_target(HitTarget{id:'shape',x:3,y:4,w:20,h:20,vector_origin:rect(3,4,20,20),vector_shapes:[vector_test_shape()]},rect(0,0,13,40))
		assert hit_test(20, 54).id == 'shape' // shape-local (2,13)
		assert hit_test(34, 46).id == '' // shape-local (9,9), in bounds, outside concave fill
		assert hit_test(48, 32).id == '' // inside painted top arm, outside ancestor clip
		assert hit_test(36, 32).id == 'shape' // exact clip boundary is inclusive for pointers
		assert hit_test(36.001,32).id == ''
		for dpi in [f32(1),1.25,1.5,2] {
			g_gg_app.ctx.scale = dpi
			assert hit_target_contains(g_hit_targets[0],20,54)
			assert !hit_target_contains(g_hit_targets[0],34,46)
		}
	}

	fn test_hole_passes_to_lower_target_and_tooltip_hover_uses_shape() {
		old_app := g_gg_app
		old_targets := g_hit_targets.clone()
		old_tooltips := g_tooltip_targets.clone()
		old_tooltip := g_tooltip
		defer { g_gg_app=old_app; g_hit_targets=old_targets.clone(); g_tooltip_targets=old_tooltips.clone(); g_tooltip=old_tooltip }
		g_gg_app = &GgApp{}
		g_hit_targets = [HitTarget{id:'lower',w:20,h:20}]
		add_hit_target(HitTarget{id:'upper',w:20,h:20,vector_shapes:[vector_test_shape()]},rect(0,0,20,20))
		assert hit_test(2,10).id == 'upper'
		assert hit_test(10,10).id == 'lower'
		el := vector_canvas(id:'upper',frame:rect(0,0,20,20),shapes:[vector_test_shape()],tooltip:'shape')!
		g_tooltip_targets = []TooltipTarget{}
		add_element_tooltip('upper','shape',el,el.frame,el.frame)
		assert tooltip_target_at(g_tooltip_targets,2,10).text == 'shape'
		assert tooltip_target_at(g_tooltip_targets,10,10).text == ''
		g_tooltip = TooltipState{pointer_in:true,pointer_x:10,pointer_y:10}
		assert !vector_element_contains(el,el.frame,10,10)
		assert vector_element_contains(el,el.frame,2,10)
		// A culled sibling cannot attach geometry to the preceding tooltip.
		add_element_tooltip('culled','culled',el,rect(40,40,20,20),rect(0,0,20,20))
		assert g_tooltip_targets.len == 1
		assert tooltip_target_at(g_tooltip_targets,2,10).text == 'shape'
		// Opaque vector paint with no tooltip still hides an underlying tooltip;
		// empty corners of its geometry leave the lower target visible.
		opaque := Element{...el,tooltip:''}
		assert tooltip_hides_beneath(opaque)
		g_tooltip_targets = [TooltipTarget{key:'lower',text:'lower tooltip',frame:el.frame}]
		add_element_tooltip('','',opaque,el.frame,el.frame)
		assert tooltip_target_at(g_tooltip_targets,2,10).text == ''
		assert tooltip_target_at(g_tooltip_targets,10,10).text == 'lower tooltip'
	}

	fn test_shape_geometry_replacement_moves_current_hits_without_mutating_snapshot() {
		shape := vector_test_shape()
		original := HitTarget{id:'shape',w:20,h:20,vector_shapes:[shape]}
		moved := HitTarget{...original,x:100,vector_origin:rect(100,0,20,20)}
		assert hit_target_contains(original,2,10)
		assert !hit_target_contains(moved,2,10)
		assert hit_target_contains(moved,102,10)
		assert !hit_target_contains(moved,110,10)
		assert shape.paint_bounds() == rect(0,0,20,20)
	}

	fn test_empty_canvas_does_not_fall_back_to_view_bounds() {
		old_app := g_gg_app
		old_targets := g_hit_targets.clone()
		old_tooltips := g_tooltip_targets.clone()
		defer { g_gg_app=old_app; g_hit_targets=old_targets.clone(); g_tooltip_targets=old_tooltips.clone() }
		g_gg_app = &GgApp{}
		for mode in [VectorHitMode.paint,.fill,.stroke,.bounds] {
			el := vector_canvas(id:'empty',frame:rect(0,0,20,20),hit_mode:mode,tooltip:'empty')!
			g_hit_targets = [HitTarget{id:'lower',w:20,h:20}]
			add_hit_target(HitTarget{id:'empty',w:20,h:20,is_vector_canvas:el.is_vector_canvas,
				vector_shapes:el.vector_shapes,vector_hit_mode:mode},el.frame)
			assert hit_test(10,10).id == 'lower'
			assert !vector_element_contains(el,el.frame,10,10)
			g_tooltip_targets = [TooltipTarget{key:'lower',text:'lower tooltip',frame:el.frame}]
			add_element_tooltip('empty','empty',el,el.frame,el.frame)
			assert tooltip_target_at(g_tooltip_targets,10,10).text == 'lower tooltip'
		}
	}

	fn test_round_stroke_excluded_geometry_passes_hits_and_tooltips_through() {
		old_app := g_gg_app
		old_targets := g_hit_targets.clone()
		old_tooltips := g_tooltip_targets.clone()
		defer { g_gg_app=old_app; g_hit_targets=old_targets.clone(); g_tooltip_targets=old_tooltips.clone() }
		g_gg_app = &GgApp{ctx:&DrawContext{content_transform:ContentTransform{scale:1.75,x:10.25,y:20.5},scale:1}}
		for variant in 0 .. 7 {
			mut path := VectorPath{}
			path.move_to(10,10)
			path.line_to(if variant == 4 || variant == 5 { 10.1 } else { 11.0 },10)
			end := match variant {
				0 { vector_point(30,10) }
				1 { vector_point(11,11) }
				2 { vector_point(11,9) }
				4, 5 { vector_point(10.1,20) }
				else { vector_point(10,10) }
			}
			path.line_to(end.x,end.y)
			if variant == 5 {
				// Reverse the short angle so its short segment is at the end cap.
				path = VectorPath{}
				path.move_to(10.1,20)
				path.line_to(10.1,10)
				path.line_to(10,10)
			}
			cap := if variant >= 4 { VectorCap.round } else { VectorCap.butt }
			join := if variant >= 4 { VectorJoin.bevel } else { VectorJoin.round }
			shape := prepare_vector_shape(path,VectorStyle{stroke:0,stroke_width:4,cap:cap,join:join,tolerance:0.001})!
			excluded := match variant {
				1 { vector_point(9.5,9.5) }
				2 { vector_point(9.5,10.5) }
				4, 5 { vector_point(11.3,8.7) }
				6 { vector_point(11.5,10) }
				else { vector_point(9.5,10) }
			}
			painted := match variant {
				0 { vector_point(20,10) }
				1 { vector_point(12.3,8.7) }
				2 { vector_point(12.3,11.3) }
				4, 5 { vector_point(10.1,21.5) }
				6 { vector_point(8.5,10) }
				else { vector_point(12.8,10) }
			}
			for mode in [VectorHitMode.paint,.stroke] {
				el := vector_canvas(id:'upper',frame:rect(3,4,40,40),shapes:[shape],hit_mode:mode,tooltip:'stroke')!
				g_hit_targets = []HitTarget{}
				add_hit_target(HitTarget{id:'lower',x:3,y:4,w:40,h:40},rect(0,0,100,100))
				add_hit_target(HitTarget{id:'upper',x:3,y:4,w:40,h:40,is_vector_canvas:true,
					vector_origin:el.frame,vector_shapes:el.vector_shapes,vector_hit_mode:mode},rect(0,0,100,100))
				g_tooltip_targets = []TooltipTarget{}
				add_tooltip_target('lower','lower tooltip',el.frame,rect(0,0,100,100))
				add_element_tooltip('upper','stroke',el,el.frame,rect(0,0,100,100))
				for dpi in [f32(1),1.25,1.5,2] {
					g_gg_app.ctx.scale = dpi
					// Window coordinates include the canvas origin and content transform.
					ex := 10.25 + 1.75 * (3 + excluded.x)
					ey := 20.5 + 1.75 * (4 + excluded.y)
					px := 10.25 + 1.75 * (3 + painted.x)
					py := 20.5 + 1.75 * (4 + painted.y)
					assert hit_test(ex,ey).id == 'lower'
					assert tooltip_target_at(g_tooltip_targets,ex,ey).text == 'lower tooltip'
					assert hit_test(px,py).id == 'upper'
					assert tooltip_target_at(g_tooltip_targets,px,py).text == 'stroke'
				}
			}
		}
	}

	fn test_cleanup_releases_retained_vector_target_references() {
		old_app := g_gg_app
		defer { g_gg_app=old_app }
		shape := vector_test_shape()
		g_gg_app = &GgApp{has_root:true,declared_root:vector_canvas(frame:rect(0,0,20,20),shapes:[shape])!}
		g_hit_targets = [HitTarget{vector_shapes:[shape],w:20,h:20}]
		g_tooltip_targets = [TooltipTarget{vector_shapes:[shape],frame:rect(0,0,20,20)}]
		g_touch = TouchState{pointer_captured:true,pointer_target:g_hit_targets[0]}
		on_cleanup(g_gg_app)
		assert g_hit_targets.len == 0
		assert g_tooltip_targets.len == 0
		assert g_touch.pointer_target.vector_shapes.len == 0
		assert g_gg_app.declared_root.vector_shapes.len == 0
		assert !g_gg_app.has_root
		assert g_gg_app.scheduler.is_closed()
	}
}

fn test_vector_geometry_is_prepared_before_frames() {
	shape := prepare_vector_shape(vector_polygon([vector_point(0,0),vector_point(10,0),vector_point(0,10)]),VectorStyle{fill:0})!
	assert shape.fill_triangles.len > 0
	assert shape.stroke_triangles.len == 0
}
