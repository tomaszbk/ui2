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
}

// Composite constructors may decorate an authored root without changing its
// owner. Keep that projection separate from the source used by property effects
// and by the next constructor invocation (an inactive slide is not authored hidden).
fn (node &CompiledVmlNode) source_element() Element {
	return Element{ ...node.declaration, compiled_node: node, compiled_source: unsafe { nil } }
}

fn (node &CompiledVmlNode) constructor_source_element() Element {
	source := node.source_element()
	mut snapshot := node.source_snapshot
	if snapshot == unsafe { nil } || !vml_declaration_equal(snapshot.value, source) {
		snapshot = &VmlSourceSnapshot{ node: node, value: source }
		// This memoizes an immutable value. Previously returned Elements retain
		// their own baseline; unchanged declarations reuse the same allocation.
		unsafe { node.source_snapshot = snapshot }
	}
	return Element{ ...source, compiled_source: snapshot }
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
	baseline := if element.compiled_source == unsafe { nil } {
		source
	} else {
		if element.compiled_source.node != &node {
			return error('compiled VML presentation must preserve snapshot ownership')
		}
		element.compiled_source.value
	}
	if vml_declaration_equal(baseline, element) {
		node.clear_presentation()
		return
	}
	if node.presentation == unsafe { nil } { node.presentation = &VmlPresentation{} }
	mut presentation := node.presentation
	presentation.source = Element{ ...baseline, children: [], compiled_source: unsafe { nil } }
	presentation.decorated = Element{ ...element, children: [], compiled_source: unsafe { nil } }
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
		if field.name !in ['id', 'key', 'kind', 'compiled_node', 'compiled_source', 'children'] {
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
