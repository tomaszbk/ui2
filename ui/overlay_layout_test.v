// vtest vflags: -d ui2_headless
module ui2

fn test_overlay_surface_does_not_take_flex_space_or_add_a_gap() ! {
	for open in [false, true] {
		surface := with_overlay(view('dialog', rect(0, 0, 300, 200), BoxStyle{}, []), OverlayConfig{ kind: .dialog, open: open })!
		root := flex(FlexConfig{
			id:       'row'
			frame:    rect(0, 0, 400, 80)
			gap:      6
			align:    .start
			children: [
				FlexChild{ element: view('first', rect(0, 0, 60, 20), BoxStyle{}, []), shrink: 0 },
				FlexChild{ element: surface, shrink: 0 },
				FlexChild{ element: view('last', rect(0, 0, 80, 20), BoxStyle{}, []), shrink: 0 },
			]
		})!
		mut layout := LayoutTree{}
		layout.replace(root)!
		resolved := layout.resolve(LayoutConstraints{}, unsafe { nil }, LayoutEnvironment{})!
		assert resolved.children[0].frame == rect(0, 0, 60, 20)
		assert resolved.children[1].frame == rect(0, 0, 300, 200)
		assert resolved.children[2].frame == rect(66, 0, 80, 20)
	}
}

fn test_overlay_tracks_transformed_anchor_and_escapes_its_transform() ! {
	anchor := view('anchor', rect(10.25, 20.5, 40, 24), BoxStyle{}, [])
	surface := with_overlay(view('popover', rect(0, 0, 100, 60), BoxStyle{}, []), OverlayConfig{ anchor: 'anchor', open: true, gap: 6 })!
	owner := with_transform(view('owner', rect(30, 40, 200, 120), BoxStyle{}, [anchor, surface]),
		VisualTransform{ translate_x: 15.5, translate_y: 8.25, scale_x: 1.5, scale_y: 2 })
	root := Element{ kind: .screen, frame: rect(0, 0, 500, 400), children: [owner] }
	mut tree := OverlayTree{}
	projected := tree.resolve(root, map[string]f64{}, root.frame, 0)!
	mut manager := FocusManager{}
	manager.update_mounted(projected, map[string]f64{}, root.frame, ContentTransform{})
	assert (manager.node('anchor') or { panic('anchor') }).frame == rect(60.875, 89.25, 60, 48)
	surface_node := manager.node('popover') or { panic('surface') }
	assert surface_node.frame == rect(60.875, 143.25, 100, 60)
	assert surface_node.transform.xx == 1 && surface_node.transform.yy == 1
}
