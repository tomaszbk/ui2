module ui2

pub struct VisualGeometry {
pub:
	frame            Rect
	transform        ContentTransform
	parent_transform ContentTransform
	clip             ClipRegion
}

// Geometry describes the most recently presented tree, in window-logical units.
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
		g_gg_app.declared_root = root
		g_gg_app.presentation_revision++
		invalidate_custom_paint()
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
	pub fn visual_geometry(_id string) !VisualGeometry {
		return error('visual geometry requires a running custom renderer')
	}
}
