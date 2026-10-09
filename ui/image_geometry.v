module ui2

import math

// Fits are centered by default. none and scale_down use logical intrinsic size.
pub enum ImageFit {
	contain
	cover
	fill
	none
	scale_down
}

pub struct ImageTint {
pub:
	r u8 = 255
	g u8 = 255
	b u8 = 255
	a u8 = 255
}

pub struct ImageStyle {
pub:
	fit  ImageFit
	tint ImageTint
	// Normalized source bounds, independent of the selected density variant.
	source  Rect = Rect{ width: 1, height: 1 }
	align_x f64  = 0.5
	align_y f64  = 0.5
}

pub struct ImageVariant {
pub:
	path    string
	density f64 = 1
}

// The base path (Element.image_path) has density 1. Variants require an explicit
// logical_size so changing DPI cannot change layout, fitting or hit geometry.
pub struct ImageAsset {
pub:
	logical_size LayoutSize
	variants     []ImageVariant
	// Bump revision when replacing a file in place, including same-size writes
	// within the filesystem's timestamp resolution.
	revision u64
}

pub fn (asset ImageAsset) validate() ! {
	w, h := asset.logical_size.width, asset.logical_size.height
	if !math.is_finite(w) || !math.is_finite(h) || w < 0 || h < 0 || (w == 0) != (h == 0) {
		return error('image logical_size must have two finite positive dimensions or be omitted')
	}
	if asset.variants.len > 0 && w == 0 {
		return error('image DPI variants require logical_size')
	}
	if asset.variants.len == 0 { return }
	mut densities := map[f64]bool{
		1.0: true
	}
	for variant in asset.variants {
		if variant.path.trim_space().len == 0 || !math.is_finite(variant.density) || variant.density <= 0 {
			return error('image variants require a path and finite positive density')
		}
		if variant.density in densities {
			return error('duplicate image variant density ${variant.density}')
		}
		densities[variant.density] = true
	}
}

pub fn (style ImageStyle) validate() ! {
	for v in [style.align_x, style.align_y, style.source.x, style.source.y, style.source.width,
		style.source.height] {
		if !math.is_finite(v) { return error('image style geometry must be finite') }
	}
	if style.align_x < 0 || style.align_x > 1 || style.align_y < 0 || style.align_y > 1 {
		return error('image alignment must be between 0 and 1')
	}
	if style.source.x < 0 || style.source.y < 0 || style.source.width <= 0 || style.source.height <= 0
		|| style.source.x + style.source.width > 1 || style.source.y + style.source.height > 1 {
		return error('image source must be a positive normalized rectangle inside 0..1')
	}
}

pub struct ImagePoint {
pub:
	x f64
	y f64
}

// Points are clockwise (top-left, top-right, bottom-right, bottom-left), in
// composition-logical coordinates. UV bounds remain normalized to the asset.
pub struct ImageGeometry {
pub:
	points [4]ImagePoint
	source Rect
	bounds Rect
	// Density needed before content/device scale, including cover enlargement.
	density f64
}

// Fit and UV geometry stays local. Element.visual_transform owns rotation;
// the shared affine projects these points once for paint and interaction.
pub fn image_geometry(frame Rect, intrinsic LayoutSize, style ImageStyle) !ImageGeometry {
	style.validate()!
	for v in [frame.x, frame.y, frame.width, frame.height, intrinsic.width, intrinsic.height] {
		if !math.is_finite(v) { return error('image geometry must be finite') }
	}
	if intrinsic.width <= 0 || intrinsic.height <= 0 || frame.width <= 0 || frame.height <= 0 {
		return error('image geometry requires positive frame and intrinsic size')
	}
	sw := intrinsic.width * style.source.width
	sh := intrinsic.height * style.source.height
	if sw <= 0 || sh <= 0 { return error('image source has no representable extent') }
	sx, sy := frame.width / sw, frame.height / sh
	mut factor := f64(1)
	match style.fit {
		.contain { factor = math.min(sx, sy) }
		.cover { factor = math.max(sx, sy) }
		.scale_down { factor = math.min(f64(1), math.min(sx, sy)) }
		.none, .fill {}
	}
	w := if style.fit == .fill { frame.width } else { sw * factor }
	h := if style.fit == .fill { frame.height } else { sh * factor }
	if !math.is_finite(w) || !math.is_finite(h) || !math.is_finite(factor) || w <= 0 || h <= 0 {
		return error('image fitted extent must be finite and positive')
	}
	full := rect(frame.x + (frame.width - w) * style.align_x,
		frame.y + (frame.height - h) * style.align_y, w, h)
	visible := intersect_rect(frame, full)
	source := rect(style.source.x + (visible.x - full.x) / w * style.source.width,
		style.source.y + (visible.y - full.y) / h * style.source.height,
		visible.width / w * style.source.width, visible.height / h * style.source.height)
	mut points := [4]ImagePoint{}
	mut min_x, min_y := math.inf(1), math.inf(1)
	mut max_x, max_y := math.inf(-1), math.inf(-1)
	for i, p in [ImagePoint{visible.x, visible.y}, ImagePoint{visible.x + visible.width, visible.y},
		ImagePoint{visible.x + visible.width, visible.y + visible.height},
		ImagePoint{visible.x, visible.y + visible.height}] {
		x, y := p.x, p.y
		points[i] = ImagePoint{x, y}
		min_x = math.min(min_x, x)
		min_y = math.min(min_y, y)
		max_x = math.max(max_x, x)
		max_y = math.max(max_y, y)
	}
	return ImageGeometry{
		points:  points
		source:  source
		bounds:  rect(min_x, min_y, max_x - min_x, max_y - min_y)
		density: if style.fit == .fill { math.max(sx, sy) } else { factor }
	}
}

// Rectangular visible-quad hits include transparent pixels; letterboxing and
// the corners outside a rotated quad do not hit. Boundaries are inclusive.
pub fn (geometry ImageGeometry) contains(x f64, y f64) bool {
	if geometry.bounds.width <= 0 || geometry.bounds.height <= 0 || !math.is_finite(x) || !math.is_finite(y) {
		return false
	}
	for i, a in geometry.points {
		b := geometry.points[(i + 1) % 4]
		if (b.x - a.x) * (y - a.y) - (b.y - a.y) * (x - a.x) < -0.000000001 { return false }
	}
	return true
}

// Pick the smallest adequate density, or the largest available. The base is
// always 1x; array order has no effect. Quality scale never changes logical size.
pub fn select_image_variant(path string, asset ImageAsset, required_density f64) !ImageVariant {
	asset.validate()!
	if path.trim_space().len == 0 || !math.is_finite(required_density) || required_density <= 0 {
		return error('image selection requires a base path and positive finite density')
	}
	mut best := ImageVariant{ path: path }
	for v in asset.variants {
		if (best.density < required_density && v.density > best.density)
			|| (v.density >= required_density && v.density < best.density) {
			best = v
		}
	}
	return best
}

pub struct ImageResourceStats {
pub:
	decodes         u64
	cache_hits      u64
	uploads         u64
	pages_created   u64
	pages_destroyed u64
	entries         int
	pages           int
	// Each page owns one texture and one sampler, including oversized images.
	textures int
	samplers int
}

// Validate explicitly for native hosts, also usable by headless tooling.
pub fn validate_native_image(el Element) ! {
	if el.kind == .image && (el.rotation != 0 || el.clickable || el.draggable || el.long_press || el.swipe_left
		|| voidptr(el.on_event) != unsafe { nil } || el.menu.len > 0 || el.tooltip.len > 0 || el.cursor.len > 0) {
		return error('image rotation and visible-quad interaction require the custom renderer (${el.id})')
	}
	$if windows {
		if el.kind == .image {
			if el.image_asset == ImageAsset{} && el.image_style == ImageStyle{ fit: .fill } && el.rotation == 0 {
				return
			}
			return error('Windows native images require BMP with fit .fill, no crop/tint/DPI/rotation; use the custom renderer (${el.id})')
		}
	}
	if el.image_asset != ImageAsset{} || el.image_style != ImageStyle{} {
		return error('image fit/source/tint/alignment and DPI assets require the custom renderer (${el.id})')
	}
}
