// vtest vflags: -d ui2_custom_rendering -d ui2_embedder -d ui2_geometry_capture
@[has_globals]
module ui2

$if macos && ui2_custom_rendering ?&& ui2_embedder ?&& ui2_geometry_capture ?&& !ui2_headless ? {
	import gg
	import math
	import os
	import sokol.gfx

	@[heap]
	struct EmbedderMotionFixture {
	mut:
		now    f64
		builds int
	}

	__global motion_gpu_vertices = []PaintVertex{}

	fn observe_motion_polygon(vertices []PaintVertex) { motion_gpu_vertices << vertices }

	fn motion_gpu_environment() gfx.Environment {
		return gfx.Environment{
			defaults: gfx.EnvironmentDefaults{
				color_format: .bgra8
				depth_format: .@none
				sample_count: 1
			}
			metal:    gfx.MetalEnvironment{ device: C.ui2_embedder_metal_device() }
		}
	}
}

fn test_actual_motion_frame_fades_text_images_vectors_retargets_without_build_and_returns_idle() ! {
	$if macos && ui2_custom_rendering ?&& ui2_embedder ?&& ui2_geometry_capture ?&& !ui2_headless ? {
		mut ctx := new_surface_draw_context(gg.Config{ width: 320, height: 240 }, motion_gpu_environment())!
		window := C.ui2_embedder_create(&C.ui2_embedder_config{
			title:   c'Motion presence fixture'
			width:   320
			height:  240
			visible: false
		}, &C.ui2_embedder_callbacks{}, unsafe { nil })
		assert window != unsafe { nil }
		mut fixture := &EmbedderMotionFixture{}
		shape := prepare_vector_shape(vector_polygon([vector_point(0, 0), vector_point(40, 0),
			vector_point(40, 24), vector_point(0, 24)]), VectorStyle{ fill: 0x00cc44 })!
		label := Element{
			kind:       .label
			id:         'label'
			text:       'año café ñ'
			frame:      rect(0, 0, 140, 32)
			text_style: TextStyle{ size: 20, font_family: 'Inter', color: 0x223344 }
			box:        BoxStyle{ transparent: true }
		}
		vector := vector_canvas(VectorCanvasConfig{ id: 'vector', frame: rect(0, 40, 40, 24), shapes: [shape] })!
		picture := image('picture', os.join_path(@VMODROOT, 'examples', 'users', 'logo.png'), rect(150, 0, 50, 50))
		field := text_input(TextInputConfig{
			id:         'edit'
			text:       'declarado'
			frame:      rect(0, 80, 150, 36)
			box:        BoxStyle{ bg: 0xffffff }
			text_style: TextStyle{ size: 18 }
		})!
		inner := Element{
			...view('inner', rect(0, 0, 220, 140), BoxStyle{ transparent: true },
				[label, vector, picture, field])
			opacity: 0.5
		}
		outer := with_motion(view('outer', rect(20, 20, 260, 180), BoxStyle{ transparent: true }, [inner]),
			MotionConfig{
				clock:            fn [fixture] () f64 { return fixture.now }
				enter_transition: MotionTransition{ duration: 0.2 }
				exit_transition:  MotionTransition{ duration: 0.15 }
				transition:       MotionTransition{ duration: 0.2 }
			})
		declared := Element{
			kind:     .screen
			id:       'root'
			frame:    rect(0, 0, 320, 240)
			box:      BoxStyle{ bg: 0xffffff }
			children: [outer]
		}
		mut w := &Window{ ctx: ctx, native_window: window }
		defer {
			w.motion_tree.dispose()
			C.ui2_embedder_close(window)
			ctx.destroy()
		}
		w.build = fn [mut fixture, declared] (mut _ Window) Element {
			fixture.builds++
			return declared
		}
		ctx.submitted_polygon = observe_motion_polygon
		on_frame(mut w)
		assert fixture.builds == 1
		fixture.now = 0.1
		motion_gpu_vertices.clear()
		on_frame(mut w)
		glyphs := motion_gpu_vertices.filter(it.r == 34 && it.g == 51 && it.b == 68)
		vectors := motion_gpu_vertices.filter(it.r == 0 && it.g == 204 && it.b == 68)
		images := motion_gpu_vertices.filter(it.x >= 170 && it.x <= 220 && it.y >= 20
			&& it.y <= 70 && it.r == 255 && it.g == 255 && it.b == 255)
		assert glyphs.len > 20 && vectors.len >= 4 && images.len >= 4
		assert glyphs.all(math.abs(it.a - 63.75) < 0.0001)
		assert vectors.all(math.abs(it.a - 63.75) < 0.0001)
		assert images.all(math.abs(it.a - 63.75) < 0.0001)
		assert ctx.opacity == 1 && ctx.content_transform == ContentTransform{}
		fixture.now = 0.21
		on_frame(mut w)
		idle := w.scheduler.stats()
		for _ in 0 .. 3 { on_frame(mut w) }
		assert w.scheduler.stats().draws == idle.draws
		assert fixture.builds == 1 && !idle.motion_active && !idle.pending
		w.set_text('edit', 'España ñ café')
		w.focus('edit')
		mut editor := w.text_editors['edit'] or { panic('missing editor') }
		editor.set_selection(1, 5)
		w.replace_text_editor('edit', editor)
		w.composition.update('edit', editor, 'á', 1, 0, -1, 0)
		on_frame(mut w)
		before_layout := w.layout_stats()
		before_shape := ctx.text.shape_builds
		w.set_visual_transform('outer', VisualTransform{ translate_x: 40 })!
		on_frame(mut w)
		fixture.now = 0.31
		on_frame(mut w)
		mounted := w.navigation.node('edit') or { panic('missing animated editor') }
		assert math.abs(mounted.transform.x - 20) < 0.00001
		assert w.text('edit') == 'España ñ café'
		assert w.text_editors['edit'].selection == TextSelection{ anchor: 1, caret: 5 }
		assert w.focused_field == 'edit' && w.composition.field_id == 'edit'
		assert fixture.builds == 1
		assert w.layout_stats().measure_visits == before_layout.measure_visits
		assert w.layout_stats().layout_visits == before_layout.layout_visits
		assert ctx.text.shape_builds == before_shape
		fixture.now = 0.42
		on_frame(mut w)
		w.declared_root = Element{ ...declared, children: [] }
		w.declaration_pending = true
		w.scheduler.invalidate(.layout)
		on_frame(mut w)
		assert w.focused_field == '' && w.composition.field_id == ''
		assert w.declared_root.children.len == 1
		fixture.now = 0.58
		on_frame(mut w)
		assert w.declared_root.children.len == 0
		mut stale_geometry := false
		w.visual_geometry('outer') or { stale_geometry = true }
		assert stale_geometry
		stale_geometry = false
		w.visual_geometry('edit') or { stale_geometry = true }
		assert stale_geometry
		completed := w.scheduler.stats()
		for _ in 0 .. 4 { on_frame(mut w) }
		assert !completed.motion_active && !completed.pending
		assert w.scheduler.stats().draws == completed.draws && fixture.builds == 1
		assert ctx.inner.r.error() == .no_error
		println('owned Metal: nested fade submitted for glyphs/images/vectors; transforms preserved edits/IME and avoided builds/relayout; enter/exit returned idle')
	}
}
