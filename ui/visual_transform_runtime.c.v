module ui2

pub struct VisualGeometry {
	// The renderer prunes stale entries only after publishing a complete frame.
	generation u64
pub:
	frame            Rect
	transform        ContentTransform
	parent_transform ContentTransform
	clip             ClipRegion
}

// Both presented and mounted snapshots use window-logical units.
pub fn (g VisualGeometry) bounds() Rect {
	return g.clip.intersect(paint_transformed_clip(g.frame, g.transform)).bounds()
}

pub fn (g VisualGeometry) contains(x f64, y f64) bool {
	return transformed_contains(g.frame, g.transform, g.clip, x, y)
}

fn replace_visual_transform(el Element, id string, transform VisualTransform) !(Element, bool) {
	if el.id == id {
		transform.matrix(el.frame)!
		replaced := with_transform(el, transform)
		if replaced.motion_state != unsafe { nil } {
			replaced.motion_state.update(replaced)!
		}
		return replaced, true
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
	updated := with_transform(node.declaration, transform)
	if updated.motion_state != unsafe { nil } { updated.motion_state.update(updated)! }
	node.declaration = updated
	mut ancestor := node.identity
	for ancestor.len > 0 {
		mut changed := tree.nodes[ancestor] or { return error('missing layout ancestor') }
		changed.authored_dirty = true
		changed.output_dirty = true
		ancestor = changed.parent
	}
}
