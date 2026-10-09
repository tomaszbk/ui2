module ui2

pub struct VisualGeometry {
pub:
	frame            Rect
	transform        ContentTransform
	parent_transform ContentTransform
	clip             ClipRegion
}

// Both presented and mounted snapshots use window-logical units.
pub fn (g VisualGeometry) bounds() Rect {
	return g.clip.intersect(transformed_clip(g.frame, g.transform)).bounds()
}

pub fn (g VisualGeometry) contains(x f64, y f64) bool {
	return transformed_contains(g.frame, g.transform, g.clip, x, y)
}

fn replace_visual_transform(el Element, id string, transform VisualTransform) !(Element, bool) {
	if el.id == id {
		transform.matrix(el.frame)!
		return with_transform(el, transform), true
	}
	for index, child in el.children {
		replaced, found := replace_visual_transform(child, id, transform)!
		if found {
			mut children := el.children.clone()
			children[index] = replaced
			return Element{ ...el, children: children }, true
		}
	}
	return el, false
}

fn (mut tree LayoutTree) set_transform(id string, transform VisualTransform) ! {
	mut node := tree.find_id(id) or { return error('no mounted element `${id}`') }
	transform.matrix(node.frame)!
	node.declaration = with_transform(node.declaration, transform)
}

$if ( android || linux || ( ( macos || windows ) && ui2_custom_rendering ?) ) && !ui2_headless ? {
	// UI-thread presentation update. A subsequent declarative rebuild replaces it.
	// No business callback, layout, text mutation or animation loop is introduced.
	pub fn set_visual_transform(id string, transform VisualTransform) ! {
		$if android {
			return error('visual transforms require the desktop custom text renderer')
		}
		if id.len == 0 { return error('visual transform updates require an element id') }
		root, found := replace_visual_transform(g_gg_app.declared_root, id, transform)!
		if !found { return error('unknown element `${id}`') }
		if g_gg_app.layout_tree.root.len > 0 {
			g_gg_app.layout_tree.set_transform(id, transform)!
		}
		g_gg_app.declared_root = root
		mounted, mounted_found := replace_visual_transform(g_focus_navigation.root, id, transform)!
		if mounted_found {
			g_focus_navigation.root = mounted
			sync_focus_navigation()
		}
		g_gg_app.presentation_revision++
		invalidate_custom_paint()
	}
	// Current resolved mounted geometry includes controls outside paint culling.
	// Querying it never resolves layout or changes the last-presented snapshot.
	pub fn mounted_geometry(id string) !VisualGeometry {
		sync_focus_navigation()
		node := g_focus_navigation.node(id) or { return error('element `${id}` has no mounted geometry') }
		if node.hidden { return error('element `${id}` is hidden') }
		return VisualGeometry{frame: node.local_frame, transform: node.transform,
			parent_transform: node.parent_transform, clip: node.clip}
	}
	pub fn visual_geometry(id string) !VisualGeometry {
		return g_gg_app.visual_geometries[id] or { return error('element `${id}` has no presented geometry') }
	}
	fn switch_pointer_right(target HitTarget, x f64, y f64) bool {
		current := current_pointer_target(target) or { target }
		if !current.has_geometry { return x >= current.x + current.w / 2 }
		lx, _ := current.content_transform.inverse(x, y)
		return lx >= current.local_frame.x + current.local_frame.width / 2
	}
} $else {
	pub fn set_visual_transform(_id string, _transform VisualTransform) ! {
		return error('visual transforms require the custom renderer')
	}
	pub fn mounted_geometry(_id string) !VisualGeometry {
		return error('mounted visual geometry requires a running custom renderer')
	}
	pub fn visual_geometry(_id string) !VisualGeometry {
		return error('visual geometry requires a running custom renderer')
	}
}
