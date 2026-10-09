// vtest vflags: -d ui2_custom_rendering -d ui2_embedder
// Common mounted layout/hit producers and synthetic host input; no OS input.
// vfmt off
@[has_globals]
module ui2

$if macos && ui2_custom_rendering ? && ui2_embedder ? && !ui2_headless ? {
	import gg
	import os
	import sokol.gfx
	__global graphics_drag_context = &DrawContext(unsafe { nil })
	__global graphics_drag_stage = ''
	__global graphics_drag_change = ''
	__global graphics_drag_mutated = false
	__global graphics_drag_queries = 0
	__global graphics_drag_events = []ElementEvent{}

	fn graphics_drag_mutate() {
		if graphics_drag_mutated { return }
		graphics_drag_mutated=true
		match graphics_drag_change {
			'blur' { reset_custom_keyboard() }
			'switch' { previous:=activate_custom_window_state(new_custom_window_state()); activate_custom_window_state(previous) }
			'switch_stay' { activate_custom_window_state(new_custom_window_state()) }
			'quit' { quit() }
			'restart' { cancel_drag(); handle_touch_down(20,30) }
			else { refresh() }
		}
	}
	fn graphics_drag_accept(_ DragOffer) DragOperation {
		graphics_drag_queries++
		if graphics_drag_stage=='accept' && graphics_drag_queries==3 { graphics_drag_mutate() }
		return .move
	}
	fn graphics_drag_record(event ElementEvent) {
		graphics_drag_events << event
		if (graphics_drag_stage=='enter' && event.kind==.drag_enter)
			|| (graphics_drag_stage=='over' && event.kind==.drag_over)
			|| (graphics_drag_stage=='drop' && event.kind==.drop) { graphics_drag_mutate() }
	}
	fn graphics_drag_build() Element {
		source := with_event(with_drag_source(view('seam-source',rect(10,20,40,40),BoxStyle{},[]),DragSource{}),graphics_drag_record)
		mut target := view('seam-target',rect(100,20,100,100),BoxStyle{},[])
		if graphics_drag_change in ['image_fit','image_tint'] {
			target=Element{...image('seam-target',os.join_path(@VMODROOT,'examples','image_assets','assets','variant1.png'),target.frame),
				image_asset:ImageAsset{logical_size:LayoutSize{width:32,height:16}},
				image_style:ImageStyle{align_y:if graphics_drag_mutated && graphics_drag_change=='image_fit' { 1.0 } else { 0.5 },
					tint:if graphics_drag_mutated { ImageTint{r:7,g:17,b:27} } else { ImageTint{} }}}
		} else {
			points := if graphics_drag_mutated && graphics_drag_change=='vector' {
				[vector_point(0,0),vector_point(10,0),vector_point(10,10),vector_point(0,10)]
			} else { [vector_point(0,0),vector_point(100,0),vector_point(100,30),vector_point(30,30),vector_point(30,100),vector_point(0,100)] }
			shape := prepare_vector_shape(vector_polygon(points),VectorStyle{fill:if graphics_drag_mutated { u32(0x009933) } else { u32(0x3388ff) }}) or { panic(err) }
			target=Element{...target,is_vector_canvas:true,vector_shapes:[shape]}
		}
		target=with_event(with_drop_target(target,DropTarget{accept:graphics_drag_accept}),graphics_drag_record)
		return screen(0xffffff,[source,target,rich_label('caption',[TextRun{text:if graphics_drag_mutated { 'niño / café' } else { 'Move' }}],rect(10,150,220,30),TextStyle{})])
	}
	fn graphics_drag_mount(stage string, change string) {
		activate_custom_window_state(new_custom_window_state())
		g_gg_app=&GgApp{ctx:graphics_drag_context}
		graphics_drag_stage=stage
		graphics_drag_change=change
		graphics_drag_mutated=false
		graphics_drag_queries=0
		graphics_drag_events=[]ElementEvent{}
		g_build_screen=graphics_drag_build
		assert build_custom_declaration(mut g_gg_app,true)
		assert sync_custom_input_geometry(custom_input_dispatch(g_gg_app))
		work:=g_gg_app.scheduler.begin_frame(0) or { panic('mount') }
		g_gg_app.scheduler.finish_frame(work)
	}
	fn test_common_vector_image_narrow_phase_current_release_and_paint_only_callbacks() {
		mut ctx:=new_surface_draw_context(gg.Config{width:320,height:240},gfx.Environment{
			defaults:gfx.EnvironmentDefaults{color_format:.bgra8,depth_format:.@none,sample_count:1},
			metal:gfx.MetalEnvironment{device:C.ui2_embedder_metal_device()}})!
		graphics_drag_context=ctx
		defer { graphics_drag_context=unsafe { nil }; ctx.destroy() }
		for stage in ['enter','over','accept'] {
			for change in ['paint','vector','image_fit','image_tint'] {
				graphics_drag_mount(stage,change)
				handle_touch_down(20,30)
				handle_touch_up(120,if change.starts_with('image') { 60.0 } else { 30.0 })
				assert graphics_drag_mutated
				valid:=change in ['paint','image_tint']
				assert graphics_drag_events.filter(it.kind==.drop).len==if valid { 1 } else { 0 }, '${stage}/${change}'
				assert graphics_drag_events.filter(it.kind==.drag_cancel).len==if valid { 0 } else { 1 }
				assert !g_touch.down && !g_touch.pointer_captured && !drag_active()
				assert graphics_drag_events.filter(it.kind==.tap).len==0 && g_gg_app.scheduler.stats().draws==0
			}
		}
		// Same concave mesh membership for fresh pointer/hover/drop and ancestor clip.
		graphics_drag_mount('','paint')
		target:=g_drag_registry.owners['id:seam-target']
		assert hit_test(110,100).id==target.id && drag_destination(110,100).id==target.id
		assert hit_test(160,80).id=='' && drag_destination(160,80).id==''
		target_node:=g_focus_navigation.node(target.id) or { panic('target') }
		pane:=with_transform(scroll('rotated-pane',rect(100,20,80,80),0xffffff,[Element{...target_node.el,frame:rect(0,0,100,100)}]),
			VisualTransform{rotation:45,origin_x:40,origin_y:40})
		update_custom_focus_tree(pane)
		mounted:=g_drag_registry.owners['id:seam-target']
		inside:=mounted.content_transform.point(mounted.local_frame.x+10,mounted.local_frame.y+70)
		clipped:=mounted.content_transform.point(mounted.local_frame.x+10,mounted.local_frame.y+90)
		hole:=mounted.content_transform.point(mounted.local_frame.x+60,mounted.local_frame.y+60)
		assert hit_test(inside.x,inside.y).id==mounted.id && drag_destination(inside.x,inside.y).id==mounted.id
		assert hit_test(clipped.x,clipped.y).id=='' && drag_destination(clipped.x,clipped.y).id==''
		assert hit_test(hole.x,hole.y).id=='' && drag_destination(hole.x,hole.y).id==''
		println('common concave/exact-clip/image-fit membership and current release passed (synthetic input)')
	}
	fn test_drag_callbacks_revalidate_window_input_token_and_preserve_nested_capture() {
		for stage in ['enter','over','accept'] {
			for change in ['blur','switch','quit','restart'] {
				graphics_drag_mount(stage,change)
				handle_touch_down(20,30)
				token:=g_touch.drag.token
				handle_touch_up(120,30)
				assert graphics_drag_mutated
				assert graphics_drag_events.filter(it.kind==.drop || it.kind==.tap).len==0
				assert graphics_drag_events.filter(it.kind==.drag_cancel).len==1, '${stage}/${change}'
				if change=='restart' {
					assert g_touch.down && g_touch.pointer_captured && g_touch.drag.pending && g_touch.drag.token!=token
					cancel_drag()
				} else { assert !g_touch.down && !g_touch.pointer_captured && !drag_active() }
				count:=graphics_drag_events.len
				handle_touch_up(120,30); cancel_drag()
				assert graphics_drag_events.len==count
			}
		}
		graphics_drag_mount('drop','restart')
		handle_touch_down(20,30); handle_touch_up(120,30)
		assert graphics_drag_events.filter(it.kind==.drop).len==1
		assert graphics_drag_events.filter(it.kind==.drag_end).len==0
		assert g_touch.down && g_touch.drag.pending
		cancel_drag()
		println('enter/over/accept/drop reentry, quit, blur, window switch and single capture retirement passed (synthetic host)')
	}
	fn test_over_switch_without_restoring_window_retires_owning_snapshot_capture() {
		graphics_drag_mount('over','switch_stay')
		first:=g_active_custom_window_state
		handle_touch_down(20,30)
		handle_touch_move(120,30)
		assert g_active_custom_window_state!=first
		assert !first.touch.down && !first.touch.pointer_captured && !g_touch.down
		count:=graphics_drag_events.len
		activate_custom_window_state(first)
		assert !drag_active() && !g_touch.down
		handle_touch_up(120,30)
		assert graphics_drag_events.len==count && graphics_drag_events.filter(it.kind==.drop || it.kind==.tap).len==0
	}

	fn test_current_dropdown_row_font_geometry_comes_from_mounted_producer() {
		graphics_drag_mount('','paint')
		base:=Element{kind:.dropdown,id:'popup',frame:rect(240,10,100,30),menu:[MenuEntry{title:'one'},MenuEntry{title:'two'}],text_style:TextStyle{size:12}}
		g_open_dropdown='popup'
		update_custom_focus_tree(base)
		before:=g_hit_targets.filter(it.dropdown_option)
		assert before.len==2
		update_custom_focus_tree(Element{...base,text_style:TextStyle{size:30}})
		after:=g_hit_targets.filter(it.dropdown_option)
		assert after.len==2 && after[0].local_frame.height>before[0].local_frame.height
		assert after[1].local_frame.y==after[0].local_frame.y+after[0].local_frame.height
		for row in after {
			hit:=hit_test(row.x+row.w/2,row.y+row.h/2)
			assert hit.dropdown_option && hit.option_index==row.option_index
		}
		close_dropdown()
	}
}
