// vfmt off
@[has_globals]
module ui2

$if (android || ios || linux || macos || windows) && !ui2_headless ? && !ui2_document_library ? {
	import gg

	struct DragSession {
	mut:
		pending bool
		active bool
		token u64
		source HitTarget
		target HitTarget
		operation DragOperation
		dispatch CustomInputDispatch = CustomInputDispatch{window:unsafe { nil },scheduler:unsafe { nil },state:unsafe { nil }}
		context &DrawContext = unsafe { nil }
		preview_transform ContentTransform
	}

	// Mounted ownership is independent of visible hit targets: scrolling a
	// captured source out of the viewport must not unmount it.
	struct DragRegistry {
	mut:
		owners map[string]HitTarget
		generation u64
		serial u64
		pointer_publication u64
		root_revision u64
	}
	__global g_drag_registry = DragRegistry{}

	fn drag_owner_key(target HitTarget) string {
		if target.pointer_owner_identity.len > 0 { return target.pointer_owner_identity }
		return if target.id.len > 0 { 'id:' + target.id } else { 'path:' + target.identity }
	}

	fn (mut w Window) publish_mounted_pointer(node FocusNode, mut hits []HitTarget, mut owners map[string]HitTarget) {
		if node.hidden || !node.enabled { return }
		el := node.el
		interactive := el.kind in [.button,.toggle_button,.checkbox,.dropdown,.text_field,.text_area,.slider,.switch_control]
			|| (el.kind in [.view,.image] && voidptr(el.on_event)!=unsafe { nil }
				&& (el.clickable || el.button_behavior || el.draggable || el.long_press || el.swipe_left
					|| el.drag_source!=none || el.drop_target!=none))
		// Passive consumers prepare with the actual paint surface's DPI. Only
		// pointer surfaces need availability before that surface is acquired.
		if !interactive { return }
		// Current selected-asset validity belongs to the same resource owner as
		// paint. Logical metadata alone must not make a placeholder interactive.
		if el.kind==.image {
			if w.ctx==unsafe { nil } { return }
			mut ctx := w.ctx
			ctx.prepare_image(el,f64(ctx.scale)*node.transform.footprint_scale()) or { return }
		}
		mut target := w.custom_focus_target(node)
		if el.drag_source!=none || el.drop_target!=none {
			key := drag_owner_key(target)
			old := g_drag_registry.owners[key] or { HitTarget{} }
			mount := if el.id.len>0 || el.key.len>0 { el.mounted_generation() } else { u64(0) }
			if old.drag_generation>0 && old.kind==el.kind && old.drag_mount_generation==mount {
				target=HitTarget{...target,drag_generation:old.drag_generation,drag_mount_generation:mount}
			} else {
				g_drag_registry.generation++
				target=HitTarget{...target,drag_generation:g_drag_registry.generation,drag_mount_generation:mount}
			}
			target=HitTarget{...target,pointer_publication:g_drag_registry.pointer_publication}
			owners[key]=target
		}
		// Append an empty slot, then retain the mounted strings and geometry.
		// Appending the populated struct would clone its string fields.
		hits << HitTarget{}
		hits[hits.len-1]=target
	}

	fn current_drag_owner(captured HitTarget) ?HitTarget {
		owner := g_drag_registry.owners[drag_owner_key(captured)] or { return none }
		if owner.drag_generation != captured.drag_generation || owner.kind != captured.kind { return none }
		return owner
	}

	fn (mut w Window) current_drag_geometry(captured HitTarget) HitTarget {
		return w.current_pointer_target(captured) or { captured }
	}

	pub fn (mut w Window) drag_active() bool { return g_touch.drag.active }

	pub fn (mut w Window) cancel_drag() { w.cancel_drag_session(.cancelled) }

	// Dispatch this before menu, focus and ordinary key handling in every host.
	fn (mut w Window) drag_owned_escape(key gg.KeyCode) bool {
		if key != .escape || (!g_touch.drag.active && !g_touch.drag.pending) { return false }
		w.cancel_drag_session(.escape)
		return true
	}

	fn (mut w Window) begin_drag_candidate(target HitTarget) {
		source := target.drag_source or { return }
		captured := HitTarget{...target,
			drag_source: &DragSource{...source, allowed: source.allowed.clone()}}
		g_drag_registry.serial++
		g_touch.drag = DragSession{pending: true, source: captured, token: g_drag_registry.serial,
			dispatch:w.custom_input_dispatch(),context:w.ctx}
	}

	fn (mut w Window) drag_offer(session DragSession, target HitTarget, x f64, y f64) DragOffer {
		source := session.source.drag_source or { return DragOffer{} }
		geometry := w.current_drag_geometry(session.source)
		sx, sy := geometry.content_transform.inverse(x, y)
		tx, ty := target.content_transform.inverse(x, y)
		return DragOffer{payload: source.payload, allowed: source.allowed,
			source_id: session.source.id, target_id: target.id, window_x: x, window_y: y,
			source_x: sx, source_y: sy, target_x: tx, target_y: ty}
	}

	fn (mut w Window) emit_drag(kind ElementEventKind, recipient HitTarget, session DragSession, target HitTarget,
		x f64, y f64, operation DragOperation, reason DragCancelReason) {
		geometry := w.current_drag_geometry(recipient)
		lx, ly := geometry.content_transform.inverse(x, y)
		w.fire_target_event(recipient, ElementEvent{kind: kind, id: recipient.id, x: lx, y: ly,
			drag: DragEvent{offer: w.drag_offer(session, target, x, y), operation: operation, reason: reason}})
	}

	fn owns_drag_token(token u64) bool {
		return g_touch.down && (g_touch.drag.active || g_touch.drag.pending) && g_touch.drag.token==token
	}

	fn (mut w Window) same_drag_session(token u64) bool {
		if !owns_drag_token(token) { return false }
		session := g_touch.drag
		stats := session.dispatch.scheduler.stats()
		if !session.dispatch.valid() || voidptr(session.dispatch.window.ctx)!=voidptr(session.context)
			|| stats.suspended || session.dispatch.window.iconified || session.dispatch.window.suspended {
			w.cancel_drag_session(.cancelled)
			return false
		}
		return true
	}

	fn (mut w Window) drag_session_current(session DragSession) bool {
		if !session.dispatch.valid() && voidptr(session.dispatch.state)!=voidptr(g_active_custom_window_state) {
			// A window switch moved capture into its owning snapshot. Retire that
			// gesture without touching input in the newly active window.
			mut state := session.dispatch.state
			if state.touch.drag.token==session.token { state.touch=TouchState{} }
			return false
		}
		return w.same_drag_session(session.token)
	}

	// Shared hit membership is authoritative. A top ordinary control blocks the
	// drop surface below it; no separate bounding-box/shape test lives here.
	fn (mut w Window) drag_destination(x f64, y f64) HitTarget {
		target := w.hit_test(x, y)
		owner := current_drag_owner(target) or { return HitTarget{} }
		if owner.drop_target == none { return HitTarget{} }
		return HitTarget{...target, on_event: owner.on_event,
			drag_source: owner.drag_source, drop_target: owner.drop_target}
	}

	fn (mut w Window) accepted_drag_operation(session DragSession, target HitTarget, x f64, y f64) DragOperation {
		destination := target.drop_target or { return .none }
		source := session.source.drag_source or { return .none }
		owner := current_drag_owner(session.source) or { return .none }
		current_source := owner.drag_source or { return .none }
		operation := destination.accept(w.drag_offer(session, target, x, y))
		if !w.drag_session_current(session) { return .none }
		latest := current_drag_owner(session.source) or { return .none }
		latest_source := latest.drag_source or { return .none }
		return if operation in source.allowed && operation in current_source.allowed && operation in latest_source.allowed { operation } else { DragOperation.none }
	}

	fn (mut w Window) update_drag_destination(x f64, y f64, send_over bool) {
		if !g_touch.drag.active { return }
		session := g_touch.drag
		current := w.drag_destination(x, y)
		operation := w.accepted_drag_operation(session, current, x, y)
		if !w.drag_session_current(session) { return }
		changed := current.drag_generation != session.target.drag_generation
			|| drag_owner_key(current) != drag_owner_key(session.target)
		if changed {
			// Clear the previous hover before leave. Reentrant cancellation must
			// neither leave it twice nor leave a target that has not entered yet.
			g_touch.drag.target = HitTarget{}
			g_touch.drag.operation = .none
		}
		if changed && session.target.drop_target != none {
			w.emit_drag(.drag_leave, session.target, session, session.target, x, y, session.operation, .none)
			if !w.drag_session_current(session) { return }
		}
		g_touch.drag.target = current
		g_touch.drag.operation = operation
		if changed && current.drop_target != none {
			w.emit_drag(.drag_enter, current, session, current, x, y, operation, .none)
			if !w.drag_session_current(session) { return }
		}
		if current.drop_target != none && (send_over || changed || operation != session.operation) {
			w.emit_drag(.drag_over, current, session, current, x, y, operation, .none)
			if !w.drag_session_current(session) { return }
		}
	}

	// Returns true whenever drag-drop owns this gesture, including its threshold
	// phase. Scrollbar/slider capture was already selected by pointer-down.
	fn (mut w Window) move_drag_session(x f64, y f64) bool {
		if !g_touch.drag.pending && !g_touch.drag.active { return false }
		if !w.reconcile_drag_release(g_touch.drag.token) { return true }
		owner := current_drag_owner(g_touch.drag.source) or {
			w.cancel_drag_session(.source_removed)
			return true
		}
		if owner.drag_source == none {
			w.cancel_drag_session(.source_removed)
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
			g_touch.drag.preview_transform = w.current_drag_geometry(g_touch.drag.source).content_transform
			session := g_touch.drag
			w.emit_drag(.drag_start, session.source, session, HitTarget{}, x, y, .none, .none)
			if !w.drag_session_current(session) { return true }
		}
		session := g_touch.drag
		w.update_drag_destination(x, y, true)
		if !w.drag_session_current(session) { return true }
		w.invalidate_custom_paint()
		return true
	}

	// Compare only the current narrow phase, after common layout resolution.
	// Fixed-frame text, tint, colors and interaction styles do not affect hits.
	fn same_drag_hit_declaration(a HitTarget, b HitTarget) bool {
		if a.local_frame!=b.local_frame || a.content_transform!=b.content_transform
			|| a.clip_region!=b.clip_region || a.is_image!=b.is_image
			|| a.is_vector_canvas!=b.is_vector_canvas || a.vector_hit_mode!=b.vector_hit_mode
			|| a.vector_shapes.len!=b.vector_shapes.len { return false }
		if a.is_image && (a.image_geometry.points!=b.image_geometry.points || a.image_geometry.bounds!=b.image_geometry.bounds) { return false }
		for i, shape in a.vector_shapes {
			other := b.vector_shapes[i]
			if shape.fill_triangles!=other.fill_triangles || shape.stroke_triangles!=other.stroke_triangles { return false }
		}
		return true
	}

	fn (mut w Window) reconcile_drag_release(token u64) bool {
		if !w.same_drag_session(token) { return false }
		dispatch := g_touch.drag.dispatch
		if !w.sync_custom_input_geometry(dispatch) {
			if owns_drag_token(token) { w.cancel_drag_session(.cancelled) }
			return false
		}
		if !w.same_drag_session(token) { return false }
		owner := current_drag_owner(g_touch.drag.source) or {
			w.cancel_drag_session(.source_removed)
			return false
		}
		if owner.drag_source==none { w.cancel_drag_session(.source_removed); return false }
		return true
	}

	fn (mut w Window) release_drag_session(x f64, y f64) bool {
		if !g_touch.drag.active && !g_touch.drag.pending { return false }
		mut app := w
		if app.releasing_drag { return true }
		app.releasing_drag = true
		defer { app.releasing_drag = false }
		token := g_touch.drag.token
		if !w.reconcile_drag_release(token) { return true }
		// A release beyond threshold counts even if the host coalesced all moves.
		w.move_drag_session(x, y)
		if !w.reconcile_drag_release(token) { return true }
		if g_touch.drag.pending {
			g_touch.drag = DragSession{}
			return false // a short press may activate the source's normal tap
		}
		w.update_drag_destination(x, y, false)
		if !w.reconcile_drag_release(token) { return true }
		session := g_touch.drag
		current := w.drag_destination(x, y)
		operation := w.accepted_drag_operation(session, current, x, y)
		// accept is also user code. Reconcile once, without a callback loop, then
		// require the accepted declaration and operation to remain authoritative.
		if !w.reconcile_drag_release(token) { return true }
		final_target := w.drag_destination(x, y)
		owner := current_drag_owner(session.source) or { return true }
		current_source := owner.drag_source or { return true }
		accepted := current.drop_target or { DropTarget{} }
		final_destination := final_target.drop_target or { DropTarget{} }
		valid := operation != .none && operation in current_source.allowed
			&& final_target.drag_generation == session.target.drag_generation
			&& drag_owner_key(final_target) == drag_owner_key(session.target)
			&& voidptr(accepted.accept) == voidptr(final_destination.accept)
			&& same_drag_hit_declaration(current,final_target)
		g_touch = TouchState{} // clear capture before terminal callbacks/reentrancy
		if valid {
			w.emit_drag(.drop, final_target, session, final_target, x, y, operation, .none)
			if !session.dispatch.valid() { return true }
			w.emit_drag(.drag_leave, final_target, session, final_target, x, y, operation, .none)
			if !session.dispatch.valid() { return true }
			w.emit_drag(.drag_end, session.source, session, final_target, x, y, operation, .none)
		} else {
			if session.target.drop_target != none {
				w.emit_drag(.drag_leave, session.target, session, session.target, x, y, .none, .invalid_target)
				if !session.dispatch.valid() { return true }
			}
			w.emit_drag(.drag_cancel, session.source, session, HitTarget{}, x, y, .none, .invalid_target)
		}
		w.invalidate_custom_paint()
		return true
	}

	fn (mut w Window) cancel_drag_session(reason DragCancelReason) {
		if !g_touch.drag.active && !g_touch.drag.pending { return }
		session := g_touch.drag
		x := g_touch.current_x
		y := g_touch.current_y
		g_touch = TouchState{}
		dispatch := w.custom_input_dispatch()
		if session.active && session.dispatch.state==dispatch.state && session.dispatch.window==dispatch.window && dispatch.valid() {
			if session.target.drop_target != none {
				w.emit_drag(.drag_leave, session.target, session, session.target, x, y, session.operation, reason)
				if !dispatch.valid() { return }
			}
			w.emit_drag(.drag_cancel, session.source, session, session.target, x, y, .none, reason)
		}
		w.invalidate_custom_paint()
	}

	fn (mut w Window) sync_drag_session() {
		if !g_touch.drag.pending && !g_touch.drag.active { return }
		if !w.same_drag_session(g_touch.drag.token) { return }
		owner := current_drag_owner(g_touch.drag.source) or {
			w.cancel_drag_session(.source_removed)
			return
		}
		if owner.drag_source == none {
			w.cancel_drag_session(.source_removed)
			return
		}
		geometry := w.current_drag_geometry(g_touch.drag.source)
		g_touch.drag.source = HitTarget{...g_touch.drag.source,
			content_transform: geometry.content_transform, x: geometry.x, y: geometry.y, w: geometry.w, h: geometry.h}
		w.update_drag_destination(g_touch.current_x, g_touch.current_y, false)
	}

	fn drag_preview_element(preview DragPreview) Element {
		return Element{kind:.image,image_path:preview.image_path,image_asset:preview.image_asset,
			image_style:preview.image_style,frame:rect(preview.offset_x,preview.offset_y,preview.width,preview.height)}
	}

	fn preload_drag_preview(mut ctx DrawContext) {
		if !g_touch.drag.active { return }
		source := g_touch.drag.source.drag_source or { return }
		if source.preview.image_path.len==0 { return }
		transform := drag_preview_transform(g_touch.drag.preview_transform,g_touch.current_x,g_touch.current_y)
		ctx.prepare_image(drag_preview_element(source.preview),f64(ctx.scale)*transform.footprint_scale()) or { eprintln('ui2: ${err}') }
	}

	fn draw_drag_preview(ctx &DrawContext) {
		if !g_touch.drag.active { return }
		source := g_touch.drag.source.drag_source or { return }
		preview := source.preview
		outer := ctx.content_transform
		base := ctx.clip_base
		region := ctx.clip_region
		window := ctx.retained_clip(ClipRegion{},rect(0,0,f64(ctx.width),f64(ctx.height)),ContentTransform{})
		unsafe {
			ctx.content_transform=drag_preview_transform(g_touch.drag.preview_transform,g_touch.current_x,g_touch.current_y)
			ctx.clip_base=window
			ctx.clip_region=window
		}
		ctx.sync_scissor()
		defer {
			unsafe { ctx.content_transform=outer; ctx.clip_base=base; ctx.clip_region=region }
			ctx.sync_scissor()
		}
		frame := rect(preview.offset_x,preview.offset_y,preview.width,preview.height)
		if !preview.box.transparent { draw_rect(ctx,frame.x,frame.y,frame.width,frame.height,preview.box.bg,preview.box.radius) }
		draw_box_borders(ctx,frame.x,frame.y,frame.width,frame.height,preview.box)
		if preview.image_path.len>0 {
			el := drag_preview_element(preview)
			geometry := ctx.image_geometry_for(el,frame) or { return }
			ctx.draw_asset_image(el,geometry)
		}
		if preview.text.len>0 { draw_text_centered(ctx,preview.text,frame.x,frame.y,frame.width,frame.height,preview.text_style) }
	}
}
