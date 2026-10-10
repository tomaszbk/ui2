module ui2

// Child rules belong to retained nodes, so keyed reorder and insertion cannot
// shift a neighbour's Flex constraints, Grid span or Stack alignment.
pub struct VmlChildLayout {
pub:
	flex  FlexChild
	grid  GridSpan
	stack StackChild
}

pub fn (node &CompiledVmlNode) child_rule() VmlChildLayout { return node.child_layout }

fn (mut node CompiledVmlNode) inherit_child_layout(layout LayoutSpec, index int) {
	match layout.kind {
		.flex {
			if index < layout.flex.children.len {
				node.child_layout = VmlChildLayout{ flex: layout.flex.children[index] }
				node.child_layout_set = true
			}
		}
		.grid {
			node.child_layout = VmlChildLayout{ grid: if index < layout.grid.child_spans.len {
				layout.grid.child_spans[index]
			} else {
				GridSpan{}
			} }
			node.child_layout_set = true
		}
		.stack {
			if index < layout.stack.children.len {
				node.child_layout = VmlChildLayout{ stack: layout.stack.children[index] }
				node.child_layout_set = true
			}
		}
		else {}
	}
}

pub fn (mut node CompiledVmlNode) set_child_layout(rule VmlChildLayout) ! {
	node.component.require_alive()!
	stripped := VmlChildLayout{
		flex:  FlexChild{ ...rule.flex, element: Element{} }
		grid:  rule.grid
		stack: StackChild{ ...rule.stack, element: Element{} }
	}
	if node.child_layout_set && node.child_layout == stripped { return }
	previous := node.child_layout
	was_set := node.child_layout_set
	node.child_layout = stripped
	node.child_layout_set = true
	if node.parent != unsafe { nil } {
		mut parent := node.parent
		for parent.is_fragment && parent.parent != unsafe { nil } { parent = parent.parent }
		parent.set_children(parent.children) or {
			node.child_layout = previous
			node.child_layout_set = was_set
			return err
		}
	}
}

fn (node &CompiledVmlNode) layout_for_children(children []&CompiledVmlNode, elements []Element) !LayoutSpec {
	mut layout := node.declaration.layout
	match layout.kind {
		.flex {
			mut rules := []FlexChild{cap: children.len}
			for i, child in children {
				rule := if resolved := child.effective_child_layout() {
					resolved.flex
				} else if i < layout.flex.children.len {
					layout.flex.children[i]
				} else {
					FlexChild{}
				}
				rules << FlexChild{ ...rule, element: elements[i] }
			}
			config := FlexConfig{ ...layout.flex, frame: node.declaration.frame, children: rules }
			flex_validate(config)!
			layout = LayoutSpec{ ...layout, flex: flex_layout_spec(config) }
		}
		.grid {
			mut spans := []GridSpan{cap: children.len}
			for i, child in children {
				spans << if resolved := child.effective_child_layout() {
					resolved.grid
				} else if i < layout.grid.child_spans.len {
					layout.grid.child_spans[i]
				} else {
					GridSpan{}
				}
			}
			config := GridConfig{ ...layout.grid, frame: node.declaration.frame, child_spans: spans }
			grid_validate_config(config, children.len)!
			layout = LayoutSpec{ ...layout, grid: config }
		}
		.stack {
			mut rules := []StackChild{cap: children.len}
			for i, child in children {
				rule := if resolved := child.effective_child_layout() {
					resolved.stack
				} else if i < layout.stack.children.len {
					layout.stack.children[i]
				} else {
					StackChild{}
				}
				rules << StackChild{ ...rule, element: elements[i] }
			}
			config := StackConfig{ ...layout.stack, frame: node.declaration.frame, children: rules }
			stack_validate(config)!
			layout = LayoutSpec{ ...layout, stack: stack_layout_spec(config) }
		}
		else {}
	}
	return layout
}

struct VmlChildSegment {
	name string
mut:
	nodes []&CompiledVmlNode
}

// Child segments flatten into the ordinary retained tree. Register groups in
// declaration order; subsequent list or slot changes only replace their group.
pub fn (mut node CompiledVmlNode) set_segment(name string, nodes []&CompiledVmlNode) ! {
	node.component.require_alive()!
	if name.len == 0 { return error('compiled VML child segment requires a name') }
	mut replacement := node.segments.clone()
	mut found := false
	for mut segment in replacement {
		if segment.name == name {
			segment.nodes = nodes.clone()
			found = true
			break
		}
	}
	if !found { replacement << VmlChildSegment{ name: name, nodes: nodes.clone() } }
	mut children := []&CompiledVmlNode{}
	for segment in replacement { children << segment.nodes }
	node.set_children(children)!
	node.segments = replacement
}
