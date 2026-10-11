// vtest vflags: -gc boehm -d no_gc_thread_local_alloc
module ui2

import math

fn test_paint_clip_reuses_storage_and_preserves_attributes() {
	mut buffer := new_paint_clip_buffer()
	axis := transformed_clip(rect(0.125, 0.25, 0.5, 0.5), ContentTransform{})
	affine := transformed_clip(rect(0, 0, 0.6, 0.8), ContentTransform{xx: 0.8, xy: -0.6, yx: 0.6, yy: 0.8})
	source := [PaintVertex{x:0,y:0,u:0,v:0,r:0,g:10,b:20,a:30},
		PaintVertex{x:1,y:0,u:1,v:0,r:100,g:110,b:120,a:130},
		PaintVertex{x:1,y:1,u:1,v:1,r:100,g:110,b:120,a:130},
		PaintVertex{x:0,y:1,u:0,v:1,r:0,g:10,b:20,a:30}]
	for region in [axis, affine] {
		result := region.clip_polygon_buffered(source, mut buffer)
		assert result.len >= 3
		for vertex in result {
			assert region.contains(vertex.x, vertex.y)
			assert math.abs(vertex.u - vertex.x) < 1e-14
			assert math.abs(vertex.v - vertex.y) < 1e-14
			assert math.abs(vertex.r - 100 * vertex.x) < 1e-12
			assert math.abs(vertex.g - (10 + 100 * vertex.x)) < 1e-12
			assert math.abs(vertex.b - (20 + 100 * vertex.x)) < 1e-12
			assert math.abs(vertex.a - (30 + 100 * vertex.x)) < 1e-12
		}
	}
	before := gc_allocation_snapshot()!
	mut count := 0
	for _ in 0 .. 1000 {
		count += axis.clip_polygon_buffered(source, mut buffer).len
		count += affine.clip_polygon_buffered(source, mut buffer).len
	}
	after := gc_allocation_snapshot()!.delta_since(before)
	assert count >= 7000
	assert after.allocated_bytes == 0
	assert after.collections == 0
}

fn test_paint_clip_capacity_grows_once_without_truncating_complex_convex_paint() {
	mut buffer := new_paint_clip_buffer()
	mut source := []PaintVertex{cap: 240}
	for i in 0 .. 240 {
		angle := 2 * math.pi * f64(i) / 240
		source << PaintVertex{x: math.cos(angle), y: math.sin(angle), u: f64(i)}
	}
	clip := transformed_clip(rect(-0.99, -2, 3, 4), ContentTransform{})
	result := clip.clip_polygon_buffered(source, mut buffer)
	assert result.len > 200
	assert result.len < source.len
	for vertex in result { assert clip.contains(vertex.x, vertex.y) }
	assert buffer.first.cap > 80
	before := gc_allocation_snapshot()!
	mut count := 0
	for _ in 0 .. 100 { count += clip.clip_polygon_buffered(source, mut buffer).len }
	after := gc_allocation_snapshot()!.delta_since(before)
	assert count > 20000
	assert after.allocated_bytes == 0
	assert after.collections == 0
}

fn test_presentation_transform_hot_geometry_uses_stack_storage() {
	t := VisualTransform{rotation: 19, scale_x: 1.3, scale_y: 0.8}.matrix(rect(20, 30, 100, 50))!
	before := gc_allocation_snapshot()!
	mut sum := 0.0
	for _ in 0 .. 1000 {
		sum += t.project(rect(20, 30, 100, 50)).width
		inverse := t.inverted()!
		sum += inverse.xx
	}
	after := gc_allocation_snapshot()!.delta_since(before)
	assert sum > 1000
	assert after.allocated_bytes == 0
	assert after.collections == 0
}

fn test_inline_axis_paint_scopes_keep_exact_edges_and_allocate_nothing() {
	outer := paint_transformed_clip(rect(10.25, 20.5, 30.75, 12.125), ContentTransform{})
	inner := paint_transformed_clip(rect(25.1, 15, 40, 10.3), ContentTransform{})
	public_clip := transformed_clip(rect(10.25, 20.5, 30.75, 12.125), ContentTransform{})
	result := outer.intersect(inner)
	assert result.has_inline_axis
	assert result.points.len == 0
	assert result.inline_axis == [Point{25.1, 20.5}, Point{41, 20.5}, Point{41, 25.3}, Point{25.1, 25.3}]!
	assert result.bounds() == public_clip.intersect(transformed_clip(rect(25.1, 15, 40, 10.3), ContentTransform{})).bounds()
	for point in [Point{25.1, 20.5}, Point{41, 25.3}, Point{30, 23}, Point{40, 26}] {
		assert outer.contains(point.x, point.y) == public_clip.contains(point.x, point.y)
	}
	before := gc_allocation_snapshot()!
	mut sum := 0.0
	for _ in 0 .. 1000 {
		clip := outer.intersect(paint_transformed_clip(rect(25.1, 15, 40, 10.3), ContentTransform{}))
		assert clip.contains(30, 23)
		sum += clip.bounds().width
	}
	after := gc_allocation_snapshot()!.delta_since(before)
	assert sum > 1000
	assert after.allocated_bytes == 0
	assert after.collections == 0
}

fn test_rounded_and_dashed_border_paint_reuses_tessellation_storage() {
	mut triangles := []BorderTriangle{cap: 512}
	frame := rect(10.25, 20.5, 130.75, 65.5)
	box := BoxStyle{radius: 12, border_left: 2, border_top: 1, border_right: 3, border_bottom: 4,
		border_pattern: .dashed, dash_length: 3, dash_gap: 2}
	box_border_triangles_into(frame, box, mut triangles)
	assert triangles.len > 100
	before := gc_allocation_snapshot()!
	mut count := 0
	for _ in 0 .. 1000 {
		box_border_triangles_into(frame, box, mut triangles)
		count += triangles.len
	}
	after := gc_allocation_snapshot()!.delta_since(before)
	assert count > 100000
	assert after.allocated_bytes == 0
	assert after.collections == 0
}

fn test_frame_text_preserves_utf8_and_reuses_mask_and_prefix_storage() {
	mut mask := FrameTextBuffer{}
	mut prefix := FrameTextBuffer{}
	text := 'año café🙂'
	assert mask.field_text(text, false) == text
	assert mask.field_text(text, true) == '•••••••••'
	assert prefix.field_prefix(text, 2, false) == 'añ'
	assert prefix.field_prefix(text, 8, false) == 'año café'
	assert prefix.field_prefix(text, 9, false) == text
	assert prefix.field_prefix(text, 100, false) == text
	assert prefix.field_prefix(text, -1, false) == ''
	assert prefix.field_prefix(text, 3, true) == '•••'
	assert prefix.bytes[prefix.bytes.len - 1] == 0
	assert prefix.field_prefix(text, 9, true) == '•••••••••'
	before := gc_allocation_snapshot()!
	mut count := 0
	for i in 0 .. 1000 {
		count += mask.field_text(text, true).len
		count += prefix.field_prefix(text, i % 10, i % 2 == 0).len
	}
	after := gc_allocation_snapshot()!.delta_since(before)
	assert count > 27000
	assert after.allocated_bytes == 0
	assert after.collections == 0
}

fn test_streaming_rune_count_and_frame_text_match_v_replacement_runes() {
	mut buffer := FrameTextBuffer{}
	for text in ['España café🙂', '', [u8(0x80), 0xc0, 0xe0, 0xff, 0x61].bytestr(), [u8(0xf0), 0x9f].bytestr()] {
		assert rune_len(text) == text.runes().len
		assert buffer.field_text(text, true) == '•'.repeat(text.runes().len)
		assert buffer.field_prefix(text, 100, false) == text.runes().string()
	}
}
