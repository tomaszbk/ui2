module ui2

import math

// PaintVertex travels through the common convex clipper with interpolated UV
// and color. Coordinates are window-logical after affine projection. Consumers
// triangulate the returned convex polygon; device DPI belongs to submission.
pub struct PaintVertex {
pub:
	x f64
	y f64
	u f64
	v f64
	r f64 = 255
	g f64 = 255
	b f64 = 255
	a f64 = 255
}

// An unbounded region is the default. Bounded regions without finite convex
// area are empty, including public snapshots constructed with points directly.
// Regions are immutable snapshots, shared by paint, hit, hover and scroll.
pub struct ClipRegion {
	// Internal presentation snapshots copy small convex regions by value.
	// Public points snapshots and unusually complex regions own their arrays.
	inline_axis     [4]Point
	has_inline_axis bool
	inline_convex   [32]Point
	inline_count    int
pub:
	bounded bool
	points  []Point
}

fn (clip ClipRegion) axis_edges() (f64, f64, f64, f64, int) {
	if clip.has_inline_axis {
		return clip.inline_axis[0].x, clip.inline_axis[0].y, clip.inline_axis[2].x, clip.inline_axis[2].y, 1
	}
	if clip.inline_count > 0 {
		return clip_axis_edges(unsafe { borrow_points(&clip.inline_convex[0], clip.inline_count) })
	}
	return clip_axis_edges(clip.points)
}

fn (clip ClipRegion) basis() (Rect, int) {
	if clip.has_inline_axis {
		return rect(clip.inline_axis[0].x, clip.inline_axis[0].y,
			clip.inline_axis[2].x - clip.inline_axis[0].x, clip.inline_axis[2].y - clip.inline_axis[0].y), 1
	}
	if clip.inline_count > 0 {
		return clip_area(unsafe { borrow_points(&clip.inline_convex[0], clip.inline_count) })
	}
	return clip_basis(clip.points)
}

fn (clip ClipRegion) point_count() int {
	return if clip.has_inline_axis {
		4
	} else if clip.inline_count > 0 {
		clip.inline_count
	} else {
		clip.points.len
	}
}

fn (clip ClipRegion) point_at(index int) Point {
	return if clip.has_inline_axis {
		clip.inline_axis[index]
	} else if clip.inline_count > 0 {
		clip.inline_convex[index]
	} else {
		clip.points[index]
	}
}

fn (clip ClipRegion) inline_storage() bool {
	return clip.has_inline_axis || clip.inline_count > 0
}

// Fixed work buffers never expose a borrowed array. Their owned profile also
// serves large public polygons, so normalization shares one control flow.
struct ClipPointBuffer {
mut:
	fixed    bool
	storage  [64]Point
	length   int
	owned    []Point
	overflow bool
}

fn new_clip_point_buffer(fixed bool, capacity int) ClipPointBuffer {
	return ClipPointBuffer{
		fixed: fixed
		owned: if fixed {
			[]Point{}
		} else {
			[]Point{cap: capacity}
		}
	}
}

@[inline]
fn (buffer ClipPointBuffer) count() int {
	return if buffer.fixed { buffer.length } else { buffer.owned.len }
}

@[inline]
fn (buffer ClipPointBuffer) point(index int) Point {
	return if buffer.fixed { buffer.storage[index] } else { buffer.owned[index] }
}

@[inline]
fn (buffer ClipPointBuffer) pushed(point Point) ClipPointBuffer {
	mut result := buffer
	if buffer.fixed {
		if buffer.length == 64 {
			result.overflow = true
			return result
		}
		result.storage[buffer.length] = point
		result.length++
	} else {
		result.owned << point
	}
	return result
}

@[inline]
fn (buffer ClipPointBuffer) popped() ClipPointBuffer {
	mut result := buffer
	if buffer.fixed { result.length-- } else { result.owned.delete_last() }
	return result
}

@[inline]
fn (buffer ClipPointBuffer) cleared() ClipPointBuffer {
	mut result := buffer
	if buffer.fixed { result.length = 0 } else { result.owned.clear() }
	result.overflow = false
	return result
}

fn (buffer ClipPointBuffer) sorted() ClipPointBuffer {
	mut result := buffer
	if !buffer.fixed {
		result.owned.sort_with_compare(compare_clip_points)
		return result
	}
	for i in 1 .. buffer.length {
		point := result.storage[i]
		mut j := i - 1
		for j >= 0 && clip_point_order(result.storage[j], point) > 0 {
			result.storage[j + 1] = result.storage[j]
			j--
		}
		result.storage[j + 1] = point
	}
	return result
}

fn (buffer ClipPointBuffer) region(inline bool) ClipRegion {
	if !inline { return ClipRegion{ bounded: true, points: buffer.owned } }
	mut points := [32]Point{}
	for i in 0 .. buffer.count() { points[i] = buffer.point(i) }
	return ClipRegion{ bounded: true, inline_convex: points, inline_count: buffer.count() }
}

fn inline_axis_clip(left f64, top f64, right f64, bottom f64) ClipRegion {
	if !finite_number(left) || !finite_number(top) || !finite_number(right) || !finite_number(bottom)
		|| !finite_number(right - left) || !finite_number(bottom - top) || right <= left || bottom <= top {
		return ClipRegion{ bounded: true }
	}
	return ClipRegion{
		bounded:         true
		has_inline_axis: true
		inline_axis:     [Point{left, top}, Point{right, top}, Point{right, bottom},
			Point{left, bottom}]!
	}
}

// Internal presentation scopes keep immutable snapshots without heap-backed
// quads. The public transformed_clip API still returns owned points.
fn paint_transformed_clip(frame Rect, t ContentTransform) ClipRegion {
	if !finite_number(frame.x) || !finite_number(frame.y) || !finite_number(frame.width)
		|| !finite_number(frame.height) || frame.width <= 0 || frame.height <= 0 || !t.invertible() {
		return ClipRegion{ bounded: true }
	}
	if t.xy != 0 || t.yx != 0 {
		mut points := new_clip_point_buffer(true, 4)
		points = points.pushed(t.point(frame.x, frame.y))
		points = points.pushed(t.point(frame.x + frame.width, frame.y))
		points = points.pushed(t.point(frame.x + frame.width, frame.y + frame.height))
		points = points.pushed(t.point(frame.x, frame.y + frame.height))
		clip := points.region(true)
		extent, winding := clip.basis()
		if winding == 0 { return ClipRegion{ bounded: true } }
		if winding > 0 && !clip.has_redundant_points(extent) { return clip }
		return convex_clip_result_buffer(points, true)
	}
	first := t.point(frame.x, frame.y)
	last := t.point(frame.x + frame.width, frame.y + frame.height)
	return inline_axis_clip(math.min(first.x, last.x), math.min(first.y, last.y),
		math.max(first.x, last.x), math.max(first.y, last.y))
}

// Scale the two axes independently, after subtraction. World-space shoelace
// products lose small translated regions and overflow/underflow for large/tiny
// coordinates. This basis preserves their orientation without an area cutoff.
fn clip_side(extent Rect, a Point, b Point, x f64, y f64) f64 {
	_, x_exp := math.frexp(extent.width)
	_, y_exp := math.frexp(extent.height)
	dx := math.ldexp(b.x - a.x, -x_exp)
	dy := math.ldexp(b.y - a.y, -y_exp)
	px := math.ldexp(x - a.x, -x_exp)
	py := math.ldexp(y - a.y, -y_exp)
	left := dx * py
	right := dy * px
	// Power-of-two scaling preserves representable coordinates. Recover the
	// product residuals too, so cancellation does not erase a positive sliver.
	return (left - right) + (clip_product_error(dx, py, left) - clip_product_error(dy, px, right))
}

fn clip_product_error(a f64, b f64, product f64) f64 {
	// Bounded polygon coordinates are small after scaling. Distant queries can
	// exceed the split range; their ordinary side/finite checks still fail closed.
	if !finite_number(product) || math.abs(a) > 1e299 || math.abs(b) > 1e299 { return 0 }
	a_split := 134217729 * a
	a_high := a_split - (a_split - a)
	a_low := a - a_high
	b_split := 134217729 * b
	b_high := b_split - (b_split - b)
	b_low := b - b_high
	return ((a_high * b_high - product) + a_high * b_low + a_low * b_high) + a_low * b_low
}

fn clip_roundoff(extent Rect, a Point, b Point, x f64, y f64) f64 {
	_, x_exp := math.frexp(extent.width)
	_, y_exp := math.frexp(extent.height)
	dx := math.ldexp(b.x - a.x, -x_exp)
	dy := math.ldexp(b.y - a.y, -y_exp)
	px := math.ldexp(x - a.x, -x_exp)
	py := math.ldexp(y - a.y, -y_exp)
	return 8 * 2.220446049250313e-16 * (math.abs(dx * py) + math.abs(dy * px) +
		math.abs(dx) + math.abs(dy))
}

fn clip_area(points []Point) (Rect, int) {
	return clip_buffer_area(ClipPointBuffer{ owned: points })
}

fn clip_buffer_area(points ClipPointBuffer) (Rect, int) {
	if points.count() < 3 { return Rect{}, 0 }
	mut left := points.point(0).x
	mut right := left
	mut top := points.point(0).y
	mut bottom := top
	for i in 0 .. points.count() {
		p := points.point(i)
		if !finite_number(p.x) || !finite_number(p.y) { return Rect{}, 0 }
		left = math.min(left, p.x)
		right = math.max(right, p.x)
		top = math.min(top, p.y)
		bottom = math.max(bottom, p.y)
	}
	extent := rect(left, top, right - left, bottom - top)
	if !finite_number(extent.width) || !finite_number(extent.height)
		|| extent.width <= 0 || extent.height <= 0 {
		return Rect{}, 0
	}
	mut area := 0.0
	for i in 1 .. points.count() - 1 {
		end := points.point(i + 1)
		area += clip_side(extent, points.point(0), points.point(i), end.x, end.y)
	}
	if !finite_number(area) || area == 0 { return Rect{}, 0 }
	winding := if area > 0 { 1 } else { -1 }
	return extent, winding
}

// clip_axis_rect recognizes a finite four-vertex axis-aligned rectangle with
// positive area. Its basis and set operations need no general polygon work.
fn clip_axis_rect(points []Point) (Rect, int) {
	left, top, right, bottom, winding := clip_axis_edges(points)
	if winding == 0 { return Rect{}, 0 }
	return rect(left, top, right - left, bottom - top), winding
}

// clip_axis_edges returns exact edge coordinates; x + width can round.
fn clip_axis_edges(points []Point) (f64, f64, f64, f64, int) {
	if points.len != 4 { return 0, 0, 0, 0, 0 }
	a, b, c, d := points[0], points[1], points[2], points[3]
	mut winding := 0
	if a.y == b.y && b.x == c.x && c.y == d.y && d.x == a.x {
		winding = if (b.x > a.x) == (c.y > b.y) { 1 } else { -1 }
	} else if a.x == b.x && b.y == c.y && c.x == d.x && d.y == a.y {
		winding = if (b.y > a.y) != (c.x > b.x) { 1 } else { -1 }
	} else {
		return 0, 0, 0, 0, 0
	}
	left := math.min(a.x, c.x)
	top := math.min(a.y, c.y)
	right := math.max(a.x, c.x)
	bottom := math.max(a.y, c.y)
	if !finite_number(left) || !finite_number(top) || !finite_number(right) || !finite_number(bottom)
		|| !finite_number(right - left) || !finite_number(bottom - top) || right <= left || bottom <= top {
		return 0, 0, 0, 0, 0
	}
	return left, top, right, bottom, winding
}

fn clip_basis(points []Point) (Rect, int) {
	axis, axis_winding := clip_axis_rect(points)
	if axis_winding != 0 { return axis, axis_winding }
	extent, winding := clip_area(points)
	if winding == 0 { return Rect{}, 0 }
	// Public snapshots must bound a convex polygon, rather than an arbitrary set
	// of halfplanes (a concave/self-crossing sequence is not a clip region).
	for i, a in points {
		b := points[(i + 1) % points.len]
		for p in points {
			if clip_side(extent, a, b, p.x, p.y) * winding < -clip_roundoff(extent, a, b, p.x, p.y) {
				return Rect{}, 0
			}
		}
	}
	return extent, winding
}

fn compare_clip_points(a &Point, b &Point) int {
	return clip_point_order(a, b)
}

fn clip_point_order(a Point, b Point) int {
	if a.x < b.x || (a.x == b.x && a.y < b.y) { return -1 }
	if a.x == b.x && a.y == b.y { return 0 }
	return 1
}

// Intersections of validated convex operands are convex by construction. Hull
// normalization removes redundant/reversed turns caused by intersection
// roundoff, rather than rejecting a positive-area result or using an epsilon
// that could erase a genuine small sliver. Paint attributes are never hulled.
fn convex_clip_result(vertices []Point) ClipRegion {
	return convex_clip_result_storage(vertices, false)
}

// Both storage profiles share hull normalization and its robust area math.
// Inline results copy vertices and do not retain work buffers.
fn convex_clip_result_storage(vertices []Point, inline bool) ClipRegion {
	return convex_clip_result_buffer(ClipPointBuffer{ owned: vertices }, inline && vertices.len <= 32)
}

fn convex_clip_result_buffer(vertices ClipPointBuffer, inline bool) ClipRegion {
	extent, winding := clip_buffer_area(vertices)
	if winding == 0 { return ClipRegion{ bounded: true } }
	mut points := new_clip_point_buffer(inline, vertices.count())
	for i in 0 .. vertices.count() { points = points.pushed(vertices.point(i)) }
	points = points.sorted()
	mut lower := new_clip_point_buffer(inline, points.count())
	mut upper := new_clip_point_buffer(inline, points.count())
	for i in 0 .. points.count() {
		p := points.point(i)
		if lower.count() > 0 && p == lower.point(lower.count() - 1) { continue }
		for lower.count() >= 2 && clip_side(extent, lower.point(lower.count() - 2), lower.point(lower.count() - 1), p.x, p.y) <= 0 {
			lower = lower.popped()
		}
		lower = lower.pushed(p)
	}
	for i := points.count() - 1; i >= 0; i-- {
		p := points.point(i)
		if upper.count() > 0 && p == upper.point(upper.count() - 1) { continue }
		for upper.count() >= 2 && clip_side(extent, upper.point(upper.count() - 2), upper.point(upper.count() - 1), p.x, p.y) <= 0 {
			upper = upper.popped()
		}
		upper = upper.pushed(p)
	}
	lower = lower.popped()
	upper = upper.popped()
	for i in 0 .. upper.count() { lower = lower.pushed(upper.point(i)) }
	_, result_winding := clip_buffer_area(lower)
	if result_winding == 0 { return ClipRegion{ bounded: true } }
	return lower.region(inline)
}

fn (clip ClipRegion) normalized() ClipRegion {
	if !clip.bounded { return ClipRegion{} }
	if clip.inline_storage() { return clip }
	_, axis_winding := clip_axis_rect(clip.points)
	if axis_winding > 0 { return clip }
	extent, winding := clip.basis()
	if winding == 0 { return ClipRegion{ bounded: true } }
	// Valid canonical snapshots can be shared without allocating. Remove only
	// exact redundant vertices; tolerance must never erase a thin valid region.
	if !clip.has_redundant_points(extent) && winding > 0 { return clip }
	return convex_clip_result(clip.points)
}

fn (clip ClipRegion) has_redundant_points(extent Rect) bool {
	for i in 0 .. clip.point_count() {
		p := clip.point_at(i)
		previous := clip.point_at((i + clip.point_count() - 1) % clip.point_count())
		next := clip.point_at((i + 1) % clip.point_count())
		if p == previous || (clip_side(extent, previous, next, p.x, p.y) == 0
			&& p.x >= math.min(previous.x, next.x) && p.x <= math.max(previous.x, next.x)
			&& p.y >= math.min(previous.y, next.y) && p.y <= math.max(previous.y, next.y)) {
			return true
		}
	}
	return false
}

pub fn transformed_clip(frame Rect, t ContentTransform) ClipRegion {
	if !finite_number(frame.x) || !finite_number(frame.y) || !finite_number(frame.width) || !finite_number(frame.height) || frame.width <= 0 || frame.height <= 0 || !t.invertible() {
		return ClipRegion{ bounded: true }
	}
	return ClipRegion{ bounded: true, points: t.quad(frame) }.normalized()
}

pub fn (clip ClipRegion) contains(x f64, y f64) bool {
	if !finite_number(x) || !finite_number(y) { return false }
	if !clip.bounded { return true }
	if clip.has_inline_axis {
		extent, _ := clip.basis()
		nx := (x - extent.x) / extent.width
		ny := (y - extent.y) / extent.height
		edge_error := 8 * 2.220446049250313e-16
		return finite_number(nx) && finite_number(ny) && nx >= -edge_error && nx <= 1 + edge_error
			&& ny >= -edge_error && ny <= 1 + edge_error
	}
	extent, winding := clip.basis()
	if winding == 0 { return false }
	// A nearly collinear valid polygon still bounds a finite area. Halfplane
	// roundoff alone must not admit arbitrarily far extensions of its edges.
	nx := (x - extent.x) / extent.width
	ny := (y - extent.y) / extent.height
	edge_error := 8 * 2.220446049250313e-16
	if !finite_number(nx) || !finite_number(ny) || nx < -edge_error || nx > 1 + edge_error
		|| ny < -edge_error || ny > 1 + edge_error {
		return false
	}
	for i in 0 .. clip.point_count() {
		a := clip.point_at(i)
		b := clip.point_at((i + 1) % clip.point_count())
		side := clip_side(extent, a, b, x, y) * winding
		// Relative floating-point roundoff only, never an absolute cross/area
		// threshold that lets tiny regions contain arbitrary distant points.
		tolerance := clip_roundoff(extent, a, b, x, y)
		if !finite_number(side) || !finite_number(tolerance) || side < -tolerance { return false }
	}
	return true
}

pub fn (clip ClipRegion) bounds() Rect {
	if !clip.bounded { return Rect{} }
	extent, _ := clip.basis()
	return extent
}

fn lerp_vertex(a PaintVertex, b PaintVertex, t f64) PaintVertex {
	return PaintVertex{
		x: a.x + (b.x - a.x) * t
		y: a.y + (b.y - a.y) * t
		u: a.u + (b.u - a.u) * t
		v: a.v + (b.v - a.v) * t
		r: a.r + (b.r - a.r) * t
		g: a.g + (b.g - a.g) * t
		b: a.b + (b.b - a.b) * t
		a: a.a + (b.a - a.a) * t
	}
}

// Paint clipping borrows ping-pong storage for immediate submission. A window
// owns one buffer; growing an unusually complex polygon raises its high-water
// capacity once, and subsequent paints reuse it. No temporary is a clip snapshot.
struct PaintClipBuffer {
mut:
	first  []PaintVertex
	second []PaintVertex
}

fn new_paint_clip_buffer() PaintClipBuffer {
	return PaintClipBuffer{
		first:  []PaintVertex{cap: 80}
		second: []PaintVertex{cap: 80}
	}
}

// clip_axis_halfplane_into keeps x >= bound (or y, or <=) with the same
// nearer-endpoint interpolation as the general clipper.
fn clip_axis_halfplane_into(polygon []PaintVertex, horizontal bool, bound f64, keep_greater bool, mut output []PaintVertex) {
	output.clear()
	if polygon.len == 0 { return }
	mut previous := polygon[polygon.len - 1]
	mut previous_side := clip_axis_side(previous, horizontal, bound, keep_greater)
	if !finite_number(previous_side) { return }
	for current in polygon {
		side := clip_axis_side(current, horizontal, bound, keep_greater)
		if !finite_number(side) {
			output.clear()
			return
		}
		if (side >= 0) != (previous_side >= 0) {
			output << clip_edge_vertex(previous, current, previous_side, side)
		}
		if side >= 0 { output << current }
		previous = current
		previous_side = side
	}
}

fn clip_edge_vertex(previous PaintVertex, current PaintVertex, previous_side f64, side f64) PaintVertex {
	magnitude := math.max(math.abs(previous_side), math.abs(side))
	previous_fraction := math.abs(previous_side) / magnitude
	current_fraction := math.abs(side) / magnitude
	// Anchor at the nearer endpoint so a tiny fraction never rounds to 1 and
	// collapses a small but valid clipped polygon.
	return if previous_fraction <= current_fraction {
		lerp_vertex(previous, current, previous_fraction / (previous_fraction + current_fraction))
	} else {
		lerp_vertex(current, previous, current_fraction / (previous_fraction + current_fraction))
	}
}

fn clip_halfplane_into(polygon []PaintVertex, extent Rect, a Point, b Point, winding int, mut output []PaintVertex) {
	output.clear()
	if polygon.len == 0 { return }
	mut previous := polygon[polygon.len - 1]
	mut previous_side := clip_side(extent, a, b, previous.x, previous.y) * winding
	if !finite_number(previous_side) { return }
	for current in polygon {
		side := clip_side(extent, a, b, current.x, current.y) * winding
		if !finite_number(side) {
			output.clear()
			return
		}
		if (side >= 0) != (previous_side >= 0) {
			output << clip_edge_vertex(previous, current, previous_side, side)
		}
		if side >= 0 { output << current }
		previous = current
		previous_side = side
	}
}

fn clip_axis_side(v PaintVertex, horizontal bool, bound f64, keep_greater bool) f64 {
	coordinate := if horizontal { v.x } else { v.y }
	return if keep_greater { coordinate - bound } else { bound - coordinate }
}

// paint_polygon_has_area matches clip_area for paint vertices, without copying them.
fn paint_polygon_has_area(vertices []PaintVertex) bool {
	if vertices.len < 3 { return false }
	mut left := vertices[0].x
	mut right := left
	mut top := vertices[0].y
	mut bottom := top
	for v in vertices {
		if !finite_number(v.x) || !finite_number(v.y) { return false }
		left = math.min(left, v.x)
		right = math.max(right, v.x)
		top = math.min(top, v.y)
		bottom = math.max(bottom, v.y)
	}
	extent := rect(left, top, right - left, bottom - top)
	if !finite_number(extent.width) || !finite_number(extent.height) || extent.width <= 0
		|| extent.height <= 0 {
		return false
	}
	origin := Point{vertices[0].x, vertices[0].y}
	mut area := 0.0
	for i in 1 .. vertices.len - 1 {
		area += clip_side(extent, origin, Point{vertices[i].x, vertices[i].y}, vertices[i + 1].x, vertices[i + 1].y)
	}
	return finite_number(area) && area != 0
}

// Public clipping returns an owned result. Paint instead borrows the retained
// window buffer until submission has consumed it.
pub fn (clip ClipRegion) clip_polygon(vertices []PaintVertex) []PaintVertex {
	mut buffer := PaintClipBuffer{}
	return clip.clip_polygon_buffered(vertices, mut buffer)
}

fn (clip ClipRegion) clip_polygon_buffered(vertices []PaintVertex, mut buffer PaintClipBuffer) []PaintVertex {
	if !clip.bounded { return vertices }
	extent, winding := clip.basis()
	if winding == 0 || vertices.len < 3 { return []PaintVertex{} }
	for v in vertices {
		if !finite_number(v.x) || !finite_number(v.y) { return []PaintVertex{} }
	}
	left, top, right, bottom, axis_winding := clip.axis_edges()
	mut polygon := unsafe { vertices }
	mut use_first := true
	if axis_winding != 0 {
		// Axis-aligned halfplanes have exact signed distances. Clip only crossed
		// edges; wholly inside paint keeps the caller's vertex storage.
		mut outside := [4]bool{}
		mut beyond := [true, true, true, true]!
		for v in vertices {
			outside[0] = outside[0] || v.y < top
			outside[1] = outside[1] || v.x > right
			outside[2] = outside[2] || v.y > bottom
			outside[3] = outside[3] || v.x < left
			beyond[0] = beyond[0] && v.y < top
			beyond[1] = beyond[1] && v.x > right
			beyond[2] = beyond[2] && v.y > bottom
			beyond[3] = beyond[3] && v.x < left
		}
		for value in beyond { if value { return []PaintVertex{} } }
		edge_bounds := [top, right, bottom, left]!
		for edge in 0 .. 4 {
			if !outside[edge] { continue }
			if use_first {
				clip_axis_halfplane_into(polygon, edge % 2 == 1, edge_bounds[edge], edge == 0 || edge == 3, mut buffer.first)
				polygon = unsafe { buffer.first }
			} else {
				clip_axis_halfplane_into(polygon, edge % 2 == 1, edge_bounds[edge], edge == 0 || edge == 3, mut buffer.second)
				polygon = unsafe { buffer.second }
			}
			use_first = !use_first
		}
	} else {
		for i in 0 .. clip.point_count() {
			if polygon.len == 0 { break }
			a := clip.point_at(i)
			b := clip.point_at((i + 1) % clip.point_count())
			if use_first {
				clip_halfplane_into(polygon, extent, a, b, winding, mut buffer.first)
				polygon = unsafe { buffer.first }
			} else {
				clip_halfplane_into(polygon, extent, a, b, winding, mut buffer.second)
				polygon = unsafe { buffer.second }
			}
			use_first = !use_first
		}
	}
	// Tangency submits no triangles. Keep all attribute-bearing vertices in
	// positive-area polygons, including coincident UV/color seams.
	return if paint_polygon_has_area(polygon) { polygon } else { []PaintVertex{} }
}

pub fn (clip ClipRegion) intersect(other ClipRegion) ClipRegion {
	left := clip.normalized()
	right := other.normalized()
	if !left.bounded { return right }
	if !right.bounded { return left }
	l0, t0, r0, b0, left_axis := left.axis_edges()
	l1, t1, r1, b1, right_axis := right.axis_edges()
	if left_axis != 0 && right_axis != 0 {
		x0, y0 := math.max(l0, l1), math.max(t0, t1)
		x1, y1 := math.min(r0, r1), math.min(b0, b1)
		if x1 <= x0 || y1 <= y0 { return ClipRegion{ bounded: true } }
		if left.inline_storage() || right.inline_storage() {
			return inline_axis_clip(x0, y0, x1, y1)
		}
		return ClipRegion{
			bounded: true
			points:  [Point{x0, y0}, Point{x1, y0}, Point{x1, y1}, Point{x0, y1}]
		}
	}
	if (left.inline_storage() || right.inline_storage()) && left.point_count() <= 32 && right.point_count() <= 32 {
		return intersect_inline_convex(left, right)
	}
	return intersect_owned_convex(left, right)
}

fn intersect_owned_convex(left ClipRegion, right ClipRegion) ClipRegion {
	mut vertices := []PaintVertex{cap: right.point_count()}
	for i in 0 .. right.point_count() {
		p := right.point_at(i)
		vertices << PaintVertex{ x: p.x, y: p.y }
	}
	return convex_clip_result(left.clip_polygon(vertices).map(Point{it.x, it.y}))
}

// A convex n-vertex subject clipped by m halfplanes has at most n + m
// intermediate vertices. Two 32-vertex operands therefore fit these work
// buffers; a result beyond the inline capacity promotes to an owned snapshot.
fn intersect_inline_convex(left ClipRegion, right ClipRegion) ClipRegion {
	mut polygon := new_clip_point_buffer(true, 32)
	mut output := new_clip_point_buffer(true, 64)
	for i in 0 .. right.point_count() {
		polygon = polygon.pushed(right.point_at(i))
	}
	extent, winding := left.basis()
	if winding == 0 { return ClipRegion{ bounded: true } }
	for i in 0 .. left.point_count() {
		if polygon.count() == 0 { break }
		output = clip_point_halfplane(polygon, extent, left.point_at(i), left.point_at((i + 1) % left.point_count()), winding, output)
		if output.overflow { return intersect_owned_convex(left, right) }
		previous := polygon
		polygon = output
		output = previous
	}
	return convex_clip_result_buffer(polygon, polygon.count() <= 32)
}

fn clip_point_halfplane(polygon ClipPointBuffer, extent Rect, a Point, b Point, winding int, target ClipPointBuffer) ClipPointBuffer {
	mut output := target.cleared()
	if polygon.count() == 0 { return output }
	mut previous := polygon.point(polygon.count() - 1)
	mut previous_side := clip_side(extent, a, b, previous.x, previous.y) * winding
	if !finite_number(previous_side) { return output }
	for i in 0 .. polygon.count() {
		current := polygon.point(i)
		side := clip_side(extent, a, b, current.x, current.y) * winding
		if !finite_number(side) {
			return output.cleared()
		}
		if (side >= 0) != (previous_side >= 0) {
			vertex := clip_edge_vertex(PaintVertex{ x: previous.x, y: previous.y }, PaintVertex{ x: current.x, y: current.y }, previous_side, side)
			output = output.pushed(Point{vertex.x, vertex.y})
		}
		if side >= 0 { output = output.pushed(current) }
		previous = current
		previous_side = side
	}
	return output
}

// Inclusive conservative broad phase. Inverse/projection roundoff must not
// discard a painted boundary before the exact narrow phase can inspect it.
pub fn presentation_bounds_contains(frame Rect, x f64, y f64) bool {
	return finite_number(x) && finite_number(y) && finite_number(frame.x) && finite_number(frame.y)
		&& finite_number(frame.width) && finite_number(frame.height) && frame.width > 0 && frame.height > 0
		&& x >= frame.x - 1e-8 && x <= frame.x + frame.width + 1e-8
		&& y >= frame.y - 1e-8 && y <= frame.y + frame.height + 1e-8
}

// Shared exact narrow phase. Bounds may accelerate this test but never replace it.
pub fn transformed_contains(frame Rect, t ContentTransform, clip ClipRegion, x f64, y f64) bool {
	if !t.invertible() || !clip.contains(x, y) { return false }
	lx, ly := t.inverse(x, y)
	return presentation_bounds_contains(frame, lx, ly)
}
