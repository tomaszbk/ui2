// vtest vflags: -d ui2_custom_rendering -d ui2_embedder -d ui2_geometry_capture
@[has_globals]
module ui2

$if macos && ui2_custom_rendering ?&& ui2_embedder ?&& ui2_geometry_capture ?&& !ui2_headless ? {
	import gg
	import json2
	import math
	import os
	import sokol.gfx
	import sokol.sgl
	#include "@VMODROOT/ui/visual_transform_fixture_darwin.h"
	fn C.ui2_transform_ime_matches(voidptr, f64, f64, f64, f64, bool) bool
	__global transform_gpu_vertices = []PaintVertex{}

	struct TransformGpuReference {
		dpi          f32
		caret        Rect
		pane_clip    []Point
		field_center Point
		vertices     []PaintVertex
	}
	fn observe_transform_polygon(vertices []PaintVertex) { transform_gpu_vertices << vertices }
	fn transform_gpu_environment() gfx.Environment {
		return gfx.Environment{ defaults: gfx.EnvironmentDefaults{ color_format: .bgra8, depth_format: .@none, sample_count: 1 }, metal: gfx.MetalEnvironment{ device: C.ui2_embedder_metal_device() } }
	}
}

fn test_full_affine_gpu_submission_clips_glyphs_images_selection_caret_and_siblings() {
	$if macos && ui2_custom_rendering ?&& ui2_embedder ?&& ui2_geometry_capture ?&& !ui2_headless ? {
		previous := g_gg_app
		previous_state := activate_custom_window_state(new_custom_window_state())
		mut ctx := new_surface_draw_context(gg.Config{ width: 400, height: 300 }, transform_gpu_environment())!
		defer {
			ctx.destroy()
			activate_custom_window_state(previous_state)
			g_gg_app = previous
		}
		g_gg_app = &GgApp{ ctx: ctx, has_root: true }
		window := C.ui2_embedder_create(&C.ui2_embedder_config{ title: c'Affine geometry fixture', width: 400, height: 300, visible: false }, &C.ui2_embedder_callbacks{}, unsafe { nil })
		assert window != unsafe { nil }
		defer { C.ui2_embedder_close(window) }
		style := TextStyle{ size: 20, font_family: 'Inter', color: 0x101010 }
		editor := text_input(
			id:         'edit'
			text:       'año café selección'
			frame:      rect(-10, 18, 220, 70)
			box:        BoxStyle{ bg: 0xffffff }
			text_style: style
			keyboard:   0
			multiline:  true
		)!
		field := text_input(
			id:         'field'
			text:       'España'
			frame:      rect(8, 94, 150, 34)
			box:        BoxStyle{ bg: 0xffffff }
			text_style: style
			keyboard:   0
			multiline:  false
		)!
		overflow := view('overflow', rect(0, 220, 160, 40), BoxStyle{ transparent: true }, [with_transform(view('translated-in', rect(10, 0, 50, 24), BoxStyle{ bg: 0xff8800 }, []Element{}), VisualTransform{ translate_y: -200 })])
		pane := with_transform(scroll('pane', rect(50, 30, 180, 140), 0xdbeafe, [
			editor,
			field,
			image('image', os.join_path(@VMODROOT, 'examples', 'users', 'logo.png'), rect(120, 0, 90, 90)),
			overflow,
		]), VisualTransform{ rotation: 28, scale_x: 1.1, scale_y: 0.8, origin_x: 90, origin_y: 70 })
		viewport := rect(20, 20, 360, 240)
		scene := with_transform(scaled_content('fixed', viewport, 400, 300, BoxStyle{ transparent: true }, [pane]), VisualTransform{ rotation: -8, origin_x: 180, origin_y: 120 })
		ctx.submitted_polygon = observe_transform_polygon
		mut reference_caret := Rect{}
		for dpi in [f32(1), 1.25, 1.5, 2] {
			mut surface := C.ui2_embedder_surface{}
			assert C.ui2_embedder_acquire_frame(window, &surface)
			// Exercise presentation at fractional DPI with the same logical scene.
			ctx.set_surface(400, 300, dpi, gfx.Swapchain{ width: int(400 * dpi), height: int(300 * dpi), sample_count: 1, color_format: .bgra8, depth_format: .@none, metal: gfx.MetalSwapchain{ current_drawable: surface.drawable } })
			ctx.clip_base = ClipRegion{}
			ctx.clip_region = ClipRegion{}
			ctx.content_transform = ContentTransform{}
			ctx.begin()
			if dpi == 1 {
				shaped := ctx.shape_text('ñ café', TextStyle{ size: 20, font_family: 'Inter', underline: true }, 200, 1, false)!
				transform_gpu_vertices.clear()
				ctx.draw_shaped(shaped, 10, 20)
				reference := transform_gpu_vertices.clone()
				transform_gpu_vertices.clear()
				ctx.content_transform = ContentTransform{ xx: 0, xy: -2, yx: 3, yy: 0, x: 200, y: 10 }
				ctx.draw_shaped(shaped, 10, 20)
				assert transform_gpu_vertices.len == reference.len && reference.len > 20
				for i, v in transform_gpu_vertices {
					assert math.abs(v.x - (200 - 2 * reference[i].y)) < 0.0001
					assert math.abs(v.y - (10 + 3 * reference[i].x)) < 0.0001
					assert v.u == reference[i].u && v.v == reference[i].v
				}
				ctx.content_transform = ContentTransform{}
			}
			render_element(ctx, scene, 0, 0, rect(0, 0, 400, 300), '', 'root')
			g_focused_field = 'edit'
			mut state := g_text_editors['edit'] or { panic('editor not mounted') }
			state.set_selection(1, 7)
			replace_text_editor('edit', state)
			transform_gpu_vertices.clear()
			render_element(ctx, scene, 0, 0, rect(0, 0, 400, 300), '', 'root')
			selection_vertices := transform_gpu_vertices.clone()
			g_gg_app.composition.update('edit', state, 'ñ', 1, 0, -1, 0)
			transform_gpu_vertices.clear()
			render_element(ctx, scene, 0, 0, rect(0, 0, 400, 300), '', 'root')
			fit := scene.visual_transform().matrix(viewport)!.compose(contain_content(viewport, 400, 300)!)
			expected := transformed_clip(rect(50, 30, 180, 140), fit.compose(pane.visual_transform().matrix(rect(50, 30, 180, 140))!))
			assert transform_gpu_vertices.len > 150
			// A descendant translates into view from an offscreen layout container.
			moved := visual_geometry('translated-in')!
			assert moved.bounds().width > 0 && moved.bounds().height > 0
			center := moved.transform.point(moved.frame.x + 25, moved.frame.y + 12)
			assert moved.contains(center.x, center.y) && expected.contains(center.x, center.y)
			field_geometry := visual_geometry('field')!
			field_center := field_geometry.transform.point(field_geometry.frame.x + 75,
				field_geometry.frame.y + 17)
			assert hit_test(field_center.x, field_center.y).id == 'field'
			corner := expected.bounds()
			assert !expected.contains(corner.x + 0.1, corner.y + 0.1)
			assert hit_test(corner.x + 0.1, corner.y + 0.1).id == ''
			assert selection_vertices.any(it.r == 184 && it.g == 215 && it.b == 255)
			for v in selection_vertices {
				assert expected.contains(v.x, v.y)
			}
			for v in transform_gpu_vertices {
				assert expected.contains(v.x, v.y)
			}
			assert text('edit') == 'año café selección'
			assert g_text_editors['edit'].selection == TextSelection{ anchor: 1, caret: 7 }
			// IME gets the AABB of the same clipped, transformed caret, snapped once.
			caret := g_gg_app.text_caret
			assert caret.width > 0 && caret.height > 0
			if dpi == 1 {
				reference_caret = caret
			} else {
				assert math.abs(caret.x - reference_caret.x) <= 1
				assert math.abs(caret.y - reference_caret.y) <= 1
			}
			println('dpi=${dpi} caret=${caret} submitted_vertices=${transform_gpu_vertices.len}')
			if os.getenv('UI2_TRANSFORM_GEOMETRY_CAPTURE') == '1' {
				println('TRANSFORM_GEOMETRY ' + json2.encode(TransformGpuReference{ dpi: dpi, caret: caret, pane_clip: expected.points, field_center: field_center, vertices: transform_gpu_vertices }))
			}
			// Scoped clipping restores the parent's region for the next sibling.
			transform_gpu_vertices.clear()
			render_element(ctx, view('sibling', rect(300, 220, 40, 40), BoxStyle{ bg: 0xff0000 }, []Element{}), 0, 0, rect(0, 0, 400, 300), '', 'sibling')
			assert transform_gpu_vertices.len == 4
			assert transform_gpu_vertices[0].x == 300
			assert ctx.content_transform == ContentTransform{}
			// A direct primitive after the scope uses the restored parent clip too.
			transform_gpu_vertices.clear()
			ctx.draw_rect_filled(350, 270, 20, 20, gg.Color{ r: 255 })
			assert transform_gpu_vertices.len == 4
			assert math.abs(transform_gpu_vertices[0].x - math.round(350 * dpi) / dpi) < 0.0001
			assert math.abs(transform_gpu_vertices[0].y - math.round(270 * dpi) / dpi) < 0.0001
			assert sgl.error() == .no_error
			ctx.end()
			C.ui2_embedder_frame_done(window)
			g_gg_app.composition = TextComposition{}
		}
	}
}

fn test_actual_transform_update_preserves_edits_layout_and_returns_to_idle() {
	$if macos && ui2_custom_rendering ?&& ui2_embedder ?&& ui2_geometry_capture ?&& !ui2_headless ? {
		previous := g_gg_app
		previous_state := activate_custom_window_state(new_custom_window_state())
		mut ctx := new_surface_draw_context(gg.Config{ width: 320, height: 240 }, transform_gpu_environment())!
		defer {
			ctx.destroy()
			activate_custom_window_state(previous_state)
			g_gg_app = previous
		}
		window := C.ui2_embedder_create(&C.ui2_embedder_config{ title: c'Affine idle fixture', width: 320, height: 240, visible: false }, &C.ui2_embedder_callbacks{}, unsafe { nil })
		assert window != unsafe { nil }
		defer { C.ui2_embedder_close(window) }
		field := text_input(
			id:         'kept'
			text:       'declared'
			frame:      rect(20.25, 30.5, 180.5, 38.25)
			box:        BoxStyle{ bg: 0xffffff }
			text_style: TextStyle{}
			keyboard:   0
			multiline:  false
		)!
		g_gg_app = &GgApp{
			ctx:           ctx
			native_window: window
			has_root:      true
			declared_root: screen(0xffffff, [
				field,
				scroll('kept-scroll', rect(220, 20, 80, 160), 0xeeeeee, [view('row', rect(0, 300, 70, 40), BoxStyle{}, []Element{})]),
			])
		}
		on_frame(mut g_gg_app)
		set_text('kept', 'año café draft')
		focus('kept')
		mut editor := g_text_editors['kept'] or { panic('editor not mounted') }
		editor.set_selection(1, 5)
		replace_text_editor('kept', editor)
		g_gg_app.composition.update('kept', editor, 'ñ', 1, 0, -1, 0)
		set_scroll_offset(named_scroll_state_id('kept-scroll'), 40, 200)
		on_frame(mut g_gg_app)
		before := g_gg_app.scheduler.stats()
		before_text := ctx.text.shape_builds
		before_layout := layout_stats()
		set_visual_transform('kept', VisualTransform{ rotation: 17, scale_x: 1.2, scale_y: 0.8, origin_x: 90, origin_y: 19 })!
		on_frame(mut g_gg_app)
		after := g_gg_app.scheduler.stats()
		assert after.builds == before.builds
		assert ctx.text.shape_builds == before_text
		assert after.draws == before.draws + 1
		assert layout_stats().measure_visits == before_layout.measure_visits
		assert layout_stats().text_measurements == before_layout.text_measurements
		assert layout_stats().layout_visits == before_layout.layout_visits
		assert g_gg_app.declared_root.children[0].frame == field.frame
		assert text('kept') == 'año café draft'
		assert g_focused_field == 'kept'
		assert scroll_offset('kept-scroll') == 40
		assert g_gg_app.composition.field_id == 'kept' && g_gg_app.composition.mark_length == 1
		caret := g_gg_app.text_caret
		sync_embedder_text(g_gg_app)
		assert C.ui2_transform_ime_matches(C.ui2_embedder_native_window(window), caret.x, caret.y, caret.width, caret.height, true)
		assert g_text_editors['kept'].selection == TextSelection{ anchor: 1, caret: 5 }
		// Recolor and selection patch the same owned text. Moving the Scroll
		// changes the exact ancestor clip without changing text/layout metrics.
		mounted := g_focus_navigation.node('kept') or { panic('mounted field') }
		refresh_element('kept', Element{...mounted.el, text_style: TextStyle{...mounted.el.text_style, color: 0x00aa00}})
		editor.set_selection(2, 4)
		replace_text_editor('kept', editor)
		set_visual_transform('kept-scroll', VisualTransform{rotation: 9})!
		on_frame(mut g_gg_app)
		assert layout_stats().measure_visits == before_layout.measure_visits
		assert layout_stats().text_measurements == before_layout.text_measurements
		assert layout_stats().layout_visits == before_layout.layout_visits
		assert ctx.text.shape_builds == before_text
		painted := g_gg_app.scheduler.stats()
		for _ in 0 .. 10 { on_frame(mut g_gg_app) }
		idle := g_gg_app.scheduler.stats()
		assert idle.draws == painted.draws && idle.builds == painted.builds && !idle.pending
		println('transform update: builds=${after.builds - before.builds} draws=${after.draws - before.draws}; shape builds=${ctx.text.shape_builds - before_text}; idle draws=${idle.draws - after.draws}')
	}
}
