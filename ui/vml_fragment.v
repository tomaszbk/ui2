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
	mut visible := []&CompiledVmlNode{cap: vml_visible_child_count(children, replacement, replacements)}
	vml_append_visible_children(children, replacement, replacements, mut visible)
	return visible
}

fn vml_visible_child_count(children []&CompiledVmlNode, replacement &CompiledVmlNode, replacements []&CompiledVmlNode) int {
	mut count := 0
	for child in children {
		count += if child.is_fragment {
			vml_visible_child_count(if voidptr(child) == voidptr(replacement) {
				replacements
			} else {
				child.children
			}, replacement, replacements)
		} else {
			1
		}
	}
	return count
}

fn vml_append_visible_children(children []&CompiledVmlNode, replacement &CompiledVmlNode, replacements []&CompiledVmlNode, mut visible []&CompiledVmlNode) {
	for child in children {
		if child.is_fragment {
			vml_append_visible_children(if voidptr(child) == voidptr(replacement) {
				replacements
			} else {
				child.children
			}, replacement, replacements, mut visible)
		} else {
			visible << child
		}
	}
}

fn vml_project_children(children []&CompiledVmlNode, prefix string, replacement &CompiledVmlNode, replacements []&CompiledVmlNode) []Element {
	mut visible := []Element{cap: vml_visible_child_count(children, replacement, replacements)}
	vml_append_projected_children(children, prefix, replacement, replacements, mut visible)
	return visible
}

fn vml_append_projected_children(children []&CompiledVmlNode, prefix string, replacement &CompiledVmlNode, replacements []&CompiledVmlNode, mut visible []Element) {
	for child in children {
		if child.is_fragment {
			vml_append_projected_children(if voidptr(child) == voidptr(replacement) {
				replacements
			} else {
				child.children
			},
				vml_composed_key(prefix, child.relative_key), replacement, replacements, mut visible)
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
}

fn (mut node CompiledVmlNode) refresh_fragment_keys() {
	prefix := node.fragment_prefix()
	key := if node.is_fragment || node.relative_key.len == 0 {
		node.relative_key
	} else {
		vml_composed_key(prefix, node.relative_key)
	}
	if node.fragment_keys_ready && node.fragment_keys_prefix == prefix && node.declaration.key == key {
		return
	}
	node.fragment_keys_ready = true
	node.fragment_keys_prefix = prefix
	node.declaration = Element{ ...node.declaration, key: key }
	node.source_snapshot = unsafe { nil }
	for mut child in node.children { child.refresh_fragment_keys() }
	node.declaration = Element{
		...node.declaration
		children: vml_project_children(node.children, prefix, unsafe { nil }, [])
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
	layout, _ := parent.child_layout_spec(visible, elements)!
	validate_element_tree(Element{
		...parent.element()
		children: elements
		layout:   layout
	})!
}

fn (mut node CompiledVmlNode) publish_structure() {
	mut visible := &node
	for visible.is_fragment && visible.parent != unsafe { nil } { visible = visible.parent }
	if visible.is_fragment || !visible.live() { return }
	visible.component.publish_element(visible.declaration.id, visible.element())
}

fn (node &CompiledVmlNode) effective_child_rule() ?VmlChildRule {
	if node.child_layout_set { return node.child_layout }
	mut parent := node.parent
	for parent != unsafe { nil } && parent.is_fragment {
		if parent.child_layout_set { return parent.child_layout }
		parent = parent.parent
	}
	return none
}
