module vml

// parse_type parses a V type and returns its text: a name (`int`,
// `ui2.StylePatch`), `[]T`, `?T`, `map[K]V` or `fn (A, B) R` (parameter
// names are allowed and dropped: `fn (r Route) bool` is `fn (Route) bool`).
fn (mut p Parser) parse_type() !string {
	token := p.at()
	if token.kind == .lsbr {
		p.pos++
		p.take(.rsbr)!
		return '[]' + p.parse_type()!
	}
	if token.kind == .question {
		p.pos++
		return '?' + p.parse_type()!
	}
	name := p.take(.name)!
	if name.text == 'map' && p.at().kind == .lsbr {
		p.pos++
		key := p.parse_type()!
		p.take(.rsbr)!
		return 'map[${key}]' + p.parse_type()!
	}
	if name.text == 'fn' && p.at().kind == .lpar {
		p.pos++
		mut params := []string{}
		for p.at().kind != .rpar {
			mut typ := p.parse_type()!
			// `name Type`: the first word was the parameter's name.
			if p.at().kind !in [.comma, .rpar] {
				typ = p.parse_type()!
			}
			params << typ
			if p.at().kind != .comma { break }
			p.pos++
		}
		p.take(.rpar)!
		mut out := 'fn (${params.join(', ')})'
		if p.at().kind in [.name, .lsbr, .question] && p.at().line == name.line && p.at().text != 'bind' {
			out += ' ' + p.parse_type()!
		}
		return out
	}
	return name.text
}

fn (mut p Parser) parse_parameters() ![]Parameter {
	p.take(.lpar)!
	mut parameters := []Parameter{}
	for p.at().kind != .rpar {
		name := p.take(.name)!
		if parameters.any(it.name == name.text) {
			return error('duplicate callback parameter `${name.text}`')
		}
		parameters << Parameter{ name: name.text, typ: p.parse_type()! }
		if p.at().kind != .comma { break }
		p.pos++
	}
	p.take(.rpar)!
	return parameters
}

fn (mut p Parser) parse_component() !&Node {
	if p.at().text != 'component' { return p.parse_node() }
	token := p.take(.name)!
	name := p.take(.name)!
	mut component := &Node{ tag: component_tag, component_name: name.text, line: token.line, column: token.column }
	p.take(.lpar)!
	for p.at().kind != .rpar {
		mut bindable := false
		if p.at().text == 'bind' {
			p.pos++
			bindable = true
		}
		input_name := p.take(.name)!
		typ := p.parse_type()!
		mut parameters := []Parameter{}
		if typ == 'event' { parameters = p.parse_parameters()! }
		mut value := unsafe { nil }
		if p.at().kind == .assign {
			p.pos++
			value = p.parse_expression()!
		}
		if typ == 'slot' && (bindable || !isnil(value)) {
			return error('slots cannot be bindable or have default values')
		}
		if typ.starts_with('?') && bindable {
			return error('an optional input cannot be bindable: `${input_name.text} ${typ}`')
		}
		if typ == 'event' && (bindable || !isnil(value)) {
			return error('events cannot be bindable or have default values')
		}
		component.inputs << Input{ name: input_name.text, typ: typ, line: input_name.line, column: input_name.column, bindable: bindable, parameters: parameters, default_value: value }
		if p.at().kind != .comma { break }
		p.pos++
	}
	p.take(.rpar)!
	p.take(.lbrace)!
	for p.at().kind !in [.rbrace, .eof] {
		if p.at().text == 'style' {
			component.styles << p.parse_style()!
		} else if p.at().text in ['state', 'computed'] {
			kind := p.take(.name)!
			data_name := p.take(.name)!
			p.take(.declare)!
			component.data << Data{ name: data_name.text, computed: kind.text == 'computed', expr: p.parse_expression()! }
		} else if p.at().text == 'ref' {
			return error('${p.file}:${p.at().line}:${p.at().column}: `ref` declarations were replaced by element ids: `TextInput(id: name_field)` makes `name_field.focus()` available')
		} else if p.at().text == 'watch' {
			component.watches << p.parse_watch()!
		} else if p.at().text == 'fn' {
			p.pos++
			fn_name := p.take(.name)!
			parameters := p.parse_parameters()!
			body := p.parse_handler()!
			if body.kind != .block { return error('local functions require a body') }
			component.functions << Function{ name: fn_name.text, parameters: parameters, body: body.args }
		} else if p.at().text in ['mount', 'unmount', 'cleanup'] {
			kind := p.take(.name)!
			body := p.parse_handler()!
			if body.kind != .block { return error('lifecycle declarations require a body') }
			match kind.text {
				'mount' { component.mount << body.args }
				'unmount' { component.unmount << body.args }
				else { component.cleanup << body.args }
			}
		} else {
			component.children << p.parse_child()!
		}
		if p.at().kind == .semicolon { p.pos++ }
	}
	p.take(.rbrace)!
	if component.children.len != 1 || is_structural(component.children[0].tag) {
		return error('component `${name.text}` requires exactly one root element')
	}
	validate_component_names(component)!
	return component
}

// parse_watch parses `watch [old,] now := value { body }` or `watch value { body }`.
fn (mut p Parser) parse_watch() !Watch {
	token := p.take(.name)!
	mut old := ''
	mut now := ''
	if p.at().kind == .name && p.pos + 1 < p.tokens.len
		&& p.tokens[p.pos + 1].kind in [.comma, .declare] {
		first := p.take(.name)!
		if p.at().kind == .comma {
			p.pos++
			old = first.text
			now = p.take(.name)!.text
		} else {
			now = first.text
		}
		p.take(.declare)!
	}
	expr := p.parse_expression()!
	body := p.parse_handler()!
	if body.kind != .block { return error('${p.file}:${token.line}:${token.column}: `watch` requires a body') }
	return Watch{ expr: expr, old: old, now: now, line: token.line, column: token.column, body: body.args }
}

fn validate_component_names(node &Node) ! {
	mut names := map[string]bool{}
	for name in ['app', 'color', 'spacing', 'radius', 'typography'] { names[name] = true }
	for input in node.inputs {
		if input.name in names {
			return error('duplicate/reserved component member `${input.name}`')
		}
		names[input.name] = true
	}
	for style in node.styles {
		if style.name in names {
			return error('duplicate/reserved component member `${style.name}`')
		}
		names[style.name] = true
	}
	for data in node.data {
		if data.name in names { return error('duplicate/reserved component member `${data.name}`') }
		names[data.name] = true
	}
	for function in node.functions {
		if function.name in names {
			return error('duplicate/reserved component member `${function.name}`')
		}
		names[function.name] = true
	}
	for data in node.data {
		if data.computed {
			for input in node.inputs {
				if input.typ == 'event' && expr_uses_path(data.expr, input.name) {
					return error('computed `${data.name}` cannot emit events')
				}
			}
			for function in node.functions {
				if expr_uses_path(data.expr, function.name) {
					return error('computed `${data.name}` cannot call a handler')
				}
			}
		}
	}
	validate_component_ids(node.children[0], mut names)!
	validate_component_calls(node, node)!
	for function in node.functions {
		mut parameters := map[string]bool{}
		for parameter in function.parameters {
			if parameter.name in names || parameter.name in parameters {
				return error('local function parameter `${parameter.name}` collides with a component member or id')
			}
			parameters[parameter.name] = true
		}
	}
}

fn validate_component_calls(node &Node, owner &Node) ! {
	for data in node.data { validate_local_call_arity(data.expr, owner)! }
	for function in node.functions {
		for statement in function.body { validate_local_call_arity(statement, owner)! }
	}
	for watch in node.watches {
		validate_local_call_arity(watch.expr, owner)!
		for statement in watch.body { validate_local_call_arity(statement, owner)! }
	}
	for expr in [node.cond, node.key_expr] {
		if !isnil(expr) { validate_local_call_arity(expr, owner)! }
	}
	for statement in node.mount { validate_local_call_arity(statement, owner)! }
	for statement in node.unmount { validate_local_call_arity(statement, owner)! }
	for statement in node.cleanup { validate_local_call_arity(statement, owner)! }
	for property in node.properties { validate_local_call_arity(property.expr, owner)! }
	for child in node.children {
		if child.tag != component_tag { validate_component_calls(child, owner)! }
	}
}

fn validate_local_call_arity(expr &Expr, owner &Node) ! {
	if expr.kind == .call {
		for function in owner.functions {
			if expr.value == function.name && expr.args.len != function.parameters.len {
				return error('${expr.source}:${expr.line}:${expr.column}: local function `${expr.value}` requires ${function.parameters.len} arguments, received ${expr.args.len}')
			}
		}
		for input in owner.inputs {
			if input.typ == 'event' && expr.value == input.name && expr.args.len != input.parameters.len {
				return error('${expr.source}:${expr.line}:${expr.column}: event `${expr.value}` requires ${input.parameters.len} payload arguments, received ${expr.args.len}')
			}
		}
	}
	if !isnil(expr.left) { validate_local_call_arity(expr.left, owner)! }
	if !isnil(expr.right) { validate_local_call_arity(expr.right, owner)! }
	if !isnil(expr.third) { validate_local_call_arity(expr.third, owner)! }
	for argument in expr.args { validate_local_call_arity(argument, owner)! }
	for part in expr.parts {
		if !isnil(part.expr) { validate_local_call_arity(part.expr, owner)! }
	}
}

fn validate_component_ids(node &Node, mut names map[string]bool) ! {
	if node.id.len > 0 {
		if node.id in names {
			return error('element id `${node.id}` collides with a component member or id')
		}
		names[node.id] = true
	}
	for child in node.children {
		if child.tag == component_tag { continue }
		validate_component_ids(child, mut names)!
	}
}
