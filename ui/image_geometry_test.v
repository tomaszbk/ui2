module ui2

import math

fn image_near(a f64, b f64) bool { return math.abs(a - b) < 0.00000001 }

fn test_image_fits_have_independent_destination_and_crop_fixtures() {
	frame := rect(10.25, 20.5, 100, 100)
	size := LayoutSize{ width: 200, height: 100 }
	contain := image_geometry(frame, size, ImageStyle{}, 0)!
	assert contain.bounds == rect(10.25, 45.5, 100, 50)
	assert contain.source == rect(0, 0, 1, 1)
	assert !contain.contains(60.25, 30)
	assert contain.contains(60.25, 45.5)
	cover := image_geometry(frame, size, ImageStyle{ fit: .cover }, 0)!
	assert cover.bounds == frame
	assert cover.source == rect(0.25, 0, 0.5, 1)
	fill := image_geometry(frame, size, ImageStyle{ fit: .fill }, 0)!
	assert fill.bounds == frame
	assert fill.source == rect(0, 0, 1, 1)
	natural := image_geometry(frame, size, ImageStyle{ fit: .none }, 0)!
	assert natural.bounds == frame
	assert natural.source == rect(0.25, 0, 0.5, 1)
	down := image_geometry(frame, size, ImageStyle{ fit: .scale_down }, 0)!
	assert down.bounds == contain.bounds
	// none and scale_down never enlarge the logical intrinsic dimensions.
	for fit in [ImageFit.none, .scale_down] {
		g := image_geometry(frame, LayoutSize{ width: 40, height: 20 }, ImageStyle{ fit: fit }, 0)!
		assert g.bounds == rect(40.25, 60.5, 40, 20)
	}
	left := image_geometry(frame, size, ImageStyle{ fit: .cover, align_x: 0 }, 0)!
	assert left.source == rect(0, 0, 0.5, 1)
	right := image_geometry(frame, size, ImageStyle{ fit: .cover, align_x: 1 }, 0)!
	assert right.source == rect(0.5, 0, 0.5, 1)
}

fn test_image_source_crop_rotation_and_fractional_projection_are_coherent() {
	crop := image_geometry(rect(0, 0, 100, 100), LayoutSize{ width: 200, height: 100 },
		ImageStyle{ source: rect(0.5, 0, 0.25, 1) }, 90)!
	// The 50x100 crop fits without resizing and rotates clockwise about 50,50.
	assert image_near(crop.points[0].x, 100)
	assert image_near(crop.points[0].y, 25)
	assert image_near(crop.points[1].x, 100)
	assert image_near(crop.points[1].y, 75)
	assert crop.contains(10, 50)
	assert !crop.contains(50, 10)
	square := image_geometry(rect(0, 0, 100, 100), LayoutSize{ width: 100, height: 100 }, ImageStyle{}, 45)!
	assert !square.contains(-10, -10)
	assert square.contains(50, 50)
	original := image_geometry(rect(0.25, 0.75, 100.5, 80.25), LayoutSize{ width: 200, height: 100 }, ImageStyle{}, 33)!
	for dpi in [1.0, 1.25, 1.5, 2.0] {
		transform := ContentTransform{ scale: 0.5, x: 10.25, y: 20.75 }
		p := original.points[0]
		projected := transform.project(rect(p.x, p.y, 0, 0))
		physical_x, physical_y := projected.x * dpi, projected.y * dpi
		lx, ly := transform.inverse(physical_x / dpi, physical_y / dpi)
		assert image_near(lx, p.x) && image_near(ly, p.y)
		assert original.contains(lx, ly)
	}
}

fn test_image_variant_selection_uses_density_and_preserves_intrinsic_layout() {
	asset := ImageAsset{
		logical_size: LayoutSize{ width: 40, height: 20 }
		variants:     [
			ImageVariant{ path: '3.png', density: 3 },
			ImageVariant{ path: '2.png', density: 2 },
		]
	}
	for required, expected in {
		0.5:  '1.png'
		1.0:  '1.png'
		1.25: '2.png'
		1.5:  '2.png'
		2.0:  '2.png'
		2.01: '3.png'
		5.0:  '3.png'
	} {
		assert select_image_variant('1.png', asset, required)!.path == expected
	}
	el := Element{ ...image('i', '1.png', Rect{}), image_asset: asset }
	assert measure_layout_element(el, LayoutConstraints{}, unsafe { nil })! == LayoutSize{ width: 40, height: 20 }
	assert image_geometry(rect(0, 0, 80, 80), asset.logical_size, ImageStyle{ fit: .cover }, 0)!.density == 4
}

fn test_image_invalid_assets_and_native_presentation_have_diagnostics() {
	for asset in [ImageAsset{ variants: [ImageVariant{ path: 'x', density: 2 }] },
		ImageAsset{ logical_size: LayoutSize{ width: 2, height: 2 }, variants: [ImageVariant{ path: 'x', density: 1 }] },
		ImageAsset{ logical_size: LayoutSize{ width: 2, height: 0 } }] {
		asset.validate() or { continue }
		assert false
	}
	for style in [ImageStyle{ source: rect(0.9, 0, 0.2, 1) }, ImageStyle{ align_x: 1.1 },
		ImageStyle{ source: Rect{} }] {
		style.validate() or { continue }
		assert false
	}
	for style in [ImageStyle{ fit: .cover }, ImageStyle{ tint: ImageTint{ a: 0 } },
		ImageStyle{ source: rect(0, 0, 0.5, 1) }] {
		validate_native_image(Element{ ...image('i', 'x', rect(0, 0, 10, 10)), image_style: style }) or {
			assert err.msg().contains('custom renderer')
			continue
		}
		assert false
	}
	image_geometry(rect(0, 0, 10, 10), LayoutSize{ width: 10, height: 10 }, ImageStyle{}, math.nan()) or { return }
	assert false
}

fn test_image_tree_rejects_custom_presentation_on_native_hosts() {
	el := Element{ ...image('styled', 'x.png', rect(0, 0, 100, 100)), image_style: ImageStyle{ fit: .cover } }
	$if !( android || linux || ( ( macos || windows ) && ui2_custom_rendering ?) ) && !ui2_headless ? {
		validate_element_tree(el) or {
			assert err.msg().contains('custom renderer')
			return
		}
		assert false
	} $else {
		validate_element_tree(el)!
	}
}

fn test_native_image_rotation_and_quad_interaction_require_custom() {
	base := image('image', 'x.png', rect(0, 0, 100, 100))
	for el in [Element{ ...base, rotation: 45 }, Element{ ...base, clickable: true },
		Element{ ...base, tooltip: 'quad' }] {
		validate_native_image(el) or {
			assert err.msg().contains('visible-quad interaction')
			continue
		}
		assert false
	}
}
