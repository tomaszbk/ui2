module ui2

fn v_modern_child_metric(parent &VNode, child &VNode, scope map[string]VValue, actual Rect, mut cache VLayoutMeasureCache) !VLayoutChildMetrics {
	if parent.tag in ['Flex', 'Row', 'Column'] {
		// Evaluate sizing and content without registering events. The actual pass
		// below resolves actions/bindings exactly once, with the allocated frame.
		parent_props := v_measurement_node(parent, scope, actual, false)!
		config := v_flex_config(parent_props, actual, []FlexChild{})!
		available := rect(0, 0, layout_max(0, actual.width - config.padding.left - config.padding.right),
			layout_max(0, actual.height - config.padding.top - config.padding.bottom))
		measured := v_measurement_node(child, scope, available, true)!
		preferred := v_layout_preferred(measured, available, mut cache)!
		return VLayoutChildMetrics{
			frame:  preferred
			flex:   v_flex_child(measured, preferred)!
			source: &VNode{ ...child }
			scope:  scope.clone()
		}
	}
	if parent.tag == 'Stack' {
		parent_props := v_measurement_node(parent, scope, actual, false)!
		config := v_stack_config(parent_props, actual, []StackChild{})!
		available := rect(0, 0, layout_max(0, actual.width - config.padding.left - config.padding.right),
			layout_max(0, actual.height - config.padding.top - config.padding.bottom))
		measured := v_measurement_node(child, scope, available, true)!
		preferred := v_layout_preferred(measured, available, mut cache)!
		return VLayoutChildMetrics{ frame: preferred, stack: v_stack_child(measured, preferred)!, source: &VNode{ ...child }, scope: scope.clone() }
	}
	metric := VLayoutChildMetrics{ frame: rect(0, 0, v_layout_dimension(child, 'width', scope, 80)!, v_layout_dimension(child, 'height', scope, 32)!) }
	if parent.tag == 'Grid' {
		return VLayoutChildMetrics{
			...metric
			span: GridSpan{
				column_span: int(v_layout_dimension(child, 'column_span', scope, 1)!)
				row_span:    int(v_layout_dimension(child, 'row_span', scope, 1)!)
			}
		}
	}
	return metric
}

// Main-axis distribution can change the width available to wrapping content.
// Measure auto heights once at that assigned width, keeping horizontal bases
// intact. Vertical layouts then distribute their updated intrinsic heights.
fn v_flex_remeasure_metrics(config FlexConfig, metrics []VLayoutChildMetrics, frames []Rect, mut cache VLayoutMeasureCache) ![]FlexChild {
	mut children := config.children.clone()
	for index, metric in metrics {
		if metric.source == unsafe { nil } { continue }
		available := rect(0, 0, frames[index].width, config.frame.height)
		assigned := v_layout_node_width(metric.source, frames[index].width)
		measured := v_measurement_node(assigned, metric.scope, available, true)!
		if v_dimension(measured, 'height', -1) >= 0 { continue }
		preferred := v_layout_preferred(measured, available, mut cache)!
		child := children[index]
		children[index] = FlexChild{
			...child
			element: Element{
				...child.element
				frame: rect(0, 0, child.element.frame.width, preferred.height)
			}
		}
	}
	return children
}

fn v_eval_layout_child(node &VNode, scope map[string]VValue, frame Rect, kind VChildLayoutKind, mut evaluation VmlEvaluation) !&VNode {
	if kind !in [.flex, .grid, .stack] || v_is_layout_metadata(node) || node.tag == 'Option' {
		return v_eval_node(node, scope, frame, mut evaluation)!
	}
	mut assigned := &VNode{ ...node, expressions: node.expressions.clone(), layout_allocated: true }
	for key, value in {
		'x':      frame.x
		'y':      frame.y
		'width':  frame.width
		'height': frame.height
	} {
		assigned.expressions[key] = &VExpression{ kind: .literal, value: value.str(), line: node.line }
	}
	return v_eval_node(assigned, scope, frame, mut evaluation)!
}

// Resolve only the declarative properties needed for measurement. In particular
// this pass must not register bindings, assign identities, or invoke actions.
fn v_measurement_node(node &VNode, incoming_scope map[string]VValue, available Rect, descend bool) !&VNode {
	mut scope := map[string]VValue{}
	for name, value in incoming_scope {
		scope[name] = value
	}
	mut resolved := &VNode{ ...node, props: node.props.clone(), children: []&VNode{} }
	if node.id.len > 0 {
		scope[node.id] = v_object({
			'x':      v_number(0, '0')
			'y':      v_number(0, '0')
			'width':  v_number(available.width, available.width.str())
			'height': v_number(available.height, available.height.str())
		})
	}
	for key in node.property_order {
		expr := node.expressions[key] or { continue }
		value := v_eval(expr, scope)!
		resolved.props[key] = value.string_value()
		if node.id.len > 0 {
			mut object := scope[node.id] or { return error('missing measurement scope for `${node.id}`') }
			object.fields[key] = value
			scope[node.id] = object
		}
	}
	for key, expr in node.expressions {
		if key == 'id' || key in node.property_types || key.starts_with('on_') { continue }
		property := if key.starts_with('bind.') { key.all_after('bind.') } else { key }
		resolved.props[property] = v_eval(expr, scope)!.string_value()
	}
	actual := v_frame(resolved, available)
	if node.id.len > 0 {
		mut object := scope[node.id] or { return error('missing measurement scope for `${node.id}`') }
		object.fields['width'] = v_number(actual.width, actual.width.str())
		object.fields['height'] = v_number(actual.height, actual.height.str())
		scope[node.id] = object
	}
	if !descend { return resolved }
	for child in node.children {
		if child.tag != 'Repeater' {
			resolved.children << v_measurement_node(child, scope, actual, true)!
			continue
		}
		expr := child.expressions['model'] or { return error('Repeater requires `model` at line ${child.line}') }
		items := v_eval(expr, scope)!
		if items.kind != .list {
			return error('Repeater model must be a collection at line ${expr.line}')
		}
		for index, item in items.items {
			mut item_scope := scope.clone()
			item_scope['item'] = item
			item_scope['index'] = v_number(index, index.str())
			for repeated in child.children {
				resolved.children << v_measurement_node(repeated, item_scope, actual, true)!
			}
		}
	}
	return resolved
}
