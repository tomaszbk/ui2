// vtest vflags: -d ui2_headless
module ui2

fn test_overlay_dialog_centers_and_clamps_in_logical_viewport() ! {
	frame := overlay_frame(OverlayConfig{ kind: .dialog, margin: 10 }, LayoutSize{ width: 500, height: 80 }, Rect{}, rect(20, 30, 300, 200))!
	assert frame == rect(30, 90, 280, 80)
	assert overlay_frame(OverlayConfig{ kind: .dialog }, LayoutSize{ width: 100, height: 100 }, Rect{}, rect(0, 0, 0, 0))! == Rect{}
}

fn test_overlay_flips_before_clamping_and_preserves_fractional_anchor() ! {
	config := OverlayConfig{ anchor: 'button', margin: 8, gap: 6 }
	frame := overlay_frame(config, LayoutSize{ width: 100, height: 60 }, rect(140.5, 170.25, 40, 20), rect(0, 0, 300, 200))!
	assert frame == rect(140.5, 104.25, 100, 60)
	left := overlay_frame(OverlayConfig{ anchor: 'button', placement: .right_end }, LayoutSize{ width: 90, height: 50 }, rect(265, 60, 20, 20), rect(0, 0, 300, 200))!
	assert left == rect(169, 30, 90, 50)
}

fn test_overlay_context_point_clamps_to_viewport_and_tiny_viewports() ! {
	config := OverlayConfig{ kind: .context_menu, point: OverlayPoint{ x: 290, y: 195 } }
	assert overlay_frame(config, LayoutSize{ width: 100, height: 50 }, Rect{}, rect(0, 0, 300, 200))! == rect(192, 139, 100, 50)
	assert overlay_frame(config, LayoutSize{ width: 100, height: 50 }, Rect{}, rect(0, 0, 8, 6))! == rect(4, 3, 0, 0)
}

fn test_overlay_config_rejects_missing_anchors_and_invalid_sizes() {
	for config in [OverlayConfig{}, OverlayConfig{ anchor: 'a', gap: -1 },
		OverlayConfig{ kind: .dialog, backdrop_opacity: 2 },
		OverlayConfig{ kind: .tooltip, anchor: 'a', initial_focus: 'a' }] {
		if _ := config.validate() {
			assert false, 'invalid overlay accepted'
		}
	}
	if _ := overlay_frame(OverlayConfig{ kind: .dialog }, LayoutSize{ width: -1 }, Rect{}, rect(0, 0, 10, 10)) {
		assert false
	}
}

fn test_overlay_requires_stable_view_and_preserves_retained_content() ! {
	content := view('dialog', rect(0, 0, 200, 100), BoxStyle{}, [Element{ kind: .text_field, id: 'draft', text: 'café ñ' }])
	closed := with_overlay(content, OverlayConfig{ kind: .dialog })!
	assert closed.hidden && closed.focus_scope && closed.accessibility_role == 'dialog'
	assert closed.children == content.children
	if _ := with_overlay(label('label', 'no', Rect{}, TextStyle{}), OverlayConfig{ kind: .dialog }) {
		assert false
	}
}
