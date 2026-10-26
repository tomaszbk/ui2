// vtest vflags: -d ui2_custom_rendering -d vml_fixtures
@[has_globals]
module ui2

// vml: fixtures/compiled_overlay_geometry.vml

struct OverlayGeometryModel {}

fn build_overlay_geometry(mut app OverlayGeometryModel) Element {
	return compiled_overlay_geometry_vml()
}

$if (linux || ((macos || windows) && ui2_custom_rendering ?)) && !ui2_headless ? {
	fn test_overlay_clamped_geometry_publishes_final_refs_and_reflows_without_oscillating() ! {
		mut model := OverlayGeometryModel{}
		root := build_overlay_geometry(mut model)
		defer { root.compiled_node.dispose_document() or { panic(err) } }
		mut w := &Window{ ctx: &DrawContext{ width: 220, height: 160 }, has_root: true, declared_root: root }
		root.compiled_node.mount()!
		projected := w.resolve_custom_layout_snapshot(FrameWork{}, measure_layout_text, [], true)!
		w.reconcile_mounted_focus_controls(projected)
		w.update_custom_focus_tree(projected)
		assert (w.navigation.node('surface') or { panic('surface') }).frame == rect(8, 8, 204, 144)
		assert (w.navigation.node('draft') or { panic('draft') }).frame == rect(16, 16, 188, 30)
		assert (w.navigation.node('resolved_width') or { panic('width ref') }).el.text.f64() == 204
		assert (w.navigation.node('resolved_x') or { panic('x ref') }).el.text.f64() == 8
		// Mounted geometry effects may publish a cold follow-up patch. It must
		// converge while every presented frame already uses the clamped geometry.
		mut settled := projected
		mut converged := false
		for _ in 0 .. 8 {
			stable := w.resolve_custom_layout_snapshot(FrameWork{}, measure_layout_text, w.take_custom_layout_patches(), true)!
			w.update_custom_focus_tree(stable)
			assert (w.navigation.node('surface') or { panic('surface') }).frame == rect(8, 8, 204, 144)
			assert (w.navigation.node('draft') or { panic('draft') }).frame == rect(16, 16, 188, 30)
			if stable == settled && w.layout_patches.len == 0 {
				converged = true
				break
			}
			settled = stable
		}
		assert converged, 'mounted overlay geometry kept publishing patches'
		serial := w.overlay_tree.source_revision
		for _ in 0 .. 8 {
			assert w.resolve_custom_layout_snapshot(FrameWork{}, measure_layout_text, w.take_custom_layout_patches(), true)! == settled
		}
		assert w.overlay_tree.source_revision == serial
	}
}

$if (linux || ((macos || windows) && ui2_custom_rendering ?)) && !ui2_headless ? {
	fn test_overlay_same_size_recenter_publishes_geometry_bindings_in_presented_frame() ! {
		mut model := OverlayGeometryModel{}
		root := build_overlay_geometry(mut model)
		defer { root.compiled_node.dispose_document() or { panic(err) } }
		mut w := &Window{ ctx: &DrawContext{ width: 400, height: 300 }, has_root: true, declared_root: root }
		root.compiled_node.mount()!
		for _ in 0 .. 8 {
			stable := w.resolve_custom_layout_snapshot(FrameWork{}, measure_layout_text, w.take_custom_layout_patches(), true)!
			w.update_custom_focus_tree(stable)
			if w.layout_patches.len == 0 { break }
		}
		assert (w.navigation.node('surface') or { panic('surface') }).frame.x == 20
		assert (w.navigation.node('resolved_x') or { panic('x ref') }).el.text.f64() == 20
		w.ctx.width = 420
		projected := w.resolve_custom_layout_snapshot(FrameWork{}, measure_layout_text, w.take_custom_layout_patches(), true)!
		w.update_custom_focus_tree(projected)
		assert (w.navigation.node('surface') or { panic('surface') }).frame.x == 30
		assert (w.navigation.node('resolved_x') or { panic('x ref') }).el.text.f64() == 30
	}
}
