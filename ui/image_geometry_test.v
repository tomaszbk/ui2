module ui2

import math

fn image_near(a f64, b f64) bool { return math.abs(a - b) < 0.00000001 }

fn test_image_fits_have_independent_destination_and_crop_fixtures() {
	frame := rect(10.25, 20.5, 100, 100)
	size := LayoutSize{ width: 200, height: 100 }
	contain := image_geometry(frame, size, ImageStyle{})!
	assert contain.bounds == rect(10.25, 45.5, 100, 50)
	assert contain.source == rect(0, 0, 1, 1)
	assert !contain.contains(60.25, 30)
	assert contain.contains(60.25, 45.5)
	cover := image_geometry(frame, size, ImageStyle{ fit: .cover })!
	assert cover.bounds == frame
	assert cover.source == rect(0.25, 0, 0.5, 1)
	fill := image_geometry(frame, size, ImageStyle{ fit: .fill })!
	assert fill.bounds == frame
	assert fill.source == rect(0, 0, 1, 1)
	natural := image_geometry(frame, size, ImageStyle{ fit: .none })!
	assert natural.bounds == frame
	assert natural.source == rect(0.25, 0, 0.5, 1)
	down := image_geometry(frame, size, ImageStyle{ fit: .scale_down })!
	assert down.bounds == contain.bounds
	// none and scale_down never enlarge the logical intrinsic dimensions.
	for fit in [ImageFit.none, .scale_down] {
		g := image_geometry(frame, LayoutSize{ width: 40, height: 20 }, ImageStyle{ fit: fit })!
		assert g.bounds == rect(40.25, 60.5, 40, 20)
	}
	left := image_geometry(frame, size, ImageStyle{ fit: .cover, align_x: 0 })!
	assert left.source == rect(0, 0, 0.5, 1)
	right := image_geometry(frame, size, ImageStyle{ fit: .cover, align_x: 1 })!
	assert right.source == rect(0.5, 0, 0.5, 1)
}

fn test_image_source_crop_rotation_and_fractional_projection_are_coherent() {
	frame := rect(0,0,100,100)
	crop := image_geometry(frame,LayoutSize{width:200,height:100},ImageStyle{source:rect(0.5,0,0.25,1)})!
	assert crop.bounds == rect(25,0,50,100)
	transform := ContentTransform{xx:2,yy:2,x:10,y:20}.compose(VisualTransform{rotation:90,origin_x:50,origin_y:50}.matrix(frame)!)
	p := transform.point(crop.points[0].x,crop.points[0].y)
	assert image_near(p.x,210) && image_near(p.y,70)
	assert crop.source == rect(0.5,0,0.25,1)
	for dpi in [1.0,1.25,1.5,2.0] {
		lx,ly := transform.inverse(p.x*dpi/dpi,p.y*dpi/dpi)
		assert crop.contains(lx,ly)
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
	assert image_geometry(rect(0, 0, 80, 80), asset.logical_size, ImageStyle{ fit: .cover })!.density == 4
}

fn test_image_invalid_assets_have_diagnostics() {
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
	image_geometry(rect(0, 0, 10, 10), LayoutSize{ width: 0, height: 10 }, ImageStyle{}) or { return }
	assert false
}

fn test_image_tree_accepts_custom_presentation() {
	el := Element{ ...image('styled', 'x.png', rect(0, 0, 100, 100)), image_style: ImageStyle{ fit: .cover } }
	validate_element_tree(el)!
}

