// vfmt off
// Keep gg-dependent hover tracking out of the native and headless builds.
@[has_globals]
module ui2

$if (android || linux || ((macos || windows) && ui2_custom_rendering ?)) && !ui2_headless ? && !ui2_document_library ? {
	// HoverEntry is one hoverable element painted this frame, with the index of
	// the hoverable element it sits in, so a region names its whole chain with
	// one index and no frame allocates a chain per element.
	struct HoverEntry {
		target HoverTarget
		parent int = -1
	}

	// HoverRegion is the visible part of an element painted this frame and the
	// innermost hoverable element it belongs to. The last region under the
	// pointer is the topmost element there, so its chain is what is hovered.
	struct HoverRegion {
		frame             Rect
		local_frame       Rect
		content_transform ContentTransform
		clip_region       ClipRegion
		entry             int = -1
	}

	struct HoverState {
	mut:
		entries []HoverEntry
		regions []HoverRegion
		current int = -1
		// hovered is the chain under the pointer, outermost first.
		hovered []HoverTarget
		pointer_x f64
		pointer_y f64
		inside    bool
	}

	__global g_hover = HoverState{}

	// begin_hover_frame forgets the previous paint's regions, keeping their
	// storage, before an element tree is painted again.
	fn begin_hover_frame() {
		g_hover.entries.clear()
		g_hover.regions.clear()
		g_hover.current = -1
	}

	// enter_hover_element registers an element being painted and returns the
	// enclosing hoverable entry, which the caller restores when it is done with
	// the element's children. Regions before the first hoverable element are
	// beneath every one of them, so nothing is recorded until one is painted.
	fn enter_hover_element(el Element, path string, area Rect, clip Rect, inert bool) int {
		outer := g_hover.current
		if !inert {
			if target := hover_target(path, el) {
				g_hover.entries << HoverEntry{
					target: target
					parent: outer
				}
				g_hover.current = g_hover.entries.len - 1
			}
		}
		if g_hover.entries.len > 0 {
			region := current_clip_region(clip)
			transform := current_content_transform()
			visible := retained_paint_clip(region, area, transform).bounds()
			if visible.width > 0 && visible.height > 0 {
				g_hover.regions << HoverRegion{
					frame:             visible
					local_frame:       area
					content_transform: transform
					clip_region:       region
					entry:             g_hover.current
				}
			}
		}
		return outer
	}

	fn leave_hover_element(outer int) {
		g_hover.current = outer
	}

	fn hover_region_contains(region HoverRegion, x f64, y f64) bool {
		return hit_target_contains(HitTarget{
			x:                 region.frame.x
			y:                 region.frame.y
			w:                 region.frame.width
			h:                 region.frame.height
			local_frame:       region.local_frame
			content_transform: region.content_transform
			clip_region:       region.clip_region
			has_geometry:      true
		}, x, y)
	}

	// hovered_chain_at lists the hoverable elements under a window point,
	// outermost first.
	fn hovered_chain_at(x f64, y f64) []HoverTarget {
		for i := g_hover.regions.len - 1; i >= 0; i-- {
			region := g_hover.regions[i]
			if !hover_region_contains(region, x, y) {
				continue
			}
			mut inner_first := []HoverTarget{}
			mut entry := region.entry
			for entry >= 0 && entry < g_hover.entries.len {
				inner_first << g_hover.entries[entry].target
				entry = g_hover.entries[entry].parent
			}
			return inner_first.reverse()
		}
		return []HoverTarget{}
	}

	fn hover_pointer_moved(x f64, y f64) {
		g_hover.pointer_x = x
		g_hover.pointer_y = y
		g_hover.inside = true
	}

	fn hover_pointer_left() {
		g_hover.inside = false
	}

	// take_hover_events compares what the pointer hovers now with what it
	// hovered at the last check and returns the leave and enter events to send.
	fn take_hover_events() []PendingHoverEvent {
		if g_hover.hovered.len == 0 && (!g_hover.inside || g_hover.entries.len == 0) {
			return []PendingHoverEvent{}
		}
		current := if g_hover.inside { hovered_chain_at(g_hover.pointer_x, g_hover.pointer_y) } else { []HoverTarget{} }
		left, entered := hover_transitions(g_hover.hovered, current)
		g_hover.hovered = current
		return hover_events(left, entered, g_hover.pointer_x, g_hover.pointer_y)
	}

	// update_hover reports hover changes to the elements' callbacks. A callback
	// that changes the model is rendered by the refresh it asks for, as after
	// any other pointer event.
	fn update_hover() {
		events := take_hover_events()
		if events.len == 0 {
			return
		}
		dispatch := custom_input_dispatch(g_gg_app)
		for pending in events {
			if !dispatch.valid() {
				return
			}
			pending.fire()
		}
		if dispatch.valid() {
			refresh()
		}
	}
}
