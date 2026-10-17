module ui2

// Child rules belong to retained nodes, so keyed reorder and insertion cannot
// shift a neighbour's Flex constraints, Grid span or Stack alignment.
pub struct VmlChildLayout {
pub:
	flex  FlexChild
	grid  GridSpan
	stack StackChild
}

// Retained rules omit FlexChild/StackChild element payloads: a node keeps the
// constraints its parent applies to it, never a second copy of a declaration.
struct VmlChildRule {
	flex  FlexRule
	grid  GridSpan
	stack StackRule
}

fn vml_child_rule(layout VmlChildLayout) VmlChildRule {
	return VmlChildRule{ flex: flex_rule(layout.flex), grid: layout.grid, stack: stack_rule(layout.stack) }
}

pub fn (node &CompiledVmlNode) child_rule() VmlChildLayout {
	return VmlChildLayout{
		flex:  node.child_layout.flex.flex_child()
		grid:  node.child_layout.grid
		stack: node.child_layout.stack.stack_child()
	}
}

fn (mut node CompiledVmlNode) inherit_child_layout(layout LayoutSpec, index int) {
	match layout.kind {
		.flex {
			if index < layout.flex_rules.len {
				node.child_layout = VmlChildRule{ flex: layout.flex_rules[index] }
				node.child_layout_set = true
			}
		}
		.grid {
			node.child_layout = VmlChildRule{ grid: if index < layout.grid.child_spans.len {
				layout.grid.child_spans[index]
			} else {
				GridSpan{}
			} }
			node.child_layout_set = true
		}
		.stack {
			if index < layout.stack_rules.len {
				node.child_layout = VmlChildRule{ stack: layout.stack_rules[index] }
				node.child_layout_set = true
			}
		}
		else {}
	}
}

pub fn (mut node CompiledVmlNode) set_child_layout(rule VmlChildLayout) ! {
	node.component.require_alive()!
	stripped := vml_child_rule(rule)
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

fn (node &CompiledVmlNode) child_flex_rule(child &CompiledVmlNode, index int) FlexRule {
	if resolved := child.effective_child_rule() { return resolved.flex }
	return flex_rule_at(node.declaration.layout.flex_rules, index)
}

fn (node &CompiledVmlNode) child_stack_rule(child &CompiledVmlNode, index int) StackRule {
	if resolved := child.effective_child_rule() { return resolved.stack }
	return stack_rule_at(node.declaration.layout.stack_rules, index)
}

fn (node &CompiledVmlNode) child_grid_span(child &CompiledVmlNode, index int) GridSpan {
	if resolved := child.effective_child_rule() { return resolved.grid }
	if index < node.declaration.layout.grid.child_spans.len {
		return node.declaration.layout.grid.child_spans[index]
	}
	return GridSpan{}
}

// child_layout_spec resolves the container's child rules against the visible
// children and their projected elements, validates them, and reports whether
// the spec differs from the current declaration. An unchanged spec is
// returned as is, without copies.
fn (node &CompiledVmlNode) child_layout_spec(children []&CompiledVmlNode, elements []Element) !(LayoutSpec, bool) {
	layout := node.declaration.layout
	match layout.kind {
		.flex {
			config := FlexConfig{ ...layout.flex, frame: node.declaration.frame }
			flex_validate_container(config)!
			mut totals := flex_validation_totals(config)
			mut changed := children.len != layout.flex_rules.len || layout.flex.id.len > 0
				|| layout.flex.frame != Rect{} || layout.flex.box != BoxStyle{} || layout.flex.children.len > 0
			for i, child in children {
				rule := node.child_flex_rule(child, i)
				flex_validate_child(rule, elements[i].frame, config.gap, mut totals)!
				if !changed && rule != layout.flex_rules[i] { changed = true }
			}
			flex_validate_totals(totals)!
			if !changed { return layout, false }
			mut rules := []FlexRule{cap: children.len}
			for i, child in children { rules << node.child_flex_rule(child, i) }
			return LayoutSpec{ ...layout, flex: flex_layout_spec(layout.flex), flex_rules: rules }, true
		}
		.grid {
			mut changed := children.len != layout.grid.child_spans.len
				|| layout.grid.frame != node.declaration.frame
			if !changed {
				for i, child in children {
					if node.child_grid_span(child, i) != layout.grid.child_spans[i] {
						changed = true
						break
					}
				}
			}
			if !changed {
				grid_validate_config(layout.grid, children.len)!
				return layout, false
			}
			mut spans := []GridSpan{cap: children.len}
			for i, child in children { spans << node.child_grid_span(child, i) }
			config := GridConfig{ ...layout.grid, frame: node.declaration.frame, child_spans: spans }
			grid_validate_config(config, children.len)!
			return LayoutSpec{ ...layout, grid: config }, true
		}
		.stack {
			config := StackConfig{ ...layout.stack, frame: node.declaration.frame }
			stack_validate_container(config)!
			mut changed := children.len != layout.stack_rules.len || layout.stack.id.len > 0
				|| layout.stack.frame != Rect{} || layout.stack.box != BoxStyle{} || layout.stack.children.len > 0
			for i, child in children {
				validate_layout_frame(elements[i].frame)!
				if !changed && node.child_stack_rule(child, i) != layout.stack_rules[i] {
					changed = true
				}
			}
			if !changed { return layout, false }
			mut rules := []StackRule{cap: children.len}
			for i, child in children { rules << node.child_stack_rule(child, i) }
			return LayoutSpec{ ...layout, stack: stack_layout_spec(layout.stack), stack_rules: rules }, true
		}
		else {}
	}
	return layout, false
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
	for segment in node.segments {
		if node.segments_current && segment.name == name && segment.nodes == nodes {
			for child in nodes { child.component.require_alive()! }
			return
		}
	}
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
	node.segments_current = true
}
