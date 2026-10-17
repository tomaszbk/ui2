module ui2

import math

// These reads use the host's sampled frame, never an independent clock.
fn (element &Element) presented_hidden() bool {
	state := element.motion_state()
	if state != unsafe { nil } && state.mounted {
		return state.disposed || state.current.phase == .absent
	}
	return element.hidden
}

fn (element &Element) presented_enabled() bool {
	state := element.motion_state()
	return element.enabled && !element.presence_exiting()
		&& (state == unsafe { nil } || state.input_enabled())
}

fn (element &Element) presented_opacity() f64 {
	state := element.presented_motion()
	return if state != unsafe { nil } { state.current.values.opacity } else { element.opacity }
}

fn (element &Element) presence_leaving() bool {
	state := element.motion_state()
	return element.presence_exiting() || (state != unsafe { nil } && state.current.phase == .exiting)
}

fn (element &Element) layout_excluded() bool {
	return element.hidden || element.presence_exiting() || element.overlay != none
}

// presented_motion is the element's mounted motion state, or nil.
fn (element &Element) presented_motion() &ElementMotionState {
	state := element.motion_state()
	if state == unsafe { nil } || !state.mounted || state.disposed {
		return unsafe { nil }
	}
	return state
}

// presented_matrix maps the element's laid-out area to where it is shown: its
// visual transform inside the offset of a running layout transition.
fn (element &Element) presented_matrix(area Rect) !ContentTransform {
	visual := element.visual_transform().matrix(area)!
	state := element.presented_motion()
	if state == unsafe { nil } || state.current.layout_offset == Rect{} {
		return visual
	}
	offset := state.current.layout_offset
	if state.config.layout == .scale && area.width > 0 && area.height > 0 {
		sx := (area.width + offset.width) / area.width
		sy := (area.height + offset.height) / area.height
		return ContentTransform{
			xx: sx
			yy: sy
			x:  area.x + offset.x - sx * area.x
			y:  area.y + offset.y - sy * area.y
		}.compose(visual)
	}
	return ContentTransform{
		x: offset.x
		y: offset.y
	}.compose(visual)
}

// presented_box_size is the size the element's own fill, border and shadow
// are drawn at: its laid-out size, resized by a box layout transition and the
// box scales. Content keeps the laid-out size.
fn (element &Element) presented_box_size(width f64, height f64) (f64, f64) {
	state := element.presented_motion()
	if state == unsafe { nil } {
		return width, height
	}
	values := state.current.values
	mut w := width
	mut h := height
	if state.config.layout == .box {
		w += state.current.layout_offset.width
		h += state.current.layout_offset.height
	}
	return math.max(0.0, w * values.box_scale_x), math.max(0.0, h * values.box_scale_y)
}

// with_motion_paint presents animated paint: the background, border and text
// color, corner radius and shadow a running motion has reached. Interaction
// styles still apply over it.
fn (element Element) with_motion_paint() Element {
	state := element.presented_motion()
	if state == unsafe { nil } {
		return element
	}
	paint := state.current.values.paint
	if paint == element_motion_paint(element) {
		return element
	}
	return Element{
		...element
		box:        BoxStyle{
			...element.box
			bg:           paint.background
			border_color: paint.border_color
			radius:       paint.radius
			shadow:       paint.shadow
		}
		text_style: TextStyle{
			...element.text_style
			color: paint.text_color
		}
	}
}

// presentation_moves reports whether motion can show the element away from
// its laid-out frame, so a scroll view must not cull it by that frame.
fn (element &Element) presentation_moves() bool {
	if element.visual_transform() != VisualTransform{} {
		return true
	}
	state := element.presented_motion()
	return state != unsafe { nil } && state.current.layout_offset != Rect{}
}

@[heap]
struct MotionTree {
mut:
	// The window whose elements move, which their states belong to.
	window           &Window = unsafe { nil }
	states           map[string]&ElementMotionState
	previous         Element
	initialized      bool
	changed          bool
	geometry_changed bool
	prune_pending    bool
	seen             map[string]bool
	// Elements with layout transitions; zero skips observing layout.
	layout_watchers int
	observed        Element
	// Events of one sample, delivered after it. The buffer keeps its capacity.
	events     []MotionDispatch
	dispatched bool
}

// The caller owns the retained tree. Only changed declarations allocate;
// sampled motion updates cached presentation on the retained state itself.
fn (mut tree MotionTree) prepare(element Element) !Element {
	if tree.states.len == 0 && !motion_subtree_managed(element)
		&& (!tree.initialized || !motion_subtree_managed(tree.previous)) {
		tree.previous = element
		tree.initialized = true
		tree.layout_watchers = 0
		return element
	}
	tree.seen.clear()
	result := tree.prepare_node(element, if tree.initialized {
		tree.previous
	} else {
		Element{}
	}, 'root', []MotionTarget{}, MotionConfig{})!
	tree.retain_states(result)
	tree.previous = result
	tree.initialized = true
	return result
}

fn (mut tree MotionTree) mark_states(element Element, path string) {
	if !motion_subtree_managed(element) {
		return
	}
	state := element.motion_state()
	if state != unsafe { nil } {
		tree.seen[motion_identity(element, path)] = true
		if state.config.layout != .none {
			tree.layout_watchers++
		}
	}
	for index, child in element.children {
		tree.mark_states(child, reconciliation_child_key(path, index, child))
	}
}

fn (mut tree MotionTree) retain_states(root Element) {
	tree.seen.clear()
	tree.layout_watchers = 0
	tree.mark_states(root, 'root')
	for identity, mut state in tree.states {
		if identity !in tree.seen {
			state.force_cancel()
			tree.states.delete(identity)
		}
	}
}

fn motion_identity(element Element, path string) string {
	return if element.id.len > 0 {
		'id:' + element.id
	} else if element.compiled_node != unsafe { nil } {
		element.compiled_node.identity()
	} else {
		path
	}
}

// Static subtrees cannot create, reverse or retain a motion exit. In
// particular a text patch must not reconcile every unchanged static sibling.
fn motion_subtree_managed(element Element) bool {
	if element.motion != none || element.motion_state() != unsafe { nil } {
		return true
	}
	for child in element.children {
		if motion_subtree_managed(child) {
			return true
		}
	}
	return false
}

// motion_target_config configures an element that only an ancestor's timeline
// animates: it has no enter or exit of its own, and keeps the clock and reduced
// motion of the ancestor that targets it.
fn motion_target_config(owner MotionConfig) MotionConfig {
	return MotionConfig{
		enter:          MotionStyle{}
		exit:           MotionStyle{}
		clock:          owner.clock
		reduced_motion: owner.reduced_motion
	}
}

// motion_targeted is the timeline the inherited targets give the element with
// id: one, or several played together.
fn motion_targeted(targets []MotionTarget, id string) MotionTimeline {
	if targets.len == 0 || id.len == 0 {
		return MotionTimeline{}
	}
	mut found := []MotionTimeline{}
	for target in targets {
		if target.id == id {
			found << target.timeline
		}
	}
	return match found.len {
		0 { MotionTimeline{} }
		1 { found[0] }
		else { motion_parallel(...found) }
	}
}

// owner is the configuration of the nearest ancestor with targets.
fn (mut tree MotionTree) prepare_node(element Element, previous Element, path string, targets []MotionTarget, owner MotionConfig) !Element {
	if targets.len == 0 && !motion_subtree_managed(element) && !motion_subtree_managed(previous) {
		return element
	}
	mut result := element
	identity := motion_identity(element, path)
	targeted := motion_targeted(targets, element.id)
	mut state := element.motion_state()
	if state == unsafe { nil } && (element.motion != none || !targeted.is_empty()) {
		if existing := tree.states[identity] {
			if !existing.disposed {
				state = existing
			}
		}
		if state == unsafe { nil } {
			mut created := new_motion_state_for(element, element.motion or {
				motion_target_config(owner)
			}, tree.window)!
			created.target_timeline = targeted
			created.sync_timeline(created.now())!
			state = created
		}
	}
	if element.motion == none && targeted.is_empty() && state != unsafe { nil }
		&& !element.presence_exiting() {
		state.force_cancel()
		state = unsafe { nil }
		runtime := result.runtime
		result = Element{
			...result
			runtime: runtime.with_motion_state(unsafe { nil })
		}
	}
	if state != unsafe { nil } {
		if !element.presence_exiting() && state.structural_exit {
			state.resume_enter()!
		}
		if element.motion == none && !targeted.is_empty() {
			state.configure(motion_target_config(owner))!
		}
		state.target_timeline = targeted
		state.update(element)!
		state.mount()!
		tree.states[identity] = state
		runtime := result.runtime
		result = Element{
			...result
			runtime: runtime.with_motion_state(state)
		}
	}
	mut child_targets := unsafe { targets }
	mut child_owner := owner
	if config := element.motion {
		if config.targets.len > 0 {
			child_targets = targets.clone()
			child_targets << config.targets
			child_owner = config
		}
	}
	// Resolve sibling identities once. Nested scans used to allocate identity
	// strings quadratically even when one small counter was the only patch.
	mut old_indices := map[string]int{}
	mut old_identities := []string{cap: previous.children.len}
	for old_index, old_child in previous.children {
		old_identity := motion_identity(old_child, reconciliation_child_key(path, old_index,
			old_child))
		old_indices[old_identity] = old_index
		old_identities << old_identity
	}
	mut present := map[string]bool{}
	mut children := []Element{cap: element.children.len}
	mut changed := false
	for index, child in element.children {
		child_path := reconciliation_child_key(path, index, child)
		child_identity := motion_identity(child, child_path)
		present[child_identity] = true
		old := if old_index := old_indices[child_identity] {
			previous.children[old_index]
		} else {
			Element{}
		}
		prepared := tree.prepare_node(child, old, child_path, child_targets, child_owner)!
		// Retained descendant snapshots are immutable; share their owned arrays.
		children << unsafe { prepared }
		if prepared != child {
			changed = true
		}
	}
	// Compiled repeaters own their exit scopes. Ordinary keyed Element trees
	// also retain a removed root until its own configured exit finishes.
	for old_index, old in previous.children {
		if present[old_identities[old_index]] or { false } || old.compiled_node != unsafe { nil } {
			continue
		}
		if begin_motion_subtree_exit(old)! {
			runtime := old.runtime
			children << Element{
				...old
				runtime: runtime.with_exiting(true)
			}
			changed = true
		}
	}
	if changed {
		result = Element{
			...result
			children: children
		}
	}
	return result
}

fn begin_motion_subtree_exit(element Element) !bool {
	mut pending := false
	mut state := element.motion_state()
	if state != unsafe { nil } && !state.disposed {
		if !state.structural_exit {
			state.begin_exit(unsafe { nil })!
		}
		pending = state.current.phase != .absent
	}
	for child in element.children {
		if begin_motion_subtree_exit(child)! {
			pending = true
		}
	}
	return pending
}

fn motion_subtree_exit_pending(element Element) bool {
	state := element.motion_state()
	if state != unsafe { nil } && !state.disposed && state.structural_exit
		&& state.current.phase != .absent {
		return true
	}
	for child in element.children {
		if motion_subtree_exit_pending(child) {
			return true
		}
	}
	return false
}

fn cancel_motion_subtree(element Element) {
	mut state := element.motion_state()
	if state != unsafe { nil } {
		state.force_cancel()
	}
	for child in element.children {
		cancel_motion_subtree(child)
	}
}

// sample advances every mounted element one frame, then delivers the events
// of that frame. dispatched reports whether any handler ran.
fn (mut tree MotionTree) sample(root Element) !bool {
	tree.changed = false
	tree.geometry_changed = false
	tree.dispatched = false
	tree.events.clear()
	tree.sample_node(root, false)!
	count := tree.events.len
	for index in 0 .. count {
		if index >= tree.events.len {
			break
		}
		dispatch := tree.events[index]
		dispatch.callback(dispatch.event)
		tree.dispatched = true
	}
	tree.events.clear()
	return tree.changed
}

fn (mut tree MotionTree) sample_node(element Element, ancestor_hidden bool) ! {
	// Hidden ancestors cannot keep an invisible child tween waking the host.
	mut state := element.motion_state()
	if ancestor_hidden && !(state != unsafe { nil } && state.structural_exit) {
		// A disappearing ancestor may finish before a child's exit. Cleanup
		// still waits for every structural timeline even after paint is hidden.
		for child in element.children {
			tree.sample_node(child, true)!
		}
		tree.mark_prunable(element)
		return
	}
	if state != unsafe { nil } {
		previous := state.current
		state.sample()!
		if !state.disposed {
			state.emit_events(element.id, mut tree.events)
		}
		if state.current != previous {
			tree.changed = true
		}
		if state.current.values.transform != previous.values.transform
			|| state.current.phase != previous.phase
			|| state.current.layout_offset != previous.layout_offset {
			tree.geometry_changed = true
		}
	}
	hidden := ancestor_hidden || element.presented_hidden()
	for child in element.children {
		tree.sample_node(child, hidden)!
	}
	tree.mark_prunable(element)
}

// observe_layout follows the laid-out frames of elements with layout
// transitions. Unchanged layout output shares its child arrays, so a frame
// whose layout did not change visits only the root.
fn (mut tree MotionTree) observe_layout(root Element, animate bool) {
	if tree.layout_watchers == 0 {
		if tree.observed.children.len > 0 {
			tree.observed = Element{}
		}
		return
	}
	tree.observe_node(root, tree.observed, animate)
	tree.observed = root
}

fn (mut tree MotionTree) observe_node(element Element, previous Element, animate bool) {
	mut state := element.motion_state()
	if state != unsafe { nil } && state.config.layout != .none {
		state.observe_layout(element.frame, animate)
	}
	same := element.children.len == previous.children.len
	if element.children.len == 0 || (same && element.children.data == previous.children.data) {
		return
	}
	for index, child in element.children {
		tree.observe_node(child, if same { previous.children[index] } else { Element{} },
			animate)
	}
}

fn (mut tree MotionTree) mark_prunable(element Element) {
	if element.presence_exiting() && element.compiled_node == unsafe { nil }
		&& !motion_subtree_exit_pending(element) {
		tree.prune_pending = true
	}
}

fn motion_tree_needs_frame(element Element) bool {
	return motion_subtree_needs_frame(element, false)
}

fn motion_subtree_needs_frame(element Element, ancestor_hidden bool) bool {
	hidden := ancestor_hidden || element.presented_hidden()
	state := element.motion_state()
	if state != unsafe { nil } && !state.disposed && state.current.running
		&& (!hidden || state.structural_exit) {
		return true
	}
	for child in element.children {
		if motion_subtree_needs_frame(child, hidden) {
			return true
		}
	}
	return false
}

fn (mut tree MotionTree) prune(element Element) Element {
	if !tree.prune_pending {
		return element
	}
	pruned := tree.prune_node(element)
	tree.retain_states(pruned)
	return pruned
}

fn (mut tree MotionTree) prune_node(element Element) Element {
	mut children := []Element{cap: element.children.len}
	mut changed := false
	for child in element.children {
		if child.presence_exiting() && child.compiled_node == unsafe { nil }
			&& !motion_subtree_exit_pending(child) {
			cancel_motion_subtree(child)
			changed = true
			continue
		}
		pruned := tree.prune_node(child)
		children << pruned
		if pruned != child {
			changed = true
		}
	}
	return if changed {
		Element{
			...element
			children: children
		}
	} else {
		element
	}
}

fn (mut tree MotionTree) dispose() {
	for _, mut state in tree.states {
		state.force_cancel()
	}
	tree.states.clear()
	tree.previous = Element{}
	tree.observed = Element{}
	tree.initialized = false
	tree.layout_watchers = 0
	tree.events.clear()
	tree.dispatched = false
}
