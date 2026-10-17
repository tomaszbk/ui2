// vfmt off
// Keep gg-dependent hover tracking out of the native and headless builds.
@[has_globals]
module ui2

$if (android || ios || linux || macos || windows) && !ui2_headless ? && !ui2_document_library ? {
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

	// begin_hover_frame forgets the previous paint's regions, keeping their
	// storage, before an element tree is painted again.
	fn (mut w Window) begin_hover_frame() {
		w.hover.entries.clear()
		w.hover.regions.clear()
		w.hover.current = -1
	}

	// enter_hover_element registers an element being painted and returns the
	// enclosing hoverable entry, which the caller restores when it is done with
	// the element's children. Regions before the first hoverable element are
	// beneath every one of them, so nothing is recorded until one is painted.
	fn (mut w Window) enter_hover_element(el Element, path string, area Rect, clip Rect, inert bool) int {
		outer := w.hover.current
		if !inert {
			if target := hover_target(path, el) {
				w.hover.entries << HoverEntry{
					target: target
					parent: outer
				}
				w.hover.current = w.hover.entries.len - 1
			}
		}
		if w.hover.entries.len > 0 {
			region := w.current_clip_region(clip)
			transform := w.current_content_transform()
			visible := w.retained_paint_clip(region, area, transform).bounds()
			if visible.width > 0 && visible.height > 0 {
				w.hover.regions << HoverRegion{
					frame:             visible
					local_frame:       area
					content_transform: transform
					clip_region:       region
					entry:             w.hover.current
				}
			}
		}
		return outer
	}

	fn (mut w Window) leave_hover_element(outer int) {
		w.hover.current = outer
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
	fn (mut w Window) hovered_chain_at(x f64, y f64) []HoverTarget {
		for i := w.hover.regions.len - 1; i >= 0; i-- {
			region := w.hover.regions[i]
			if !hover_region_contains(region, x, y) {
				continue
			}
			mut inner_first := []HoverTarget{}
			mut entry := region.entry
			for entry >= 0 && entry < w.hover.entries.len {
				inner_first << w.hover.entries[entry].target
				entry = w.hover.entries[entry].parent
			}
			return inner_first.reverse()
		}
		return []HoverTarget{}
	}

	fn (mut w Window) hover_pointer_moved(x f64, y f64) {
		w.hover.pointer_x = x
		w.hover.pointer_y = y
		w.hover.inside = true
	}

	fn (mut w Window) hover_pointer_left() {
		w.hover.inside = false
	}

	// take_hover_events compares what the pointer hovers now with what it
	// hovered at the last check and returns the leave and enter events to send.
	fn (mut w Window) take_hover_events() []PendingHoverEvent {
		if w.hover.hovered.len == 0 && (!w.hover.inside || w.hover.entries.len == 0) {
			return []PendingHoverEvent{}
		}
		current := if w.hover.inside { w.hovered_chain_at(w.hover.pointer_x, w.hover.pointer_y) } else { []HoverTarget{} }
		left, entered := hover_transitions(w.hover.hovered, current)
		w.hover.hovered = current
		return hover_events(left, entered, w.hover.pointer_x, w.hover.pointer_y)
	}

	// update_hover reports hover changes to the elements' callbacks. A callback
	// that changes the model is rendered by the refresh it asks for, as after
	// any other pointer event.
	fn (mut w Window) update_hover() {
		events := w.take_hover_events()
		if events.len == 0 {
			return
		}
		dispatch := w.custom_input_dispatch()
		for pending in events {
			if !dispatch.valid() {
				return
			}
			pending.fire(w)
		}
		if dispatch.valid() {
			w.request_refresh()
		}
	}
}
