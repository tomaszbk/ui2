// vtest vflags: -d ui2_custom_rendering -d ui2_embedder -d ui2_geometry_capture
// vfmt off
@[has_globals]
module ui2

$if !gcboehm ? {
	$compile_error('Exact clip fixtures require normal Boehm GC')
}

$if macos && ui2_custom_rendering ?&& ui2_embedder ?&& ui2_geometry_capture ?&& !ui2_headless ? {
	import gg
	import math
	import sokol.gfx
	import sokol.sgl
	__global dropdown_clip_vertices = []PaintVertex{}

	fn observe_dropdown_clip_polygon(vertices []PaintVertex) {
		dropdown_clip_vertices << vertices
	}

	fn dropdown_clip_environment() gfx.Environment {
		return gfx.Environment{
			defaults: gfx.EnvironmentDefaults{ color_format: .bgra8, depth_format: .@none, sample_count: 1 }
			metal: gfx.MetalEnvironment{ device: C.ui2_embedder_metal_device() }
		}
	}

	fn dropdown_clip_control(id string, frame Rect) Element {
		return with_interaction_style(with_tooltip(dropdown(id, 'Uno', ['Uno', 'Dos'], frame,
			BoxStyle{ bg: 0x204080 }, TextStyle{}), 'Elige'), InteractionStyle{
			hover: BoxStylePatch{ bg: u32(0x00a070) }
		})
	}

	fn dropdown_clip_click(mut w Window, point Point) {
		on_event(&gg.Event{ typ: .mouse_down, mouse_x: f32(point.x), mouse_y: f32(point.y) }, mut w)
		on_event(&gg.Event{ typ: .mouse_up, mouse_x: f32(point.x), mouse_y: f32(point.y) }, mut w)
	}
}

fn test_rotated_dropdown_popup_closes_when_exact_owner_clip_becomes_empty() {
	$if macos && ui2_custom_rendering ?&& ui2_embedder ?&& ui2_geometry_capture ?&& !ui2_headless ? {
		mut ctx := new_surface_draw_context(gg.Config{ width: 320, height: 240 }, dropdown_clip_environment())!
		window := C.ui2_embedder_create(&C.ui2_embedder_config{ title: c'Dropdown exact clip fixture', width: 320, height: 240, visible: false }, &C.ui2_embedder_callbacks{}, unsafe { nil })
		assert window != unsafe { nil }
		defer {
			C.ui2_embedder_close(window)
			ctx.destroy()
			dropdown_clip_vertices.clear()
		}
		owner := with_transform(dropdown_clip_control('owner', rect(95, 95, 10, 10)),
			VisualTransform{ rotation: 45, origin_x: 5, origin_y: 5, translate_x: -6, translate_y: -50 })
		mut w := &Window{
			ctx: ctx, native_window: window, has_root: true
			declared_root: screen(0xffffff, [scroll('pane', rect(0, 0, 100, 100), 0xeeeeee, [owner])])
		}
		ctx.submitted_polygon = observe_dropdown_clip_polygon
		on_frame(mut w)
		visible := Point{87.5, 50}
		clipped := Point{100.5, 50}
		boundary := Point{100, 50}
		assert w.visual_geometry('owner')!.contains(visible.x, visible.y)
		assert !w.visual_geometry('owner')!.contains(clipped.x, clipped.y)
		assert w.hit_test(visible.x, visible.y).id == 'owner'
		assert w.hit_test(clipped.x, clipped.y).id != 'owner'
		assert w.visual_geometry('owner')!.contains(boundary.x, boundary.y)
		assert w.hit_test(boundary.x, boundary.y).id == 'owner'
		assert tooltip_target_at(w.tooltip_targets, visible.x, visible.y).key == 'dropdown#owner'
		assert tooltip_target_at(w.tooltip_targets, clipped.x, clipped.y).key == ''
		assert tooltip_target_at(w.tooltip_targets, boundary.x, boundary.y).key == 'dropdown#owner'
		on_event(&gg.Event{ typ: .mouse_move, mouse_x: 87.5, mouse_y: 50 }, mut w)
		dropdown_clip_vertices.clear()
		on_frame(mut w)
		assert dropdown_clip_vertices.any(it.r == 0 && it.g == 160 && it.b == 112)
		dropdown_clip_click(mut w, visible)
		on_frame(mut w)
		assert w.dropdown_id == 'owner' && w.dropdown_popup.mounted
		assert w.hit_targets.any(it.dropdown_option)
		old_option := Point{w.dropdown_popup.x + w.dropdown_popup.width / 2,
			w.dropdown_popup.y + dropdown_popup_padding + w.dropdown_popup.row_height * 1.5}
		assert w.hit_test(old_option.x, old_option.y).dropdown_option
		captured := w.hit_targets.filter(it.dropdown && !it.dropdown_option)[0]

		w.set_visual_transform('owner', VisualTransform{ rotation: 45, origin_x: 5, origin_y: 5,
			translate_x: 10, translate_y: -50 })!
		dropdown_clip_vertices.clear()
		on_frame(mut w)
		hidden := w.visual_geometry('owner')!
		// Original review geometry: inverse AABB contains the complete logical
		// owner despite the diamond's leftmost x being greater than 100.
		broad := hidden.transform.inverse_rect(rect(0, 0, 100, 100))
		assert intersect_rect(hidden.frame, broad) == hidden.frame
		assert hidden.bounds() == Rect{}
		assert !hidden.contains(110, 50)
		assert w.dropdown_id == '' && !w.dropdown_popup.mounted
		assert !w.hit_targets.any(it.dropdown_option)
		assert w.current_pointer_target(captured) != none
		assert !dropdown_clip_vertices.any(it.r == 32 && it.g == 64 && it.b == 128)
		assert !dropdown_clip_vertices.any(it.r == 0 && it.g == 160 && it.b == 112)
		assert w.hit_test(110, 50).id != 'owner'
		assert tooltip_target_at(w.tooltip_targets, 110, 50).key == ''
		dropdown_clip_click(mut w, Point{110, 50})
		dropdown_clip_click(mut w, old_option)
		on_frame(mut w)
		assert w.dropdown_id == '' && w.text('owner') == 'Uno'
		assert !w.hit_targets.any(it.dropdown_option)
		assert sgl.error() == .no_error
	}
}

fn test_partial_dropdown_clip_survives_nested_scaled_scroll_and_translated_descendant() {
	$if macos && ui2_custom_rendering ?&& ui2_embedder ?&& ui2_geometry_capture ?&& !ui2_headless ? {
		mut ctx := new_surface_draw_context(gg.Config{ width: 360, height: 280 }, dropdown_clip_environment())!
		window := C.ui2_embedder_create(&C.ui2_embedder_config{ title: c'Dropdown nested clip fixture', width: 360, height: 280, visible: false }, &C.ui2_embedder_callbacks{}, unsafe { nil })
		assert window != unsafe { nil }
		defer {
			C.ui2_embedder_close(window)
			ctx.destroy()
			dropdown_clip_vertices.clear()
		}
		owner := with_transform(dropdown_clip_control('partial', rect(95, 85, 20, 20)),
			VisualTransform{ rotation: 45, origin_x: 10, origin_y: 10, translate_x: -4, translate_y: -65 })
		translated := view('offscreen', rect(0, 300, 50, 30), BoxStyle{ transparent: true }, [
			with_transform(dropdown_clip_control('translated', rect(5, 0, 35, 24)), VisualTransform{ translate_y: -250 }),
		])
		pane := with_transform(scroll('pane', rect(10, 10, 100, 80), 0xeeeeee, [owner, translated]),
			VisualTransform{ rotation: 25, origin_x: 50, origin_y: 40 })
		viewport := rect(20, 20, 240, 180)
		scene := with_transform(scaled_content('fixed', viewport, 160, 120,
			BoxStyle{ transparent: true }, [pane]), VisualTransform{ rotation: -8, origin_x: 120, origin_y: 90 })
		mut w := &Window{ ctx: ctx, native_window: window, has_root: true, declared_root: screen(0xffffff, [scene]) }
		ctx.submitted_polygon = observe_dropdown_clip_polygon
		on_frame(mut w)
		w.scroll_to_offset('pane', 20)
		on_frame(mut w)
		assert w.scroll_offset('pane') == 20
		geometry := w.visual_geometry('partial')!
		fit := scene.visual_transform().matrix(viewport)!.compose(contain_content(viewport, 160, 120)!)
		pane_clip := transformed_clip(rect(10, 10, 100, 80), fit.compose(pane.visual_transform().matrix(rect(10, 10, 100, 80))!))
		visible := geometry.transform.point(geometry.frame.x + 0.5, geometry.frame.y + 19.5)
		clipped := geometry.transform.point(geometry.frame.x + 19, geometry.frame.y + 10)
		assert pane_clip.contains(visible.x, visible.y)
		assert !pane_clip.contains(clipped.x, clipped.y)
		assert geometry.contains(visible.x, visible.y) && !geometry.contains(clipped.x, clipped.y)
		assert geometry.bounds().width > 0 && geometry.bounds().height > 0
		assert w.hit_test(visible.x, visible.y).id == 'partial'
		assert w.hit_test(clipped.x, clipped.y).id != 'partial'
		assert tooltip_target_at(w.tooltip_targets, visible.x, visible.y).key == 'dropdown#partial'
		assert tooltip_target_at(w.tooltip_targets, clipped.x, clipped.y).key != 'dropdown#partial'
		on_event(&gg.Event{ typ: .mouse_move, mouse_x: f32(visible.x), mouse_y: f32(visible.y) }, mut w)
		dropdown_clip_vertices.clear()
		on_frame(mut w)
		assert dropdown_clip_vertices.any(it.r == 0 && it.g == 160 && it.b == 112)
		for vertex in dropdown_clip_vertices.filter(it.r == 0 && it.g == 160 && it.b == 112) {
			assert pane_clip.contains(vertex.x, vertex.y)
		}
		dropdown_clip_click(mut w, clipped)
		on_frame(mut w)
		assert w.dropdown_id == ''
		dropdown_clip_click(mut w, visible)
		on_frame(mut w)
		assert w.dropdown_id == 'partial' && w.dropdown_popup.mounted
		option := Point{w.dropdown_popup.x + w.dropdown_popup.width / 2,
			w.dropdown_popup.y + dropdown_popup_padding + w.dropdown_popup.row_height * 1.5}
		assert w.hit_test(option.x, option.y).dropdown_option
		dropdown_clip_click(mut w, option)
		on_frame(mut w)
		assert w.text('partial') == 'Dos' && w.dropdown_id == ''
		// A descendant's own translation can bring it into the viewport even
		// when its layout container is outside the Scroll broad phase.
		moved := w.visual_geometry('translated')!
		center := moved.transform.point(moved.frame.x + moved.frame.width / 2, moved.frame.y + moved.frame.height / 2)
		assert moved.bounds().width > 0 && moved.bounds().height > 0
		assert moved.contains(center.x, center.y)
		assert w.hit_test(center.x, center.y).id == 'translated'
		dropdown_clip_click(mut w, center)
		on_frame(mut w)
		assert w.dropdown_id == 'translated' && w.dropdown_popup.mounted
		assert math.abs(ctx.content_transform.xx - 1) < 1e-12
		assert ctx.content_transform == ContentTransform{}
		assert sgl.error() == .no_error
	}
}
