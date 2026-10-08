// vfmt off
@[has_globals]
module ui2

$if (android || linux || ((macos || windows) && ui2_custom_rendering ?)) && !ui2_headless ? {
	struct DragSession {
	mut:
		pending bool
		active bool
		token u64
		source HitTarget
		target HitTarget
		operation DragOperation
		preview_transform ContentTransform
	}

	// Mounted ownership is independent of visible hit targets: scrolling a
	// captured source out of the viewport must not unmount it.
	struct DragRegistry {
	mut:
		owners map[string]HitTarget
		generation u64
		serial u64
	}
	__global g_drag_registry = DragRegistry{}

	fn drag_owner_key(target HitTarget) string {
		return if target.id.len > 0 { 'id:' + target.id } else { 'path:' + target.identity }
	}

	fn collect_drag_owners(el Element, path string, enabled bool, mut next map[string]HitTarget) {
		if el.hidden || !enabled || !el.enabled { return }
		if el.drag_source != none || el.drop_target != none {
			mut target := HitTarget{identity: path, id: el.id, kind: el.kind,
				on_event: el.on_event, drag_source: el.drag_source, drop_target: el.drop_target}
			key := drag_owner_key(target)
			old := g_drag_registry.owners[key] or { HitTarget{} }
			if old.drag_generation > 0 && old.kind == el.kind {
				target = HitTarget{...target, drag_generation: old.drag_generation}
			} else {
				g_drag_registry.generation++
				target = HitTarget{...target, drag_generation: g_drag_registry.generation}
			}
			next[key] = target
		}
		for index, child in el.children {
			collect_drag_owners(child, reconciliation_child_key(path, index, child), true, mut next)
		}
	}

	fn refresh_drag_owners(root Element) {
		mut next := map[string]HitTarget{}
		collect_drag_owners(root, 'root', true, mut next)
		g_drag_registry.owners = next
	}

	fn current_drag_owner(captured HitTarget) ?HitTarget {
		owner := g_drag_registry.owners[drag_owner_key(captured)] or { return none }
		if owner.drag_generation != captured.drag_generation || owner.kind != captured.kind { return none }
		return owner
	}

	fn current_drag_geometry(captured HitTarget) HitTarget {
		for i := g_hit_targets.len - 1; i >= 0; i-- {
			current := g_hit_targets[i]
			if drag_owner_key(current) == drag_owner_key(captured) && current.drag_generation == captured.drag_generation {
				return current
			}
		}
		return captured
	}

	pub fn drag_active() bool { return g_touch.drag.active }

	pub fn cancel_drag() { cancel_drag_session(.cancelled) }

	fn begin_drag_candidate(target HitTarget) {
		source := target.drag_source or { return }
		captured := HitTarget{...target,
			drag_source: DragSource{...source, allowed: source.allowed.clone()}}
		g_drag_registry.serial++
		g_touch.drag = DragSession{pending: true, source: captured, token: g_drag_registry.serial}
	}

	fn drag_offer(session DragSession, target HitTarget, x f64, y f64) DragOffer {
		source := session.source.drag_source or { return DragOffer{} }
		geometry := current_drag_geometry(session.source)
		sx, sy := geometry.content_transform.inverse(x, y)
		tx, ty := target.content_transform.inverse(x, y)
		return DragOffer{payload: source.payload, allowed: source.allowed,
			source_id: session.source.id, target_id: target.id, window_x: x, window_y: y,
			source_x: sx, source_y: sy, target_x: tx, target_y: ty}
	}

	fn emit_drag(kind ElementEventKind, recipient HitTarget, session DragSession, target HitTarget,
		x f64, y f64, operation DragOperation, reason DragCancelReason) {
		geometry := current_drag_geometry(recipient)
		lx, ly := geometry.content_transform.inverse(x, y)
		fire_target_event(recipient, ElementEvent{kind: kind, id: recipient.id, x: lx, y: ly,
			drag: DragEvent{offer: drag_offer(session, target, x, y), operation: operation, reason: reason}})
	}

	fn same_drag_session(token u64) bool {
		return g_touch.down && g_touch.drag.active && g_touch.drag.token == token
	}

	// Shared hit membership is authoritative. A top ordinary control blocks the
	// drop surface below it; no separate bounding-box/shape test lives here.
	fn drag_destination(x f64, y f64) HitTarget {
		target := hit_test(x, y)
		if target.drop_target == none || current_drag_owner(target) == none { return HitTarget{} }
		return target
	}

	fn accepted_drag_operation(session DragSession, target HitTarget, x f64, y f64) DragOperation {
		destination := target.drop_target or { return .none }
		source := session.source.drag_source or { return .none }
		owner := current_drag_owner(session.source) or { return .none }
		current_source := owner.drag_source or { return .none }
		operation := destination.accept(drag_offer(session, target, x, y))
		return if operation in source.allowed && operation in current_source.allowed { operation } else { DragOperation.none }
	}

	fn update_drag_destination(x f64, y f64, send_over bool) {
		if !g_touch.drag.active { return }
		session := g_touch.drag
		current := drag_destination(x, y)
		operation := accepted_drag_operation(session, current, x, y)
		if !same_drag_session(session.token) { return }
		changed := current.drag_generation != session.target.drag_generation
			|| drag_owner_key(current) != drag_owner_key(session.target)
		if changed {
			// Clear the previous hover before leave. Reentrant cancellation must
			// neither leave it twice nor leave a target that has not entered yet.
			g_touch.drag.target = HitTarget{}
			g_touch.drag.operation = .none
		}
		if changed && session.target.drop_target != none {
			emit_drag(.drag_leave, session.target, session, session.target, x, y, session.operation, .none)
			if !same_drag_session(session.token) { return }
		}
		g_touch.drag.target = current
		g_touch.drag.operation = operation
		if changed && current.drop_target != none {
			emit_drag(.drag_enter, current, session, current, x, y, operation, .none)
			if !same_drag_session(session.token) { return }
		}
		if current.drop_target != none && (send_over || changed || operation != session.operation) {
			emit_drag(.drag_over, current, session, current, x, y, operation, .none)
		}
	}

	// Returns true whenever drag-drop owns this gesture, including its threshold
	// phase. Scrollbar/slider capture was already selected by pointer-down.
	fn move_drag_session(x f64, y f64) bool {
		if !g_touch.drag.pending && !g_touch.drag.active { return false }
		owner := current_drag_owner(g_touch.drag.source) or {
			cancel_drag_session(.source_removed)
			return true
		}
		if owner.drag_source == none {
			cancel_drag_session(.source_removed)
			return true
		}
		if g_touch.drag.pending {
			source := g_touch.drag.source.drag_source or { return true }
			dx := x - g_touch.start_x
			dy := y - g_touch.start_y
			if dx * dx + dy * dy <= source.threshold * source.threshold {
				g_touch.moved = false // this source owns the threshold, not raw scroll/tap
				return true
			}
			g_touch.drag.pending = false
			g_touch.drag.active = true
			g_touch.moved = true
			g_touch.pressed_id = ''
			g_touch.drag.preview_transform = current_drag_geometry(g_touch.drag.source).content_transform
			session := g_touch.drag
			emit_drag(.drag_start, session.source, session, HitTarget{}, x, y, .none, .none)
			if !same_drag_session(session.token) { return true }
		}
		update_drag_destination(x, y, true)
		invalidate_custom_paint()
		return true
	}

	fn release_drag_session(x f64, y f64) bool {
		if !g_touch.drag.active && !g_touch.drag.pending { return false }
		// A release beyond threshold counts even if the host coalesced all moves.
		move_drag_session(x, y)
		if !g_touch.down { return true }
		if g_touch.drag.pending {
			g_touch.drag = DragSession{}
			return false // a short press may activate the source's normal tap
		}
		update_drag_destination(x, y, false)
		if !g_touch.down { return true }
		session := g_touch.drag
		owner := current_drag_owner(session.source) or {
			cancel_drag_session(.source_removed)
			return true
		}
		if owner.drag_source == none {
			cancel_drag_session(.source_removed)
			return true
		}
		// Revalidate after callbacks; enter/over may withdraw a target.
		current := drag_destination(x, y)
		operation := accepted_drag_operation(session, current, x, y)
		if !same_drag_session(session.token) { return true }
		valid := operation != .none && current.drag_generation == session.target.drag_generation
			&& drag_owner_key(current) == drag_owner_key(session.target)
		g_touch = TouchState{} // clear capture before terminal callbacks/reentrancy
		if valid {
			emit_drag(.drop, current, session, current, x, y, operation, .none)
			// No callback intervenes between final validation and drop. Leave is
			// cleanup after the commit, so it cannot withdraw a validated target.
			emit_drag(.drag_leave, current, session, current, x, y, operation, .none)
			emit_drag(.drag_end, session.source, session, current, x, y, operation, .none)
		} else {
			if session.target.drop_target != none {
				emit_drag(.drag_leave, session.target, session, session.target, x, y, .none, .invalid_target)
			}
			emit_drag(.drag_cancel, session.source, session, HitTarget{}, x, y, .none, .invalid_target)
		}
		invalidate_custom_paint()
		return true
	}

	fn cancel_drag_session(reason DragCancelReason) {
		if !g_touch.drag.active && !g_touch.drag.pending { return }
		session := g_touch.drag
		x := g_touch.current_x
		y := g_touch.current_y
		g_touch = TouchState{}
		if session.active {
			if session.target.drop_target != none {
				emit_drag(.drag_leave, session.target, session, session.target, x, y, session.operation, reason)
			}
			emit_drag(.drag_cancel, session.source, session, session.target, x, y, .none, reason)
		}
		invalidate_custom_paint()
	}

	fn sync_drag_session() {
		if !g_touch.drag.pending && !g_touch.drag.active { return }
		owner := current_drag_owner(g_touch.drag.source) or {
			cancel_drag_session(.source_removed)
			return
		}
		if owner.drag_source == none {
			cancel_drag_session(.source_removed)
			return
		}
		geometry := current_drag_geometry(g_touch.drag.source)
		g_touch.drag.source = HitTarget{...g_touch.drag.source,
			content_transform: geometry.content_transform, x: geometry.x, y: geometry.y, w: geometry.w, h: geometry.h}
		update_drag_destination(g_touch.current_x, g_touch.current_y, false)
	}

	fn preload_drag_preview() {
		if !g_touch.drag.active { return }
		source := g_touch.drag.source.drag_source or { return }
		if source.preview.image_path.len > 0 { cache_image(source.preview.image_path) }
	}

	fn draw_drag_preview(ctx &DrawContext) {
		if !g_touch.drag.active { return }
		source := g_touch.drag.source.drag_source or { return }
		preview := source.preview
		outer := ctx.content_transform
		transform := drag_preview_transform(g_touch.drag.preview_transform, g_touch.current_x, g_touch.current_y)
		unsafe { ctx.content_transform = transform }
		defer { unsafe { ctx.content_transform = outer } }
		window := rect(0, 0, f64(ctx.width), f64(ctx.height))
		apply_clip(ctx, transform.inverse_rect(window))
		frame := rect(preview.offset_x, preview.offset_y, preview.width, preview.height)
		if !preview.box.transparent { draw_rect(ctx, frame.x, frame.y, frame.width, frame.height, preview.box.bg, preview.box.radius) }
		draw_box_borders(ctx, frame.x, frame.y, frame.width, frame.height, preview.box)
		if preview.image_path.len > 0 {
			draw_cached_image(ctx, preview.image_path, frame.x, frame.y, frame.width, frame.height, 0)
		}
		if preview.text.len > 0 { draw_text_centered(ctx, preview.text, frame.x, frame.y, frame.width, frame.height, preview.text_style) }
	}
}
