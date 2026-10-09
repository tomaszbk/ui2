// vfmt off
// Keep gg imports out of the native AppKit/Win32 and headless builds.
@[has_globals]
module ui2

$if ( android || linux || ( ( macos || windows ) && ui2_custom_rendering ?) ) && !ui2_headless ? {
	import math

	const text_area_vertical_padding = 8.0
	const named_scroll_prefix = '@scroll-id:'
	const anonymous_text_area_scroll_prefix = '@text-area-key:'
	const anonymous_scroll_prefix = '@scroll-path:'

	fn reset_scroll_frame() {
		g_scroll_targets = map[string]HitTarget{}
		g_scroll_areas = map[string]Rect{}
		g_scroll_transforms = map[string]ContentTransform{}
		g_scroll_viewports = map[string]Rect{}
		g_scroll_order = []string{}
		g_scroll_parents = map[string]string{}
		g_scrollbar_geometries = map[string]ScrollbarGeometry{}
	}

	fn mounted_scroll_node(id string) ?FocusNode {
		if id.starts_with(named_scroll_prefix) {
			return g_focus_navigation.node(id[named_scroll_prefix.len..])
		}
		if id.starts_with(anonymous_scroll_prefix) {
			return g_focus_navigation.path_node(id[anonymous_scroll_prefix.len..])
		}
		return none
	}

	// Publish every mounted Scroll before focus restoration can call user code.
	// Nested public scroll calls then see the same handlers and logical ranges
	// as the current focus registry, including panes culled by painting.
	fn sync_mounted_scroll_views() {
		for id in g_scroll_targets.keys() {
			// Anonymous text areas keep their separate editor/layout lifecycle.
			if id.starts_with(anonymous_text_area_scroll_prefix) { continue }
			if node := mounted_scroll_node(id) {
				if node.el.kind == .scroll { continue }
				previous := g_scroll_targets[id] or { HitTarget{} }
				if node.el.kind == .text_area && previous.kind != .scroll {
					g_scroll_targets[id] = HitTarget{ id: node.el.id, kind: node.el.kind,
						on_event: if !node.hidden && node.enabled { node.el.on_event } else { ElementCallback(unsafe { nil }) } }
					continue
				}
			}
			g_scroll_targets.delete(id)
			g_scroll_viewports.delete(id)
			g_scroll_content_h.delete(id)
			g_scroll_transforms.delete(id)
			g_scroll_areas.delete(id)
			g_scroll_parents.delete(id)
			g_scrollbar_geometries.delete(id)
		}
		mut mounted_hits := []HitTarget{}
		mut mounted_owners := map[string]HitTarget{}
		g_dropdown_popup.mounted=false
		for node in g_focus_navigation.nodes {
			publish_mounted_pointer(node,mut mounted_hits,mut mounted_owners)
			if node.el.kind==.dropdown && node.el.id==g_open_dropdown && !node.hidden && node.enabled {
				mut options := []string{}
				for entry in node.el.menu { options << entry.title }
				ctx := g_gg_app.ctx
				window := if ctx!=unsafe { nil } { rect(0,0,f64(ctx.width),f64(ctx.height)) } else { bounds() }
				track_dropdown_popup_for(node.el,node.local_frame,node.transform,options,g_text_values[node.el.id] or { node.el.text },window)
			}
			if node.el.kind != .scroll { continue }
			id := scroll_view_state_id(node.el, node.path)
			g_scroll_targets[id] = HitTarget{ id: node.el.id, kind: .scroll,
				on_event: if !node.hidden && node.enabled { node.el.on_event } else { ElementCallback(unsafe { nil }) } }
			g_scroll_viewports[id] = node.local_frame
			g_scroll_content_h[id] = scroll_content_height(node.el)
			g_scroll_transforms[id] = node.transform
			g_scroll_parents.delete(id)
			if node.scrolls.len > 0 {
				parent := g_focus_navigation.path_node(node.scrolls.last()) or { continue }
				g_scroll_parents[id] = scroll_view_state_id(parent.el, parent.path)
			}
			if node.hidden || !node.enabled {
				g_scroll_areas.delete(id)
				g_scrollbar_geometries.delete(id)
			}
		}
		g_drag_registry.owners=mounted_owners
		// Popup rows are window overlays; all tree targets came from the same
		// mounted frames/affine/clip above, including offscreen declarations.
		if g_dropdown_popup.mounted && g_open_dropdown.len>0 {
			ctx := g_gg_app.ctx
			window := if ctx!=unsafe { nil } { rect(0,0,f64(ctx.width),f64(ctx.height)) } else { bounds() }
			list := dropdown_list_frame(g_dropdown_popup,window)
			for i, _ in g_dropdown_popup.options {
				target := dropdown_row_target(g_dropdown_popup,i,list)
				if target.w>0 && target.h>0 { mounted_hits << target }
			}
		}
		unsafe { g_hit_targets=mounted_hits }
	}

	fn custom_scroll_dispatch_current(dispatch CustomInputDispatch, ctx &DrawContext, root Element) bool {
		return dispatch.valid() && dispatch.app.ctx == ctx
			&& (ctx == unsafe { nil } || !ctx.destroyed)
			&& !dispatch.app.iconified && !dispatch.app.suspended
			&& g_focus_navigation.root == root
	}

	fn scroll_maximum(id string) f64 {
		frame := g_scroll_viewports[id] or { return 0.0 }
		if frame.width <= 0 || frame.height <= 0 {
			return 0.0
		}
		content_height := g_scroll_content_h[id] or { 0.0 }
		return if content_height > frame.height { content_height - frame.height } else { 0.0 }
	}

	fn register_scroll_view(id string, frame Rect, clip Rect, content_height f64, enabled bool, show_scrollbar bool, persistent bool, target HitTarget) f64 {
		return register_scroll_view_in_parent(id, '', frame, clip, content_height, enabled,
			show_scrollbar, persistent, target)
	}

	fn register_scroll_view_in_parent(id string, parent_id string, frame Rect, clip Rect, content_height f64, enabled bool, show_scrollbar bool, persistent bool, target HitTarget) f64 {
		dispatch := custom_input_dispatch(g_gg_app)
		ctx := dispatch.app.ctx
		build_pending := dispatch.scheduler.build_pending()
		root := g_focus_navigation.root
		focused := g_focused_field
		if id.len == 0 {
			return 0.0
		}
		g_active_scrolls[id] = true
		g_scroll_targets[id] = HitTarget{ ...target, local_frame: frame, content_transform: current_content_transform(), clip_region: current_clip_region(clip), has_geometry: true }
		g_scroll_viewports[id] = frame
		g_scroll_transforms[id] = current_content_transform()
		g_scroll_content_h[id] = content_height
		if parent_id.len > 0 {
			g_scroll_parents[id] = parent_id
		}
		// Preserve the position across rebuilds and resizes, only clamping when
		// the content or viewport changes the available range. A position asked for
		// before this view existed takes precedence, now that there is a range to
		// clamp it to.
		mut requested := scroll_state_offset(id)
		if pending := g_pending_scroll[id] {
			requested = pending
			g_pending_scroll.delete(id)
		}
		set_scroll_offset(id, requested, scroll_maximum(id))
		if !custom_scroll_dispatch_current(dispatch, ctx, root)
			|| (!build_pending && dispatch.scheduler.build_pending()) || g_focused_field != focused { return 0 }
		offset := scroll_state_offset(id)
		area := current_clip_region(clip).intersect(transformed_clip(frame, current_content_transform())).bounds()
		if enabled && area.width > 0 && area.height > 0 {
			g_scroll_areas[id] = area
			g_scroll_order << id
			if show_scrollbar {
				bar := scrollbar_geometry(frame, content_height, offset, persistent)
				g_scrollbar_geometries[id] = bar
			}
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
		if el.visual_transform() != VisualTransform{} { return true }
		for child in el.children {
			if subtree_has_visual_transform(child) { return true }
		}
		return false
	}

	fn retain_culled_scroll_state(el Element, path string) {
		if el.hidden {
			return
		}
		if el.kind == .scroll {
			id := scroll_view_state_id(el, path)
			g_active_scrolls[id] = true
			g_scroll_targets[id] = HitTarget{ id: el.id, kind: .scroll, on_event: el.on_event }
		} else if el.kind == .text_area {
			id := text_area_scroll_id(el)
			if id.len > 0 {
				g_active_scrolls[id] = true
				g_scroll_targets[id] = HitTarget{ id: el.id, on_event: el.on_event }
			}
		}
		for index, child in el.children {
			retain_culled_scroll_state(child, reconciliation_child_key(path, index, child))
		}
	}

	fn scroll_rect_contains(r Rect, x f64, y f64) bool {
		return r.width > 0 && r.height > 0 && x >= r.x && x < r.x + r.width
			&& y >= r.y && y < r.y + r.height
	}

	fn scroll_hit_test(x f64, y f64) string {
		// Children and later-painted panes get the event before their parents.
		for index := g_scroll_order.len - 1; index >= 0; index-- {
			id := g_scroll_order[index]
			area := g_scroll_areas[id] or { continue }
			// A fitted child has nowhere to scroll. Let its scrollable parent
			// receive the wheel or drag instead of trapping the gesture here.
			if scroll_maximum(id) > 0 && presentation_bounds_contains(area, x, y)
				&& transformed_contains(g_scroll_viewports[id], g_scroll_transforms[id], g_scroll_targets[id].clip_region, x, y) {
				return id
			}
		}
		return ''
	}

	fn scroll_ancestor_chain(id string) []string {
		mut chain := []string{}
		mut current_id := id
		for _ in 0 .. g_scroll_viewports.len {
			if current_id.len == 0 {
				break
			}
			chain << current_id
			current_id = g_scroll_parents[current_id] or { '' }
		}
		return chain
	}

	// Apply a scroll delta to the innermost available pane first, then pass any
	// distance left at its boundary to each available ancestor. Touch input
	// captures this chain on pointer-down so frame culling cannot sever it.
	// Wheel/drag vectors are window-logical. Consume each pane's local vertical
	// component and pass the remaining window vector to its ancestors.
	fn apply_scroll_vector(chain []string, dx f64, dy f64) {
		dispatch := custom_input_dispatch(g_gg_app)
		ctx := dispatch.app.ctx
		root := g_focus_navigation.root
		mut remaining := Point{dx, dy}
		for id in chain {
			if node := mounted_scroll_node(id) {
				if node.hidden || !node.enabled || node.el.kind !in [.scroll, .text_area] { continue }
			} else if id !in g_scroll_areas { continue }
			transform := g_scroll_transforms[id] or { ContentTransform{} }
			local := transform.inverse_vector(remaining.x, remaining.y)
			before := scroll_state_offset(id)
			set_scroll_offset(id, before + local.y, scroll_maximum(id))
			if !custom_scroll_dispatch_current(dispatch, ctx, root) { return }
			consumed := transform.vector(0, scroll_state_offset(id) - before)
			remaining = Point{remaining.x - consumed.x, remaining.y - consumed.y}
			if math.abs(remaining.x) + math.abs(remaining.y) < 1e-6 { return }
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

	fn begin_scrollbar_drag(x f64, y f64) bool {
		id := g_touch.scroll_id
		bar := g_scrollbar_geometries[id] or { return false }
		transform := g_scroll_transforms[id] or { ContentTransform{} }
		if !(g_scroll_targets[id] or { HitTarget{} }).clip_region.contains(x, y) { return false }
		lx, ly := transform.inverse(x, y)
		// Give the narrow drawn track a slightly wider pointer target.
		target := rect(bar.track.x - 3, bar.track.y, 12, bar.track.height)
		if !scroll_rect_contains(target, lx, ly) || scroll_maximum(id) <= 0
			|| bar.track.height <= bar.thumb.height {
			return false
		}
		g_touch.scrollbar_drag = true
		if ly >= bar.thumb.y && ly < bar.thumb.y + bar.thumb.height {
			g_touch.scrollbar_grab_y = ly - bar.thumb.y
		} else {
			g_touch.scrollbar_grab_y = bar.thumb.height / 2
			drag_scrollbar_at(x, y)
		}
		return true
	}

	fn drag_scrollbar_at(x f64, y f64) {
		transform := g_scroll_transforms[g_touch.scroll_id] or { ContentTransform{} }
		_, ly := transform.inverse(x, y)
		drag_scrollbar_local(ly)
	}
	fn drag_scrollbar_local(y f64) {
		id := g_touch.scroll_id
		bar := g_scrollbar_geometries[id] or { return }
		travel := bar.track.height - bar.thumb.height
		if travel <= 0 {
			return
		}
		maximum := scroll_maximum(id)
		set_scroll_offset(id, (y - bar.track.y - g_touch.scrollbar_grab_y) / travel * maximum,
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

	fn scroll_state_offset(state_id string) f64 {
		return g_scroll_offsets[state_id] or { 0.0 }
	}

	// Anonymous Scroll nodes retain state by structural/key identity. The
	// private state key never becomes the event's authored source id.
	fn scroll_view_state_id(el Element, path string) string {
		return if el.id.len > 0 { named_scroll_state_id(el.id) } else { anonymous_scroll_prefix + path }
	}

	fn text_area_scroll_id(el Element) string {
		if el.id.len > 0 {
			return named_scroll_state_id(el.id)
		}
		// Keyed repeater children do not need public ids for reconciliation, but
		// the immediate backend still needs stable private state to scroll them.
		// This namespace is distinct from named ids and anonymous Scroll paths.
		if el.key.len > 0 {
			return anonymous_text_area_scroll_prefix + el.key
		}
		return ''
	}

	// Like editor state, a layout snapshot owns its text independently of the
	// mounted tree and the editor allocations replaced by input events.
	@[manualfree]
	fn replace_text_area_layout(id string, layout TextAreaLayout) {
		mut lines := []string{cap: layout.lines.len}
		for line in layout.lines { lines << line.clone() }
		owned := TextAreaLayout{
			...layout
			text: layout.text.clone()
			style: TextStyle{...layout.style, font_family: layout.style.font_family.clone()}
			lines: lines
			ranges: layout.ranges.clone()
		}
		forget_text_area_layout(id)
		g_text_area_layouts[id] = owned
	}

	@[manualfree]
	fn forget_text_area_layout(id string) {
		if previous := g_text_area_layouts[id] {
			free_owned_string(previous.text)
			free_owned_string(previous.style.font_family)
			for line in previous.lines { free_owned_string(line) }
			unsafe {
				previous.lines.free()
				previous.ranges.free()
			}
		}
		g_text_area_layouts.delete(id)
	}

	fn clear_text_area_layouts() {
		for id in g_text_area_layouts.keys() { forget_text_area_layout(id) }
	}

	fn focused_text_area_line_index(ranges []TextAreaLineRange, caret int) int {
		for index, line in ranges {
			if caret <= line.end {
				return index
			}
		}
		return ranges.len - 1
	}

	fn move_focused_text_area_caret(mut editor TextEditor, direction int, extend bool) bool {
		layout := g_text_area_layouts[g_focused_field] or { return false }
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

	fn move_focused_text_area_line_boundary(mut editor TextEditor, end bool, extend bool) bool {
		layout := g_text_area_layouts[g_focused_field] or { return false }
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

	fn draw_text_area_content(ctx &DrawContext, el Element, value string, x f64, y f64, clip Rect, scroll_parent_id string) {
		$if android {
			draw_legacy_text_area_content(ctx, el, value, x, y, clip, scroll_parent_id)
		} $else {
			draw_shaped_text_area(ctx, el, value, x, y, clip, scroll_parent_id)
		}
	}
	$if !android {
		fn remember_shaped_text_area(id string, shaped ShapedText, width f64, style TextStyle) {
			if id.len == 0 { return }
			mut lines := []string{cap: shaped.lines.len}
			mut ranges := []TextAreaLineRange{cap: shaped.lines.len}
			for line in shaped.lines {
				lines << line.text
				ranges << TextAreaLineRange{start: line.start, end: line.end}
			}
			replace_text_area_layout(id, TextAreaLayout{
				text: shaped.text
				width: width
				style: style
				lines: lines
				ranges: ranges
			})
		}
	}

	$if !android {
		fn draw_shaped_text_area(ctx &DrawContext, el Element, value string, x f64, y f64, clip Rect,
			scroll_parent_id string) {
			dispatch := custom_input_dispatch(g_gg_app)
			root := g_focus_navigation.root
			mut editor := g_text_editors[el.id] or { text_editor(value.clone()) }
			$if macos && ui2_embedder ? {
				editor = custom_composition_editor(el.id, editor)
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
			remember_shaped_text_area(el.id, shaped, content.width, style)
			content_height := shaped.size.height + text_area_vertical_padding * 2
			scroll_id := text_area_scroll_id(el)
			offset := register_scroll_view_in_parent(scroll_id, scroll_parent_id, frame, clip,
				content_height, el.enabled, !el.disable_scroll, el.persistent_scrollbars, HitTarget{ id: el.id, on_event: el.on_event })
			// Range clamping can call user code. The shaped text belongs to the
			// captured context; selection, caret and drawing cannot outlive it.
			if !custom_frame_current(dispatch, ctx) || g_focus_navigation.root != root { return }
			text_clip := intersect_rect(content, clip)
			if text_clip.width > 0 && text_clip.height > 0 {
				apply_clip(ctx, text_clip)
				top := content.y - offset
				if g_focused_field == el.id && !editor.selection.collapsed() {
					start, end := editor.selection.ordered()
					for selected in shaped.selection(start, end) {
						if top + selected.y + selected.height <= text_clip.y
							|| top + selected.y >= text_clip.y + text_clip.height {
							continue
						}
						draw_rect(ctx, content.x + selected.x, top + selected.y, selected.width,
							selected.height, 0xb8d7ff, 0)
					}
				}
				ctx.draw_shaped_clipped(shaped, content.x, top, text_clip)
				if g_focused_field == el.id {
					cursor := shaped.cursor(editor.selection.caret)
					g_gg_app.text_caret = current_presentation_rect(rect(content.x + cursor.x, top + cursor.y, 2, cursor.height))
					caret := rect(content.x + cursor.x, top + cursor.y, 2, cursor.height)
					if caret.y + caret.height > text_clip.y && caret.y < text_clip.y + text_clip.height {
						draw_rect(ctx, caret.x, caret.y, caret.width, caret.height, style.color, 0)
					}
					$if macos && ui2_embedder ? {
						composition := g_gg_app.composition
						if composition.field_id == el.id {
							start := composition.start + composition.mark_start
							for marked in shaped.selection(start, start + composition.mark_length) {
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
