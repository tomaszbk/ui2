// vfmt off
module ui2

$if (android || linux || ((macos || windows) && ui2_custom_rendering ?)) && !ui2_headless ? {
	import sokol.sgl

	fn draw_vector_shapes(ctx &DrawContext, shapes []VectorShape, x f64, y f64) {
		for shape in shapes {
			if color := shape.style.fill {
				for triangle in shape.fill_triangles { draw_vector_triangle(ctx, triangle, x, y, color) }
			}
			if color := shape.style.stroke {
				for triangle in shape.stroke_triangles { draw_vector_triangle(ctx, triangle, x, y, color) }
			}
		}
		if sgl.error() != .no_error { panic('ui2: vector canvas exceeded the shared renderer command/vertex capacity: ${sgl.error()}') }
	}

	fn draw_vector_triangle(ctx &DrawContext, triangle VectorTriangle, x f64, y f64, color u32) {
		// Delegate vertex projection, device DPI and clip to the shared renderer.
		ctx.draw_triangle_filled(f32(x + triangle.a.x), f32(y + triangle.a.y),
			f32(x + triangle.b.x), f32(y + triangle.b.y), f32(x + triangle.c.x),
			f32(y + triangle.c.y), hex_color(color))
	}

	fn add_element_tooltip(key string, text string, el Element, area Rect, clip Rect) {
		count := g_tooltip_targets.len
		add_tooltip_target(key, text, area, clip)
		if (!el.is_vector_canvas && el.vector_shapes.len == 0) || g_tooltip_targets.len == count { return }
		last := g_tooltip_targets.last()
		g_tooltip_targets[g_tooltip_targets.len - 1] = TooltipTarget{...last,
			is_vector_canvas: el.is_vector_canvas,
			vector_shapes: el.vector_shapes, vector_hit_mode: el.vector_hit_mode,
			vector_origin: area, content_transform: current_content_transform()}
	}
}
