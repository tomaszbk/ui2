module main

import ui2

fn test_public_image_fixture_uses_fractional_frames_and_all_fit_modes() {
	root := build()
	mut modes := []ui2.ImageFit{}
	for el in root.children {
		if el.id.starts_with('fit') {
			assert el.frame.y == 54.5
			assert el.frame.width == 100 && el.frame.height == 100
			modes << el.image_style.fit
		}
	}
	assert modes == [ui2.ImageFit.contain, .cover, .fill, .none, .scale_down]
	asset := root.children[root.children.len - 2].children[0].image_asset
	assert ui2.select_image_variant('base', asset, 1.25)!.density == 2
	assert ui2.select_image_variant('base', asset, 3)!.density == 3
	g := ui2.image_geometry(ui2.rect(10.25, 20.5, 100, 100), ui2.LayoutSize{ width: 200, height: 100 }, ui2.ImageStyle{ fit: .cover }, 0)!
	assert g.bounds == ui2.rect(10.25, 20.5, 100, 100)
	assert g.source == ui2.rect(0.25, 0, 0.5, 1)
}
