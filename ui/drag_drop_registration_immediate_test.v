// vtest build: macos && ui2_custom_rendering? && ui2_embedder? && !ui2_headless?
// vtest vflags: -d ui2_custom_rendering -d ui2_embedder
// Real render_element traversal/registration with a Metal drawing context.
// No native input injection or window/swapchain is needed for hit dispatch.
@[has_globals]
module ui2

$if macos && ui2_custom_rendering ? && ui2_embedder ? && !ui2_headless ? {
	import gg
	import os
	import sokol.gfx
	import sokol.sgl

	__global registration_drag_events = []ElementEvent{}
	fn registration_drag_record(event ElementEvent) { registration_drag_events << event }
	fn registration_drag_accept(_ DragOffer) DragOperation { return .move }

	fn registration_drag_surface(kind Kind, anonymous bool, source bool, x f64) Element {
		id := if anonymous { '' } else { if source { 'registered-source' } else { 'registered-target' } }
		base := with_event(Element{kind: kind, id: id, frame: rect(x, 20, 40, 40),
			image_path:if kind==.image { os.join_path(@VMODROOT,'examples','image_assets','assets','variant1.png') } else { '' },
			box: BoxStyle{transparent: true},image_asset:if kind==.image { ImageAsset{logical_size:LayoutSize{width:32,height:16}} } else { ImageAsset{} }}, registration_drag_record)
		return if source { with_drag_source(base, DragSource{}) }
			else { with_drop_target(base, DropTarget{accept: registration_drag_accept}) }
	}
	fn registration_drag_tree(kind Kind, anonymous bool, source bool, depth int, enabled bool, hidden bool) Element {
		mut branch := registration_drag_surface(kind, anonymous, source, if source { 10.0 } else { 100.0 })
		for index in 0 .. if depth > 0 { depth } else { 0 } {
			branch = view('ancestor-${index}', rect(0, 0, 200, 100), BoxStyle{transparent: true}, [branch])
		}
		if depth >= 0 { branch = Element{...branch, enabled: enabled, hidden: hidden} }
		other := registration_drag_surface(.view, false, !source, if source { 100.0 } else { 10.0 })
		return Element{...screen(0, [branch, other]), box: BoxStyle{transparent: true},
			enabled: if depth < 0 { enabled } else { true }, hidden: depth < 0 && hidden}
	}
	fn registration_drag_render(ctx &DrawContext, root Element) {
		g_gg_app.declared_root = root
		g_gg_app.has_root = true
		g_gg_app.declaration_pending=true
		assert sync_custom_input_geometry(custom_input_dispatch(g_gg_app))
		sgl.defaults()
		render_element(ctx, root, 0, 0, rect(0, 0, 300, 100), '', 'root')
		assert sgl.error() == .no_error
	}
	fn registration_drag_reset(ctx &DrawContext) {
		g_gg_app = &GgApp{ctx: unsafe { ctx }}
		g_touch = TouchState{}
		g_drag_registry = DragRegistry{}
		g_build_screen = unsafe { nil }
		g_tooltip = TooltipState{}
		g_tooltip_targets.clear()
		g_tooltip_owners = 0
		set_menu_bar([]Menu{})
		reset_scroll_frame()
		close_dropdown()
		registration_drag_events.clear()
		work := g_gg_app.scheduler.begin_frame(0) or { panic('missing mount') }
		g_gg_app.scheduler.finish_frame(work)
	}
	fn test_actual_renderer_excludes_disabled_or_hidden_drag_ancestry_and_remounts() {
		mut ctx := new_surface_draw_context(gg.Config{width: 300, height: 100}, gfx.Environment{
			defaults: gfx.EnvironmentDefaults{color_format: .bgra8, depth_format: .@none, sample_count: 1},
			metal: gfx.MetalEnvironment{device: C.ui2_embedder_metal_device()}})!
		defer { ctx.destroy() }
		for kind in [Kind.view, .image] {
			for anonymous in [false, true] {
				for source in [false, true] {
					for depth in [-1, 0, 5] {
						for hidden in [false, true] {
							registration_drag_reset(ctx)
							eligible := registration_drag_tree(kind, anonymous, source, depth, true, false)
							registration_drag_render(ctx, eligible)
							x := if source { 20.0 } else { 120.0 }
							owner := hit_test(x, 30)
							assert owner.drag_generation > 0
							assert (owner.drag_source != none) == source
							ineligible := registration_drag_tree(kind, anonymous, source, depth, hidden, hidden)
							registration_drag_render(ctx, ineligible)
							assert hit_test(x, 30).on_event == unsafe { nil }
							// A press beginning in the disabled/hidden subtree cannot
							// turn into a tap, capture, raw move or drag lifecycle.
							for moved in [false, true] {
								handle_touch_down(x, 30)
								assert !g_touch.pointer_captured && !g_touch.drag.pending
								if moved { handle_touch_move(x + 15, 30) }
								handle_touch_up(x, 30)
								assert registration_drag_events.len == 0
							}
							registration_drag_render(ctx, eligible)
							assert hit_test(x, 30).drag_generation != owner.drag_generation
							handle_touch_down(20, 30)
							handle_touch_up(120, 30)
							assert registration_drag_events.filter(it.kind == .drop).len == 1
							assert registration_drag_events.filter(it.kind == .drag_cancel).len == 0
							assert !g_touch.pointer_captured && !drag_active()
							registration_drag_events.clear()
							handle_touch_down(x, 30)
							handle_touch_up(x, 30)
							assert registration_drag_events.map(it.kind) == [.tap]
							println('RENDER ancestry kind=${kind} anonymous=${anonymous} source=${source} depth=${depth} hidden=${hidden} PASS')
						}
					}
				}
			}
		}
	}
	fn test_actual_renderer_dynamic_disable_cancels_capture_without_tap_and_preserves_blockers() {
		mut ctx := new_surface_draw_context(gg.Config{width: 300, height: 100}, gfx.Environment{
			defaults: gfx.EnvironmentDefaults{color_format: .bgra8, depth_format: .@none, sample_count: 1},
			metal: gfx.MetalEnvironment{device: C.ui2_embedder_metal_device()}})!
		defer { ctx.destroy() }
		for kind in [Kind.view, .image] {
			for anonymous in [false, true] {
				for source in [false, true] {
					for active in [false, true] {
						registration_drag_reset(ctx)
						eligible := registration_drag_tree(kind, anonymous, source, 5, true, false)
						registration_drag_render(ctx, eligible)
						handle_touch_down(20, 30)
						if active { handle_touch_move(120, 30) }
						registration_drag_render(ctx, registration_drag_tree(kind, anonymous, source, 5, false, false))
						if active { handle_touch_move(120, 30) }
						handle_touch_up(if active { 120.0 } else { 20.0 }, 30)
						assert registration_drag_events.filter(it.kind == .drop).len == 0
						assert registration_drag_events.filter(it.kind == .tap).len == if !active && !source { 1 } else { 0 }
						assert registration_drag_events.filter(it.kind == .drag_cancel).len == if active { 1 } else { 0 }
						assert !g_touch.pointer_captured && !drag_active()
					}
				}
			}
		}
		registration_drag_reset(ctx)
		root := registration_drag_tree(.view, false, true, 5, true, false)
		// A role-free eligible View remains a normal interactive top blocker.
		blocker := with_event(Element{kind: .view, id: 'ordinary', frame: rect(100, 20, 40, 40),
			box: BoxStyle{transparent: true}, button_behavior: true}, registration_drag_record)
		registration_drag_render(ctx, Element{...root, children: [root.children[0], root.children[1], blocker]})
		handle_touch_down(20, 30)
		handle_touch_up(120, 30)
		assert registration_drag_events.filter(it.kind == .drop).len == 0
		assert registration_drag_events.filter(it.kind == .drag_cancel).len == 1
		registration_drag_events.clear()
		handle_touch_down(120, 30)
		handle_touch_up(120, 30)
		assert registration_drag_events.map(it.kind) == [.tap]
	}

	fn test_selected_image_asset_validity_controls_current_pointer_and_drop_eligibility() {
		mut ctx := new_surface_draw_context(gg.Config{width:300,height:100},gfx.Environment{
			defaults:gfx.EnvironmentDefaults{color_format:.bgra8,depth_format:.@none,sample_count:1},
			metal:gfx.MetalEnvironment{device:C.ui2_embedder_metal_device()}})!
		defer { ctx.destroy() }
		ctx.scale=1
		folder:=os.join_path(@VMODROOT,'examples','image_assets','assets')
		base:=os.join_path(folder,'variant1.png')
		valid:=os.join_path(folder,'variant2.png')
		corrupt:=os.join_path(os.temp_dir(),'ui2-image-eligibility-${os.getpid()}.png')
		os.write_file(corrupt,'not an image')!
		defer { os.rm(corrupt) or {} }
		source:=registration_drag_surface(.view,false,true,10)
		underneath:=with_event(with_drop_target(view('underneath',rect(100,20,64,32),BoxStyle{},[]),
			DropTarget{accept:registration_drag_accept}),registration_drag_record)
		for selected in [os.join_path(folder,'missing-selected-image.png'),corrupt,base,valid] {
			registration_drag_reset(ctx)
			selected_image:=with_event(with_drop_target(Element{...image('selected-image',base,rect(100,20,64,32)),
				clickable:true,image_asset:ImageAsset{logical_size:LayoutSize{width:32,height:16},
					variants:[ImageVariant{path:selected,density:2}]}},DropTarget{accept:registration_drag_accept}),registration_drag_record)
			root:=screen(0,[source,underneath,selected_image])
			registration_drag_render(ctx,root)
			available:=selected==valid
			expected:=if available { 'selected-image' } else { 'underneath' }
			assert hit_test(120,30).id==expected
			assert drag_destination(120,30).id==expected
			assert ('id:selected-image' in g_drag_registry.owners)==available
			handle_touch_down(120,30); handle_touch_up(120,30)
			assert registration_drag_events.map(it.kind)==if available {
				[ElementEventKind.pointer_down,.pointer_up]
			} else { [ElementEventKind.tap] }
			assert registration_drag_events.all(it.id==expected)
			registration_drag_events.clear()
			handle_touch_down(20,30); handle_touch_up(120,30)
			drops:=registration_drag_events.filter(it.kind==.drop)
			assert drops.len==1 && drops[0].id==expected
			assert !g_touch.pointer_captured && !drag_active()
		}
		// An already captured image also loses eligibility when the selected
		// variant changes to an unavailable one before the next rendered frame.
		registration_drag_reset(ctx)
		image_source:=with_event(with_drag_source(Element{...image('image-source',base,rect(10,20,64,32)),
			image_asset:ImageAsset{logical_size:LayoutSize{width:32,height:16},
				variants:[ImageVariant{path:valid,density:2}]}},DragSource{}),registration_drag_record)
		registration_drag_render(ctx,screen(0,[image_source,underneath]))
		handle_touch_down(20,30); handle_touch_move(120,30)
		assert drag_active()
		missing_source:=Element{...image_source,image_asset:ImageAsset{logical_size:LayoutSize{width:32,height:16},
			variants:[ImageVariant{path:os.join_path(folder,'missing-selected-image.png'),density:2}]}}
		g_gg_app.declared_root=screen(0,[missing_source,underneath])
		g_gg_app.declaration_pending=true
		handle_touch_up(120,30)
		assert registration_drag_events.filter(it.kind==.drop).len==0
		cancels:=registration_drag_events.filter(it.kind==.drag_cancel)
		assert cancels.len==1 && (cancels[0].drag or { panic('cancel') }).reason==.source_removed
		assert !g_touch.pointer_captured && !drag_active()
	}
}
