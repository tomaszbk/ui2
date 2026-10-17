module ui2

@[heap]
struct VmlPresentation {
mut:
	active    bool
	source    Element
	decorated Element
}

@[heap]
struct VmlSourceSnapshot {
	node  &CompiledVmlNode
	value Element
mut:
	// The runtime record handed out with the snapshot: the node's own state
	// plus a link back to this snapshot.
	runtime &ElementRuntime = unsafe { nil }
}

// Composite constructors may decorate an authored root without changing its
// owner. Keep that projection separate from the source used by property effects
// and by the next constructor invocation (an inactive slide is not authored hidden).
fn (node &CompiledVmlNode) source_element() Element {
	node.ensure_projection()
	return Element{ ...node.declaration, compiled_node: node }
}

fn (node &CompiledVmlNode) constructor_source_element() Element {
	node.ensure_projection()
	mut snapshot := node.source_snapshot
	if snapshot == unsafe { nil } {
		value := node.source_element()
		snapshot = &VmlSourceSnapshot{ node: node, value: value }
		snapshot.runtime = if value.runtime == unsafe { nil } {
			&ElementRuntime{ source: snapshot }
		} else {
			&ElementRuntime{ ...*value.runtime, source: snapshot }
		}
		// This memoizes an immutable value. Previously returned Elements retain
		// their own baseline; declaration writes invalidate the memo explicitly.
		// A read never walks or clones the unchanged descendant tree.
		unsafe { node.source_snapshot = snapshot }
	}
	return Element{ ...snapshot.value, runtime: snapshot.runtime }
}

fn (mut node CompiledVmlNode) set_presentation(element Element, parent &CompiledVmlNode) ! {
	if node.is_fragment { return }
	if node.parent != unsafe { nil } && node.parent != parent {
		return error('compiled VML element already belongs to another parent')
	}
	source := node.source_element()
	if element.id != source.id || element.kind != source.kind || element.key != source.key {
		return error('compiled VML presentation must preserve child identity and kind')
	}
	if !vml_same_child_ownership(element.children, source.children) {
		return error('compiled VML presentation cannot replace owned children')
	}
	snapshot := element.compiled_source()
	baseline := if snapshot == unsafe { nil } {
		source
	} else {
		if snapshot.node != &node {
			return error('compiled VML presentation must preserve snapshot ownership')
		}
		snapshot.value
	}
	if vml_declaration_equal(baseline, element) {
		node.clear_presentation()
		return
	}
	if node.presentation == unsafe { nil } { node.presentation = &VmlPresentation{} }
	mut presentation := node.presentation
	// Runtime records follow the live source, never a projection.
	presentation.source = Element{ ...baseline, children: [], runtime: unsafe { nil } }
	presentation.decorated = Element{ ...element, children: [], runtime: unsafe { nil } }
	presentation.active = true
}

// Preferred/allocated passes and effects update the values in a child's
// snapshot. Ownership follows its retained handle and order, rather than those
// presentation values; descendants remain owned by each retained child.
fn vml_same_child_ownership(left []Element, right []Element) bool {
	if left.len != right.len { return false }
	for index, child in left {
		if child.compiled_node == unsafe { nil } || child.compiled_node != right[index].compiled_node {
			return false
		}
	}
	return true
}

fn (mut node CompiledVmlNode) clear_presentation() {
	if node.presentation == unsafe { nil } { return }
	mut presentation := node.presentation
	presentation.active = false
	presentation.source = Element{}
	presentation.decorated = Element{}
}

fn vml_present(source Element, presentation &VmlPresentation) Element {
	if presentation == unsafe { nil } || !presentation.active { return source }
	mut element := source
	// This is a typed, compile-time field merge. Identity and owned children are
	// reconciled by the node graph; every other constructor-produced field follows
	// the projection while untouched fields continue to follow their live source.
	$for field in Element.fields {
		if field.name !in ['id', 'key', 'kind', 'compiled_node', 'mount', 'runtime', 'children'] {
			if presentation.decorated.$(field.name) != presentation.source.$(field.name) {
				// `element` is a fresh value; this never mutates either source snapshot.
				$if field.typ is $enum {
					unsafe { element.$(field.name) = int(presentation.decorated.$(field.name)) }
				} $else {
					unsafe { element.$(field.name) = presentation.decorated.$(field.name) }
				}
			}
		}
	}
	return element
}
