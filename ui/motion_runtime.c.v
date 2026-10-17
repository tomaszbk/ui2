module ui2

// These reads use the host's sampled frame, never an independent clock.
fn (element Element) presented_hidden() bool {
	if element.motion_state != unsafe { nil } && element.motion_state.mounted {
		return element.motion_state.disposed || element.motion_state.current.phase == .absent
	}
	return element.hidden
}

fn (element Element) presented_enabled() bool {
	return element.enabled && !element.presence_exiting
		&& (element.motion_state == unsafe { nil } || element.motion_state.input_enabled())
}

fn (element Element) presented_opacity() f64 {
	return if element.motion_state != unsafe { nil } && element.motion_state.mounted {
		element.motion_state.current.style.opacity
	} else {
		element.opacity
	}
}

fn (element Element) presence_leaving() bool {
	return element.presence_exiting || (element.motion_state != unsafe { nil }
		&& element.motion_state.current.phase == .exiting)
}

fn (element Element) layout_excluded() bool {
	return element.hidden || element.presence_exiting || element.overlay != none
}

@[heap]
struct MotionTree {
mut:
	states        map[string]&ElementMotionState
	previous      Element
	initialized   bool
	changed       bool
	geometry_changed bool
	prune_pending bool
	seen          map[string]bool
}

// The caller owns the retained tree. Only changed declarations allocate;
// sampled motion updates cached presentation on the retained state itself.
fn (mut tree MotionTree) prepare(element Element) !Element {
	if tree.states.len == 0 && !motion_subtree_managed(element)
		&& (!tree.initialized || !motion_subtree_managed(tree.previous)) {
		tree.previous = element
		tree.initialized = true
		return element
	}
	tree.seen.clear()
	result := tree.prepare_node(element, if tree.initialized {
		tree.previous
	} else {
		Element{}
	}, 'root')!
	tree.retain_states(result)
	tree.previous = result
	tree.initialized = true
	return result
}

fn (mut tree MotionTree) mark_states(element Element, path string) {
	if !motion_subtree_managed(element) { return }
	if element.motion_state != unsafe { nil } {
		tree.seen[motion_identity(element, path)] = true
	}
	for index, child in element.children {
		tree.mark_states(child, reconciliation_child_key(path, index, child))
	}
}

fn (mut tree MotionTree) retain_states(root Element) {
	tree.seen.clear()
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
	if element.motion != none || element.motion_state != unsafe { nil } { return true }
	for child in element.children {
		if motion_subtree_managed(child) { return true }
	}
	return false
}

fn (mut tree MotionTree) prepare_node(element Element, previous Element, path string) !Element {
	if !motion_subtree_managed(element) && !motion_subtree_managed(previous) { return element }
	mut result := element
	identity := motion_identity(element, path)
	mut state := element.motion_state
	if state == unsafe { nil } {
		if _ := element.motion {
			if existing := tree.states[identity] {
				if !existing.disposed { state = existing }
			}
			if state == unsafe { nil } { state = new_element_motion_state(element)! }
		}
	}
	if element.motion == none && state != unsafe { nil } && !element.presence_exiting {
		state.force_cancel()
		state = unsafe { nil }
		result = Element{ ...result, motion_state: unsafe { nil } }
	}
	if state != unsafe { nil } {
		if !element.presence_exiting && state.structural_exit { state.resume_enter()! }
		state.update(element)!
		state.mount()!
		tree.states[identity] = state
		result = Element{ ...result, motion_state: state }
	}
	// Resolve sibling identities once. Nested scans used to allocate identity
	// strings quadratically even when one small counter was the only patch.
	mut old_indices := map[string]int{}
	mut old_identities := []string{cap: previous.children.len}
	for old_index, old_child in previous.children {
		old_identity := motion_identity(old_child, reconciliation_child_key(path, old_index, old_child))
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
		old := if old_index := old_indices[child_identity] { previous.children[old_index] } else { Element{} }
		prepared := tree.prepare_node(child, old, child_path)!
		// Retained descendant snapshots are immutable; share their owned arrays.
		children << unsafe { prepared }
		if prepared != child { changed = true }
	}
	// Compiled repeaters own their exit scopes. Ordinary keyed Element trees
	// also retain a removed root until its own configured exit finishes.
	for old_index, old in previous.children {
		if present[old_identities[old_index]] or { false } || old.compiled_node != unsafe { nil } {
			continue
		}
		if begin_motion_subtree_exit(old)! {
			children << Element{ ...old, presence_exiting: true }
			changed = true
		}
	}
	if changed { result = Element{ ...result, children: children } }
	return result
}

fn begin_motion_subtree_exit(element Element) !bool {
	mut pending := false
	if element.motion_state != unsafe { nil } && !element.motion_state.disposed {
		mut state := element.motion_state
		if !state.structural_exit { state.begin_exit(unsafe { nil })! }
		pending = state.current.phase != .absent
	}
	for child in element.children {
		if begin_motion_subtree_exit(child)! { pending = true }
	}
	return pending
}

fn motion_subtree_exit_pending(element Element) bool {
	if element.motion_state != unsafe { nil } && !element.motion_state.disposed
		&& element.motion_state.structural_exit && element.motion_state.current.phase != .absent {
		return true
	}
	for child in element.children {
		if motion_subtree_exit_pending(child) { return true }
	}
	return false
}

fn cancel_motion_subtree(element Element) {
	if element.motion_state != unsafe { nil } { element.motion_state.force_cancel() }
	for child in element.children { cancel_motion_subtree(child) }
}

fn (mut tree MotionTree) sample(root Element) !bool {
	tree.changed = false
	tree.geometry_changed = false
	tree.sample_node(root, false)!
	return tree.changed
}

fn (mut tree MotionTree) sample_node(element Element, ancestor_hidden bool) ! {
	// Hidden ancestors cannot keep an invisible child tween waking the host.
	if ancestor_hidden && !(element.motion_state != unsafe { nil } && element.motion_state.structural_exit) {
		// A disappearing ancestor may finish before a child's exit. Cleanup
		// still waits for every structural timeline even after paint is hidden.
		for child in element.children { tree.sample_node(child, true)! }
		tree.mark_prunable(element)
		return
	}
	if element.motion_state != unsafe { nil } {
		mut state := element.motion_state
		previous := state.current
		state.sample()!
		if state.current != previous { tree.changed = true }
		if state.current.style.transform != previous.style.transform
			|| state.current.phase != previous.phase {
			tree.geometry_changed = true
		}
	}
	hidden := ancestor_hidden || element.presented_hidden()
	for child in element.children { tree.sample_node(child, hidden)! }
	tree.mark_prunable(element)
}

fn (mut tree MotionTree) mark_prunable(element Element) {
	if element.presence_exiting && element.compiled_node == unsafe { nil }
		&& !motion_subtree_exit_pending(element) {
		tree.prune_pending = true
	}
}

fn motion_tree_needs_frame(element Element) bool {
	return motion_subtree_needs_frame(element, false)
}

fn motion_subtree_needs_frame(element Element, ancestor_hidden bool) bool {
	hidden := ancestor_hidden || element.presented_hidden()
	if element.motion_state != unsafe { nil } && !element.motion_state.disposed
		&& element.motion_state.current.running && (!hidden || element.motion_state.structural_exit) {
		return true
	}
	for child in element.children {
		if motion_subtree_needs_frame(child, hidden) { return true }
	}
	return false
}

fn (mut tree MotionTree) prune(element Element) Element {
	if !tree.prune_pending { return element }
	pruned := tree.prune_node(element)
	tree.retain_states(pruned)
	return pruned
}

fn (mut tree MotionTree) prune_node(element Element) Element {
	mut children := []Element{cap: element.children.len}
	mut changed := false
	for child in element.children {
		if child.presence_exiting && child.compiled_node == unsafe { nil }
			&& !motion_subtree_exit_pending(child) {
			cancel_motion_subtree(child)
			changed = true
			continue
		}
		pruned := tree.prune_node(child)
		children << pruned
		if pruned != child { changed = true }
	}
	return if changed { Element{ ...element, children: children } } else { element }
}

fn (mut tree MotionTree) dispose() {
	for _, mut state in tree.states { state.force_cancel() }
	tree.states.clear()
	tree.previous = Element{}
	tree.initialized = false
}
