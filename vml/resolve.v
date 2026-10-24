module vml

// The resolver: it reads a parsed document once into the IR (ir.v). It knows
// the language (scopes, components, repeaters, slots, handlers, helper
// values) and the identity rules of the retained runtime, but no widget and
// no model type. An unknown name, a misplaced assignment or a component input
// supplied twice is an error here; a wrong property or model field is an
// error of the consumer that knows the widgets and the model.

const reserved_roots = ['app', 'color', 'spacing', 'radius', 'typography']

const geometry_fields = ['x', 'y', 'width', 'height']

// Tags that describe their parent rather than being elements of their own.
pub const part_tags = ['Keyframe', 'MenuItem', 'Option', 'Run', 'Timeline']

pub const ref_methods = {
	'is_available': 0
	'focus':        0
	'id':           0
	'element':      0
	'set_text':     1
}

struct Resolver {
	library &Library = unsafe { nil }
mut:
	next_scope       int
	module_functions []string
	uses_app         bool
	defs             map[string]&IComponentDef
	// The definitions being resolved, innermost last: `Slot` is valid inside one.
	def_stack []&IComponentDef
}

// resolve_file parses the document at `path` with the components it imports
// and resolves it.
pub fn resolve_file(path string) !&Program {
	library := parse_library(path, validate_document: validate_vml_document)!
	return resolve_library(library)
}

// resolve_library reads a parsed document and its component definitions into
// the IR. Each definition the document uses is resolved once.
pub fn resolve_library(library &Library) !&Program {
	mut r := Resolver{
		library: library
	}
	root := library.root
	mut scope := r.new_scope(.document, unsafe { nil }, unsafe { nil })
	mut program := &Program{
		path:  root.source
		scope: scope
		menus: root.tag in ['Menu', 'MenuBar']
	}
	if root.tag == component_tag {
		// A document that only declares a component builds that component with
		// its declared defaults.
		key := component_key(root.source, root.component_name)
		def := r.definition(key)!
		program.root = r.invocation(&Node{
			tag:           root.component_name
			line:          root.line
			column:        root.column
			source:        root.source
			component_ref: key
		}, '0', mut scope, false)!
		_ = def
	} else {
		program.root = r.node(root, '0', mut scope, false)!
	}
	program.components = r.defs.clone()
	program.module_functions = r.module_functions
	program.uses_app = r.uses_app
	mut files := []string{}
	collect_document_files(root, mut files)
	for _, def in library.components {
		collect_document_files(def, mut files)
	}
	program.files = files
	return program
}

fn collect_document_files(node &Node, mut files []string) {
	if node.source.len > 0 && node.source !in files {
		files << node.source
	}
	for child in node.children {
		collect_document_files(child, mut files)
	}
}

fn (mut r Resolver) new_scope(kind ScopeKind, parent &Scope, caller &Scope) &Scope {
	r.next_scope++
	return &Scope{
		id:     r.next_scope
		kind:   kind
		parent: parent
		caller: caller
	}
}

fn (mut s Scope) add(name string, binding Binding) Binding {
	bound := Binding{
		...binding
		name:     name
		slot:     s.order.len
		scope_id: s.id
	}
	s.names[name] = bound
	s.order << name
	return bound
}

fn add_tokens(scope &Scope, names []string) {
	mut owner := scope.owner_scope()
	for name in names {
		if name !in owner.tokens {
			owner.tokens << name
		}
	}
}

fn expr_tokens(e &Expr, mut names []string) {
	if e.kind == .path {
		if token := token_name(e.value) {
			if token !in names {
				names << token
			}
		}
	}
	if !isnil(e.left) {
		expr_tokens(e.left, mut names)
	}
	if !isnil(e.right) {
		expr_tokens(e.right, mut names)
	}
	if !isnil(e.third) {
		expr_tokens(e.third, mut names)
	}
	for arg in e.args {
		expr_tokens(arg, mut names)
	}
	for part in e.parts {
		if !isnil(part.expr) {
			expr_tokens(part.expr, mut names)
		}
	}
}

// token_name maps a theme path to its token: `color.surface` is
// `color:surface`, `typography.title` is `font_size:title`.
pub fn token_name(value string) ?string {
	for pair in [['color', 'color'], ['spacing', 'spacing'], ['radius', 'radius'],
		['typography', 'font_size']] {
		if value.starts_with(pair[0] + '.') {
			name := value.all_after(pair[0] + '.')
			if name.len == 0 || name.contains('.') {
				return none
			}
			return pair[1] + ':' + name
		}
	}
	return none
}

fn loc(source string, line int, column int) Location {
	return Location{
		path:   source
		line:   line
		column: column
	}
}

fn expr_loc(e &Expr) Location {
	return loc(e.source, e.line, e.column)
}

fn node_loc(n &Node) Location {
	return loc(n.source, n.line, n.column)
}

fn property_loc(n &Node, property Property) Location {
	return loc(if property.expr.source.len > 0 { property.expr.source } else { n.source },
		property.line, property.column)
}

fn (l Location) error(message string) IError {
	if l.path.len > 0 {
		return error('${l.path}:${l.line}:${l.column}: ${message}')
	}
	return error('${message} at line ${l.line}, column ${l.column}')
}

// node resolves an element, a component invocation or (inside a component
// definition) a `Slot` at `path` in `scope`, adding the ids it declares to
// `scope`. `relative` marks paths relative to a component instance.
fn (mut r Resolver) node(n &Node, path string, mut scope Scope, relative bool) !&INode {
	if n.component_ref.len > 0 {
		return r.invocation(n, path, mut scope, relative)
	}
	if n.tag == component_tag {
		return node_loc(n).error('a component is declared at the top of a document')
	}
	if n.tag == 'Repeater' {
		return node_loc(n).error('a Repeater must be the child of a container')
	}
	if n.tag == 'Slot' {
		if r.def_stack.len == 0 {
			return node_loc(n).error('`Slot` is only valid inside a component')
		}
		name := if property := find_property(n, 'name') {
			property.expr.value
		} else {
			'content'
		}
		mut def := r.def_stack.last()
		if name in def.slots {
			return node_loc(n).error('slot `${name}` is placed twice')
		}
		if !def_declares_slot(r.library.components[def.key] or { unsafe { nil } }, name) {
			return node_loc(n).error('unknown slot `${name}`')
		}
		def.slots[name] = path
		return &INode{
			kind:     .slot
			tag:      name
			path:     path
			src:      node_loc(n)
			relative: relative
		}
	}
	return r.element(n, path, mut scope, relative)
}

fn def_declares_slot(definition &Node, name string) bool {
	if isnil(definition) {
		return false
	}
	return definition.inputs.any(it.typ == 'slot' && it.name == name)
}

fn (mut r Resolver) element(n &Node, path string, mut scope Scope, relative bool) !&INode {
	src := node_loc(n)
	mut node := &INode{
		kind:     .element
		tag:      n.tag
		path:     path
		src:      src
		id:       n.id
		relative: relative
	}
	if n.id.len > 0 {
		if n.id in reserved_roots {
			return src.error('element id `${n.id}` collides with the reserved name `${n.id}`')
		}
		node.id_binding = scope.add(n.id, Binding{
			kind: .id
		})
		node.id_slot = node.id_binding.slot
	}
	mut names := []string{}
	for property in n.properties {
		expr_tokens(property.expr, mut names)
	}
	add_tokens(scope, names)
	for property in n.properties {
		psrc := property_loc(n, property)
		if property.name in ['id', 'ref'] {
			continue
		}
		if property.name == 'key' {
			node.key = r.expr(property.expr, scope, true)!
			node.key_src = psrc
			continue
		}
		if property.name.starts_with('bind.') {
			node.binds << r.bind(property, scope, psrc)!
			continue
		}
		if property.name.starts_with('on_') {
			node.events << r.event(property, scope, psrc)!
			continue
		}
		node.props << r.prop(property.name, property.expr, scope, psrc)!
	}
	if property := find_property(n, 'ref') {
		node.ref = r.ref_target(n, property, scope)!
	}
	for index, child in n.children {
		child_path := '${path}.${index}'
		if child.tag == 'Repeater' {
			node.children << r.repeater(child, '${generated_name(path)}.${index}', mut
				scope, relative)!
			continue
		}
		node.children << r.node(child, child_path, mut scope, relative)!
	}
	return node
}

// generated_name is the identifier form of a path: `0.1-a` is `0_1_a`.
pub fn generated_name(path string) string {
	return path.replace('.', '_').replace('-', '_')
}

// prop resolves a property value. A list, a helper call or a conditional with
// one is a helper value of the property's namespace.
fn (mut r Resolver) prop(name string, e &Expr, scope &Scope, src Location) !IProp {
	helper := r.is_helper_value(e, scope)
	expr := if helper { r.helper_value(e, scope)! } else { r.expr(e, scope, true)! }
	return IProp{
		name:     name
		expr:     expr
		helper:   helper
		reactive: ir_reactive(expr)
		uses_app: ir_uses_app(expr)
		src:      src
	}
}

fn (mut r Resolver) bind(property Property, scope &Scope, src Location) !IBind {
	if property.expr.kind != .path {
		return src.error('`${property.name}` must target a writable path')
	}
	return IBind{
		prop:   property.name.all_after('bind.')
		target: r.expr(property.expr, scope, false)!
		write:  r.assignment_target(property.expr, scope, src)!
		src:    src
	}
}

fn (mut r Resolver) event(property Property, scope &Scope, src Location) !IEvent {
	mut handler_scope := r.new_scope(.handler, scope, unsafe { nil })
	handler_scope.add('event', Binding{
		kind: .param
		typ:  'ui2.ElementEvent'
	})
	handler := r.handler(property.expr, mut handler_scope, [])!
	return IEvent{
		name:     property.name
		handler:  handler
		scope:    handler_scope
		uses_app: ir_uses_app(handler)
		src:      src
	}
}

fn (mut r Resolver) ref_target(n &Node, property Property, scope &Scope) !&IExpr {
	src := property_loc(n, property)
	if property.expr.kind != .path || property.expr.value.contains('.') {
		return src.error('`ref` takes the name of a `ref` declaration')
	}
	binding, depth := scope.lookup(property.expr.value) or {
		return src.error('unknown ref `${property.expr.value}`')
	}
	if binding.kind != .ref {
		return src.error('`${property.expr.value}` is not a ref')
	}
	return &IExpr{
		kind:    .binding
		binding: binding
		depth:   depth
		src:     src
	}
}

// ------------------------------------------------------------- repeaters

fn (mut r Resolver) repeater(n &Node, path string, mut scope Scope, relative bool) !&INode {
	src := node_loc(n)
	model_property := find_property(n, 'model') or {
		return src.error('Repeater requires `model`')
	}
	key_property := find_property(n, 'key') or {
		return src.error('Repeater requires a stable `key`')
	}
	for property in n.properties {
		if property.name !in ['model', 'key'] {
			return property_loc(n, property).error('unsupported `${property.name}` on Repeater')
		}
	}
	model := r.expr(model_property.expr, scope, false)!
	mut key_scope := r.new_scope(.key, scope, unsafe { nil })
	key_scope.add('item', Binding{
		kind: .item
	})
	key := r.expr(key_property.expr, key_scope, false)!
	mut item_scope := r.new_scope(.item, scope, unsafe { nil })
	item_slot := item_scope.add('item', Binding{
		kind: .item
	}).slot
	index_slot := item_scope.add('index', Binding{
		kind: .index
	}).slot
	mut repeat := &IRepeater{
		name:           generated_name(path)
		model:          model
		model_uses_app: ir_uses_app(model)
		key:            key
		key_scope:      key_scope
		item_scope:     item_scope
		item_slot:      item_slot
		index_slot:     index_slot
		src:            src
		model_src:      property_loc(n, model_property)
		key_src:        property_loc(n, key_property)
	}
	for index, child in n.children {
		child_path := '${path}.${index}'
		if child.tag == 'Repeater' {
			repeat.children << r.repeater(child, child_path, mut item_scope, relative)!
		} else {
			repeat.children << r.node(child, child_path, mut item_scope, relative)!
		}
	}
	return &INode{
		kind:     .repeater
		tag:      'Repeater'
		path:     path
		src:      src
		repeat:   repeat
		relative: relative
	}
}

// ------------------------------------------------------------ components

// definition resolves the component definition `key` once.
fn (mut r Resolver) definition(key string) !&IComponentDef {
	if def := r.defs[key] {
		return def
	}
	n := r.library.components[key] or { return error('unknown VML component `${key}`') }
	src := node_loc(n)
	if n.children.len == 0 {
		return src.error('component `${n.component_name}` has no root element')
	}
	mut scope := r.new_scope(.component, unsafe { nil }, unsafe { nil })
	mut def := &IComponentDef{
		key:    key
		name:   n.component_name
		source: n.source
		scope:  scope
		src:    src
	}
	mut own_tokens := []string{}
	for input in n.inputs {
		if !isnil(input.default_value) {
			expr_tokens(input.default_value, mut own_tokens)
		}
	}
	for data in n.data {
		expr_tokens(data.expr, mut own_tokens)
	}
	for function in n.functions {
		for statement in function.body {
			expr_tokens(statement, mut own_tokens)
		}
	}
	add_tokens(scope, own_tokens)
	for input in n.inputs {
		isrc := loc(n.source, input.line, input.column)
		if input.typ == 'slot' {
			continue
		}
		if input.typ == 'event' {
			slot := scope.add(input.name, Binding{
				kind:   .event
				params: input.parameters
			}).slot
			def.inputs << IInputDecl{
				name:   input.name
				typ:    input.typ
				slot:   slot
				event:  true
				params: input.parameters
				src:    isrc
			}
			continue
		}
		mut default_value := &IExpr(unsafe { nil })
		mut default_helper := false
		if !isnil(input.default_value) {
			namespace := type_namespace(input.typ) or { '' }
			default_helper = namespace.len > 0 && r.is_helper_value(input.default_value, scope)
			default_value = if default_helper {
				r.helper_value(input.default_value, scope)!
			} else {
				r.expr(input.default_value, scope, true)!
			}
		}
		slot := scope.add(input.name, Binding{
			kind:     .input
			writable: input.bindable
			typ:      input.typ
		}).slot
		def.inputs << IInputDecl{
			name:           input.name
			typ:            input.typ
			slot:           slot
			bindable:       input.bindable
			default_value:  default_value
			default_helper: default_helper
			src:            isrc
		}
	}
	for reference in n.refs {
		slot := scope.add(reference.name, Binding{
			kind:    .ref
			ref_tag: reference.typ
		}).slot
		def.refs << IRef{
			name: reference.name
			slot: slot
			tag:  reference.typ
		}
	}
	for data in n.data {
		expr := r.expr(data.expr, scope, true)!
		slot := scope.add(data.name, Binding{
			kind:     if data.computed { BindingKind.computed } else { BindingKind.state }
			writable: !data.computed
		}).slot
		def.data << IData{
			name:     data.name
			slot:     slot
			computed: data.computed
			expr:     expr
			uses_app: ir_uses_app(expr)
			src:      expr_loc(data.expr)
		}
	}
	for function in n.functions {
		mut fn_scope := r.new_scope(.function, scope, unsafe { nil })
		for parameter in function.parameters {
			fn_scope.add(parameter.name, Binding{
				kind: .param
				typ:  parameter.typ
			})
		}
		mut fun := &IFunction{
			name:   function.name
			params: function.parameters
			scope:  fn_scope
		}
		fun.body = r.action(&Expr{
			kind:   .block
			args:   function.body
			source: n.source
			line:   n.line
			column: n.column
		}, fn_scope)!
		scope.add(function.name, Binding{
			kind:   .func
			params: function.parameters
			func:   fun
		})
		def.functions << fun
	}
	if n.mount.len > 0 {
		def.mount = r.action(&Expr{ kind: .block, args: n.mount, source: n.source }, scope)!
	}
	if n.unmount.len > 0 {
		def.unmount = r.action(&Expr{ kind: .block, args: n.unmount, source: n.source },
			scope)!
	}
	if n.cleanup.len > 0 {
		def.cleanup = r.action(&Expr{ kind: .block, args: n.cleanup, source: n.source },
			scope)!
	}
	r.defs[key] = def
	r.def_stack << def
	def.root = r.node(n.children[0], 'root', mut scope, true)!
	r.def_stack.delete_last()
	def.uses_app = node_uses_path(n, 'app')
	return def
}

// invocation resolves a use of a component in the caller's scope: its
// arguments, event handlers, slot content, key, ref and the properties the
// component does not declare, which configure the component's root.
fn (mut r Resolver) invocation(n &Node, path string, mut caller Scope, relative bool) !&INode {
	src := node_loc(n)
	def := r.definition(n.component_ref)!
	definition := r.library.components[n.component_ref] or {
		return src.error('unknown VML component `${n.tag}`')
	}
	mut inv := &IInvocation{
		def_key: n.component_ref
		caller:  &caller
	}
	mut caller_tokens := []string{}
	for property in n.properties {
		expr_tokens(property.expr, mut caller_tokens)
	}
	add_tokens(caller, caller_tokens)
	for property in n.properties {
		psrc := property_loc(n, property)
		if property.name in ['id', 'key', 'ref'] {
			continue
		}
		name := property.name.all_after('bind.')
		declared := if property.name.starts_with('on_') {
			definition.inputs.any(it.typ == 'event' && it.name == property.name.all_after('on_'))
		} else {
			definition.inputs.any(it.typ !in ['event', 'slot'] && it.name == name)
		}
		if declared {
			continue
		}
		if property.name.starts_with('bind.') {
			inv.forwarded_binds << r.bind(property, caller, psrc)!
		} else if property.name.starts_with('on_') {
			inv.forwarded_events << r.event(property, caller, psrc)!
		} else {
			inv.forwarded << r.prop(property.name, property.expr, caller, psrc)!
		}
	}
	for decl in def.inputs {
		if decl.event {
			mut listener := r.new_scope(.listener, &caller, unsafe { nil })
			for parameter in decl.params {
				listener.add(parameter.name, Binding{
					kind: .param
					typ:  parameter.typ
				})
			}
			mut handler := &IExpr(unsafe { nil })
			mut hsrc := decl.src
			if property := find_property(n, 'on_' + decl.name) {
				handler = r.handler(property.expr, mut listener, decl.params)!
				hsrc = property_loc(n, property)
			}
			inv.args << IArg{
				name:    decl.name
				typ:     decl.typ
				kind:    .event
				handler: handler
				scope:   listener
				params:  decl.params
				src:     hsrc
			}
			continue
		}
		argument := find_property(n, decl.name)
		binding := find_property(n, 'bind.' + decl.name)
		if argument != none && binding != none {
			return src.error('component input cannot have both value and bind connection')
		}
		if property := binding {
			psrc := property_loc(n, property)
			if !decl.bindable {
				return psrc.error('input `${decl.name}` is not declared bindable')
			}
			if property.expr.kind != .path {
				return psrc.error('`bind.${decl.name}` must target a writable path')
			}
			expr := r.expr(property.expr, caller, false)!
			inv.args << IArg{
				name:     decl.name
				typ:      decl.typ
				kind:     .bound
				expr:     expr
				uses_app: ir_uses_app(expr)
				write:    r.assignment_target(property.expr, caller, psrc)!
				src:      psrc
			}
		} else if property := argument {
			namespace := type_namespace(decl.typ) or { '' }
			helper := namespace.len > 0 && r.is_helper_value(property.expr, caller)
			expr := if helper {
				r.helper_value(property.expr, caller)!
			} else {
				r.expr(property.expr, caller, true)!
			}
			inv.args << IArg{
				name:     decl.name
				typ:      decl.typ
				kind:     .argument
				expr:     expr
				helper:   helper
				uses_app: ir_uses_app(expr)
				src:      property_loc(n, property)
			}
		} else {
			if isnil(decl.default_value) {
				return src.error('required component input `${decl.name}` is missing')
			}
			inv.args << IArg{
				name: decl.name
				typ:  decl.typ
				kind: .default_value
				src:  decl.src
			}
		}
	}
	// Slot content: named `Slot(name: "x") { ... }` blocks, or the children as
	// the `content` slot.
	mut content := map[string][]&Node{}
	if n.children.len > 0 {
		if definition.inputs.filter(it.typ == 'slot').len == 0 {
			return src.error('component `${n.tag}` does not declare a content slot')
		}
		if n.children.any(it.tag == 'Slot') {
			for child in n.children {
				if child.tag != 'Slot' {
					return node_loc(child).error('named slot content requires Slot(name: "name") blocks')
				}
				name := if property := find_property(child, 'name') {
					property.expr.value
				} else {
					'content'
				}
				if !def_declares_slot(definition, name) {
					return node_loc(child).error('unknown component slot `${name}`')
				}
				mut values := content[name] or { []&Node{} }
				values << child.children
				content[name] = values
			}
		} else {
			if !def_declares_slot(definition, 'content') {
				return src.error('implicit content requires a slot named `content`')
			}
			content['content'] = n.children.clone()
		}
	}
	for name, nodes in content {
		slot_path := def.slots[name] or { continue }
		mut slot_scope := r.new_scope(.slot, &caller, unsafe { nil })
		mut resolved := []&INode{cap: nodes.len}
		for index, child in nodes {
			child_path := '${slot_path}.${index}'
			if child.tag == 'Repeater' {
				resolved << r.repeater(child, generated_name(child_path), mut slot_scope,
					true)!
			} else {
				resolved << r.node(child, child_path, mut slot_scope, true)!
			}
		}
		inv.slots[name] = resolved
		inv.slot_scopes[name] = slot_scope
	}
	if property := find_property(n, 'key') {
		inv.key = r.expr(property.expr, caller, true)!
	}
	if property := find_property(n, 'ref') {
		inv.ref = r.ref_target(n, property, caller)!
	}
	mut node := &INode{
		kind:     .component
		tag:      n.tag
		path:     path
		src:      src
		id:       n.id
		invoke:   inv
		relative: relative
	}
	if n.id.len > 0 {
		node.id_binding = caller.add(n.id, Binding{
			kind: .id
		})
		node.id_slot = node.id_binding.slot
	}
	return node
}

// type_namespace is the helper namespace a declared input type names:
// `ui2.StylePatch` is `ui2.style`, the type name without its last word in
// snake case. Types of one word, and composite types, have none.
pub fn type_namespace(typ string) ?string {
	name := typ.trim_left('?&')
	if name.contains('[') || name.contains(' ') {
		return none
	}
	prefix := if name.contains('.') { name.all_before_last('.') + '.' } else { '' }
	base := name.all_after_last('.')
	if base.len == 0 || !base[0].is_capital() {
		return none
	}
	mut words := []string{}
	mut start := 0
	for index in 1 .. base.len {
		if base[index].is_capital() {
			words << base[start..index].to_lower()
			start = index
		}
	}
	if words.len == 0 {
		return none
	}
	return prefix + words.join('_')
}

// ----------------------------------------------------------- helper values

// is_helper_value reports whether a value is built by a helper namespace: a
// list, a bare call that names nothing in scope, or a conditional with such
// an arm. Dotted calls and calls of local functions are V calls.
fn (r &Resolver) is_helper_value(e &Expr, scope &Scope) bool {
	match e.kind {
		.array {
			return true
		}
		.call {
			if e.value.contains('.') {
				return false
			}
			_, _ := scope.lookup_value(e.value) or { return true }
			return false
		}
		.conditional {
			return r.is_helper_value(e.right, scope) || r.is_helper_value(e.third, scope)
		}
		else {
			return false
		}
	}
}

// helper_value resolves a helper value: lists of entries (nested lists
// flatten in order), conditionals choosing between values, helper calls whose
// list arguments are entries of the same namespace, and V values.
fn (mut r Resolver) helper_value(e &Expr, scope &Scope) !&IExpr {
	src := expr_loc(e)
	match e.kind {
		.array {
			mut entries := []&IExpr{cap: e.args.len}
			for item in e.args {
				entries << r.helper_value(item, scope)!
			}
			return &IExpr{
				kind: .array
				args: entries
				src:  src
			}
		}
		.conditional {
			return &IExpr{
				kind: .conditional
				args: [r.expr(e.left, scope, false)!, r.helper_value(e.right, scope)!,
					r.helper_value(e.third, scope)!]
				src:  src
			}
		}
		.call {
			if !r.is_helper_value(e, scope) {
				return r.expr(e, scope, true)
			}
			mut fallible := e.fallible
			mut args := []&IExpr{cap: e.args.len}
			for arg in e.args {
				if arg.kind == .array {
					fallible = true
					args << r.helper_value(arg, scope)!
				} else if arg.kind == .literal && arg.quoted && is_hex_color(arg.value) {
					// A quoted `"#RRGGBB"` helper argument is a color, as `#RRGGBB` is.
					args << &IExpr{
						kind: .color
						name: arg.value
						src:  expr_loc(arg)
					}
				} else {
					args << r.expr(arg, scope, true)!
				}
			}
			return &IExpr{
				kind:     .helper
				name:     e.value
				args:     args
				fallible: fallible
				src:      src
			}
		}
		else {
			return r.expr(e, scope, true)
		}
	}
}

pub fn is_hex_color(value string) bool {
	if !value.starts_with('#') || value.len !in [7, 9] {
		return false
	}
	return value[1..].bytes().all(it.is_hex_digit())
}

// ------------------------------------------------------------- expressions

// expr resolves a value expression. `enums` allows a bare unknown name, which
// is an enum value of the value's type (`align: center`).
fn (mut r Resolver) expr(e &Expr, scope &Scope, enums bool) !&IExpr {
	src := expr_loc(e)
	match e.kind {
		.literal {
			return literal_expr(e, src)
		}
		.path {
			return r.path(e, scope, enums)
		}
		.call {
			return r.call(e, scope)
		}
		.unary {
			operand := r.expr(e.left, scope, false)!
			return &IExpr{
				kind: if e.value == '!' { IKind.not_ } else { IKind.negate }
				args: [operand]
				src:  src
			}
		}
		.binary {
			left := r.expr(e.left, scope, true)!
			right := r.expr(e.right, scope, true)!
			kind := match e.value {
				'&&' { IKind.and_ }
				'||' { IKind.or_ }
				else { IKind.binary }
			}
			return &IExpr{
				kind: kind
				name: e.value
				args: [left, right]
				src:  src
			}
		}
		.conditional {
			return &IExpr{
				kind: .conditional
				args: [r.expr(e.left, scope, false)!, r.expr(e.right, scope, enums)!,
					r.expr(e.third, scope, enums)!]
				src:  src
			}
		}
		.array {
			mut items := []&IExpr{cap: e.args.len}
			for arg in e.args {
				items << r.expr(arg, scope, enums)!
			}
			return &IExpr{
				kind: .array
				args: items
				src:  src
			}
		}
		.interpolation {
			mut parts := []&IExpr{cap: e.parts.len}
			for part in e.parts {
				if isnil(part.expr) {
					parts << &IExpr{
						kind:    .literal
						literal: .string
						value:   part.text
						src:     src
					}
				} else {
					parts << r.expr(part.expr, scope, false)!
				}
			}
			return &IExpr{
				kind: .interp
				args: parts
				src:  src
			}
		}
		.assignment {
			return src.error('an assignment is only valid in an event handler')
		}
		.block {
			return src.error('a `{ ... }` block is only valid in an event handler')
		}
	}
}

fn literal_expr(e &Expr, src Location) !&IExpr {
	if e.quoted {
		return &IExpr{
			kind:    .literal
			literal: .string
			value:   e.value
			src:     src
		}
	}
	if e.value in ['true', 'false'] {
		return &IExpr{
			kind:    .literal
			literal: .bool
			value:   e.value
			src:     src
		}
	}
	if e.value.contains('.') {
		if e.value.count('.') > 1 {
			return src.error('invalid literal `${e.value}`')
		}
		return &IExpr{
			kind:    .literal
			literal: .float
			value:   e.value
			src:     src
		}
	}
	if e.value.len == 0 || !e.value.bytes().all(it.is_digit()) {
		return src.error('invalid literal `${e.value}`')
	}
	return &IExpr{
		kind:    .literal
		literal: .int
		value:   e.value
		src:     src
	}
}

fn (mut r Resolver) path(e &Expr, scope &Scope, enums bool) !&IExpr {
	src := expr_loc(e)
	value := e.value
	if value.starts_with('.') && value.len > 1 && !value[1..].contains('.') {
		return src.error('VML enum values omit the dot: use `${value[1..]}`')
	}
	if value.starts_with('#') {
		if is_hex_color(value) {
			return &IExpr{
				kind: .color
				name: value
				src:  src
			}
		}
		return src.error('invalid color `${value}`; colors are #RRGGBB')
	}
	parts := value.split('.')
	if parts.any(it.len == 0) {
		return src.error('invalid name `${value}`')
	}
	root := parts[0]
	if root in ['color', 'spacing', 'radius', 'typography'] && parts.len > 1 {
		token := token_name(value) or {
			return src.error('`${value}` is not a theme token; write `${root}.name`')
		}
		add_tokens(scope, [token])
		return &IExpr{
			kind: .token
			name: token
			src:  src
		}
	}
	if root == 'app' {
		if parts.len == 1 {
			return src.error('`app` is not a value; read one of its fields')
		}
		r.uses_app = true
		base := &IExpr{
			kind: .app_field
			name: parts[1]
			src:  src
		}
		return members(base, parts[2..], src)
	}
	found := if parts.len == 1 { scope.lookup_value(root) } else { scope.lookup(root) }
	if binding, depth := found {
		match binding.kind {
			.id {
				if parts.len == 2 && parts[1] in geometry_fields {
					return &IExpr{
						kind:    .geometry
						name:    parts[1]
						binding: binding
						depth:   depth
						src:     src
					}
				}
				return src.error('`${value}`: an element id exposes only x, y, width and height')
			}
			else {
				// Functions, events and refs are values too: a ref can be passed to
				// a model method (`app.remember(target)`).
				base := &IExpr{
					kind:    .binding
					binding: binding
					depth:   depth
					src:     src
				}
				return members(base, parts[1..], src)
			}
		}
	}
	if parts.len > 1 {
		// A dotted name of no VML value: a V constant or enum the module can see.
		return &IExpr{
			kind: .external
			name: value
			src:  src
		}
	}
	if enums {
		return &IExpr{
			kind: .enum_name
			name: value
			src:  src
		}
	}
	return src.error('unknown name `${root}`')
}

// members applies `.field` and `.len` reads.
fn members(base &IExpr, names []string, src Location) &IExpr {
	mut current := unsafe { base }
	for name in names {
		current = &IExpr{
			kind: if name == 'len' { IKind.length } else { IKind.member }
			name: name
			args: [current]
			src:  src
		}
	}
	return current
}

fn (mut r Resolver) call(e &Expr, scope &Scope) !&IExpr {
	src := expr_loc(e)
	value := e.value
	parts := value.split('.')
	mut args := []&IExpr{cap: e.args.len}
	if parts.len == 2 && parts[0] == 'app' {
		r.uses_app = true
		for arg in e.args {
			args << r.expr(arg, scope, true)!
		}
		return &IExpr{
			kind:     .app_call
			name:     parts[1]
			args:     args
			fallible: e.fallible
			src:      src
		}
	}
	if parts.len >= 2 && parts.last() == 'str' && e.args.len == 0 {
		base := r.path(&Expr{
			...e
			kind:  .path
			value: parts[..parts.len - 1].join('.')
		}, scope, false)!
		return &IExpr{
			kind: .to_str
			args: [base]
			src:  src
		}
	}
	if parts.len == 2 {
		if binding, depth := scope.lookup(parts[0]) {
			if binding.kind == .ref {
				for arg in e.args {
					args << r.expr(arg, scope, false)!
				}
				method := parts[1]
				arity := ref_methods[method] or {
					return src.error('a ref has no method `${method}`; refs have is_available, focus, set_text, id and element')
				}
				if args.len != arity {
					return src.error('`${value}` takes ${arity} argument(s), not ${args.len}')
				}
				return &IExpr{
					kind:     .ref_call
					name:     method
					binding:  binding
					depth:    depth
					args:     args
					fallible: e.fallible
					src:      src
				}
			}
		}
	}
	if parts.len == 1 {
		if binding, depth := scope.lookup_value(value) {
			for arg in e.args {
				args << r.expr(arg, scope, true)!
			}
			match binding.kind {
				.func {
					if args.len != binding.params.len {
						return src.error('`${value}` takes ${binding.params.len} argument(s), not ${args.len}')
					}
					return &IExpr{
						kind:    .fn_call
						binding: binding
						depth:   depth
						args:    args
						src:     src
					}
				}
				.event {
					if args.len != binding.params.len {
						return src.error('event `${value}` takes ${binding.params.len} payload value(s), not ${args.len}')
					}
					return &IExpr{
						kind:    .emit
						binding: binding
						depth:   depth
						args:    args
						src:     src
					}
				}
				else {
					return src.error('`${value}` is not a function')
				}
			}
		}
	}
	for arg in e.args {
		args << r.expr(arg, scope, true)!
	}
	// A call of no VML function: a function of the module the document is
	// generated into (or a helper, where the value is a helper value).
	if value !in r.module_functions {
		r.module_functions << value
	}
	return &IExpr{
		kind:     .module_call
		name:     value
		args:     args
		fallible: e.fallible
		src:      src
	}
}

// ---------------------------------------------------------------- handlers

// handler resolves an event handler: a reference (`app.save`, a component
// function or event, a module function) or an action. `payload` are the
// parameters of the component event it handles.
fn (mut r Resolver) handler(e &Expr, mut scope Scope, payload []Parameter) !&IExpr {
	src := expr_loc(e)
	if e.kind != .path {
		return r.action(e, scope)
	}
	value := e.value
	parts := value.split('.')
	if parts.len == 2 && parts[0] == 'app' {
		r.uses_app = true
		return &IExpr{
			kind: .app_method
			name: parts[1]
			src:  src
		}
	}
	if parts.len == 1 {
		if binding, depth := scope.lookup_value(value) {
			match binding.kind {
				.func {
					return &IExpr{
						kind:    .fn_ref
						binding: binding
						depth:   depth
						src:     src
					}
				}
				.event {
					return &IExpr{
						kind:    .event_ref
						binding: binding
						depth:   depth
						src:     src
					}
				}
				else {
					return src.error('`${value}` is not callable')
				}
			}
		}
		if value !in r.module_functions {
			r.module_functions << value
		}
		return &IExpr{
			kind: .module_fn
			name: value
			src:  src
		}
	}
	return &IExpr{
		kind: .external
		name: value
		src:  src
	}
}

// action resolves a statement: an assignment, a call or a block.
fn (mut r Resolver) action(e &Expr, scope &Scope) !&IExpr {
	src := expr_loc(e)
	match e.kind {
		.block {
			mut statements := []&IExpr{cap: e.args.len}
			for statement in e.args {
				statements << r.action(statement, scope)!
			}
			return &IExpr{
				kind: .block
				args: statements
				src:  src
			}
		}
		.assignment {
			target := r.assignment_target(e.left, scope, src)!
			value := r.expr(e.right, scope, true)!
			return &IExpr{
				...target
				args: [value]
			}
		}
		else {
			return r.expr(e, scope, true)
		}
	}
}

// assignment_target resolves a writable target: a top-level `app` field, a
// component state or a bindable component input.
fn (mut r Resolver) assignment_target(e &Expr, scope &Scope, src Location) !&IExpr {
	if e.kind != .path {
		return src.error('assignment target must be a name')
	}
	value := e.value
	parts := value.split('.')
	if parts.len == 2 && parts[0] == 'app' {
		r.uses_app = true
		return &IExpr{
			kind: .assign_app
			name: parts[1]
			src:  src
		}
	}
	if parts.len == 1 {
		if binding, depth := scope.lookup_value(value) {
			if binding.kind == .state || (binding.kind == .input && binding.writable) {
				return &IExpr{
					kind:    .assign_binding
					binding: binding
					depth:   depth
					src:     src
				}
			}
		}
	}
	return src.error('VML target `${value}` is read-only or unknown; use state or an explicit bind connection')
}

// ------------------------------------------------------------ static facts

// ir_reactive reports whether an expression reads anything that can change:
// the model, a scope value, an element's geometry or a theme token.
pub fn ir_reactive(e &IExpr) bool {
	if e.kind in [.app_field, .binding, .geometry, .token, .app_call, .fn_call, .ref_call, .emit] {
		return true
	}
	for arg in e.args {
		if ir_reactive(arg) {
			return true
		}
	}
	return false
}

// ir_uses_app reports whether an expression reads or writes the model.
pub fn ir_uses_app(e &IExpr) bool {
	if e.kind in [.app_field, .app_call, .app_method, .assign_app] {
		return true
	}
	for arg in e.args {
		if ir_uses_app(arg) {
			return true
		}
	}
	return false
}

// ir_uses_theme reports whether an expression reads a theme token.
pub fn ir_uses_theme(e &IExpr) bool {
	if e.kind == .token {
		return true
	}
	for arg in e.args {
		if ir_uses_theme(arg) {
			return true
		}
	}
	return false
}
