module ui2

// A fragment is an ownership and reconciliation target, never a presentation
// element. It shares the ordinary node/segment/list engine; snapshots omit it.
pub fn (mut component CompiledVmlComponent) fragment(identity string) !&CompiledVmlNode {
	return component.owned_element(Element{ kind: .view }, VmlNodeConfig{ identity: identity }, true)
}

fn vml_composed_key(prefix string, key string) string {
	if prefix.len == 0 { return key }
	if key.len == 0 { return prefix }
	return '${prefix.len}:${prefix}/${key.len}:${key}'
}

fn (node &CompiledVmlNode) fragment_prefix() string {
	mut prefix := ''
	if node.parent != unsafe { nil } && node.parent.is_fragment {
		prefix = node.parent.fragment_prefix()
	}
	return if node.is_fragment { vml_composed_key(prefix, node.relative_key) } else { prefix }
}

fn vml_visible_children(children []&CompiledVmlNode, replacement &CompiledVmlNode, replacements []&CompiledVmlNode) []&CompiledVmlNode {
	mut visible := []&CompiledVmlNode{}
	for child in children {
		if child.is_fragment {
			visible << vml_visible_children(if child == replacement {
				replacements
			} else {
				child.children
			}, replacement, replacements)
		} else {
			visible << child
		}
	}
	return visible
}

fn vml_project_children(children []&CompiledVmlNode, prefix string, replacement &CompiledVmlNode, replacements []&CompiledVmlNode) []Element {
	mut visible := []Element{}
	for child in children {
		if child.is_fragment {
			visible << vml_project_children(if child == replacement {
				replacements
			} else {
				child.children
			},
				vml_composed_key(prefix, child.relative_key), replacement, replacements)
		} else {
			// Unkeyed controls continue to use their private retained identity.
			key := if child.relative_key.len == 0 {
				''
			} else {
				vml_composed_key(prefix, child.relative_key)
			}
			visible << Element{ ...child.element(), key: key }
		}
	}
	return visible
}

fn (mut node CompiledVmlNode) refresh_fragment_keys() {
	key := if node.is_fragment || node.relative_key.len == 0 {
		node.relative_key
	} else {
		vml_composed_key(node.fragment_prefix(), node.relative_key)
	}
	node.declaration = Element{ ...node.declaration, key: key }
	node.source_snapshot = unsafe { nil }
	for mut child in node.children { child.refresh_fragment_keys() }
	node.declaration = Element{
		...node.declaration
		children: vml_project_children(node.children, node.fragment_prefix(), unsafe { nil }, [])
	}
}

fn (mut node CompiledVmlNode) set_reconciliation_key(key string) {
	node.relative_key = key
	node.refresh_fragment_keys()
}

fn (node &CompiledVmlNode) validate_fragment_children(children []&CompiledVmlNode) ! {
	mut parent := node.parent
	for parent != unsafe { nil } && parent.is_fragment { parent = parent.parent }
	if parent == unsafe { nil } { return }
	visible := vml_visible_children(parent.children, node, children)
	elements := vml_project_children(parent.children, parent.fragment_prefix(), node, children)
	validate_element_tree(Element{
		...parent.element()
		children: elements
		layout:   parent.layout_for_children(visible, elements)!
	})!
}

fn (mut node CompiledVmlNode) publish_structure() {
	mut visible := &node
	for visible.is_fragment && visible.parent != unsafe { nil } { visible = visible.parent }
	if visible.is_fragment || !visible.mounted { return }
	visible.component.publish(visible.declaration.id, visible.element())
}

fn (mut node CompiledVmlNode) mount_visible_owners() ! {
	mut owner := node.component
	mut owners := []&CompiledVmlComponent{}
	// Empty attached fragments remain available for later insertion, but do not
	// mount a scope until one of its actual controls has been attached.
	for owner != unsafe { nil } {
		owners << owner
		owner = owner.parent
	}
	for i := owners.len - 1; i >= 0; i-- {
		mut candidate := owners[i]
		if candidate.has_mounted_nodes() { candidate.mount()! }
	}
	for mut child in node.children {
		if child.component.has_mounted_nodes() { child.component.mount()! }
	}
}

fn (node &CompiledVmlNode) effective_child_layout() ?VmlChildLayout {
	if node.child_layout_set { return node.child_layout }
	mut parent := node.parent
	for parent != unsafe { nil } && parent.is_fragment {
		if parent.child_layout_set { return parent.child_layout }
		parent = parent.parent
	}
	return none
}
