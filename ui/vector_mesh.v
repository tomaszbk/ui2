module ui2

import math

struct VectorEdge {
	a VectorPoint
	b VectorPoint
}

struct VectorCrossing {
	x       f64
	edge    VectorEdge
	winding int
}

fn vector_edge_x(edge VectorEdge, y f64) f64 {
	return edge.a.x + (edge.b.x - edge.a.x) * (y - edge.a.y) / (edge.b.y - edge.a.y)
}

// Sweep horizontal slabs, splitting at every vertex and edge intersection.
// Within a slab the winding intervals are trapezoids. This handles concavity,
// multiple contours, holes and self intersections with the same fill contract.
fn vector_fill_mesh(contours []VectorContour, rule VectorFillRule) ![]VectorTriangle {
	mut edges := []VectorEdge{}
	mut levels := []f64{}
	for contour in contours {
		if contour.points.len < 3 { continue }
		for index, a in contour.points {
			b := contour.points[(index + 1) % contour.points.len]
			levels << a.y
			if math.abs(a.y - b.y) > vector_epsilon { edges << VectorEdge{a, b} }
		}
	}
	for i, edge in edges {
		for j in i + 1 .. edges.len {
			other := edges[j]
			r := vector_sub(edge.b, edge.a)
			s := vector_sub(other.b, other.a)
			denominator := vector_cross(r, s)
			if math.abs(denominator) <= vector_epsilon { continue }
			delta := vector_sub(other.a, edge.a)
			t := vector_cross(delta, s) / denominator
			u := vector_cross(delta, r) / denominator
			if t > 0 && t < 1 && u > 0 && u < 1 {
				levels << edge.a.y + t * r.y
				if levels.len > 32768 { return error('vector fill exceeds 32768 sweep levels') }
			}
		}
	}
	levels.sort()
	mut unique := []f64{}
	for level in levels {
		if unique.len == 0 || level - unique.last() > vector_epsilon { unique << level }
	}
	mut mesh := []VectorTriangle{}
	if unique.len < 2 { return mesh }
	for i in 0 .. unique.len - 1 {
		top := unique[i]
		bottom := unique[i + 1]
		mid := (top + bottom) * 0.5
		mut crossings := []VectorCrossing{}
		for edge in edges {
			if mid > math.min(edge.a.y, edge.b.y) && mid < math.max(edge.a.y, edge.b.y) {
				crossings << VectorCrossing{ x: vector_edge_x(edge, mid), edge: edge, winding: if edge.b.y > edge.a.y {
					1
				} else {
					-1
				} }
			}
		}
		crossings.sort(a.x < b.x)
		mut winding := 0
		for k in 0 .. crossings.len {
			winding += crossings[k].winding
			inside := if rule == .nonzero { winding != 0 } else { winding % 2 != 0 }
			if !inside || k + 1 == crossings.len { continue }
			left := crossings[k].edge
			right := crossings[k + 1].edge
			a := vector_point(vector_edge_x(left, top), top)
			b := vector_point(vector_edge_x(right, top), top)
			c := vector_point(vector_edge_x(right, bottom), bottom)
			d := vector_point(vector_edge_x(left, bottom), bottom)
			vector_triangle(mut mesh, a, b, c)
			vector_triangle(mut mesh, a, c, d)
			if mesh.len > 131072 { return error('vector fill exceeds 131072 triangles') }
		}
	}
	return mesh
}

fn vector_round_arc(mut mesh []VectorTriangle, center VectorPoint, a VectorPoint, b VectorPoint, radius f64, sweep f64, tolerance f64) ! {
	if radius <= 0 { return }
	// Inscribed arc, with maximum chord error <= tolerance. Limit each chord
	// to 45 degrees even at coarse tolerances, so a semicircle never collapses.
	step := 2 * math.acos(math.max(-1.0, math.min(1.0, 1 - tolerance / radius)))
	count := int(math.max(1.0, math.ceil(math.abs(sweep) / math.min(step, math.pi / 4))))
	if count > 4096 { return error('vector round stroke exceeds 4096 arc segments') }
	if mesh.len + count > 131072 { return error('vector stroke exceeds 131072 triangles') }
	start := math.atan2(a.y - center.y, a.x - center.x)
	mut previous := a
	for i in 0 .. count {
		angle := start + sweep * f64(i + 1) / f64(count)
		// Exact normal endpoints keep the arc joined to both segment quads.
		next := if i + 1 == count { b } else { vector_point(center.x + radius * math.cos(angle), center.y + radius * math.sin(angle)) }
		vector_triangle(mut mesh, center, previous, next)
		previous = next
	}
}

fn vector_disk(mut mesh []VectorTriangle, center VectorPoint, radius f64, tolerance f64) ! {
	edge := vector_point(center.x + radius, center.y)
	vector_round_arc(mut mesh, center, edge, edge, radius, 2 * math.pi, tolerance)!
}

fn vector_stroke_join(mut mesh []VectorTriangle, previous VectorPoint, point VectorPoint, next VectorPoint, style VectorStyle) ! {
	radius := style.stroke_width / 2
	d1 := vector_sub(point, previous)
	d2 := vector_sub(next, point)
	u1 := vector_mul(d1, 1 / vector_length(d1))
	u2 := vector_mul(d2, 1 / vector_length(d2))
	// Normalization can introduce a tiny cross product even for exactly
	// collinear segments of different lengths. Preserve their zero turn.
	turn := if vector_cross(d1, d2) == 0 { 0.0 } else { vector_cross(u1, u2) }
	dot := u1.x * u2.x + u1.y * u2.y
	// Positive dot distinguishes straight-through from a reversing cusp.
	// Keep small nonzero round turns: their displacement can exceed tolerance
	// at large widths even when the normalized cross product is tiny.
	if turn == 0 && dot > 0 { return }
	if style.join != .round && math.abs(turn) <= vector_epsilon { return }
	side := if turn >= 0 { -1.0 } else { 1.0 }
	a := vector_add(point, vector_point(-u1.y * radius * side, u1.x * radius * side))
	b := vector_add(point, vector_point(-u2.y * radius * side, u2.x * radius * side))
	if style.join == .round {
		// The signed turn sweeps only the outer corner. An exact reversal uses
		// the incoming forward semicircle, rather than filling behind the cusp.
		sweep := if turn == 0 && dot < 0 { math.pi } else { math.atan2(turn, dot) }
		vector_round_arc(mut mesh, point, a, b, radius, sweep, style.tolerance)!
		return
	}
	if style.join == .miter {
		t := vector_cross(vector_sub(b, a), u2) / turn
		miter := vector_add(a, vector_mul(u1, t))
		if vector_length(vector_sub(miter, point)) <= radius * style.miter_limit {
			vector_triangle(mut mesh, point, a, miter)
			vector_triangle(mut mesh, point, miter, b)
			return
		}
	}
	vector_triangle(mut mesh, point, a, b)
}

fn vector_stroke_mesh(contours []VectorContour, style VectorStyle) ![]VectorTriangle {
	mut mesh := []VectorTriangle{}
	if style.stroke_width == 0 { return mesh }
	radius := style.stroke_width / 2
	for contour in contours {
		points := contour.points
		if points.len < 2 {
			if points.len == 1 && !contour.closed && style.cap == .round {
				vector_disk(mut mesh, points[0], radius, style.tolerance)!
			}
			// A zero-length path has no tangent; butt/square and closed points paint nothing.
			continue
		}
		segments := if contour.closed { points.len } else { points.len - 1 }
		for index in 0 .. segments {
			mut a := points[index]
			mut b := points[(index + 1) % points.len]
			d := vector_sub(b, a)
			u := vector_mul(d, 1 / vector_length(d))
			n := vector_point(-u.y * radius, u.x * radius)
			if !contour.closed && style.cap == .square {
				if index == 0 { a = vector_sub(a, vector_mul(u, radius)) }
				if index == segments - 1 { b = vector_add(b, vector_mul(u, radius)) }
			}
			vector_triangle(mut mesh, vector_add(a, n), vector_sub(a, n), vector_sub(b, n))
			vector_triangle(mut mesh, vector_add(a, n), vector_sub(b, n), vector_add(b, n))
		}
		for index in 0 .. points.len {
			if !contour.closed && (index == 0 || index == points.len - 1) {
				if style.cap == .round {
					vector_disk(mut mesh, points[index], radius, style.tolerance)!
				}
			} else {
				vector_stroke_join(mut mesh, points[(index + points.len - 1) % points.len], points[index], points[(index + 1) % points.len], style)!
			}
			if mesh.len > 131072 { return error('vector stroke exceeds 131072 triangles') }
		}
	}
	return mesh
}
