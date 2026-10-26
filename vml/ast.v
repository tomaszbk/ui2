module vml

// ExprKind is the kind of an `Expr` node.
pub enum ExprKind {
	literal       // `value` is the literal text; `quoted` marks a string literal
	path          // `value` is a dotted name such as `app.count`, `item.id`, `left`, `.start`
	call          // `value` is the callee path, `args` the arguments; `fallible` marks `f()!`
	unary         // `value` is `!` or `-`; the operand is `left`
	binary        // `value` is the operator; operands are `left` and `right`
	assignment    // `left op right`; `value` is the operator (`=`, `+=`, `<<`, ...); `x++` is `x += 1`
	block         // `{ a; b }` handler; the statements are `args`
	array         // `[a, b]`; the elements are `args`
	conditional   // `left ? right : third`
	interpolation // a string literal containing `${...}`; see `parts`
	index         // `left[right]`
	selector      // `left.value`: a field path read after an index or a call
	method        // `left.value(args)`: a method call after an index or a call; `fallible` marks `!`
	or_else       // `left or { right }`
}

// InterpolationPart is one segment of an `.interpolation` expression: either
// literal text or an embedded expression.
pub struct InterpolationPart {
pub:
	text string
	// A nil expression marks a literal-text part. V requires `unsafe` only to
	// declare that sentinel pointer default; interpolation logic checks it before use.
	expr &Expr = unsafe { nil }
}

// Expr is a VML expression. The meaning of `value`, `left`, `right`, `third`,
// `args` and `parts` depends on `kind` (see `ExprKind`). `line`/`column` are the
// 1-based position of the expression's first or operator token; `source` is the
// document path once `set_source` has run (it is empty for in-memory sources).
pub struct Expr {
pub:
	kind  ExprKind
	value string
	line  int
pub mut:
	column int = 1
	source string
	// The tagged expression tree is recursive. Nil marks child links unused by
	// the current kind, and V requires `unsafe` only for those pointer defaults.
	left     &Expr = unsafe { nil }
	right    &Expr = unsafe { nil }
	third    &Expr = unsafe { nil }
	args     []&Expr
	parts    []InterpolationPart
	quoted   bool
	fallible bool
}

// Property is one named element argument, `name: expr`. Names can be dotted,
// for example `bind.text`. Arguments starting with `on_` hold a handler: a
// callback path, a call, an assignment or a `{ ... }` block.
pub struct Property {
pub:
	name   string
	line   int
	column int
	expr   &Expr
}

// Node is an element `Tag(name: value, ...) { children }`, a structural node
// (`if_tag`, `branch_tag` or `for_tag`) or, when `tag` is `component_tag`, a
// component definition or invocation. Component members
// (`inputs`, `data`, `functions`, `watches`, `mount`, `unmount`, `cleanup`) and
// `component_name` are set only on component nodes; `styles` holds the named
// styles visible to that document or component. Imports and local components
// are expanded in place: an invocation becomes a copy of the definition (with
// the definition's position and source) with `imported` set, the caller's
// `properties` and `id`, and slot content (`caller_content` set) substituted
// for `Slot` elements.
pub struct Node {
pub:
	tag    string
	line   int
	column int = 1
pub mut:
	source         string
	imported       bool
	import_id      bool
	id             string
	properties     []Property
	children       []&Node
	component_name string
	// An invocation kept by `parse_library`: the key (`file#Name`) of the
	// component definition it instantiates.
	component_ref string
	inputs         []Input
	data           []Data
	functions      []Function
	watches        []Watch
	caller_content bool
	// Structural nodes. A branch: its condition (nil for `else`) and, for
	// `if name := option`, the name of the unwrapped value. A `for`: the
	// iterated value, its item and index names and its key.
	cond       &Expr = unsafe { nil }
	bind_name  string
	index_name string
	key_expr   &Expr = unsafe { nil }
	mount          []&Expr
	unmount        []&Expr
	cleanup        []&Expr
	styles         []Style
}

// component_tag is the `Node.tag` of component definitions and expanded invocations.
pub const component_tag = '__Component'

// if_tag is the `Node.tag` of an `if` chain; its children are its branches.
pub const if_tag = '__If'

// branch_tag is the `Node.tag` of one branch of an `if` chain.
pub const branch_tag = '__Branch'

// for_tag is the `Node.tag` of a `for item in values key k { ... }` loop.
pub const for_tag = '__For'

// is_structural reports whether a tag is a structural node rather than an element.
pub fn is_structural(tag string) bool {
	return tag in [if_tag, branch_tag, for_tag]
}

// Parameter is a `name type` pair: a callback, event or function parameter.
pub struct Parameter {
pub:
	name string
	typ  string
}

// Input is one component signature entry: `name type = default`,
// `bind name type = default`, `name event(payload types)` or `name slot`.
// `typ` is the V type text (`[]` prefixes kept), or `event`/`slot`.
pub struct Input {
pub:
	name          string
	typ           string
	line          int
	column        int
	bindable      bool
	parameters    []Parameter
	default_value &Expr = unsafe { nil }
}

// Watch is a component `watch [old,] now := expr { body }` (or `watch expr
// { body }`) declaration: `body` runs each time the value of `expr` changes.
pub struct Watch {
pub:
	expr   &Expr
	old    string
	now    string
	line   int
	column int
pub mut:
	body []&Expr
}

// Data is a component `state name := expr` or `computed name := expr` declaration.
pub struct Data {
pub:
	name     string
	computed bool
	expr     &Expr
}

// Function is a component-local `fn name(parameters) { body }` declaration.
pub struct Function {
pub:
	name       string
	parameters []Parameter
pub mut:
	body []&Expr
}

// Style is a named style declaration, `style name = [ ... ]`.
// Named styles are lexical values. The compiler resolves references; ui2 owns
// typed patches, ordered composition, theme signals and retained application.
pub struct Style {
pub:
	name   string
	line   int
	column int
	expr   &Expr
}

// find_property returns the first argument of `node` called `name`.
pub fn find_property(node &Node, name string) ?Property {
	for property in node.properties {
		if property.name == name {
			return property
		}
	}
	return none
}

// node_uses_path reports whether any expression of `node` or its descendants
// reads `base` or a member path below it (`base.x`).
pub fn node_uses_path(node &Node, base string) bool {
	for data in node.data { if expr_uses_path(data.expr, base) { return true } }
	for input in node.inputs {
		if !isnil(input.default_value) && expr_uses_path(input.default_value, base) {
			return true
		}
	}
	for function in node.functions {
		for statement in function.body { if expr_uses_path(statement, base) { return true } }
	}
	for watch in node.watches {
		if expr_uses_path(watch.expr, base) { return true }
		for statement in watch.body { if expr_uses_path(statement, base) { return true } }
	}
	for expr in [node.cond, node.key_expr] {
		if !isnil(expr) && expr_uses_path(expr, base) { return true }
	}
	for statement in node.mount { if expr_uses_path(statement, base) { return true } }
	for statement in node.cleanup { if expr_uses_path(statement, base) { return true } }
	for statement in node.unmount { if expr_uses_path(statement, base) { return true } }
	for property in node.properties {
		if expr_uses_path(property.expr, base) {
			return true
		}
	}
	for child in node.children {
		if node_uses_path(child, base) {
			return true
		}
	}
	return false
}

// expr_uses_path reports whether `expr` reads or calls `base` or a member path
// below it (`base.x`).
pub fn expr_uses_path(expr &Expr, base string) bool {
	if expr.kind in [.path, .call] && (expr.value == base || expr.value.starts_with(base + '.')) {
		return true
	}
	if !isnil(expr.left) && expr_uses_path(expr.left, base) {
		return true
	}
	if !isnil(expr.right) && expr_uses_path(expr.right, base) {
		return true
	}
	if !isnil(expr.third) && expr_uses_path(expr.third, base) {
		return true
	}
	for arg in expr.args {
		if expr_uses_path(arg, base) {
			return true
		}
	}
	for part in expr.parts {
		if !isnil(part.expr) && expr_uses_path(part.expr, base) {
			return true
		}
	}
	return false
}

// expr_text renders `expr` back to VML-like source text, for messages.
pub fn expr_text(expr &Expr) string {
	return match expr.kind {
		.literal, .path { expr.value }
		.call { expr.value + '(' + expr.args.map(expr_text(it)).join(', ') + ')' }
		.unary { expr.value + expr_text(expr.left) }
		.binary { '${expr_text(expr.left)} ${expr.value} ${expr_text(expr.right)}' }
		.assignment { '${expr_text(expr.left)} ${expr.value} ${expr_text(expr.right)}' }
		.index { '${expr_text(expr.left)}[${expr_text(expr.right)}]' }
		.selector { '${expr_text(expr.left)}.${expr.value}' }
		.method { '${expr_text(expr.left)}.${expr.value}(' + expr.args.map(expr_text(it)).join(', ') + ')' }
		.or_else { '${expr_text(expr.left)} or { ${expr_text(expr.right)} }' }
		.block { '{' + expr.args.map(expr_text(it)).join('; ') + '}' }
		.array { '[' + expr.args.map(expr_text(it)).join(', ') + ']' }
		.conditional {
			'${expr_text(expr.left)} ? ${expr_text(expr.right)} : ${expr_text(expr.third)}'
		}
		.interpolation {
			mut value := ''
			for part in expr.parts {
				value += if isnil(part.expr) {
					part.text
				} else {
					r'${' + expr_text(part.expr) + '}'
				}
			}
			value
		}
	}
}

// set_source records `path` as the source of `node`, its expressions and descendants.
pub fn set_source(mut node Node, path string) {
	node.source = path
	for property in node.properties { set_expr_source(mut property.expr, path) }
	for data in node.data { set_expr_source(mut data.expr, path) }
	for style in node.styles { set_expr_source(mut style.expr, path) }
	for input in node.inputs {
		if !isnil(input.default_value) { set_expr_source(mut input.default_value, path) }
	}
	for mut function in node.functions {
		for mut statement in function.body { set_expr_source(mut statement, path) }
	}
	for mut watch in node.watches {
		set_expr_source(mut watch.expr, path)
		for mut statement in watch.body { set_expr_source(mut statement, path) }
	}
	if !isnil(node.cond) { set_expr_source(mut node.cond, path) }
	if !isnil(node.key_expr) { set_expr_source(mut node.key_expr, path) }
	for mut statement in node.mount { set_expr_source(mut statement, path) }
	for mut statement in node.unmount { set_expr_source(mut statement, path) }
	for mut statement in node.cleanup { set_expr_source(mut statement, path) }
	for mut child in node.children { set_source(mut child, path) }
}

fn set_expr_source(mut expr Expr, path string) {
	expr.source = path
	if !isnil(expr.left) { set_expr_source(mut expr.left, path) }
	if !isnil(expr.right) { set_expr_source(mut expr.right, path) }
	if !isnil(expr.third) { set_expr_source(mut expr.third, path) }
	for mut arg in expr.args { set_expr_source(mut arg, path) }
	for part in expr.parts {
		if !isnil(part.expr) { set_expr_source(mut part.expr, path) }
	}
}

// clone_node copies `node` and its element tree. Expressions are shared.
pub fn clone_node(node &Node) &Node {
	return &Node{ ...node, properties: node.properties.clone(), children: node.children.map(clone_node(it)) }
}

fn node_has_tag(node &Node, tag string) bool {
	if node.tag == tag { return true }
	for child in node.children { if node_has_tag(child, tag) { return true } }
	return false
}

// node_error formats a diagnostic at `node`: `path:line:column: message` when
// the source is known, `message at line L, column C` otherwise.
pub fn node_error(node &Node, message string) IError {
	return if node.source.len > 0 {
		error('${node.source}:${node.line}:${node.column}: ${message}')
	} else {
		error('${message} at line ${node.line}, column ${node.column}')
	}
}

// expr_error formats a diagnostic at `expr` like `node_error`.
pub fn expr_error(expr &Expr, message string) IError {
	return if expr.source.len > 0 {
		error('${expr.source}:${expr.line}:${expr.column}: ${message}')
	} else {
		error('${message} at line ${expr.line}, column ${expr.column}')
	}
}
