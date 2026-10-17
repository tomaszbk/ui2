// vfmt off
// Keep gg imports out of the headless and document builds.
@[has_globals]
module ui2

$if (android || ios || linux || macos || windows) && !ui2_headless ? && !ui2_document_library ? {
	import math

	const text_area_vertical_padding = 8.0

	@[markused]
	fn (mut w Window) reset_scroll_frame() {
		w.scroll_targets = map[string]HitTarget{}
		w.scroll_areas = map[string]Rect{}
		w.scroll_transforms = map[string]ContentTransform{}
		w.scroll_viewports = map[string]Rect{}
		w.scroll_order = []string{}
		w.scroll_parents = map[string]string{}
		w.scrollbar_geometries = map[string]ScrollbarGeometry{}
		w.scrollbar_geometries_x = map[string]ScrollbarGeometry{}
	}

	fn (mut w Window) mounted_scroll_node(id string) ?FocusNode {
		if id.starts_with(named_scroll_prefix) {
			return w.navigation.node(id[named_scroll_prefix.len..])
		}
		if id.starts_with(anonymous_scroll_prefix) {
			return w.navigation.path_node(id[anonymous_scroll_prefix.len..])
		}
		return none
	}

	// Publish every mounted Scroll before focus restoration can call user code.
	// Nested public scroll calls then see the same handlers and logical ranges
	// as the current focus registry, including panes culled by painting.
	fn (mut w Window) sync_mounted_scroll_views() {
		selected := w.text_values[w.dropdown_id] or { '' }
		if w.pointer_geometry_serial == w.navigation.geometry_serial
			&& w.navigation.geometry_serial > 0
			&& w.pointer_popup_owner == w.dropdown_id
			&& w.pointer_popup_scroll == w.dropdown_scroll
			&& w.pointer_popup_selected == selected
			&& w.hit_targets.len >= w.mounted_hit_count { return }
		// Mounted identities change with declarations, not with sampled motion.
		// Enumerating keys is only needed when a source tree changes.
		if w.drag_registry.root_revision != w.navigation.root_revision {
			for id in w.scroll_targets.keys() {
				// Anonymous text areas keep their separate editor/layout lifecycle.
				if id.starts_with(anonymous_text_area_scroll_prefix) { continue }
				if node := w.mounted_scroll_node(id) {
					if node.el.kind == .scroll { continue }
					previous := w.scroll_targets[id] or { HitTarget{} }
					if node.el.kind == .text_area && previous.kind != .scroll {
						w.scroll_targets[id] = HitTarget{ id: node.el.id, kind: node.el.kind,
							on_event: if !node.hidden && node.enabled { node.el.on_event } else { ElementCallback(unsafe { nil }) } }
						continue
					}
				}
				w.scroll_targets.delete(id)
				w.scroll_viewports.delete(id)
				w.scroll_content_h.delete(id)
				w.scroll_content_w.delete(id)
				w.scroll_offsets_x.delete(id)
				w.scroll_transforms.delete(id)
				w.scroll_areas.delete(id)
				w.scroll_parents.delete(id)
				w.scrollbar_geometries.delete(id)
				w.scrollbar_geometries_x.delete(id)
			}
		}
		mut mounted_hits := unsafe { w.hit_targets }
		mounted_hits.clear()
		mut mounted_owners := unsafe { w.drag_registry.owners }
		w.drag_registry.pointer_publication++
		mut owner_count := 0
		w.dropdown_popup.mounted=false
		for node in w.navigation.nodes {
			w.publish_mounted_pointer(node,mut mounted_hits,mut mounted_owners)
			if !node.hidden && node.enabled && (node.el.drag_source!=none || node.el.drop_target!=none)
				&& node.pointer_owner_identity in mounted_owners
				&& mounted_owners[node.pointer_owner_identity].pointer_publication==w.drag_registry.pointer_publication {
				owner_count++
			}
			if node.el.kind==.dropdown && node.el.id==w.dropdown_id && !node.hidden && node.enabled {
				options := node.menu_options_snapshot()
				ctx := w.ctx
				window := if ctx!=unsafe { nil } { rect(0,0,f64(ctx.width),f64(ctx.height)) } else { w.bounds() }
				visible := node.clip.intersect(paint_transformed_clip(node.local_frame,node.transform)).bounds()
				if options.len>0 && visible.width>0 && visible.height>0 {
					w.track_dropdown_popup_for(node.el,node.local_frame,node.transform,options,w.text_values[node.el.id] or { node.el.text },window)
				}
			}
			if node.el.kind != .scroll { continue }
			id := scroll_view_state_id(node.el, node.path)
			w.scroll_targets[id] = HitTarget{ id: node.el.id, kind: .scroll,
				on_event: if !node.hidden && node.enabled { node.el.on_event } else { ElementCallback(unsafe { nil }) } }
			w.scroll_viewports[id] = node.local_frame
			w.scroll_content_h[id] = scroll_content_height(node.el)
			w.scroll_content_w[id] = if node.el.scroll_mode != .vertical_only { scroll_content_width(node.el.children) } else { 0.0 }
			w.scroll_transforms[id] = node.transform
			if node.scrolls.len > 0 {
				parent := w.navigation.path_node(node.scrolls.last()) or { continue }
				w.scroll_parents[id] = scroll_view_state_id(parent.el, parent.path)
			} else {
				w.scroll_parents.delete(id)
			}
			if node.hidden || !node.enabled {
				w.scroll_areas.delete(id)
				w.scrollbar_geometries.delete(id)
				w.scrollbar_geometries_x.delete(id)
			}
		}
		if mounted_owners.len > owner_count {
			for key, target in mounted_owners {
				if target.pointer_publication!=w.drag_registry.pointer_publication { mounted_owners.delete(key) }
			}
		}
		unsafe { w.drag_registry.owners=mounted_owners }
		w.drag_registry.root_revision=w.navigation.root_revision
		if w.dropdown_id.len>0 && !w.dropdown_popup.mounted { w.close_dropdown() }
		// Popup rows are window overlays; all tree targets came from the same
		// mounted frames/affine/clip above, including offscreen declarations.
		if w.dropdown_popup.mounted && w.dropdown_id.len>0 {
			ctx := w.ctx
			window := if ctx!=unsafe { nil } { rect(0,0,f64(ctx.width),f64(ctx.height)) } else { w.bounds() }
			list := dropdown_list_frame(w.dropdown_popup,window)
			for i, _ in w.dropdown_popup.options {
				target := w.dropdown_row_target(w.dropdown_popup,i,list)
				if target.w>0 && target.h>0 {
					mounted_hits << HitTarget{}
					mounted_hits[mounted_hits.len-1]=target
				}
			}
		}
		unsafe { w.hit_targets=mounted_hits }
		w.mounted_hit_count = mounted_hits.len
		w.pointer_geometry_serial = w.navigation.geometry_serial
		w.pointer_popup_owner = w.dropdown_id
		w.pointer_popup_scroll = w.dropdown_scroll
		w.pointer_popup_selected = w.text_values[w.dropdown_id] or { '' }
	}

	fn (mut w Window) custom_scroll_dispatch_current(dispatch CustomInputDispatch, ctx &DrawContext, root u64) bool {
		return dispatch.valid() && voidptr(dispatch.window.ctx) == voidptr(ctx)
			&& (ctx == unsafe { nil } || !ctx.destroyed)
			&& !dispatch.window.iconified && !dispatch.window.suspended
			&& w.navigation.root_revision == root
	}

	fn (mut w Window) scroll_maximum(id string) f64 {
		frame := w.scroll_viewports[id] or { return 0.0 }
		if frame.width <= 0 || frame.height <= 0 {
			return 0.0
		}
		content_height := w.scroll_content_h[id] or { 0.0 }
		return if content_height > frame.height { content_height - frame.height } else { 0.0 }
	}

	fn (mut w Window) scroll_maximum_x(id string) f64 {
		frame := w.scroll_viewports[id] or { return 0.0 }
		if frame.width <= 0 || frame.height <= 0 {
			return 0.0
		}
		content_width := w.scroll_content_w[id] or { 0.0 }
		return if content_width > frame.width { content_width - frame.width } else { 0.0 }
	}

	fn (mut w Window) register_scroll_view_in_parent(id string, parent_id string, frame Rect, clip Rect, content_height f64, enabled bool, show_scrollbar bool, persistent bool, target HitTarget) f64 {
		dispatch := w.custom_input_dispatch()
		ctx := dispatch.window.ctx
		build_pending := dispatch.scheduler.build_pending()
		root := w.navigation.root_revision
		focused := w.focused_field
		if id.len == 0 {
			return 0.0
		}
		w.active_scrolls[id] = true
		w.scroll_targets[id] = HitTarget{ ...target, local_frame: frame, content_transform: w.current_content_transform(), clip_region: w.current_clip_region(clip), has_geometry: true }
		w.scroll_viewports[id] = frame
		w.scroll_transforms[id] = w.current_content_transform()
		w.scroll_content_h[id] = content_height
		if parent_id.len > 0 {
			w.scroll_parents[id] = parent_id
		}
		// Preserve the position across rebuilds and resizes, only clamping when
		// the content or viewport changes the available range. A position asked for
		// before this view existed takes precedence, now that there is a range to
		// clamp it to.
		mut requested := w.scroll_state_offset(id)
		if pending := w.pending_scroll[id] {
			requested = pending
			w.pending_scroll.delete(id)
		}
		w.set_scroll_offset(id, requested, w.scroll_maximum(id))
		if !w.custom_scroll_dispatch_current(dispatch, ctx, root)
			|| (!build_pending && dispatch.scheduler.build_pending()) || w.focused_field != focused { return 0 }
		offset := w.scroll_state_offset(id)
		area := w.retained_paint_clip(w.current_clip_region(clip), frame, w.current_content_transform()).bounds()
		if enabled && area.width > 0 && area.height > 0 {
			w.scroll_areas[id] = area
			w.scroll_order << unsafe { id }
			if show_scrollbar {
				bar := scrollbar_geometry(frame, content_height, offset, persistent)
				w.scrollbar_geometries[id] = bar
			}
		}
		return offset
	}

	// register_scroll_view_width gives a registered pane its sideways range. It
	// follows register_scroll_view_in_parent, which is what makes the viewport known,
	// and a pane that does not scroll sideways passes no width, so a mode changed
	// between rebuilds leaves no offset behind.
	fn (mut w Window) register_scroll_view_width(id string, content_width f64, show_scrollbar bool, persistent bool, beside_vertical bool) f64 {
		if id.len == 0 {
			return 0.0
		}
		frame := w.scroll_viewports[id] or { return 0.0 }
		dispatch := w.custom_input_dispatch()
		ctx := dispatch.window.ctx
		root := w.navigation.root_revision
		focused := w.focused_field
		build_pending := dispatch.scheduler.build_pending()
		w.scroll_content_w[id] = content_width
		mut requested := w.scroll_state_offset_x(id)
		if pending := w.pending_scroll_x[id] {
			requested = pending
			w.pending_scroll_x.delete(id)
		}
		w.set_scroll_offset_x(id, requested, w.scroll_maximum_x(id))
		if !w.custom_scroll_dispatch_current(dispatch, ctx, root) || (!build_pending && dispatch.scheduler.build_pending()) || w.focused_field != focused { return 0 }
		offset := w.scroll_state_offset_x(id)
		if show_scrollbar && id in w.scroll_areas {
			w.scrollbar_geometries_x[id] = scrollbar_geometry_x(frame, content_width, offset,
				persistent, beside_vertical)
		}
		return offset
	}

	// Rendering skips subtrees outside a scroll viewport, but those elements are
	// still mounted. Keep their scroll-backed state active so unmount cleanup
	// does not discard positions that must be restored when they re-enter view.
	// Layout bounds cannot cull a subtree whose presentation can move descendants
	// back into the viewport. Keep ordinary rows cheap; transformed subtrees use
	// the common exact clipper when they are submitted.
	fn subtree_has_visual_transform(el Element) bool {
		if el.presentation_moves() { return true }
		for child in el.children {
			if subtree_has_visual_transform(child) { return true }
		}
		return false
	}

	fn (mut w Window) retain_culled_scroll_state(el Element, path string) {
		if el.hidden {
			return
		}
		if el.kind == .scroll {
			id := scroll_view_state_id(el, path)
			w.active_scrolls[id] = true
			w.scroll_targets[id] = HitTarget{ id: el.id, kind: .scroll, on_event: el.on_event }
		} else if el.kind == .text_area {
			id := text_area_scroll_id(el)
			if id.len > 0 {
				w.active_scrolls[id] = true
				w.scroll_targets[id] = HitTarget{ id: el.id, on_event: el.on_event }
			}
		}
		for index, child in el.children {
			w.retain_culled_scroll_state(child, reconciliation_child_key(path, index, child))
		}
	}

	fn scroll_rect_contains(r Rect, x f64, y f64) bool {
		return r.width > 0 && r.height > 0 && x >= r.x && x < r.x + r.width
			&& y >= r.y && y < r.y + r.height
	}

	fn (mut w Window) scroll_hit_test(x f64, y f64) string {
		// Children and later-painted panes get the event before their parents.
		for index := w.scroll_order.len - 1; index >= 0; index-- {
			id := w.scroll_order[index]
			if node := w.mounted_scroll_node(id) { if node.hidden || !node.enabled { continue } }
			area := w.scroll_areas[id] or { continue }
			// A fitted child has nowhere to scroll. Let its scrollable parent
			// receive the wheel or drag instead of trapping the gesture here.
			if (w.scroll_maximum(id) > 0 || w.scroll_maximum_x(id) > 0) && presentation_bounds_contains(area, x, y)
				&& transformed_contains(w.scroll_viewports[id], w.scroll_transforms[id], w.scroll_targets[id].clip_region, x, y) {
				return id
			}
		}
		return ''
	}

	fn (mut w Window) scroll_ancestor_chain(id string) []string {
		mut chain := []string{}
		mut current_id := id
		for _ in 0 .. w.scroll_viewports.len {
			if current_id.len == 0 {
				break
			}
			chain << current_id
			current_id = w.scroll_parents[current_id] or { '' }
		}
		return chain
	}

	// Apply a scroll delta to the innermost available pane first, then pass any
	// distance left at its boundary to each available ancestor. Touch input
	// captures this chain on pointer-down so frame culling cannot sever it.
	// Wheel/drag vectors are window-logical. Consume each pane's local vertical
	// component and pass the remaining window vector to its ancestors.
	fn (mut w Window) apply_scroll_vector(chain []string, dx f64, dy f64) {
		dispatch := w.custom_input_dispatch()
		ctx := dispatch.window.ctx
		root := w.navigation.root_revision
		mut remaining := Point{dx, dy}
		for id in chain {
			if node := w.mounted_scroll_node(id) {
				if node.hidden || !node.enabled || node.el.kind !in [.scroll, .text_area] { continue }
			} else if id !in w.scroll_areas { continue }
			transform := w.scroll_transforms[id] or { ContentTransform{} }
			local := transform.inverse_vector(remaining.x, remaining.y)
			before_x := w.scroll_state_offset_x(id)
			w.set_scroll_offset_x(id, before_x + local.x, w.scroll_maximum_x(id))
			if !w.custom_scroll_dispatch_current(dispatch, ctx, root) { return }
			before := w.scroll_state_offset(id)
			w.set_scroll_offset(id, before + local.y, w.scroll_maximum(id))
			if !w.custom_scroll_dispatch_current(dispatch, ctx, root) { return }
			consumed := transform.vector(w.scroll_state_offset_x(id) - before_x, w.scroll_state_offset(id) - before)
			remaining = Point{remaining.x - consumed.x, remaining.y - consumed.y}
			if math.abs(remaining.x) + math.abs(remaining.y) < 1e-6 { return }
		}
	}

	// scrollbar_geometry_x is the scroller along the bottom edge. Beside a vertical
	// scroller it stops short of the corner the two would otherwise share.
	fn scrollbar_geometry_x(frame Rect, content_width f64, offset f64, persistent bool, beside_vertical bool) ScrollbarGeometry {
		if frame.width < 16 || frame.height < 12 {
			return ScrollbarGeometry{}
		}
		maximum := if content_width > frame.width { content_width - frame.width } else { 0.0 }
		if !persistent && maximum <= 0 {
			return ScrollbarGeometry{}
		}
		corner := if beside_vertical { 9.0 } else { 0.0 }
		track := rect(frame.x + 4, frame.y + frame.height - 9, frame.width - 8 - corner, 5)
		if track.width <= 0 {
			return ScrollbarGeometry{}
		}
		content := if content_width > frame.width { content_width } else { frame.width }
		thumb_width := math.min(track.width, math.max(28.0, track.width * frame.width / content))
		progress := if maximum > 0 { math.max(0.0, math.min(offset, maximum)) / maximum } else { 0.0 }
		return ScrollbarGeometry{
			track: track
			thumb: rect(track.x + (track.width - thumb_width) * progress, track.y, thumb_width,
				track.height)
		}
	}

	fn scrollbar_geometry(frame Rect, content_height f64, offset f64, persistent bool) ScrollbarGeometry {
		if frame.width < 12 || frame.height < 16 {
			return ScrollbarGeometry{}
		}
		maximum := if content_height > frame.height { content_height - frame.height } else { 0.0 }
		if !persistent && maximum <= 0 {
			return ScrollbarGeometry{}
		}
		track := rect(frame.x + frame.width - 9, frame.y + 4, 5, frame.height - 8)
		content := if content_height > frame.height { content_height } else { frame.height }
		thumb_height := math.min(track.height, math.max(28.0, track.height * frame.height / content))
		progress := if maximum > 0 { math.max(0.0, math.min(offset, maximum)) / maximum } else { 0.0 }
		return ScrollbarGeometry{
			track: track
			thumb: rect(track.x, track.y + (track.height - thumb_height) * progress,
				track.width, thumb_height)
		}
	}

	fn (mut w Window) begin_scrollbar_drag(x f64, y f64) bool {
		// A pane's scrollers are drawn over its children, so where a column reaches
		// under the scroller of the strip it sits in, the strip's is the one the
		// pointer is on. Try the panes from the outside in.
		for index := w.touch.scroll_chain.len - 1; index >= 0; index-- {
			id := w.touch.scroll_chain[index]
			if w.begin_horizontal_scrollbar_drag(id, x, y) || w.begin_vertical_scrollbar_drag(id, x, y) {
				return true
			}
		}
		return false
	}

	fn (mut w Window) begin_vertical_scrollbar_drag(id string, x f64, y f64) bool {
		bar := w.scrollbar_geometries[id] or { return false }
		transform := w.scroll_transforms[id] or { ContentTransform{} }
		if !(w.scroll_targets[id] or { HitTarget{} }).clip_region.contains(x, y) { return false }
		lx, ly := transform.inverse(x, y)
		// Give the narrow drawn track a slightly wider pointer target.
		target := rect(bar.track.x - 3, bar.track.y, 12, bar.track.height)
		if !scroll_rect_contains(target, lx, ly) || w.scroll_maximum(id) <= 0
			|| bar.track.height <= bar.thumb.height {
			return false
		}
		w.touch.scroll_id = id
		w.touch.scrollbar_drag = true
		w.touch.scrollbar_horizontal = false
		if ly >= bar.thumb.y && ly < bar.thumb.y + bar.thumb.height {
			w.touch.scrollbar_grab_y = ly - bar.thumb.y
		} else {
			w.touch.scrollbar_grab_y = bar.thumb.height / 2
			w.drag_scrollbar_at(x, y)
		}
		return true
	}

	fn (mut w Window) begin_horizontal_scrollbar_drag(id string, x f64, y f64) bool {
		bar := w.scrollbar_geometries_x[id] or { return false }
		transform := w.scroll_transforms[id] or { ContentTransform{} }
		if !(w.scroll_targets[id] or { HitTarget{} }).clip_region.contains(x, y) { return false }
		lx, ly := transform.inverse(x, y)
		target := rect(bar.track.x, bar.track.y - 3, bar.track.width, 12)
		if !scroll_rect_contains(target, lx, ly) || w.scroll_maximum_x(id) <= 0
			|| bar.track.width <= bar.thumb.width {
			return false
		}
		w.touch.scroll_id = id
		w.touch.scrollbar_drag = true
		w.touch.scrollbar_horizontal = true
		if lx >= bar.thumb.x && lx < bar.thumb.x + bar.thumb.width {
			w.touch.scrollbar_grab_x = lx - bar.thumb.x
		} else {
			w.touch.scrollbar_grab_x = bar.thumb.width / 2
			w.drag_scrollbar_at(x, y)
		}
		return true
	}

	fn (mut w Window) drag_scrollbar_at(x f64, y f64) {
		transform := w.scroll_transforms[w.touch.scroll_id] or { ContentTransform{} }
		lx, ly := transform.inverse(x, y)
		w.drag_scrollbar_local(lx, ly)
	}

	fn (mut w Window) drag_scrollbar_local(x f64, y f64) {
		id := w.touch.scroll_id
		if w.touch.scrollbar_horizontal {
			bar := w.scrollbar_geometries_x[id] or { return }
			travel := bar.track.width - bar.thumb.width
			if travel <= 0 {
				return
			}
			maximum := w.scroll_maximum_x(id)
			w.set_scroll_offset_x(id, (x - bar.track.x - w.touch.scrollbar_grab_x) / travel * maximum,
				maximum)
			return
		}
		bar := w.scrollbar_geometries[id] or { return }
		travel := bar.track.height - bar.thumb.height
		if travel <= 0 {
			return
		}
		maximum := w.scroll_maximum(id)
		w.set_scroll_offset(id, (y - bar.track.y - w.touch.scrollbar_grab_y) / travel * maximum,
			maximum)
	}

	fn text_area_content_rect(frame Rect, padding_left f64, show_scrollbar bool) Rect {
		left := math.max(2.0, padding_left)
		// Reserve the gutter even when the text currently fits, avoiding a
		// wrap/scrollbar feedback loop as the window is resized.
		right := if show_scrollbar { 12.0 } else { 8.0 }
		return rect(frame.x + left, frame.y + text_area_vertical_padding,
			math.max(0.0, frame.width - left - right),
			math.max(0.0, frame.height - text_area_vertical_padding * 2))
	}

	// Named ids and anonymous reconciliation paths occupy separate private
	// namespaces. Every authored id remains valid, including these prefixes.
	fn named_scroll_state_id(id string) string {
		return named_scroll_prefix + id
	}

	fn (mut w Window) scroll_state_offset_x(state_id string) f64 {
		return w.scroll_offsets_x[state_id] or { 0.0 }
	}

	fn (mut w Window) scroll_state_offset(state_id string) f64 {
		return w.scroll_offsets[state_id] or { 0.0 }
	}

	// Anonymous Scroll nodes retain state by structural/key identity. The
	// private state key never becomes the event's authored source id.
	fn scroll_view_state_id(el Element, path string) string {
		mounted := el.mounted_scroll_id()
		if mounted.len > 0 && el.mounted_path() == path { return mounted }
		return authored_scroll_state_id(Element{...el, kind: .scroll}, path)
	}

	fn text_area_scroll_id(el Element) string {
		mounted := el.mounted_scroll_id()
		if mounted.len > 0 { return mounted }
		return authored_scroll_state_id(Element{...el, kind: .text_area}, '')
	}

	// Like editor state, a layout snapshot owns its text independently of the
	// mounted tree and the editor allocations replaced by input events.
	@[manualfree]
	fn (mut w Window) replace_text_area_layout(id string, layout TextAreaLayout) {
		mut lines := []string{cap: layout.lines.len}
		for line in layout.lines { lines << line.clone() }
		owned := TextAreaLayout{
			...layout
			text: layout.text.clone()
			style: TextStyle{...layout.style, font_family: layout.style.font_family.clone()}
			lines: lines
			ranges: layout.ranges.clone()
		}
		w.forget_text_area_layout(id)
		w.text_area_layouts[id] = owned
	}

	@[manualfree]
	fn (mut w Window) forget_text_area_layout(id string) {
		if previous := w.text_area_layouts[id] {
			free_owned_string(previous.text)
			free_owned_string(previous.style.font_family)
			for line in previous.lines { free_owned_string(line) }
			unsafe {
				previous.lines.free()
				previous.ranges.free()
			}
		}
		w.text_area_layouts.delete(id)
	}

	fn (mut w Window) clear_text_area_layouts() {
		for id in w.text_area_layouts.keys() { w.forget_text_area_layout(id) }
	}

	fn focused_text_area_line_index(ranges []TextAreaLineRange, caret int) int {
		for index, line in ranges {
			if caret <= line.end {
				return index
			}
		}
		return ranges.len - 1
	}

	fn (mut w Window) move_focused_text_area_caret(mut editor TextEditor, direction int, extend bool) bool {
		layout := w.text_area_layouts[w.focused_field] or { return false }
		if layout.text != editor.text || layout.lines.len == 0 || layout.ranges.len != layout.lines.len {
			return false
		}
		if !extend && !editor.selection.collapsed() {
			start, end := editor.selection.ordered()
			editor.set_caret(if direction < 0 { start } else { end })
			return true
		}
		ranges := layout.ranges
		if ranges.len == 0 {
			return false
		}
		current := focused_text_area_line_index(ranges, editor.selection.caret)
		next := clamp_int(current + direction, 0, ranges.len - 1)
		column := clamp_int(editor.selection.caret - ranges[current].start, 0,
			ranges[current].end - ranges[current].start)
		editor.move_caret_to(ranges[next].start + clamp_int(column, 0,
			ranges[next].end - ranges[next].start), extend)
		return true
	}

	fn (mut w Window) move_focused_text_area_line_boundary(mut editor TextEditor, end bool, extend bool) bool {
		layout := w.text_area_layouts[w.focused_field] or { return false }
		if layout.text != editor.text || layout.lines.len == 0 || layout.ranges.len != layout.lines.len {
			return false
		}
		ranges := layout.ranges
		if ranges.len == 0 {
			return false
		}
		line := ranges[focused_text_area_line_index(ranges, editor.selection.caret)]
		editor.move_caret_to(if end { line.end } else { line.start }, extend)
		return true
	}

	fn (mut w Window) draw_text_area_content(ctx &DrawContext, el Element, value string, x f64, y f64, clip Rect, scroll_parent_id string) {
		$if android || ios {
			w.draw_legacy_text_area_content(ctx, el, value, x, y, clip, scroll_parent_id)
		} $else {
			w.draw_shaped_text_area(ctx, el, value, x, y, clip, scroll_parent_id)
		}
	}
	$if !(android || ios) {
		fn (mut w Window) remember_shaped_text_area(id string, shaped ShapedText, width f64, style TextStyle) {
			if id.len == 0 { return }
			if previous := w.text_area_layouts[id] {
				if previous.text == shaped.text && previous.width == width && previous.style == style { return }
			}
			mut lines := []string{cap: shaped.lines.len}
			mut ranges := []TextAreaLineRange{cap: shaped.lines.len}
			for line in shaped.lines {
				lines << line.text
				ranges << TextAreaLineRange{start: line.start, end: line.end}
			}
			w.replace_text_area_layout(id, TextAreaLayout{
				text: shaped.text
				width: width
				style: style
				lines: lines
				ranges: ranges
			})
		}
	}

	$if !(android || ios) {
		fn (mut w Window) draw_shaped_text_area(ctx &DrawContext, el Element, value string, x f64, y f64, clip Rect,
			scroll_parent_id string) {
			dispatch := w.custom_input_dispatch()
			root := w.navigation.root_revision
			mut editor := w.text_editors[el.id] or { text_editor(value.clone()) }
			$if macos && ui2_embedder ? {
				editor = w.custom_composition_editor(el.id, editor)
			}
			frame := rect(x, y, el.frame.width, el.frame.height)
			content := text_area_content_rect(frame, el.padding_left, !el.disable_scroll)
			style := el.text_style
			shaped := ctx.shape_text_area(editor.text, style, content.width) or {
				eprintln('ui2: text area `${el.id}`: ${err}')
				return
			}
			// Retain only source line boundaries for editor navigation. Glyphs and
			// queries belong to this draw's shaped text and window text context.
			w.remember_shaped_text_area(el.id, shaped, content.width, style)
			content_height := shaped.size.height + text_area_vertical_padding * 2
			scroll_id := text_area_scroll_id(el)
			offset := w.register_scroll_view_in_parent(scroll_id, scroll_parent_id, frame, clip,
				content_height, el.enabled, !el.disable_scroll, el.persistent_scrollbars, HitTarget{ id: el.id, on_event: el.on_event })
			// Range clamping can call user code. The shaped text belongs to the
			// captured context; selection, caret and drawing cannot outlive it.
			if !custom_frame_current(dispatch, ctx) || w.navigation.root_revision != root { return }
			text_clip := intersect_rect(content, clip)
			if text_clip.width > 0 && text_clip.height > 0 {
				apply_clip(ctx, text_clip)
				top := content.y - offset
				if w.focused_field == el.id && !editor.selection.collapsed() {
					start, end := editor.selection.ordered()
					for selected in ctx.shaped_selection(shaped, start, end) {
						if top + selected.y + selected.height <= text_clip.y
							|| top + selected.y >= text_clip.y + text_clip.height {
							continue
						}
						draw_rect(ctx, content.x + selected.x, top + selected.y, selected.width,
							selected.height, 0xb8d7ff, 0)
					}
				}
				ctx.draw_shaped_clipped(shaped, content.x, top, text_clip)
				if w.focused_field == el.id {
					cursor := shaped.cursor(editor.selection.caret)
					w.text_caret = w.current_presentation_rect(rect(content.x + cursor.x, top + cursor.y, 2, cursor.height))
					caret := rect(content.x + cursor.x, top + cursor.y, 2, cursor.height)
					if caret.y + caret.height > text_clip.y && caret.y < text_clip.y + text_clip.height {
						draw_rect(ctx, caret.x, caret.y, caret.width, caret.height, style.color, 0)
					}
					$if macos && ui2_embedder ? {
						composition := w.composition
						if composition.field_id == el.id {
							start := composition.start + composition.mark_start
							for marked in ctx.shaped_selection(shaped, start, start + composition.mark_length) {
								if top + marked.y + marked.height <= text_clip.y
									|| top + marked.y >= text_clip.y + text_clip.height {
									continue
								}
								draw_rect(ctx, content.x + marked.x, top + marked.y + marked.height - 1,
									marked.width, 1, style.color, 0)
							}
						}
					}
				}
			}
			pane_clip := intersect_rect(frame, clip)
			if !el.disable_scroll && pane_clip.width > 0 && pane_clip.height > 0 {
				apply_clip(ctx, pane_clip)
				draw_scrollbar(ctx, x, y, frame.width, frame.height, content_height, offset,
					el.persistent_scrollbars)
			}
			apply_clip(ctx, clip)
		}
	}
}
