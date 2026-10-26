module vml

// ParseConfig lets the host add widget-specific validation and replace file IO
// without changing the grammar. Every hook is optional.
@[params]
pub struct ParseConfig {
pub:
	// validate_style checks one resolved named style declaration (the list after
	// named references were inlined). `owner` is the document root or component
	// that declares the style. It runs while the document is parsed, in
	// declaration order.
	validate_style ?fn (owner &Node, style &Expr) !
	// validate_document checks a document parsed by `parse_file`, after its imports
	// were expanded. `imported` is true for a document reached through `import`.
	// Imported documents are validated before the importing document.
	validate_document ?fn (root &Node, imported bool) !
	// read_file reads a VML document. The default is `os.read_file`.
	read_file ?fn (path string) !string
	// is_file reports whether an import candidate exists. The default is `os.is_file`.
	is_file ?fn (path string) bool
}

// Parser is a recursive-descent parser over the tokens of one VML document.
// `file` prefixes positioned diagnostics; it is empty for in-memory sources.
pub struct Parser {
pub:
	file   string
	tokens []Token
	config ParseConfig
	// keep_components leaves local component invocations unexpanded and the
	// definitions in `local_definitions` (see `parse_library`).
	keep_components bool
mut:
	pos               int
	local_definitions map[string]&Node
}

// new_parser returns a parser for `tokens` (from `tokenize`).
pub fn new_parser(tokens []Token, file string, config ParseConfig) Parser {
	return Parser{ tokens: tokens, file: file, config: config }
}

// parse_source parses an in-memory document: optional leading `style` and
// `component` declarations followed by one root element, or a document made only
// of component declarations (the last one is the root). Local components are
// expanded and named styles resolved. `Node.source` stays empty.
pub fn parse_source(source string, config ParseConfig) !&Node {
	tokens := tokenize(source)!
	mut parser := Parser{ tokens: tokens, config: config }
	root := parser.parse_document()!
	parser.take(.eof)!
	return root
}

// at returns the current token, or `.eof` past the end.
pub fn (p &Parser) at() Token {
	return if p.pos < p.tokens.len {
		p.tokens[p.pos]
	} else {
		Token{ kind: .eof, text: '', line: 0, column: 1 }
	}
}

// take consumes the current token, which must be of `kind`.
pub fn (mut p Parser) take(kind TokenKind) !Token {
	token := p.at()
	if token.kind != kind {
		return error('${p.file}:${token.line}:${token.column}: expected ${kind}, got ${token.kind} (`${token.text}`)')
	}
	p.pos++
	return token
}

// parse_node parses one element: `Tag`, `Tag(name: value, ...)`, optionally followed
// by `{ children }`. `id` is a local name; `on_*` arguments are handlers.
// Children can be elements and the structural `if` and `for` nodes.
pub fn (mut p Parser) parse_node() !&Node {
	tag := p.take(.name)!
	if tag.text == 'Repeater' {
		return error('${p.file}:${tag.line}:${tag.column}: `Repeater` was replaced by `for item in values key item.id { ... }`')
	}
	mut node := &Node{ tag: tag.text, line: tag.line, column: tag.column }
	if p.at().kind == .lpar {
		p.pos++
		for p.at().kind != .rpar {
			name := p.take(.name)!
			if node.properties.any(it.name == name.text) {
				return error('duplicate VML argument `${name.text}` at line ${name.line}:${name.column}')
			}
			if name.text == 'ref' {
				return error('${p.file}:${name.line}:${name.column}: `ref:` was replaced by the element id: `id: name` makes `name.focus()` available')
			}
			p.take(.colon)!
			expr := if name.text.starts_with('on_') {
				p.parse_handler()!
			} else {
				p.parse_expression()!
			}
			if name.text.starts_with('on_') && expr.kind !in [.path, .call, .assignment, .block, .method] {
				return error('callback `${name.text}` requires a typed function reference or an action at line ${name.line}:${name.column}')
			}
			if name.text == 'id' {
				if expr.kind != .path || expr.value.contains('.') || expr.value.starts_with('#') {
					return error('${p.file}:${name.line}:${name.column}: id must be a local name, such as `id: name_field`')
				}
				node.id = expr.value
			}
			node.properties << Property{ name: name.text, line: name.line, column: name.column, expr: expr }
			if p.at().kind != .comma { break }
			p.pos++
		}
		p.take(.rpar)!
	}
	if p.at().kind == .lbrace {
		node.children = p.parse_children()!
	}
	return node
}

// parse_children parses a `{ ... }` block of child nodes.
fn (mut p Parser) parse_children() ![]&Node {
	p.take(.lbrace)!
	mut children := []&Node{}
	for p.at().kind !in [.rbrace, .eof] {
		if p.at().text in ['property', 'computed', 'state', 'style', 'watch'] || (p.pos + 1 < p.tokens.len && p.tokens[p.pos + 1].kind == .colon) {
			return error('${p.file}:${p.at().line}:${p.at().column}: element arguments use `Name(name: value)`; state, computed and watch belong to the component body')
		}
		children << p.parse_child()!
	}
	p.take(.rbrace)!
	return children
}

// parse_child parses a child node: an element, an `if` chain or a `for` loop.
pub fn (mut p Parser) parse_child() !&Node {
	return match p.at().text {
		'if' { p.parse_if()! }
		'for' { p.parse_for()! }
		'else' { error('${p.file}:${p.at().line}:${p.at().column}: `else` without `if`') }
		else { p.parse_node()! }
	}
}

// parse_if parses `if cond { ... } else if cond { ... } else { ... }`. A
// condition `name := value` unwraps an option: the branch is shown while the
// value is not `none`, with `name` bound to it.
fn (mut p Parser) parse_if() !&Node {
	token := p.at()
	mut chain := &Node{ tag: if_tag, line: token.line, column: token.column }
	for {
		start := p.take(.name)! // `if`
		mut branch := &Node{ tag: branch_tag, line: start.line, column: start.column }
		if p.at().kind == .name && p.pos + 1 < p.tokens.len && p.tokens[p.pos + 1].kind == .declare {
			name := p.take(.name)!
			if name.text.contains('.') {
				return error('${p.file}:${name.line}:${name.column}: `if name := value` binds a local name')
			}
			branch.bind_name = name.text
			p.take(.declare)!
		}
		branch.cond = p.parse_expression()!
		branch.children = p.parse_children()!
		chain.children << branch
		if p.at().text != 'else' { break }
		else_token := p.take(.name)!
		if p.at().text == 'if' { continue }
		mut otherwise := &Node{ tag: branch_tag, line: else_token.line, column: else_token.column }
		otherwise.children = p.parse_children()!
		chain.children << otherwise
		break
	}
	return chain
}

// parse_for parses `for [index,] item in values key expression { ... }`.
fn (mut p Parser) parse_for() !&Node {
	token := p.take(.name)!
	mut node := &Node{ tag: for_tag, line: token.line, column: token.column }
	first := p.take(.name)!
	mut item := first
	if p.at().kind == .comma {
		p.pos++
		node.index_name = first.text
		item = p.take(.name)!
	}
	for name in [item, first] {
		if name.text.contains('.') || name.text in ['in', 'key'] {
			return error('${p.file}:${name.line}:${name.column}: `for` binds local names: `for item in values key item.id`')
		}
	}
	node.bind_name = item.text
	if p.at().text != 'in' {
		return error('${p.file}:${p.at().line}:${p.at().column}: expected `in` after the loop names')
	}
	p.pos++
	node.cond = p.parse_expression()!
	if p.at().text != 'key' {
		return error('${p.file}:${p.at().line}:${p.at().column}: a `for` requires a stable key: `for ${item.text} in values key ${item.text}.id { ... }`')
	}
	p.pos++
	node.key_expr = p.parse_expression()!
	node.children = p.parse_children()!
	return node
}

// parse_handler parses an event handler: a `{ a; b }` block or one assignment/expression.
pub fn (mut p Parser) parse_handler() !&Expr {
	if p.at().kind == .lbrace {
		token := p.take(.lbrace)!
		mut statements := []&Expr{}
		for p.at().kind !in [.rbrace, .eof] {
			statements << p.parse_assignment()!
			if p.at().kind == .semicolon { p.pos++ }
		}
		p.take(.rbrace)!
		return &Expr{ kind: .block, line: token.line, column: token.column, args: statements }
	}
	return p.parse_assignment()
}

const assignment_operators = {
	TokenKind.assign: '='
	.plus_assign:     '+='
	.minus_assign:    '-='
	.mul_assign:      '*='
	.div_assign:      '/='
	.mod_assign:      '%='
	.left_shift:      '<<'
}

// parse_assignment parses a statement: `target op value` (`=`, `+=`, `-=`,
// `*=`, `/=`, `%=`, `<<`), `target++`, `target--` or an expression.
fn (mut p Parser) parse_assignment() !&Expr {
	left := p.parse_expression()!
	if p.at().kind in [.increment, .decrement] {
		op := p.at()
		p.pos++
		return &Expr{
			kind:   .assignment
			value:  if op.kind == .increment { '+=' } else { '-=' }
			line:   op.line
			column: op.column
			left:   left
			right:  &Expr{ kind: .literal, value: '1', line: op.line, column: op.column }
		}
	}
	operator := assignment_operators[p.at().kind] or { return left }
	op := p.at()
	p.pos++
	return &Expr{ kind: .assignment, value: operator, line: op.line, column: op.column, left: left, right: p.parse_expression()! }
}

// parse_expression parses a full expression (conditional, logic, comparison,
// arithmetic, unary, calls, paths, literals, arrays and interpolated strings).
pub fn (mut p Parser) parse_expression() !&Expr {
	return p.parse_conditional()
}

fn (mut p Parser) parse_conditional() !&Expr {
	condition := p.parse_or()!
	if p.at().kind != .question {
		return condition
	}
	line := p.take(.question)!.line
	when_true := p.parse_expression()!
	p.take(.colon)!
	return &Expr{
		kind:  .conditional
		line:  line
		left:  condition
		right: when_true
		third: p.parse_expression()!
	}
}

fn (mut p Parser) parse_or() !&Expr {
	mut left := p.parse_and()!
	for p.at().kind == .or {
		op := p.at()
		p.pos++
		left = &Expr{
			kind:   .binary
			value:  op.text
			line:   op.line
			column: op.column
			left:   left
			right:  p.parse_and()!
		}
	}
	return left
}

fn (mut p Parser) parse_and() !&Expr {
	mut left := p.parse_equality()!
	for p.at().kind == .and {
		op := p.at()
		p.pos++
		left = &Expr{
			kind:   .binary
			value:  op.text
			line:   op.line
			column: op.column
			left:   left
			right:  p.parse_equality()!
		}
	}
	return left
}

fn (mut p Parser) parse_equality() !&Expr {
	mut left := p.parse_comparison()!
	for p.at().kind in [.eq, .ne] {
		op := p.at()
		p.pos++
		left = &Expr{
			kind:   .binary
			value:  op.text
			line:   op.line
			column: op.column
			left:   left
			right:  p.parse_comparison()!
		}
	}
	return left
}

fn (mut p Parser) parse_comparison() !&Expr {
	mut left := p.parse_term()!
	for p.at().kind in [.lt, .le, .gt, .ge] {
		op := p.at()
		p.pos++
		left = &Expr{
			kind:   .binary
			value:  op.text
			line:   op.line
			column: op.column
			left:   left
			right:  p.parse_term()!
		}
	}
	return left
}

fn (mut p Parser) parse_term() !&Expr {
	mut left := p.parse_factor()!
	for p.at().kind in [.plus, .minus] {
		op := p.at()
		p.pos++
		left = &Expr{
			kind:   .binary
			value:  op.text
			line:   op.line
			column: op.column
			left:   left
			right:  p.parse_factor()!
		}
	}
	return left
}

fn (mut p Parser) parse_factor() !&Expr {
	mut left := p.parse_unary()!
	for p.at().kind in [.mul, .div, .mod] {
		op := p.at()
		p.pos++
		left = &Expr{
			kind:   .binary
			value:  op.text
			line:   op.line
			column: op.column
			left:   left
			right:  p.parse_unary()!
		}
	}
	return left
}

fn (mut p Parser) parse_unary() !&Expr {
	if p.at().kind in [.not, .minus] {
		op := p.at()
		p.pos++
		return &Expr{ kind: .unary, value: op.text, line: op.line, column: op.column, left: p.parse_unary()! }
	}
	return p.parse_postfix(p.parse_primary()!)
}

// same_line reports whether the current token starts on the line where the
// previous one is, so that `[`, `.name` and `or` continue an expression
// instead of starting another.
fn (p &Parser) same_line() bool {
	return p.pos > 0 && p.pos < p.tokens.len && p.tokens[p.pos - 1].line == p.tokens[p.pos].line
}

// parse_postfix parses what follows a primary expression: `[index]`,
// `.field`, `.method(args)` (with `!`) and `or { fallback }`.
fn (mut p Parser) parse_postfix(primary &Expr) !&Expr {
	mut expr := unsafe { primary }
	for {
		token := p.at()
		if token.kind == .lsbr && p.same_line() {
			p.pos++
			index := p.parse_expression()!
			p.take(.rsbr)!
			expr = &Expr{ kind: .index, line: token.line, column: token.column, left: expr, right: index }
		} else if token.kind == .name && token.text.starts_with('.') && token.text.len > 1 && p.same_line() {
			p.pos++
			names := token.text[1..].split('.')
			if names.any(it.len == 0) {
				return error('${p.file}:${token.line}:${token.column}: invalid member `${token.text}`')
			}
			for index, name in names {
				if index == names.len - 1 && p.at().kind == .lpar {
					args := p.parse_arguments()!
					fallible := p.at().kind == .not
					if fallible { p.pos++ }
					expr = &Expr{ kind: .method, value: name, line: token.line, column: token.column, left: expr, args: args, fallible: fallible }
				} else {
					expr = &Expr{ kind: .selector, value: name, line: token.line, column: token.column, left: expr }
				}
			}
		} else if token.kind == .name && token.text == 'or' && p.pos + 1 < p.tokens.len
			&& p.tokens[p.pos + 1].kind == .lbrace {
			p.pos += 2
			fallback := p.parse_expression()!
			p.take(.rbrace)!
			expr = &Expr{ kind: .or_else, line: token.line, column: token.column, left: expr, right: fallback }
		} else {
			return expr
		}
	}
	return expr
}

// parse_arguments parses `(a, b, ...)`.
fn (mut p Parser) parse_arguments() ![]&Expr {
	p.take(.lpar)!
	mut args := []&Expr{}
	if p.at().kind != .rpar {
		for {
			args << p.parse_expression()!
			if p.at().kind != .comma {
				break
			}
			p.pos++
		}
	}
	p.take(.rpar)!
	return args
}

fn (mut p Parser) parse_primary() !&Expr {
	token := p.at()
	match token.kind {
		.string_ {
			p.pos++
			mut expr := parse_interpolation(token)!
			expr.column = token.column
			return expr
		}
		.name, .number {
			p.pos++
			if p.at().kind == .lpar {
				args := p.parse_arguments()!
				fallible := p.at().kind == .not
				if fallible { p.pos++ }
				return &Expr{ fallible: fallible, kind: .call, value: token.text, line: token.line, column: token.column, args: args }
			}
			return &Expr{
				kind:   if token.kind == .number || token.text in ['true', 'false'] {
					ExprKind.literal
				} else {
					ExprKind.path
				}
				value:  token.text
				line:   token.line
				column: token.column
			}
		}
		.lsbr {
			p.pos++
			mut values := []&Expr{}
			for p.at().kind != .rsbr {
				values << p.parse_expression()!
				if p.at().kind != .comma { break }
				p.pos++
			}
			p.take(.rsbr)!
			return &Expr{ kind: .array, args: values, line: token.line, column: token.column }
		}
		.lpar {
			p.pos++
			expr := p.parse_expression()!
			p.take(.rpar)!
			return expr
		}
		else {
			return error('expected expression, got ${token.kind} (`${token.text}`) at line ${token.line}')
		}
	}
}

fn interpolation_end(value string, start int) ?int {
	mut quote := u8(0)
	mut escaped := false
	mut nested_braces := 0
	for i := start; i < value.len; i++ {
		ch := value[i]
		if quote != 0 {
			if escaped {
				escaped = false
			} else if ch == `\\` {
				escaped = true
			} else if ch == quote {
				quote = 0
			}
			continue
		}
		if ch == `"` || ch == `'` {
			quote = ch
		} else if ch == `{` {
			nested_braces++
		} else if ch == `}` {
			if nested_braces == 0 {
				return i
			}
			nested_braces--
		}
	}
	return none
}

fn parse_interpolation(token Token) !&Expr {
	value := token.text
	line := token.line
	if !value.contains(r'${') {
		return &Expr{ kind: .literal, value: value, line: line, quoted: true }
	}
	mut parts := []InterpolationPart{}
	mut cursor := 0
	for cursor < value.len {
		start_relative := value[cursor..].index(r'${') or {
			parts << InterpolationPart{ text: value[cursor..] }
			break
		}
		start := cursor + start_relative
		if start > cursor {
			parts << InterpolationPart{ text: value[cursor..start] }
		}
		end := interpolation_end(value, start + 2) or {
			return error('unterminated interpolation at line ${line}')
		}
		fragment := value[start + 2..end]
		mut tokens := tokenize(fragment) or {
			return error('${token.line}:${token.column}: invalid interpolation: ${err}')
		}
		mut line_starts := [0]
		for offset, ch in fragment {
			if ch == `\n` { line_starts << offset + 1 }
		}
		// Decoded escapes can introduce newlines that do not exist in the file.
		// Map fragment tokens back to the original string bytes, including nested
		// strings, before parsing their expressions.
		for index, part_token in tokens {
			location := token.string_locations[start + 2 + line_starts[part_token.line - 1] + part_token.column - 1]
			mut nested_locations := []Location{cap: part_token.string_locations.len}
			for nested in part_token.string_locations {
				nested_locations << token.string_locations[start + 2 + line_starts[nested.line - 1] + nested.column - 1]
			}
			tokens[index] = Token{ ...part_token, line: location.line, column: location.column, string_locations: nested_locations }
		}
		mut parser := Parser{ tokens: tokens }
		parts << InterpolationPart{ expr: parser.parse_expression()! }
		parser.take(.eof) or { return error('invalid interpolation at line ${line}: ${err}') }
		cursor = end + 1
	}
	return &Expr{ kind: .interpolation, line: line, parts: parts }
}
