module ui2

import math

struct BorderPoint {
	x f64
	y f64
}

struct BorderTriangle {
	a     BorderPoint
	b     BorderPoint
	c     BorderPoint
	color u32
}

// A border is a closed ring tessellated into colored side strips. Matching
// outer/inner vertices share joins, so corners neither overlap nor leave gaps.
fn box_border_triangles(frame Rect, box BoxStyle) []BorderTriangle {
	if frame.width <= 0 || frame.height <= 0 || !box_draws_border(box) {
		return []BorderTriangle{}
	}
	mut left := box_border_width(box.border_left, frame.width)
	mut right := box_border_width(box.border_right, frame.width)
	mut top := box_border_width(box.border_top, frame.height)
	mut bottom := box_border_width(box.border_bottom, frame.height)
	if left + right > frame.width {
		factor := frame.width / (left + right)
		left *= factor
		right *= factor
	}
	if top + bottom > frame.height {
		factor := frame.height / (top + bottom)
		top *= factor
		bottom *= factor
	}
	radius := math.max(0, math.min(box.radius, math.min(frame.width, frame.height) / 2))
	inner := Rect{
		x:      frame.x + left
		y:      frame.y + top
		width:  frame.width - left - right
		height: frame.height - top - bottom
	}
	mut outer_points := []BorderPoint{}
	mut inner_points := []BorderPoint{}
	mut sides := []int{}
	// Begin halfway around top-left, then follow the perimeter clockwise.
	for corner in 0 .. 5 {
		actual := corner % 4
		start := if corner == 0 { 225.0 } else { 180.0 + f64(actual) * 90 }
		end := if corner == 4 { 225.0 } else { 270.0 + f64(actual) * 90 }
		steps := if radius > 0 {
			if corner == 0 || corner == 4 { 8 } else { 16 }
		} else {
			2
		}
		for index in 0 .. steps + 1 {
			angle := start + (end - start) * f64(index) / f64(steps)
			outer_points << border_corner_point(frame, actual, radius, radius, angle)
			rx := math.max(0, radius - if actual == 0 || actual == 3 { left } else { right })
			ry := math.max(0, radius - if actual == 0 || actual == 1 { top } else { bottom })
			inner_points << border_corner_point(inner, actual, rx, ry, angle)
			// A corner's halves meet on its diagonal; sides use their own colors.
			sides << if angle < 225 + f64(actual) * 90 { (actual + 3) % 4 } else { actual }
		}
	}
	mut triangles := []BorderTriangle{}
	mut distance := 0.0
	for index in 1 .. outer_points.len {
		a := outer_points[index - 1]
		b := outer_points[index]
		ia := inner_points[index - 1]
		ib := inner_points[index]
		length := math.sqrt((b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y))
		if length < 0.0000001 { continue }
		// Between corners the destination owns the edge; inside a corner the
		// midpoint of the segment determines the half (avoid one-step bias).
		side := sides[index - 1]
		color := box_edge_color(box, side)
		mut cursor := 0.0
		for cursor < length - 0.0000001 {
			mut amount := length - cursor
			mut paint := true
			if box.border_pattern == .dashed && box.dash_length > 0 && box.dash_gap > 0 {
				period := box.dash_length + box.dash_gap
				phase := math.fmod(distance + cursor, period)
				paint = phase < box.dash_length
				amount = math.min(amount, if paint {
					box.dash_length - phase
				} else {
					period - phase
				})
			}
			if amount < 0.0000001 { amount = math.min(0.000001, length - cursor) }
			if paint {
				ta := cursor / length
				tb := (cursor + amount) / length
				p := border_lerp(a, b, ta)
				q := border_lerp(a, b, tb)
				ip := border_lerp(ia, ib, ta)
				iq := border_lerp(ia, ib, tb)
				triangles << BorderTriangle{ a: p, b: q, c: iq, color: color }
				triangles << BorderTriangle{ a: p, b: iq, c: ip, color: color }
			}
			cursor += amount
		}
		distance += length
	}
	return triangles
}

fn border_lerp(a BorderPoint, b BorderPoint, t f64) BorderPoint {
	return BorderPoint{ x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t }
}

fn border_corner_point(frame Rect, corner int, rx f64, ry f64, degrees f64) BorderPoint {
	cx := if corner == 0 || corner == 3 { frame.x + rx } else { frame.x + frame.width - rx }
	cy := if corner == 0 || corner == 1 { frame.y + ry } else { frame.y + frame.height - ry }
	angle := degrees * math.pi / 180
	return BorderPoint{ x: cx + rx * math.cos(angle), y: cy + ry * math.sin(angle) }
}
