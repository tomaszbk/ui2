module ui2

// A retained node projects its children's declarations into its own. When a
// child's output changes, only its parent is marked stale; ancestors learn
// that a descendant is stale. Each stale parent is projected once when the
// runtime settles: at the outer batch boundary, before the next effect wave,
// or immediately when nothing is running. A read of a stale node projects it
// (and stale nodes below it) on demand, so values observed inside a batch or
// an effect are never behind their children.
@[heap]
struct VmlProjections {
mut:
	pending []&CompiledVmlNode
	spare   []&CompiledVmlNode
	// Nonzero while projections are being refreshed. A node marked meanwhile
	// waits for that refresh to finish instead of starting a nested settle.
	depth int
}

fn new_vml_projections(mut runtime SignalRuntime) &VmlProjections {
	mut projections := &VmlProjections{}
	runtime.settle = fn [mut projections] () ! {
		projections.settle()
	}
	return projections
}

fn (mut projections VmlProjections) settle() {
	projections.depth++
	defer { projections.depth-- }
	for projections.pending.len > 0 {
		// Swap buffers: nodes marked while this round settles start the next.
		mut round := unsafe { projections.pending }
		projections.pending = unsafe { projections.spare }
		projections.pending.clear()
		for mut node in round {
			node.settle_projection()
		}
		round.clear()
		projections.spare = unsafe { round }
	}
}

fn (mut projections VmlProjections) clear() {
	projections.pending.clear()
	projections.spare.clear()
}

// propagate reports that this node's output changed: owners of it as a
// widget source are notified, and its parent's projection becomes stale.
fn (mut node CompiledVmlNode) propagate() {
	node.notify_sources()
	if node.parent == unsafe { nil } { return }
	mut parent := node.parent
	parent.mark_projection_dirty()
}

fn (mut node CompiledVmlNode) mark_projection_dirty() {
	if node.projection_dirty { return }
	node.projection_dirty = true
	mut ancestor := node.parent
	for ancestor != unsafe { nil } && !ancestor.descendant_dirty {
		ancestor.descendant_dirty = true
		ancestor = ancestor.parent
	}
	if !node.projection_queued {
		node.projection_queued = true
		mut projections := node.component.projections
		projections.pending << node
	}
	mut runtime := node.component.runtime
	runtime.settle_pending = true
	if node.component.projections.depth == 0 {
		runtime.flush_if_ready() or { eprintln('ui2 compiled VML children failed: ${err}') }
	}
}

// ensure_projection brings this node's declaration up to date before a read.
fn (node &CompiledVmlNode) ensure_projection() {
	if !node.projection_dirty && !node.descendant_dirty { return }
	mut live := unsafe { &CompiledVmlNode(voidptr(node)) }
	mut projections := live.component.projections
	projections.depth++
	live.refresh_projection_tree()
	projections.depth--
	if projections.depth == 0 {
		// Settle whatever this refresh marked, if nothing else is running.
		mut runtime := live.component.runtime
		runtime.flush_if_ready() or { eprintln('ui2 compiled VML children failed: ${err}') }
	}
}

// Children first: a parent's projection embeds each child's own projection.
fn (mut node CompiledVmlNode) refresh_projection_tree() {
	if node.descendant_dirty {
		node.descendant_dirty = false
		for mut child in node.children {
			if child.projection_dirty || child.descendant_dirty {
				child.refresh_projection_tree()
			}
		}
	}
	if node.projection_dirty { node.refresh_projection() }
}

fn (mut node CompiledVmlNode) refresh_projection() {
	node.projection_dirty = false
	if node.component.is_disposed() { return }
	changed := node.reproject() or {
		eprintln('ui2 compiled VML children layout failed: ${err}')
		return
	}
	if !changed { return }
	node.source_snapshot = unsafe { nil }
	// Subscribers to children_revision are notified when the node settles,
	// even if a read projected it earlier (a memo read cannot write signals).
	node.revision_pending = true
	node.propagate()
}

fn (mut node CompiledVmlNode) settle_projection() {
	node.projection_queued = false
	if node.component.is_disposed() {
		node.projection_dirty = false
		node.descendant_dirty = false
		node.revision_pending = false
		return
	}
	node.refresh_projection_tree()
	if !node.revision_pending { return }
	node.revision_pending = false
	if node.has_sources { return }
	previous := node.children_revision.peek() or { return }
	node.children_revision.set(previous + 1) or {
		eprintln('ui2 compiled VML children failed: ${err}')
	}
}

// Recompute the projected children and child layout. Returns whether the
// declaration changed. An unchanged projection allocates nothing: children
// are compared in place before a new array is built.
fn (mut node CompiledVmlNode) reproject() !bool {
	prefix := node.fragment_prefix()
	old := node.declaration.children
	same := vml_projection_matches(node.children, prefix, old)
	children := if same { old } else { vml_project_children(node.children, prefix, unsafe { nil }, []) }
	visible := node.collect_visible(node.children)
	layout, layout_changed := node.child_layout_spec(visible, children)!
	if same && !layout_changed { return false }
	node.declaration = Element{
		...node.declaration
		children: children
		layout:   layout
	}
	return true
}

// The flattened (fragment-free) children reuse one buffer per node. Callers
// use the result before the next collection on the same node.
fn (mut node CompiledVmlNode) collect_visible(children []&CompiledVmlNode) []&CompiledVmlNode {
	node.visible_buffer.clear()
	vml_append_visible_children(children, unsafe { nil }, [], mut node.visible_buffer)
	return node.visible_buffer
}

fn vml_projection_matches(children []&CompiledVmlNode, prefix string, old []Element) bool {
	return vml_projection_matches_from(children, prefix, old, 0) == old.len
}

// Returns the index after the last matching projected child, or -1.
fn vml_projection_matches_from(children []&CompiledVmlNode, prefix string, old []Element, start int) int {
	mut index := start
	for child in children {
		if child.is_fragment {
			index = vml_projection_matches_from(child.children, vml_composed_key(prefix, child.relative_key),
				old, index)
			if index < 0 { return -1 }
			continue
		}
		if index >= old.len { return -1 }
		key := if child.relative_key.len == 0 { '' } else { vml_composed_key(prefix, child.relative_key) }
		if !vml_declaration_equal(Element{ ...child.element(), key: key }, old[index]) {
			return -1
		}
		index++
	}
	return index
}

// Elements are immutable values: arrays that share storage hold equal
// children, so comparison only descends into storage that was replaced.
fn vml_same_elements(left []Element, right []Element) bool {
	if left.len != right.len { return false }
	if left.len == 0 || left.data == right.data { return true }
	for index, child in left {
		if !vml_declaration_equal(child, right[index]) { return false }
	}
	return true
}

fn vml_declaration_equal(left Element, right Element) bool {
	if left.compiled_metadata != right.compiled_metadata {
		if left.compiled_metadata == unsafe { nil } || right.compiled_metadata == unsafe { nil } {
			return false
		}
		if *left.compiled_metadata != *right.compiled_metadata { return false }
	}
	if left.children.len != right.children.len { return false }
	// Presentation state counts; the provenance of a source snapshot does not.
	if left.motion_state() != right.motion_state() || left.presence_exiting() != right.presence_exiting() {
		return false
	}
	if Element{ ...left, compiled_metadata: unsafe { nil }, compiled_node: unsafe { nil }, runtime: unsafe { nil }, children: [] } !=
		Element{ ...right, compiled_metadata: unsafe { nil }, compiled_node: unsafe { nil }, runtime: unsafe { nil }, children: [] } {
		return false
	}
	return vml_same_elements(left.children, right.children)
}
