// vtest vflags: -d ui2_custom_rendering
@[has_globals]
module ui2

$if ( linux || macos || windows ) && !ui2_headless ?&& ( linux || ui2_custom_rendering ?) && !ui2_embedder ? {
	import os
	import time

	__global image_tooltip_started = false
	__global image_tooltip_passed = false

	fn image_tooltip_path(name string) string {
		return os.join_path(@VMODROOT, 'examples', 'image_assets', 'assets', name)
	}

	fn image_tooltip_build() Element {
		if !image_tooltip_started {
			image_tooltip_started = true
			spawn image_tooltip_worker(ui_dispatcher())
		}
		asset := image_tooltip_path('red.png')
		missing := image_tooltip_path('missing-tooltip-fixture.png')
		return screen(0xffffff, [
			with_tooltip(view('view-owner', rect(10, 10, 100, 60), BoxStyle{}, [
				image('view-child', asset, rect(10, 10, 40, 40)),
			]), 'View ancestor'),
			with_tooltip(scroll('scroll-owner', rect(130, 10, 100, 60), 0xffffff, [
				Element{ ...image('scroll-child', asset, rect(0, 0, 100, 100)), rotation: 45 },
			]), 'Scroll ancestor'),
			with_tooltip(view('override-owner', rect(250, 10, 100, 60), BoxStyle{}, [
				with_tooltip(Element{ ...image('override-child', asset, rect(10, 10, 40, 40)), rotation: 45 }, 'Image override'),
			]), 'Override ancestor'),
			with_tooltip(view('underneath', rect(0, 120, 120, 90), BoxStyle{}, []), 'Sibling underneath'),
			// This transparent sibling contributes no rectangular occluder. Its
			// image alone hides the tip, through the real scaled/clip render path.
			scaled_content('image-viewport', rect(10.25, 130.75, 30, 30), 60, 60,
				BoxStyle{ transparent: true }, [
					Element{ ...image('obscurer', asset, rect(0, 0, 100, 100)), rotation: 45 },
				]),
			with_tooltip(view('missing-owner', rect(150, 120, 100, 60), BoxStyle{}, [
				image('missing-child', missing, rect(10, 10, 20, 40)),
				with_tooltip(image('missing-override', missing, rect(40, 10, 20, 40)), 'Unavailable image'),
			]), 'Missing ancestor'),
			with_tooltip(view('missing-underneath', rect(270, 120, 100, 60), BoxStyle{}, []), 'Placeholder underneath'),
			image('missing-sibling', missing, rect(280, 130, 40, 40)),
		])
	}

	fn image_tooltip_worker(dispatcher UiDispatcher) {
		mut waits := 0
		for dispatcher.stats().draws == 0 {
			time.sleep(20 * time.millisecond)
			waits++
			assert waits < 500
		}
		// The callback runs on the UI thread after on_frame has registered and
		// submitted the fixture. Never supply a handcrafted TooltipTarget list.
		assert dispatcher.post(image_tooltip_check)
	}

	fn image_tooltip_check() {
		stats := image_resource_stats()
		assert stats.decodes == 1 && stats.entries == 1 && stats.uploads == 1
		assert g_tooltip_owners == 0
		view_tip := tooltip_target_at(g_tooltip_targets, 40, 40)
		scroll_tip := tooltip_target_at(g_tooltip_targets, 180, 60)
		explicit_tip := tooltip_target_at(g_tooltip_targets, 280, 40)
		println('rendered image tooltips: View="${view_tip.text}", Scroll="${scroll_tip.text}", explicit="${explicit_tip.text}"')
		assert view_tip.key == 'view#view-owner' && view_tip.text == 'View ancestor'
		assert scroll_tip.key == 'scroll#scroll-owner' && scroll_tip.text == 'Scroll ancestor'
		assert tooltip_target_at(g_tooltip_targets, 135, 15).text == 'Scroll ancestor' // outside rotated quad
		assert tooltip_target_at(g_tooltip_targets, 180, 90).text == '' // outside Scroll clip
		assert explicit_tip.key == 'image#override-child' && explicit_tip.text == 'Image override'
		assert tooltip_target_at(g_tooltip_targets, 261, 21).text == 'Override ancestor' // outside image quad

		// Local 50,50 is inside the visible rotated quad; local 5,5 is in its
		// AABB but outside the quad. Local 50,80 is in the quad, beyond the clip.
		obscurer := tooltip_target_at(g_tooltip_targets, 35.25, 155.75)
		assert obscurer.key == 'image#obscurer' && obscurer.text == ''
		assert obscurer.image_hit.content_transform == ContentTransform{ scale: 0.5, x: 10.25, y: 130.75 }
		assert obscurer.image_hit.image_clip == rect(0, 0, 60, 60)
		assert tooltip_target_at(g_tooltip_targets, 12.75, 133.25).text == 'Sibling underneath'
		assert tooltip_target_at(g_tooltip_targets, 35.25, 170.75).text == 'Sibling underneath'
		assert tooltip_target_at(g_tooltip_targets, 35.25, 160.75).text == 'Sibling underneath' // clip edge is excluded

		// Missing images still take the placeholder early return: no quad target,
		// explicit image tip or new occlusion, and ancestor ownership unwinds.
		assert tooltip_target_at(g_tooltip_targets, 170, 150).text == 'Missing ancestor'
		assert tooltip_target_at(g_tooltip_targets, 200, 150).text == 'Missing ancestor'
		assert tooltip_target_at(g_tooltip_targets, 300, 150).text == 'Placeholder underneath'
		mut image_targets := 0
		for target in g_tooltip_targets {
			if target.image_hit.image_geometry.bounds.width > 0 {
				image_targets++
			}
			assert !target.key.starts_with('image#missing-')
		}
		assert image_targets == 2 // explicit override and ownerless sibling only
		image_tooltip_passed = true
		println('image tooltip render registration: inheritance, override, rotated/clipped occlusion and placeholders passed')
		quit()
	}
}

fn test_image_tooltips_registered_by_the_running_renderer() {
	$if ( linux || macos || windows ) && !ui2_headless ?&& ( linux || ui2_custom_rendering ?) && !ui2_embedder ? {
		image_tooltip_started = false
		image_tooltip_passed = false
		run_window('Image tooltip registration fixture', 400, 240, image_tooltip_build)
		assert image_tooltip_passed
		assert g_gg_app.ctx == unsafe { nil }
	}
}
