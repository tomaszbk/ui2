@[has_globals]
module ui2

struct OverlayGeometryModel {}

fn build_overlay_geometry(mut app OverlayGeometryModel) Element {
	return $vml('fixtures/compiled_overlay_geometry.vml')
}

$if (linux || macos || windows) && !ui2_headless ? {
	fn test_overlay_clamped_geometry_publishes_final_refs_and_reflows_without_oscillating() ! {
		previous_app := g_gg_app
		previous_build := g_build_screen
		previous := activate_custom_window_state(new_custom_window_state())
		defer {
			activate_custom_window_state(previous)
			g_gg_app = previous_app
			g_build_screen = previous_build
		}
		g_build_screen = unsafe { nil }
		mut model := OverlayGeometryModel{}
		root := build_overlay_geometry(mut model)
		defer { root.compiled_node.dispose_document() or { panic(err) } }
		mut app := &GgApp{ ctx: &DrawContext{ width: 220, height: 160 }, has_root: true, declared_root: root }
		g_gg_app = app
		root.compiled_node.mount()!
		projected := resolve_custom_layout_snapshot(mut app, FrameWork{}, measure_layout_text, [], true)!
		reconcile_mounted_focus_controls(projected)
		update_custom_focus_tree(projected)
		assert (g_focus_navigation.node('surface') or { panic('surface') }).frame == rect(8, 8, 204, 144)
		assert (g_focus_navigation.node('draft') or { panic('draft') }).frame == rect(16, 16, 188, 30)
		assert (g_focus_navigation.node('resolved_width') or { panic('width ref') }).el.text.f64() == 204
		assert (g_focus_navigation.node('resolved_x') or { panic('x ref') }).el.text.f64() == 8
		// Mounted geometry effects may publish a cold follow-up patch. It must
		// converge while every presented frame already uses the clamped geometry.
		mut settled := projected
		mut converged := false
		for _ in 0 .. 8 {
			stable := resolve_custom_layout_snapshot(mut app, FrameWork{}, measure_layout_text, take_custom_layout_patches(mut app), true)!
			update_custom_focus_tree(stable)
			assert (g_focus_navigation.node('surface') or { panic('surface') }).frame == rect(8, 8, 204, 144)
			assert (g_focus_navigation.node('draft') or { panic('draft') }).frame == rect(16, 16, 188, 30)
			if stable == settled && app.layout_patches.len == 0 {
				converged = true
				break
			}
			settled = stable
		}
		assert converged, 'mounted overlay geometry kept publishing patches'
		serial := app.overlay_tree.source_revision
		for _ in 0 .. 8 {
			assert resolve_custom_layout_snapshot(mut app, FrameWork{}, measure_layout_text, take_custom_layout_patches(mut app), true)! == settled
		}
		assert app.overlay_tree.source_revision == serial
	}
}

$if (linux || macos || windows) && !ui2_headless ? {
	fn test_overlay_same_size_recenter_publishes_geometry_bindings_in_presented_frame() ! {
		previous_app := g_gg_app
		previous_build := g_build_screen
		previous := activate_custom_window_state(new_custom_window_state())
		defer {
			activate_custom_window_state(previous)
			g_gg_app = previous_app
			g_build_screen = previous_build
		}
		g_build_screen = unsafe { nil }
		mut model := OverlayGeometryModel{}
		root := build_overlay_geometry(mut model)
		defer { root.compiled_node.dispose_document() or { panic(err) } }
		mut app := &GgApp{ ctx: &DrawContext{ width: 400, height: 300 }, has_root: true, declared_root: root }
		g_gg_app = app
		root.compiled_node.mount()!
		for _ in 0 .. 8 {
			stable := resolve_custom_layout_snapshot(mut app, FrameWork{}, measure_layout_text, take_custom_layout_patches(mut app), true)!
			update_custom_focus_tree(stable)
			if app.layout_patches.len == 0 { break }
		}
		assert (g_focus_navigation.node('surface') or { panic('surface') }).frame.x == 20
		assert (g_focus_navigation.node('resolved_x') or { panic('x ref') }).el.text.f64() == 20
		app.ctx.width = 420
		projected := resolve_custom_layout_snapshot(mut app, FrameWork{}, measure_layout_text, take_custom_layout_patches(mut app), true)!
		update_custom_focus_tree(projected)
		assert (g_focus_navigation.node('surface') or { panic('surface') }).frame.x == 30
		assert (g_focus_navigation.node('resolved_x') or { panic('x ref') }).el.text.f64() == 30
	}
}
