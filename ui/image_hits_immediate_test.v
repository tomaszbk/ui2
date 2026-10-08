// vtest vflags: -d ui2_custom_rendering
module ui2

fn test_image_visible_quad_hits_share_fractional_scaled_coordinates_and_clip() {
	$if ( android || linux || ( ( macos || windows ) && ui2_custom_rendering ?) ) && !ui2_headless ? {
		previous := g_gg_app.ctx
		previous_hits := g_hit_targets
		g_gg_app.ctx = &DrawContext{ content_transform: ContentTransform{ scale: 0.5, x: 10.25, y: 20.75 }, scale: 1.5 }
		defer {
			g_gg_app.ctx = previous
			g_hit_targets = previous_hits.clone()
		}
		g_hit_targets = []HitTarget{}
		geometry := image_geometry(rect(0, 0, 100, 100), LayoutSize{ width: 100, height: 100 }, ImageStyle{}, 45)!
		add_hit_target(HitTarget{
			id:             'image'
			x:              geometry.bounds.x
			y:              geometry.bounds.y
			w:              geometry.bounds.width
			h:              geometry.bounds.height
			image_geometry: geometry
			image_clip:     rect(0, 0, 100, 60)
		}, rect(0, 0, 100, 60))
		assert hit_test(35.25, 45.75).id == 'image' // local 50,50
		tip := TooltipTarget{
			key:       'image'
			text:      'visible quad'
			image_hit: HitTarget{
				content_transform: g_gg_app.ctx.content_transform
				image_geometry:    geometry
				image_clip:        rect(0, 0, 100, 60)
			}
		}
		assert tooltip_target_at([tip], 35.25, 45.75).text == 'visible quad'
		assert tooltip_target_at([tip], 12.75, 23.25).text == ''
		assert tooltip_target_at([tip], 5.25, 15.75).text == ''
		assert tooltip_target_at([tip], 35.25, 60.75).text == ''
		assert hit_test(12.75, 23.25).id == '' // local 5,5: inside clip/AABB, outside rotated square
		assert hit_test(5.25, 15.75).id == '' // local -10,-10 in rotated AABB
		assert hit_test(35.25, 60.75).id == '' // local 50,80 excluded by clip
		// A later rectangle still wins in reverse paint order.
		add_hit_target(HitTarget{ id: 'front', x: 40, y: 40, w: 20, h: 20 }, rect(0, 0, 100, 100))
		assert hit_test(35.25, 45.75).id == 'front'
	}
}
