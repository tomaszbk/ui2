module ui2

import math

// All vector coordinates and the flattening tolerance are local logical units.
pub struct VectorPoint {
pub:
	x f64
	y f64
}

pub fn vector_point(x f64, y f64) VectorPoint {
	return VectorPoint{x, y}
}

pub enum VectorCommandKind {
	move
	line
	quadratic
	cubic
	close
}

pub struct VectorCommand {
pub:
	kind     VectorCommandKind
	end      VectorPoint
	control1 VectorPoint
	control2 VectorPoint
}

// A builder owns commands; preparing a shape takes an immutable geometry snapshot.
pub struct VectorPath {
pub mut:
	commands []VectorCommand
}

pub fn (mut path VectorPath) move_to(x f64, y f64) {
	path.commands << VectorCommand{ kind: .move, end: vector_point(x, y) }
}

pub fn (mut path VectorPath) line_to(x f64, y f64) {
	path.commands << VectorCommand{ kind: .line, end: vector_point(x, y) }
}

pub fn (mut path VectorPath) quadratic_to(cx f64, cy f64, x f64, y f64) {
	path.commands << VectorCommand{ kind: .quadratic, end: vector_point(x, y), control1: vector_point(cx, cy) }
}

pub fn (mut path VectorPath) cubic_to(cx1 f64, cy1 f64, cx2 f64, cy2 f64, x f64, y f64) {
	path.commands << VectorCommand{ kind: .cubic, end: vector_point(x, y), control1: vector_point(cx1, cy1), control2: vector_point(cx2, cy2) }
}

pub fn (mut path VectorPath) close() {
	path.commands << VectorCommand{ kind: .close }
}

pub fn vector_polygon(points []VectorPoint) VectorPath {
	mut path := VectorPath{}
	if points.len == 0 { return path }
	path.move_to(points[0].x, points[0].y)
	for point in points[1..] { path.line_to(point.x, point.y) }
	path.close()
	return path
}

pub enum VectorFillRule {
	nonzero
	even_odd
}

pub enum VectorCap {
	butt
	round
	square
}

pub enum VectorJoin {
	miter
	bevel
	round
}

pub enum VectorHitMode {
	paint
	fill
	stroke
	bounds
}

pub struct VectorStyle {
pub:
	fill         ?u32
	stroke       ?u32
	fill_rule    VectorFillRule
	stroke_width f64 = 1
	cap          VectorCap
	join         VectorJoin
	miter_limit  f64 = 4
	tolerance    f64 = 0.25
}

pub struct VectorContour {
pub:
	points []VectorPoint
	closed bool
}

pub struct VectorTriangle {
pub:
	a VectorPoint
	b VectorPoint
	c VectorPoint
}

// Retained CPU triangles feed both the existing DrawContext and exact shape hits.
// No per-shape textures, GPU handles, global cache or second renderer is needed.
pub struct VectorShape {
	style            VectorStyle
	prepared         bool
	contours         []VectorContour
	fill_triangles   []VectorTriangle
	stroke_triangles []VectorTriangle
	bounds           Rect
}

pub fn (shape VectorShape) paint_style() VectorStyle { return shape.style }

pub fn (shape VectorShape) paint_bounds() Rect { return shape.bounds }

pub fn (shape VectorShape) flattened_contours() []VectorContour {
	mut snapshot := []VectorContour{cap: shape.contours.len}
	for contour in shape.contours {
		snapshot << VectorContour{ points: contour.points.clone(), closed: contour.closed }
	}
	return snapshot
}

pub fn (shape VectorShape) fill_mesh() []VectorTriangle { return shape.fill_triangles.clone() }

pub fn (shape VectorShape) stroke_mesh() []VectorTriangle { return shape.stroke_triangles.clone() }

const vector_epsilon = 1e-9
const vector_max_points = 4096

fn vector_finite(point VectorPoint) bool {
	return layout_finite(point.x) && layout_finite(point.y) && math.abs(point.x) <= 1e7 && math.abs(point.y) <= 1e7
}

fn vector_sub(a VectorPoint, b VectorPoint) VectorPoint {
	return vector_point(a.x - b.x, a.y - b.y)
}

fn vector_add(a VectorPoint, b VectorPoint) VectorPoint {
	return vector_point(a.x + b.x, a.y + b.y)
}

fn vector_mul(a VectorPoint, scale f64) VectorPoint {
	return vector_point(a.x * scale, a.y * scale)
}

fn vector_cross(a VectorPoint, b VectorPoint) f64 {
	return a.x * b.y - a.y * b.x
}

fn vector_length(a VectorPoint) f64 {
	return math.sqrt(a.x * a.x + a.y * a.y)
}

fn vector_mid(a VectorPoint, b VectorPoint) VectorPoint {
	return vector_mul(vector_add(a, b), 0.5)
}

fn vector_append(mut points []VectorPoint, point VectorPoint) ! {
	if points.len > 0 && vector_length(vector_sub(points.last(), point)) <= vector_epsilon {
		return
	}
	if points.len >= vector_max_points { return error('vector path exceeds 4096 flattened points') }
	points << point
}

// Distance to the finite chord also catches collinear curves that double back.
fn vector_chord_distance(point VectorPoint, a VectorPoint, b VectorPoint) f64 {
	d := vector_sub(b, a)
	l2 := d.x * d.x + d.y * d.y
	if l2 <= vector_epsilon * vector_epsilon { return vector_length(vector_sub(point, a)) }
	t := math.max(0.0, math.min(1.0, ((point.x - a.x) * d.x + (point.y - a.y) * d.y) / l2))
	return vector_length(vector_sub(point, vector_add(a, vector_mul(d, t))))
}

fn vector_flatten_quad(a VectorPoint, b VectorPoint, c VectorPoint, tolerance f64, depth int, mut points []VectorPoint) ! {
	if vector_chord_distance(b, a, c) <= tolerance {
		vector_append(mut points, c)!
		return
	}
	if depth >= 20 { return error('quadratic curve cannot meet vector tolerance') }
	ab := vector_mid(a, b)
	bc := vector_mid(b, c)
	mid := vector_mid(ab, bc)
	vector_flatten_quad(a, ab, mid, tolerance, depth + 1, mut points)!
	vector_flatten_quad(mid, bc, c, tolerance, depth + 1, mut points)!
}

fn vector_flatten_cubic(a VectorPoint, b VectorPoint, c VectorPoint, d VectorPoint, tolerance f64, depth int, mut points []VectorPoint) ! {
	if math.max(vector_chord_distance(b, a, d), vector_chord_distance(c, a, d)) <= tolerance {
		vector_append(mut points, d)!
		return
	}
	if depth >= 20 { return error('cubic curve cannot meet vector tolerance') }
	ab := vector_mid(a, b)
	bc := vector_mid(b, c)
	cd := vector_mid(c, d)
	abc := vector_mid(ab, bc)
	bcd := vector_mid(bc, cd)
	mid := vector_mid(abc, bcd)
	vector_flatten_cubic(a, ab, abc, mid, tolerance, depth + 1, mut points)!
	vector_flatten_cubic(mid, bcd, cd, d, tolerance, depth + 1, mut points)!
}

pub fn (path VectorPath) flatten(tolerance f64) ![]VectorContour {
	if !layout_finite(tolerance) || tolerance < 0.001 || tolerance > 10 {
		return error('vector tolerance must be finite and in 0.001..10 local units')
	}
	if path.commands.len > vector_max_points { return error('vector path exceeds 4096 commands') }
	mut contours := []VectorContour{}
	mut points := []VectorPoint{}
	mut active := false
	mut total := 0
	for command in path.commands {
		if command.kind != .close && !vector_finite(command.end) {
			return error('vector points must be finite and within +/-10000000')
		}
		if command.kind in [.quadratic, .cubic] && !vector_finite(command.control1) {
			return error('invalid vector control point')
		}
		if command.kind == .cubic && !vector_finite(command.control2) {
			return error('invalid vector control point')
		}
		match command.kind {
			.move {
				if active {
					contours << VectorContour{ points: points.clone() }
					total += points.len
				}
				points = [command.end]
				active = true
			}
			.close {
				if !active { return error('vector close requires an active contour') }
				if points.len > 1 && vector_length(vector_sub(points[0], points.last())) <= vector_epsilon {
					points.delete_last()
				}
				contours << VectorContour{ points: points.clone(), closed: true }
				total += points.len
				points = []VectorPoint{}
				active = false
			}
			else {
				if !active { return error('vector segment requires move_to (also after close)') }
				match command.kind {
					.line { vector_append(mut points, command.end)! }
					.quadratic {
						vector_flatten_quad(points.last(), command.control1, command.end, tolerance, 0, mut points)!
					}
					.cubic {
						vector_flatten_cubic(points.last(), command.control1, command.control2, command.end, tolerance, 0, mut points)!
					}
					else {}
				}
			}
		}
		if total + points.len > vector_max_points {
			return error('vector path exceeds 4096 flattened points')
		}
	}
	if active { contours << VectorContour{ points: points.clone() } }
	return contours
}

pub fn prepare_vector_shape(path VectorPath, style VectorStyle) !VectorShape {
	if !layout_finite(style.stroke_width) || style.stroke_width < 0 || style.stroke_width > 1e7 {
		return error('vector stroke width must be finite and in 0..10000000')
	}
	if !layout_finite(style.miter_limit) || style.miter_limit < 1 || style.miter_limit > 1000 {
		return error('vector miter limit must be finite and in 1..1000')
	}
	contours := path.flatten(style.tolerance)!
	fill := if _ := style.fill {
		vector_fill_mesh(contours, style.fill_rule)!
	} else {
		[]VectorTriangle{}
	}
	stroke := if _ := style.stroke {
		vector_stroke_mesh(contours, style)!
	} else {
		[]VectorTriangle{}
	}
	return VectorShape{ style: style, prepared: true, contours: contours, fill_triangles: fill, stroke_triangles: stroke, bounds: vector_mesh_bounds(fill, stroke) }
}

pub fn (shape VectorShape) contains(x f64, y f64, mode VectorHitMode) bool {
	if !layout_finite(x) || !layout_finite(y) { return false }
	if mode == .bounds {
		return shape.bounds.width > 0 && shape.bounds.height > 0 && box_contains_point(shape.bounds, x, y)
	}
	point := vector_point(x, y)
	if mode in [.paint, .fill] && vector_mesh_contains(shape.fill_triangles, point) { return true }
	return mode in [.paint, .stroke] && vector_mesh_contains(shape.stroke_triangles, point)
}

fn vector_mesh_contains(mesh []VectorTriangle, point VectorPoint) bool {
	for triangle in mesh {
		a := vector_cross(vector_sub(triangle.b, triangle.a), vector_sub(point, triangle.a))
		b := vector_cross(vector_sub(triangle.c, triangle.b), vector_sub(point, triangle.b))
		c := vector_cross(vector_sub(triangle.a, triangle.c), vector_sub(point, triangle.c))
		if (a >= -vector_epsilon && b >= -vector_epsilon && c >= -vector_epsilon) || (a <= vector_epsilon && b <= vector_epsilon && c <= vector_epsilon) {
			return true
		}
	}
	return false
}

fn vector_triangle(mut mesh []VectorTriangle, a VectorPoint, b VectorPoint, c VectorPoint) {
	if math.abs(vector_cross(vector_sub(b, a), vector_sub(c, a))) > vector_epsilon {
		mesh << VectorTriangle{a, b, c}
	}
}

fn vector_mesh_bounds(fill []VectorTriangle, stroke []VectorTriangle) Rect {
	mut left := math.inf(1)
	mut top := math.inf(1)
	mut right := math.inf(-1)
	mut bottom := math.inf(-1)
	for mesh in [fill, stroke] {
		for triangle in mesh {
			for point in [triangle.a, triangle.b, triangle.c] {
				left = math.min(left, point.x)
				right = math.max(right, point.x)
				top = math.min(top, point.y)
				bottom = math.max(bottom, point.y)
			}
		}
	}
	if math.is_inf(left, 0) { return Rect{} }
	return rect(left, top, right - left, bottom - top)
}
