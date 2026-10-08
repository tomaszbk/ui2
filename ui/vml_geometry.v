module ui2

// Authored geometry is validated before Flex/Grid/Stack allocate child frames.
// Repeater templates inherit their actual container's layout context.
fn v_validate_geometry(node &VNode, parent string) ! {
	if !node.layout_allocated && parent != 'Absolute' {
		if 'x' in node.props || 'y' in node.props {
			return error('x/y require a parent Absolute container at line ${node.line}')
		}
		for property in ['width', 'height', 'min_width', 'max_width', 'min_height', 'max_height',
			'flex_basis', 'gap', 'line_gap', 'padding', 'padding_left', 'padding_top', 'padding_right',
			'padding_bottom', 'spacing_x', 'spacing_y', 'col_default_width', 'row_default_height',
			'auto_columns_min_width'] {
			// A declared data property can share a layout parameter's name on a
			// node that does not arrange children with that parameter.
			if property in node.property_types && property !in ['width', 'height', 'min_width',
				'max_width', 'min_height', 'max_height', 'flex_basis']
				&& node.tag !in ['Flex', 'Row', 'Column', 'Grid', 'Stack'] {
				continue
			}
			expr := if parsed := node.expressions[property] {
				parsed
			} else if raw := node.props[property] {
				mut parser := Parser{ tokens: tokenize(raw)! }
				parser.parse_expression() or { continue }
			} else {
				continue
			}
			if v_reads_geometry(expr) {
				return error('geometry expressions require a parent Absolute container at line ${node.line}')
			}
		}
	}
	context := if node.tag == 'Repeater' { parent } else { node.tag }
	for child in node.children { v_validate_geometry(child, context)! }
}

fn v_reads_geometry(expr &VExpression) bool {
	if expr == unsafe { nil } { return false }
	if expr.kind == .path && !expr.value.starts_with('app.') && !expr.value.starts_with('item.') {
		parts := expr.value.split('.')
		if parts.len > 1 && parts.last() in ['x', 'y', 'width', 'height'] { return true }
	}
	if v_reads_geometry(expr.left) || v_reads_geometry(expr.right) || v_reads_geometry(expr.third) {
		return true
	}
	for argument in expr.args { if v_reads_geometry(argument) { return true } }
	for part in expr.parts { if v_reads_geometry(part.expr) { return true } }
	return false
}
