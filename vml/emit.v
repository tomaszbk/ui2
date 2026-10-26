module vml

import os
import strings

// The emitter prints the IR (ir.v) as V. Every `.vml` file becomes one V file:
// a document file holds its builders, `<name>_vml[A](mut app A)` and
// `<name>_vml_framed[A](mut app A, frame)`, and every file holds one builder
// function per component it declares, `vmlc_<file>_<Name>`. A component is
// emitted once and instantiated by calls: its invocations pass their
// arguments, event handlers, slot content and the properties the component
// does not declare as closures of the caller's scope in a `Vmlc...Args`
// value. Builders are generic over the model, so the emitter never needs the
// model's type; V checks every `app.x` for each caller. `#line` directives map
// V's errors in the generated code to the document line that produced them.

const runtime_module = 'ui2'

// GenFile is one generated V file: the `.vml` file it comes from and its code.
pub struct GenFile {
pub:
	// The base name of the generated file (`counter` for counter.vml).
	name   string
	source string
	code   string
}

// generate_files resolves the document at `path` and returns the V file of
// the document and of every file whose components it uses.
pub fn generate_files(path string, config GenConfig) ![]GenFile {
	library := parse_library(path, validate_document: validate_vml_document)!
	program := resolve_library(library)!
	return emit_program(program, library, config)
}

fn emit_program(program &Program, library &Library, config GenConfig) ![]GenFile {
	mut e := Emitter{
		program: program
		library: library
		config:  config
	}
	e.analyze()
	mut sources := []string{}
	sources << program.path
	for _, def in program.components {
		if def.source !in sources {
			sources << def.source
		}
	}
	mut files := []GenFile{}
	for source in sources {
		mut code := e.file(source)!
		if config.module == runtime_module {
			code = unqualify_runtime(code)
		}
		files << GenFile{
			name:   if source == program.path && config.name.len > 0 {
				config.name
			} else {
				builder_base_name(source)
			}
			source: source
			code:   if config.dir.len > 0 {
				code.replace(os.real_path(config.dir) + os.path_separator, '')
			} else {
				code
			}
		}
	}
	return files
}

// unqualify_runtime drops the `ui2.` qualifier from code generated into
// module ui2 itself (its test fixtures), where the runtime's names are local.
fn unqualify_runtime(code string) string {
	prefix := runtime_module + '.'
	mut out := strings.new_builder(code.len)
	mut i := 0
	for i < code.len {
		if code[i] == prefix[0] && i + prefix.len <= code.len && code[i..i + prefix.len] == prefix
			&& (i == 0 || !(code[i - 1].is_letter() || code[i - 1].is_digit()
			|| code[i - 1] in [`_`, `.`])) {
			i += prefix.len
			continue
		}
		out.write_u8(code[i])
		i++
	}
	return out.str()
}

struct Emitter {
	program &Program = unsafe { nil }
	library &Library = unsafe { nil }
	config  GenConfig
mut:
	out              strings.Builder
	location         Location
	locations        []Location
	guards           []VmlGuard
	guard_prefix     string
	checks           map[string]bool
	uses_unreachable bool
	// Definitions that need the model, directly or through what they use.
	needs_app map[string]bool
	// The handle type of the parent of every slot, by definition and slot.
	slot_parents map[string]string
	// The props type of every definition's root element.
	root_props map[string]string
	// Constant helper values of the file being emitted, by their code.
	constants      map[string]string
	constant_decls []Constant
}

// Constant is a helper value that reads nothing: a module constant, computed
// once when the program starts.
struct Constant {
	name     string
	code     string
	location Location
}

// Var is a value the generated code declared, as a capture candidate.
struct Var {
	name    string
	mutable bool
}

// Ctx is where code is being generated: a builder body, or a closure in one.
struct Ctx {
mut:
	// The component owner variable of the current owner scope.
	owner string
	// V expression of the instance path; empty for document paths.
	base string
	// The definition being emitted, and its args value.
	def  &IComponentDef = unsafe { nil }
	args string
	// Binding (`scope:slot`) to its V names.
	values map[string]Value
	// Every declared variable, for closure captures.
	visible []Var
	// The model is available.
	app bool
}

struct Value {
	read   string // the value: `s_count.get() or { panic(err) }`, `n_0_1`, `name`
	signal string // the signal variable, for state and inputs
	setter string // the writer of a writable value: a state signal's `.set` or an input setter
	node   string // an element id: its node variable
}

fn binding_key(binding Binding) string {
	return '${binding.scope_id}:${binding.slot}'
}

fn (c Ctx) clone() Ctx {
	return Ctx{
		owner:   c.owner
		base:    c.base
		def:     c.def
		args:    c.args
		values:  c.values.clone()
		visible: c.visible.clone()
		app:     c.app
	}
}

fn (mut c Ctx) declare(name string, mutable bool) {
	c.visible << Var{
		name:    name
		mutable: mutable
	}
}

fn (c &Ctx) candidates() []string {
	mut out := []string{cap: c.visible.len + 1}
	if c.app {
		out << 'mut app'
	}
	for v in c.visible {
		out << if v.mutable { 'mut ${v.name}' } else { v.name }
	}
	return out
}

// closure captures, from `candidates`, the names `body` reads.
fn (c &Ctx) captures(body string) string {
	return vml_used_captures(body, c.candidates()).join(', ')
}

// ---------------------------------------------------------------- analysis

fn (mut e Emitter) analyze() {
	for key, _ in e.program.components {
		e.def_needs_app(key, []string{})
	}
	for key, def in e.program.components {
		e.root_props[key] = e.node_root_props(def.root)
		e.collect_slot_parents(key, def.root, '')
	}
}

fn (mut e Emitter) def_needs_app(key string, stack []string) bool {
	if needed := e.needs_app[key] {
		return needed
	}
	def := e.program.components[key] or { return false }
	if def.uses_app || key in stack {
		e.needs_app[key] = def.uses_app
		return def.uses_app
	}
	mut next := stack.clone()
	next << key
	needed := e.node_needs_app(def.root, next)
	e.needs_app[key] = needed
	return needed
}

fn (mut e Emitter) node_needs_app(n &INode, stack []string) bool {
	if n.kind == .component {
		if e.def_needs_app(n.invoke.def_key, stack) {
			return true
		}
		for _, nodes in n.invoke.slots {
			for child in nodes {
				if e.node_needs_app(child, stack) {
					return true
				}
			}
		}
		return false
	}
	if n.kind == .repeater {
		for child in n.repeat.children {
			if e.node_needs_app(child, stack) {
				return true
			}
		}
		return false
	}
	if n.kind == .cond {
		for branch in n.cond.branches {
			for child in branch.children {
				if e.node_needs_app(child, stack) {
					return true
				}
			}
		}
		return false
	}
	for child in n.children {
		if e.node_needs_app(child, stack) {
			return true
		}
	}
	return false
}

fn (e &Emitter) node_root_props(n &INode) string {
	if n.kind == .component {
		def := e.program.components[n.invoke.def_key] or { return 'ui2.ViewProps' }
		return e.node_root_props(def.root)
	}
	return props_type(n.tag)
}

fn (mut e Emitter) collect_slot_parents(key string, n &INode, parent string) {
	if n.kind == .slot {
		e.slot_parents['${key}#${n.tag}'] = parent
		return
	}
	if n.kind == .repeater {
		for child in n.repeat.children {
			e.collect_slot_parents(key, child, 'ui2.VmlSegment')
		}
		return
	}
	if n.kind == .cond {
		for branch in n.cond.branches {
			for child in branch.children {
				e.collect_slot_parents(key, child, 'ui2.VmlSegment')
			}
		}
		return
	}
	if n.kind == .component {
		return
	}
	handle := 'ui2.VmlWidgetNode[${props_type(n.tag)}]'
	for child in n.children {
		e.collect_slot_parents(key, child, handle)
	}
}

// props_type names the props type of a tag: `Slider` is `ui2.SliderProps` and a
// dotted tag `pkg.Gauge` names `pkg.GaugeProps` in the caller's imports.
fn props_type(tag string) string {
	if tag.contains('.') {
		return tag.all_before_last('.') + '.' + tag.all_after_last('.') + 'Props'
	}
	return '${runtime_module}.${tag}Props'
}

// def_function names the builder function of a definition.
fn def_function(def &IComponentDef) string {
	file := builder_base_name(def.source)
	name := snake_name(def.name)
	return if name == file { 'vmlc_${file}' } else { 'vmlc_${file}_${name}' }
}

fn def_args_type(def &IComponentDef) string {
	return pascal_name(def_function(def)) + 'Args'
}

fn snake_name(name string) string {
	mut out := strings.new_builder(name.len + 4)
	for index, ch in name {
		if ch.is_capital() {
			if index > 0 {
				out.write_u8(`_`)
			}
			out.write_u8(ch + 32)
		} else if ch.is_letter() || ch.is_digit() {
			out.write_u8(ch)
		} else {
			out.write_u8(`_`)
		}
	}
	return out.str()
}

// pascal_name is `vmlc_todo_item` as `VmlcTodoItem`.
fn pascal_name(s string) string {
	mut out := []u8{cap: s.len}
	mut upper := true
	for ch in s {
		if ch == `_` {
			upper = true
			continue
		}
		if upper && ch >= `a` && ch <= `z` {
			out << ch - 32
		} else {
			out << ch
		}
		upper = false
	}
	return out.bytestr()
}

// ---------------------------------------------------------------- files

fn (mut e Emitter) begin(source string) {
	e.out = strings.new_builder(8192)
	e.locations = []Location{}
	e.guards = []VmlGuard{}
	e.checks = map[string]bool{}
	e.uses_unreachable = false
	e.guard_prefix = 'vml_check_${builder_base_name(source)}'
	e.constants = map[string]string{}
	e.constant_decls = []Constant{}
}

fn (mut e Emitter) writeln(line string) {
	e.out.writeln(line)
	for _ in 0 .. line.count('\n') + 1 {
		e.locations << e.location
	}
}

// cont writes lines that continue a statement (fields of a literal and its
// closing line): V accepts no `#line` directive among them.
fn (mut e Emitter) cont(line string) {
	e.out.writeln(line)
	for _ in 0 .. line.count('\n') + 1 {
		e.locations << Location{}
	}
}

fn (mut e Emitter) at(l Location) {
	e.location = l
}

fn (mut e Emitter) file(source string) !string {
	mut functions := strings.new_builder(16384)
	mut function_locations := []Location{}
	mut defs := []&IComponentDef{}
	for _, def in e.program.components {
		if def.source == source {
			defs << def
		}
	}
	defs.sort(a.name < b.name)
	e.begin(source)
	mut type_decls := []string{}
	for def in defs {
		type_decls << e.args_type(def)
		e.def_builder(def)!
		functions.write_string(e.out.str())
		function_locations << e.locations
		e.out = strings.new_builder(8192)
		e.locations = []Location{}
	}
	if source == e.program.path {
		e.document_builder()!
		functions.write_string(e.out.str())
		function_locations << e.locations
		e.out = strings.new_builder(8192)
		e.locations = []Location{}
	}
	body := functions.str()
	e.write_list_guards()
	guards := e.out.str()
	guard_locations := e.locations.clone()
	mut out := strings.new_builder(body.len + guards.len + 2048)
	out.writeln('// Code generated by `ui2 gen` from ${os.file_name(source)}. DO NOT EDIT.')
	out.writeln('module ${e.config.module}')
	out.writeln('')
	if e.config.module != runtime_module {
		out.writeln('import ui2')
		out.writeln('')
	}
	for decl in type_decls {
		out.writeln(decl)
	}
	if e.constant_decls.len > 0 {
		mut constants := strings.new_builder(1024)
		mut constant_locations := []Location{}
		for constant in e.constant_decls {
			constants.writeln('const ${constant.name} = ${constant.code}')
			constant_locations << constant.location
		}
		vml_write_mapped(mut out, constants.str(), constant_locations)
		out.writeln('')
	}
	if guards.len > 0 {
		vml_write_mapped(mut out, guards, guard_locations)
		out.writeln('')
	}
	vml_write_mapped(mut out, body, function_locations)
	return out.str()
}

// ---------------------------------------------------------------- builders

fn (mut e Emitter) document_builder() ! {
	program := e.program
	name := if e.config.name.len > 0 { e.config.name } else { builder_base_name(program.path) }
	document := os.file_name(program.path)
	app := program.uses_app || e.node_needs_app(program.root, []string{})
	e.at(program.root.src)
	if app {
		e.writeln('// ${name}_vml builds ${document} for the model `app`, following the window.')
		e.writeln('pub fn ${name}_vml[A](mut app A) ui2.Element {')
		e.writeln('\treturn ${name}_vml_build(mut app, ui2.vml_bounds(), true)')
		e.writeln('}')
		e.writeln('')
		e.writeln('// ${name}_vml_framed builds ${document} for the model `app` in a fixed frame.')
		e.writeln('pub fn ${name}_vml_framed[A](mut app A, frame ui2.Rect) ui2.Element {')
		e.writeln('\treturn ${name}_vml_build(mut app, frame, false)')
		e.writeln('}')
		e.writeln('')
		e.writeln('fn ${name}_vml_build[A](mut app A, vml_template_frame ui2.Rect, vml_follow_viewport bool) ui2.Element {')
	} else {
		e.writeln('// ${name}_vml builds ${document}, following the window.')
		e.writeln('pub fn ${name}_vml() ui2.Element {')
		e.writeln('\treturn ${name}_vml_build(ui2.vml_bounds(), true)')
		e.writeln('}')
		e.writeln('')
		e.writeln('// ${name}_vml_framed builds ${document} in a fixed frame.')
		e.writeln('pub fn ${name}_vml_framed(frame ui2.Rect) ui2.Element {')
		e.writeln('\treturn ${name}_vml_build(frame, false)')
		e.writeln('}')
		e.writeln('')
		e.writeln('fn ${name}_vml_build(vml_template_frame ui2.Rect, vml_follow_viewport bool) ui2.Element {')
	}
	start := e.out.len
	start_line := e.locations.len
	e.dev_build(app)
	e.writeln('\tmut vml_doc := ui2.vml_document(vml_template_frame, follow_viewport: vml_follow_viewport) or { panic(err) }')
	e.writeln('\tmut vml_root_component := vml_doc.owner')
	mut ctx := Ctx{
		owner: 'vml_root_component'
		app:   app
	}
	ctx.declare('vml_root_component', true)
	e.prepare_tokens(program.scope, ctx.owner)
	e.refs(program.refs, program.scope, mut ctx)
	e.node(program.root, 'vml_doc', 'ui2.VmlDocument', mut ctx, RootHooks{})!
	e.at(program.root.src)
	e.writeln('\treturn vml_doc.finish() or { panic(err) }')
	e.writeln('}')
	e.writeln('')
	if app {
		e.genericize(start, start_line)
	}
}

// dev_build lets a development build (`ui2 dev`: -d vml_interpreter
// -d ui2_dev) build the document with the interpreter from its file, which
// reloads it when the file changes; a document the interpreter cannot run is
// built compiled.
fn (mut e Emitter) dev_build(app bool) {
	program := e.program
	mut callbacks := []string{}
	for name in program.module_callbacks {
		callbacks << '${vml_quote(name)}: ui2.vml_callback(${name}, refresh: false)'
	}
	callback_map := if callbacks.len == 0 {
		'map[string]ui2.ElementCallback{}'
	} else {
		'{' + callbacks.join(', ') + '}'
	}
	path := 'ui2.vml_dev_path(@DIR, ${vml_quote(program.path)})'
	call := if app {
		'ui2.vml_dev_build(mut app, ${path}, vml_template_frame, vml_follow_viewport, ${callback_map})'
	} else {
		'ui2.vml_dev_build_static(${path}, vml_template_frame, vml_follow_viewport, ${callback_map})'
	}
	e.writeln('\t\$if ui2_dev ? {')
	e.writeln('\t\t\$if vml_interpreter ? {')
	e.writeln('\t\t\tif vml_dev_element := ${call} {')
	e.writeln('\t\t\t\treturn vml_dev_element')
	e.writeln('\t\t\t}')
	e.writeln('\t\t}')
	e.writeln('\t}')
}

// genericize gives the model's type parameter to every closure written since
// `start` that captures `app`: a closure over a generic value is generic.
fn (mut e Emitter) genericize(start int, start_line int) {
	_ = start_line
	text := e.out.cut_to(start)
	e.out.write_string(vml_generic_closures(text))
}

fn (mut e Emitter) prepare_tokens(scope &Scope, owner string) {
	if scope.tokens.len > 0 {
		e.writeln('\t${owner}.prepare_theme_tokens(' +
			vml_array_literal('string', scope.tokens.map(vml_quote(it))) + ') or { panic(err) }')
	}
}

// args_type declares the arguments a definition's invocations pass.
fn (mut e Emitter) args_type(def &IComponentDef) string {
	root := e.root_props[def.key] or { 'ui2.ViewProps' }
	mut out := strings.new_builder(512)
	out.writeln('// ${def_args_type(def)} is what an invocation of `${def.name}` passes: the')
	out.writeln('// inputs it supplies, its event handlers, slot content and root configuration.')
	out.writeln('pub struct ${def_args_type(def)} {')
	out.writeln('pub:')
	out.writeln('\tkey string')
	for decl in def.inputs {
		if decl.event {
			signature := decl.params.map('${it.name} ${it.typ}').join(', ')
			out.writeln('\t${decl.name} fn (${signature}) = unsafe { nil }')
			continue
		}
		out.writeln('\t${decl.name} fn () !${input_storage(decl.typ)} = unsafe { nil }')
		if decl.bindable {
			out.writeln('\t${decl.name}_write fn (${decl.typ}) ! = unsafe { nil }')
		}
	}
	definition := e.library.components[def.key] or { unsafe { nil } }
	if !isnil(definition) {
		for input in definition.inputs {
			if input.typ != 'slot' {
				continue
			}
			parent := e.slot_parents['${def.key}#${input.name}'] or { 'ui2.VmlSegment' }
			out.writeln('\tslot_${input.name} fn (mut ui2.CompiledVmlComponent, mut ${parent}, string) ! = unsafe { nil }')
		}
	}
	out.writeln('\tforward fn (mut ${root}) = unsafe { nil }')
	out.writeln('\tforward_after fn (mut ui2.VmlWidgetNode[${root}]) ! = unsafe { nil }')
	out.writeln('}')
	out.writeln('')
	return out.str()
}

fn (mut e Emitter) def_builder(def &IComponentDef) ! {
	app := e.needs_app[def.key] or { false }
	root := e.root_props[def.key] or { 'ui2.ViewProps' }
	fname := def_function(def)
	e.at(def.src)
	e.writeln('// ${fname} builds an instance of `${def.name}` under `parent` at `path`.')
	model_param := if app { 'mut app A, ' } else { '' }
	generics := if app { '[A, N]' } else { '[N]' }
	e.writeln('pub fn ${fname}${generics}(${model_param}mut parent N, mut caller ui2.CompiledVmlComponent, path string, args ${def_args_type(def)}) !&ui2.VmlWidgetNode[${root}] {')
	start := e.out.len
	start_line := e.locations.len
	e.writeln('\tmut owner := caller.child(path)!')
	mut ctx := Ctx{
		owner: 'owner'
		base:  'path'
		def:   def
		args:  'args'
		app:   app
	}
	ctx.declare('owner', true)
	ctx.declare('args', false)
	ctx.declare('path', false)
	e.prepare_tokens(def.scope, 'owner')
	e.def_inputs(def, mut ctx)
	e.def_members(def, mut ctx)
	hooks := RootHooks{
		key:           'args.key'
		forward:       'args.forward'
		forward_after: 'args.forward_after'
	}
	root_var := e.node(def.root, 'parent', '', mut ctx, hooks)!
	e.at(def.src)
	e.writeln('\treturn ${root_var}')
	e.writeln('}')
	e.writeln('')
	if app {
		e.genericize(start, start_line)
	}
}

fn (mut e Emitter) def_inputs(def &IComponentDef, mut ctx Ctx) {
	for decl in def.inputs {
		e.at(decl.src)
		key := '${def.scope.id}:${decl.slot}'
		if decl.event {
			variable := 'e_${decl.name}'
			signature := decl.params.map('${it.name} ${it.typ}').join(', ')
			mut noop := 'fn (${signature}) {'
			for parameter in decl.params {
				noop += ' _ = ${parameter.name}'
			}
			noop += ' }'
			e.writeln('\t${variable} := if args.${decl.name} == unsafe { nil } { ${noop} } else { args.${decl.name} }')
			ctx.values[key] = Value{
				read: variable
			}
			ctx.declare(variable, false)
			continue
		}
		variable := 'i_${decl.name}'
		storage := input_storage(decl.typ)
		mut fallback := '\'\''
		mut default_body := ''
		if !isnil(decl.default_value) {
			value := if decl.default_helper {
				namespace := type_namespace(decl.typ) or { '' }
				e.constant_helper(decl.default_value, namespace, ctx)
			} else {
				e.expr(decl.default_value, ctx)
			}
			default_body = 'return ${input_value(decl.typ, value)}'
			fallback = value
		} else if decl.typ.starts_with('?') {
			default_body = 'return ${storage}{}'
		} else {
			default_body = "return error('component input `${decl.name}` is required')"
		}
		_ = fallback
		// A supplied input is one memo of the caller's value: the state starts
		// from it and follows it, so the caller's expression is evaluated once.
		memo := '${variable}_memo'
		e.writeln('\tmut ${memo} := if args.${decl.name} != unsafe { nil } { owner.computed(' +
			vml_quote('@input:' + decl.name) + ', args.${decl.name}) or { panic(err) } } else { &${runtime_module}.Memo[${storage}](unsafe { nil }) }')
		ctx.declare(memo, true)
		body := 'if args.${decl.name} != unsafe { nil } { return ${memo}.get()! } ${default_body}'
		e.writeln('\tmut ${variable} := owner.state_factory(' + vml_quote(decl.name) + ', fn [${ctx.captures(body)}] () !${storage} { ${body} }) or { panic(err) }')
		e.writeln('\tif args.${decl.name} != unsafe { nil } {')
		e.writeln('\t\towner.scope.effect(' + vml_quote('@input:' + decl.name) + ', fn [mut ${memo}, mut ${variable}] () ! { ${variable}.set(${memo}.get()!)! }) or { panic(err) }')
		e.writeln('\t}')
		mut setter := ''
		if decl.bindable {
			setter = '${variable}_write'
			e.writeln('\t${setter} := fn [args, mut ${variable}] (value ${decl.typ}) ! { if args.${decl.name}_write != unsafe { nil } { args.${decl.name}_write(value)! } ${variable}.set(value)! }')
			ctx.declare(setter, false)
		}
		read := if decl.typ.starts_with('?') {
			'(${variable}.get() or { panic(err) }).option()'
		} else {
			'${variable}.get() or { panic(err) }'
		}
		ctx.values[key] = Value{
			read:   read
			signal: variable
			setter: setter
		}
		ctx.declare(variable, true)
	}
	e.refs(def.refs, def.scope, mut ctx)
}

// input_storage is the type an input of type `typ` is kept as: an optional
// `?T` is a `VmlOption[T]`, since V has no signals or results of options.
fn input_storage(typ string) string {
	if typ.starts_with('?') {
		return '${runtime_module}.VmlOption[${typ[1..]}]'
	}
	return typ
}

// input_value converts `value`, of type `typ`, to its input storage.
fn input_value(typ string, value string) string {
	if typ.starts_with('?') {
		return '${runtime_module}.vml_option[${typ[1..]}](${value})'
	}
	return value
}

// refs declares the refs of the element ids whose methods the code calls;
// each element binds its ref when it is declared.
fn (mut e Emitter) refs(refs []IRef, scope &Scope, mut ctx Ctx) {
	for reference in refs {
		variable := 'r_${reference.name}'
		e.writeln('\tmut ${variable} := ${ctx.owner}.ref[${props_type(reference.tag)}](' +
			vml_quote(reference.name) + ') or { panic(err) }')
		for method in reference.methods {
			if method.name in ref_command_targets {
				e.at(method.src)
				name := '${e.guard_prefix}_ref_${e.guards.len}'
				e.guards << VmlGuard{
					name:       name
					ref_method: method.name
					location:   e.location
				}
				e.uses_unreachable = true
				e.writeln('\tif ${e.guard_prefix}_unreachable() { ${name}(${variable}) }')
			}
		}
		ctx.values['${scope.id}:${reference.slot}'] = Value{
			read: variable
		}
		ctx.declare(variable, false)
	}
}

// ref_command_targets are the props types whose elements take each ref command.
const ref_command_targets = {
	'focus':    ['ButtonProps', 'ViewProps', 'DialogProps', 'PopoverProps', 'MenuOverlayProps',
		'ContextMenuProps', 'TooltipProps', 'TextInputProps', 'TextAreaProps', 'CheckboxProps',
		'DropdownProps', 'SliderProps', 'SwitchProps', 'ToggleButtonProps']
	'set_text': ['TextInputProps', 'TextAreaProps']
}

fn (mut e Emitter) def_members(def &IComponentDef, mut ctx Ctx) {
	for data in def.data {
		e.at(data.src)
		e.model_path_checks(data.expr, ctx)
		e.at(data.src)
		value := e.expr(data.expr, ctx)
		key := '${def.scope.id}:${data.slot}'
		if data.computed {
			variable := 'c_${data.name}'
			dependency := if data.uses_app { 'owner.watch_app()!; ' } else { '' }
			body := '${dependency}return ${value}'
			mut captures := ctx.captures(body)
			if data.uses_app || ir_uses_theme(data.expr) {
				captures = add_capture(captures, 'mut owner')
			}
			e.writeln('\tmut ${variable} := owner.computed(' + vml_quote(data.name) +
				', fn [${captures}] () !typeof(${value}) { ${body} }) or { panic(err) }')
			ctx.values[key] = Value{
				read:   '${variable}.get() or { panic(err) }'
				signal: variable
			}
			ctx.declare(variable, true)
		} else {
			variable := 's_${data.name}'
			mut captures := ctx.captures(value)
			if ir_uses_theme(data.expr) {
				captures = add_capture(captures, 'mut owner')
			}
			e.writeln('\tmut ${variable} := owner.state_factory(' + vml_quote(data.name) +
				', fn [${captures}] () !typeof(${value}) { return ${value} }) or { panic(err) }')
			ctx.values[key] = Value{
				read:   '${variable}.get() or { panic(err) }'
				signal: variable
				setter: '${variable}.set'
			}
			ctx.declare(variable, true)
		}
	}
	e.at(def.src)
	for fun in def.functions {
		variable := 'f_${fun.name}'
		mut fctx := ctx.clone()
		for index, parameter in fun.params {
			fctx.values['${fun.scope.id}:${index}'] = Value{
				read: parameter.name
			}
		}
		e.app_action_checks(fun.body)
		action := e.action(fun.body, fctx)
		signature := fun.params.map('${it.name} ${it.typ}').join(', ')
		e.writeln('\t${variable} := fn [${ctx.captures(action)}] (${signature}) { ${action} }')
		binding := def.scope.names[fun.name] or { Binding{} }
		ctx.values[binding_key(binding)] = Value{
			read: variable
		}
		ctx.declare(variable, false)
	}
	for index, watch in def.watches {
		e.at(watch.src)
		e.model_path_checks(watch.expr, ctx)
		value := e.expr(watch.expr, ctx)
		dependency := if ir_uses_app(watch.expr) { 'owner.watch_app()!; ' } else { '' }
		read_body := '${dependency}return ${value}'
		mut read_captures := ctx.captures(read_body)
		if ir_uses_app(watch.expr) || ir_uses_theme(watch.expr) {
			read_captures = add_capture(read_captures, 'mut owner')
		}
		old := if watch.old.len > 0 { watch.old } else { 'vml_old' }
		now := if watch.now.len > 0 { watch.now } else { 'vml_now' }
		mut wctx := ctx.clone()
		wctx.values['${watch.scope.id}:0'] = Value{
			read: old
		}
		wctx.values['${watch.scope.id}:1'] = Value{
			read: now
		}
		e.app_action_checks(watch.body)
		action := '_ = ${old}\n_ = ${now}\n' + e.action(watch.body, wctx)
		e.writeln('\towner.watch(' + vml_quote('watch:${index}') +
			', fn [${read_captures}] () !typeof(${value}) { ${read_body} }, fn [${wctx.captures(action)}] (${old} typeof(${value}), ${now} typeof(${value})) ! {\n${action}\n}) or { panic(err) }')
	}
	for kind in ['mount', 'unmount', 'cleanup'] {
		body := match kind {
			'mount' { def.mount }
			'unmount' { def.unmount }
			else { def.cleanup }
		}
		if isnil(body) {
			continue
		}
		e.app_action_checks(body)
		action := e.action(body, ctx)
		fallible := if kind == 'mount' { ' !' } else { '' }
		e.writeln('\towner.on_${kind}(' + vml_quote(kind) +
			', fn [${ctx.captures(action)}] ()${fallible} { ${action} }) or { panic(err) }')
	}
}

fn add_capture(captures string, name string) string {
	if captures.split(', ').any(it == name) {
		return captures
	}
	return if captures.len == 0 { name } else { captures + ', ' + name }
}

// ---------------------------------------------------------------- nodes

// RootHooks configure the root of a definition from its invocation: the
// invocation's key replaces the root's own, and the forwarded properties
// configure it before (`forward`) and after (`forward_after`) it is declared.
struct RootHooks {
	key           string
	forward       string
	forward_after string
}

// path_expr is the V expression of a node's path in the current context.
fn path_expr(path string, ctx &Ctx) string {
	if ctx.base.len == 0 {
		return vml_quote(path)
	}
	return '${ctx.base} + ' + vml_quote('.' + path)
}

fn source_location(l Location) string {
	return 'ui2.VmlSourceLocation{source: ${vml_quote(l.path)}, line: ${l.line}, column: ${l.column}}'
}

// node emits one node under `parent` (of props type `parent_props`, empty for
// a definition's caller-chosen parent) and returns its variable.
fn (mut e Emitter) node(n &INode, parent string, parent_props string, mut ctx Ctx, hooks RootHooks) !string {
	match n.kind {
		.element {
			return e.element(n, parent, parent_props, mut ctx, hooks)
		}
		.component {
			return e.invocation(n, parent, parent_props, mut ctx, hooks)
		}
		.repeater {
			e.repeater(n, parent, parent_props, mut ctx)!
			return ''
		}
		.cond {
			e.cond(n, parent, parent_props, mut ctx)!
			return ''
		}
		.slot {
			e.at(n.src)
			e.writeln('\tif ${ctx.args}.slot_${n.tag} != unsafe { nil } { ${ctx.args}.slot_${n.tag}(mut ${ctx.owner}, mut ${parent}, ${ctx.base})! }')
			return ''
		}
	}
}

fn (mut e Emitter) element(n &INode, parent string, parent_props string, mut ctx Ctx, hooks RootHooks) !string {
	variable := 'n_' + generated_name(n.path)
	props := props_type(n.tag)
	e.at(n.src)
	if n.id.len > 0 {
		ctx.values[binding_key(n.id_binding)] = Value{
			read: variable
			node: variable
		}
	}
	for prop in n.props {
		e.at(prop.src)
		e.model_path_checks(prop.expr, ctx)
	}
	for bind in n.binds {
		e.at(bind.src)
		e.write_checks(bind.write)
		e.model_path_checks(bind.target, ctx)
	}
	for event in n.events {
		e.at(event.src)
		e.app_action_checks(event.handler)
	}
	e.at(n.src)
	if parent_props.len > 0 && parent_props != 'ui2.VmlDocument' {
		e.uses_unreachable = true
		e.writeln('\tif ${e.guard_prefix}_unreachable() { ui2.vml_guard_child[${parent_props}, ${props}]() }')
	}
	for prop in n.props {
		if prop.name in ['x', 'y'] && (parent_props.len > 0 || hooks.forward.len == 0) {
			positioner := if parent_props.len > 0 { parent_props } else { 'ui2.VmlDocument' }
			e.at(prop.src)
			e.uses_unreachable = true
			e.writeln('\tif ${e.guard_prefix}_unreachable() { ui2.vml_guard_positioned[${positioner}]() }')
			break
		}
	}
	props_variable := 'p_' + generated_name(n.path)
	e.at(n.src)
	e.writeln('\tmut ${props_variable} := ${props}{}')
	for prop in n.props {
		if prop.reactive {
			continue
		}
		e.at(prop.src)
		e.writeln('\t${props_variable}.${prop.name} = ${e.prop_value(prop, ctx)}')
	}
	for event in n.events {
		e.at(event.src)
		e.writeln('\t${props_variable}.${event.name} = ${e.event_value(event, ctx)}')
	}
	e.at(n.src)
	if hooks.forward.len > 0 {
		e.writeln('\tif ${hooks.forward} != unsafe { nil } { ${hooks.forward}(mut ${props_variable}) }')
	}
	mut options := []string{}
	if n.id.len > 0 {
		options << 'id: ' + vml_quote(n.id)
	}
	options << 'path: ' + path_expr(n.path, ctx)
	own_key := if isnil(n.key) { '' } else { e.key_value(n.key, ctx) }
	if hooks.key.len > 0 {
		fallback := if own_key.len > 0 { own_key } else { "''" }
		options << 'key: if ${hooks.key}.len > 0 { ${hooks.key} } else { ${fallback} }'
	} else if own_key.len > 0 {
		options << 'key: ' + own_key
	}
	options << 'src: ' + source_location(n.src)
	e.writeln('\tmut ${variable} := ui2.vml_child(mut ${parent}, mut ${ctx.owner}, ${props_variable}, ${options.join(', ')}) or { panic(err) }')
	e.writeln('\t_ = ${variable}')
	ctx.declare(variable, false)
	for prop in n.props {
		if !prop.reactive {
			continue
		}
		e.reactive_prop(variable, props, prop.name, prop, ctx)
	}
	for bind in n.binds {
		e.binding(variable, props, bind, ctx)
	}
	if hooks.forward_after.len > 0 {
		e.at(n.src)
		e.writeln('\tif ${hooks.forward_after} != unsafe { nil } { ${hooks.forward_after}(mut ${variable})! }')
	}
	if !isnil(n.ref) {
		e.at(n.src)
		e.writeln('\t' + e.expr(n.ref, ctx) + '.bind_widget(mut ${variable}) or { panic(err) }')
	}
	for child in n.children {
		e.node(child, variable, props, mut ctx, RootHooks{})!
	}
	return variable
}

fn (mut e Emitter) key_value(key &IExpr, ctx &Ctx) string {
	if key.kind == .literal && key.literal == .string {
		return vml_quote(key.value)
	}
	return vml_stringify(e.expr(key, ctx))
}

fn (mut e Emitter) prop_value(prop IProp, ctx &Ctx) string {
	if prop.helper {
		return e.constant_helper(prop.expr, '${runtime_module}.${prop.name}', ctx)
	}
	return e.expr(prop.expr, ctx)
}

// reactive_prop registers a property whose value can change: its effect reads
// the tracked sources and assigns the field.
fn (mut e Emitter) reactive_prop(variable string, props string, field string, prop IProp, ctx &Ctx) {
	e.at(prop.src)
	value := e.prop_value(prop, ctx)
	dependency := if prop.uses_app { '${ctx.owner}.watch_app()!; ' } else { '' }
	body := '${dependency}vml_p.${field} = ${value}'
	mut captures := ctx.captures(body)
	if prop.uses_app || ir_uses_theme(prop.expr) {
		captures = add_capture(captures, 'mut ${ctx.owner}')
	}
	e.writeln('\t${variable}.prop(' + vml_quote(field) +
		', fn [${captures}] (mut vml_p ${props}) ! { ${body} }) or { panic(err) }')
}

// binding keeps `bind.name: target` two-way: the field follows the target, and
// a widget change writes the field back through the target.
fn (mut e Emitter) binding(variable string, props string, bind IBind, ctx &Ctx) {
	prop := IProp{
		name:     bind.prop
		expr:     bind.target
		reactive: true
		uses_app: ir_uses_app(bind.target)
		src:      bind.src
	}
	e.reactive_prop(variable, props, bind.prop, prop, ctx)
	current := e.current_value(bind.target, ctx)
	write := e.write(bind.write, 'ui2.vml_assign(${current}, vml_p.${bind.prop})', ctx)
	e.writeln('\t${variable}.bind(' + vml_quote(bind.prop) +
		', fn [${ctx.captures(write)}] (vml_p ${props}) ! { ${write} }) or { panic(err) }')
}

// current_value reads a binding target without subscribing, for the write.
fn (mut e Emitter) current_value(target &IExpr, ctx &Ctx) string {
	if target.kind == .binding {
		if value := ctx.values[binding_key(target.binding)] {
			if value.signal.len > 0 {
				return '${value.signal}.peek() or { panic(err) }'
			}
		}
	}
	return e.expr(target, ctx)
}

// event_value is the value of an `on_*` field: a callback reference or an
// action, run in the owner's batch.
fn (mut e Emitter) event_value(event IEvent, ctx &Ctx) string {
	mut hctx := ctx.clone()
	hctx.values['${event.scope.id}:0'] = Value{
		read: 'event'
	}
	mut body := '_ = event\n'
	if callback := e.callback_reference(event.handler, hctx) {
		body += 'ui2.vml_callback(${callback}, refresh: false)(event)\n'
	} else {
		body += e.action(event.handler, hctx) + '\n'
	}
	return '${ctx.owner}.callback(fn [${hctx.captures(body)}] (event ui2.ElementEvent) ! { ${body} })'
}

// callback_reference is the V function value a handler names, if it names one.
fn (mut e Emitter) callback_reference(h &IExpr, ctx &Ctx) ?string {
	match h.kind {
		.app_method {
			return 'app.${h.name}'
		}
		.fn_ref, .event_ref {
			value := ctx.values[binding_key(h.binding)] or { return none }
			return value.read
		}
		.module_fn, .external {
			return h.name
		}
		else {
			return none
		}
	}
}

// ---------------------------------------------------------------- repeaters

fn (mut e Emitter) repeater(n &INode, parent string, parent_props string, mut ctx Ctx) ! {
	repeat := n.repeat
	suffix := repeat.name
	e.at(repeat.src)
	collection := 'vml_collection_' + suffix
	source := e.expr(repeat.model, ctx)
	e.at(repeat.model_src)
	e.model_path_checks(repeat.model, ctx)
	e.writeln('\t${collection} := ${source}')
	e.write_list_guard(collection, suffix, true)
	item_type := 'typeof(${collection}[0])'
	item := 'vml_item_' + suffix
	signal := 'vml_item_signal_' + suffix
	owner := 'vml_item_component_' + suffix
	segment := 'vml_segment_' + suffix
	index := 'vml_index_signal_' + suffix
	ctx.declare(collection, false)
	// Key paths read item fields: they follow the same public-field rule.
	mut check := ctx.clone()
	check.values['${repeat.key_scope.id}:0'] = Value{
		read: '${collection}[0]'
	}
	e.at(repeat.key_src)
	e.model_path_checks(repeat.key, check)
	mut kctx := ctx.clone()
	kctx.values['${repeat.key_scope.id}:0'] = Value{
		read: item
	}
	key_body := '_ = ${collection}; return ${vml_stringify(e.expr(repeat.key, kctx))}'
	dependency := if repeat.model_uses_app { '${ctx.owner}.watch_app()!; ' } else { '' }
	model_body := '${dependency}return ${source}'
	mut model_captures := ctx.captures(model_body)
	if repeat.model_uses_app {
		model_captures = add_capture(model_captures, 'mut ${ctx.owner}')
	}
	mut ictx := ctx.clone()
	ictx.owner = owner
	ictx.values['${repeat.item_scope.id}:${repeat.item_slot}'] = Value{
		read:   '${signal}.get() or { panic(err) }'
		signal: signal
	}
	ictx.values['${repeat.item_scope.id}:${repeat.index_slot}'] = Value{
		read:   '${index}.get() or { panic(err) }'
		signal: index
	}
	ictx.declare(owner, true)
	ictx.declare(signal, true)
	ictx.declare(index, true)
	// The item body is emitted into a buffer first: its captures are the outer
	// values it reads.
	saved := e.out
	saved_locations := e.locations
	e.out = strings.new_builder(4096)
	e.locations = []Location{}
	e.writeln('\tmut ${signal} := unsafe { ${signal}_input }')
	e.writeln('\t_ = ${signal}')
	e.writeln('\tmut ${index} := ${owner}.state(' + vml_quote('@index') + ', 0)!')
	e.writeln('\t_ = ${index}')
	e.prepare_tokens(repeat.item_scope, owner)
	for child in repeat.children {
		e.node(child, segment, parent_props, mut ictx, RootHooks{})!
	}
	body := e.out.str()
	body_locations := e.locations.clone()
	e.out = saved
	e.locations = saved_locations
	build_captures := ctx.captures(body)
	e.at(repeat.src)
	e.writeln('\tui2.vml_repeat(mut ${parent}, ' + vml_quote(suffix) +
		', fn [${model_captures}] () ![]${item_type} { ${model_body} }, fn [${ctx.captures(key_body)}] (${item} ${item_type}) string { ${key_body} }, fn [${build_captures}] (mut ${owner} ui2.CompiledVmlComponent, mut ${segment} ui2.VmlSegment, ${signal}_input &ui2.Signal[${item_type}]) ! {')
	e.out.write_string(body)
	e.locations << body_locations
	e.at(repeat.src)
	e.writeln('\t}, ' + source_location(repeat.src) + ') or { panic(err) }')
}

// cond emits an `if` chain: a keyed list of at most one item, the index of
// the branch whose condition holds. A change of branch removes the old
// branch's nodes, with their exit motion, and builds the new one's.
fn (mut e Emitter) cond(n &INode, parent string, parent_props string, mut ctx Ctx) ! {
	c := n.cond
	suffix := c.name
	e.at(n.src)
	mut choices := []string{}
	mut otherwise := false
	mut reads_theme := false
	for index, branch in c.branches {
		if isnil(branch.cond) {
			choices << 'return [${index}]'
			otherwise = true
			break
		}
		e.at(branch.src)
		e.model_path_checks(branch.cond, ctx)
		value := e.expr(branch.cond, ctx)
		reads_theme = reads_theme || ir_uses_theme(branch.cond)
		test := if branch.bind_slot >= 0 { '(${value}) != none' } else { vml_condition(value) }
		choices << 'if ${test} { return [${index}] }'
	}
	if !otherwise {
		choices << 'return []int{}'
	}
	dependency := if c.cond_uses_app { '${ctx.owner}.watch_app()!\n' } else { '' }
	select_body := dependency + choices.join('\n')
	mut select_captures := ctx.captures(select_body)
	if c.cond_uses_app || reads_theme {
		select_captures = add_capture(select_captures, 'mut ${ctx.owner}')
	}
	owner := 'vml_branch_component_' + suffix
	segment := 'vml_branch_segment_' + suffix
	signal := 'vml_branch_signal_' + suffix
	// The branches are emitted into a buffer first: their captures are the
	// outer values they read.
	saved := e.out
	saved_locations := e.locations
	e.out = strings.new_builder(4096)
	e.locations = []Location{}
	// One `if` per branch: `#line` directives may not sit between match arms.
	e.writeln('\tvml_branch_${suffix} := ${signal}.peek() or { -1 }')
	for index, branch in c.branches {
		e.at(branch.src)
		e.writeln('\tif vml_branch_${suffix} == ${index} {')
		mut bctx := ctx.clone()
		bctx.owner = owner
		bctx.declare(owner, true)
		e.prepare_tokens(branch.scope, owner)
		if branch.bind_slot >= 0 {
			value := e.expr(branch.cond, ctx)
			variable := 'vml_unwrapped_${suffix}'
			dependency_read := if ir_uses_app(branch.cond) { '${owner}.watch_app() or {}\n' } else { '' }
			read_body := '${dependency_read}return ${value}'
			mut read_captures := bctx.captures(read_body)
			if ir_uses_app(branch.cond) || ir_uses_theme(branch.cond) {
				read_captures = add_capture(read_captures, 'mut ${owner}')
			}
			e.writeln('\tmut ${variable} := ui2.vml_unwrapped(mut ${owner}, ${value}, fn [${read_captures}] () typeof(${value}) {\n${read_body}\n})!')
			bctx.values['${branch.scope.id}:${branch.bind_slot}'] = Value{
				read:   '${variable}.get() or { panic(err) }'
				signal: variable
			}
			bctx.declare(variable, true)
		}
		for child in branch.children {
			e.node(child, segment, parent_props, mut bctx, RootHooks{})!
		}
		e.writeln('\t}')
	}
	body := e.out.str()
	body_locations := e.locations.clone()
	e.out = saved
	e.locations = saved_locations
	build_captures := ctx.captures(body)
	e.at(n.src)
	e.writeln('\tui2.vml_repeat(mut ${parent}, ' + vml_quote(suffix) +
		', fn [${select_captures}] () ![]int {\n${select_body}\n}, fn (vml_branch int) string { return ${vml_quote(c.name + ':')} + vml_branch.str() }, fn [${build_captures}] (mut ${owner} ui2.CompiledVmlComponent, mut ${segment} ui2.VmlSegment, ${signal} &ui2.Signal[int]) ! {')
	e.out.write_string(body)
	e.locations << body_locations
	e.at(n.src)
	e.writeln('\t}, ' + source_location(n.src) + ') or { panic(err) }')
}

// ---------------------------------------------------------------- invocations

// invocation emits a call of a definition's builder: its arguments, handlers,
// slot content and forwarded properties are closures of this scope.
fn (mut e Emitter) invocation(n &INode, parent string, parent_props string, mut ctx Ctx, hooks RootHooks) !string {
	inv := n.invoke
	def := e.program.components[inv.def_key] or {
		return n.src.error('unknown component `${n.tag}`')
	}
	variable := 'n_' + generated_name(n.path)
	root := e.root_props[def.key] or { 'ui2.ViewProps' }
	e.at(n.src)
	for arg in inv.args {
		if !isnil(arg.expr) {
			e.at(arg.src)
			e.model_path_checks(arg.expr, ctx)
			if arg.kind == .bound {
				e.write_checks(arg.write)
			}
		}
		if !isnil(arg.handler) {
			e.at(arg.src)
			e.app_action_checks(arg.handler)
		}
	}
	for prop in inv.forwarded {
		if prop.name in ['x', 'y'] {
			e.at(prop.src)
			e.uses_unreachable = true
			positioner := if parent_props.len > 0 { parent_props } else { 'ui2.VmlDocument' }
			e.writeln('\tif ${e.guard_prefix}_unreachable() { ui2.vml_guard_positioned[${positioner}]() }')
			break
		}
	}
	mut fields := []string{}
	for arg in inv.args {
		e.at(arg.src)
		match arg.kind {
			.argument, .bound {
				value := if arg.helper {
					namespace := type_namespace(arg.typ) or { '' }
					e.constant_helper(arg.expr, namespace, ctx)
				} else {
					e.expr(arg.expr, ctx)
				}
				dependency := if arg.uses_app { '${ctx.owner}.watch_app()!; ' } else { '' }
				body := '${dependency}return ${input_value(arg.typ, value)}'
				mut captures := ctx.captures(body)
				if arg.uses_app || ir_uses_theme(arg.expr) {
					captures = add_capture(captures, 'mut ${ctx.owner}')
				}
				fields << '${arg.name}: fn [${captures}] () !${input_storage(arg.typ)} { ${body} }'
				if arg.kind == .bound {
					write := e.write(arg.write, 'value', ctx)
					fields << '${arg.name}_write: fn [${ctx.captures(write)}] (value ${arg.typ}) ! { ${write} }'
				}
			}
			.event {
				if isnil(arg.handler) {
					continue
				}
				fields << '${arg.name}: ' + e.listener(arg, ctx)
			}
			.default_value {}
		}
	}
	for name, nodes in inv.slots {
		slot_scope := inv.slot_scopes[name] or { continue }
		slot_parent := e.slot_parents['${def.key}#${name}'] or { 'ui2.VmlSegment' }
		slot_path := def.slots[name] or { continue }
		host_parent_props := if slot_parent.starts_with('ui2.VmlWidgetNode[') {
			slot_parent.all_after('ui2.VmlWidgetNode[').trim_right(']')
		} else {
			parent_props
		}
		mut sctx := ctx.clone()
		sctx.owner = 'vml_slot_owner'
		sctx.base = 'vml_slot_base'
		sctx.declare('vml_slot_owner', true)
		sctx.declare('vml_slot_base', false)
		saved := e.out
		saved_locations := e.locations
		e.out = strings.new_builder(2048)
		e.locations = []Location{}
		e.at(n.src)
		e.writeln('\tmut vml_slot_owner := ${ctx.owner}.slot_child(mut vml_slot_host, vml_slot_base + ' +
			vml_quote('.' + slot_path) + ')!')
		e.prepare_tokens(slot_scope, 'vml_slot_owner')
		for child in nodes {
			e.node(child, 'vml_slot_parent', host_parent_props, mut sctx, RootHooks{})!
		}
		body := e.out.str()
		body_locations := e.locations.clone()
		e.out = saved
		e.locations = saved_locations
		_ = body_locations
		mut captures := ctx.captures(body)
		captures = add_capture(captures, 'mut ${ctx.owner}')
		fields << 'slot_${name}: fn [${captures}] (mut vml_slot_host ui2.CompiledVmlComponent, mut vml_slot_parent ${slot_parent}, vml_slot_base string) ! {\n${body}}'
	}
	// An enclosing invocation's key replaces the invocation's own, as it
	// replaces a root element's.
	e.at(n.src)
	own_key := if isnil(inv.key) { '' } else { e.key_value(inv.key, ctx) }
	if hooks.key.len > 0 {
		fallback := if own_key.len > 0 { own_key } else { "''" }
		fields << 'key: if ${hooks.key}.len > 0 { ${hooks.key} } else { ${fallback} }'
	} else if own_key.len > 0 {
		fields << 'key: ' + own_key
	}
	forward, forward_after := e.forwards(inv, root, ctx, hooks)
	if forward.len > 0 {
		fields << 'forward: ${forward}'
	}
	if forward_after.len > 0 {
		fields << 'forward_after: ${forward_after}'
	}
	app := e.needs_app[def.key] or { false }
	model := if app { 'mut app, ' } else { '' }
	e.at(n.src)
	e.writeln('\tmut ${variable} := ${def_function(def)}(${model}mut ${parent}, mut ${ctx.owner}, ${path_expr(n.path,
		ctx)}, ${def_args_type(def)}{')
	for field in fields {
		e.cont('\t\t${field}')
	}
	e.cont('\t}) or { panic(err) }')
	e.writeln('\t_ = ${variable}')
	ctx.declare(variable, false)
	if n.id.len > 0 {
		binding := n.id_binding
		ctx.values[binding_key(binding)] = Value{
			read: variable
			node: variable
		}
	}
	if !isnil(inv.ref) {
		e.writeln('\t' + e.expr(inv.ref, ctx) + '.bind_widget(mut ${variable}) or { panic(err) }')
	}
	return variable
}

// listener is the closure an invocation passes for a component event.
fn (mut e Emitter) listener(arg IArg, ctx &Ctx) string {
	signature := arg.params.map('${it.name} ${it.typ}').join(', ')
	payload := arg.params.map(it.name).join(', ')
	types := arg.params.map(it.typ).join(', ')
	mut lctx := ctx.clone()
	for index, parameter in arg.params {
		lctx.values['${arg.scope.id}:${index}'] = Value{
			read: parameter.name
		}
	}
	mut body := ''
	for parameter in arg.params {
		body += '_ = ${parameter.name}\n'
	}
	if callback := e.callback_reference(arg.handler, lctx) {
		body += 'vml_listener := ${callback}\n'
		body += '\$if vml_listener is fn () { vml_listener() } \$else \$if vml_listener is fn (${types}) { vml_listener(${payload}) } \$else { \$compile_error(' +
			vml_quote('event callback `${arg.name}` requires fn() or the exact declared payload and a void return') +
			') }\n'
	} else {
		body += e.action(arg.handler, lctx) + '\n'
	}
	return 'fn [${lctx.captures(body)}] (${signature}) { ${body} }'
}

// forwards builds the closures that configure a definition's root from the
// invocation's undeclared properties, composed with the hooks the enclosing
// definition received when this invocation is its root.
fn (mut e Emitter) forwards(inv &IInvocation, root string, ctx &Ctx, hooks RootHooks) (string, string) {
	mut before := []string{}
	mut after := []string{}
	for prop in inv.forwarded {
		e.at(prop.src)
		e.model_path_checks(prop.expr, ctx)
		if prop.reactive {
			continue
		}
		before << 'vml_p.${prop.name} = ${e.prop_value(prop, ctx)}'
	}
	for event in inv.forwarded_events {
		e.at(event.src)
		e.app_action_checks(event.handler)
		before << 'vml_p.${event.name} = ${e.event_value(event, ctx)}'
	}
	mut forward := ''
	if before.len > 0 || hooks.forward.len > 0 {
		mut body := before.join('\n')
		if hooks.forward.len > 0 {
			body += '\nif ${hooks.forward} != unsafe { nil } { ${hooks.forward}(mut vml_p) }'
		}
		forward = 'fn [${ctx.captures(body)}] (mut vml_p ${root}) {\n${body}\n}'
	}
	saved := e.out
	saved_locations := e.locations
	e.out = strings.new_builder(1024)
	e.locations = []Location{}
	for prop in inv.forwarded {
		if prop.reactive {
			e.reactive_prop('vml_root_node', root, prop.name, prop, ctx)
		}
	}
	for bind in inv.forwarded_binds {
		e.binding('vml_root_node', root, bind, ctx)
	}
	if hooks.forward_after.len > 0 {
		e.writeln('\tif ${hooks.forward_after} != unsafe { nil } { ${hooks.forward_after}(mut vml_root_node)! }')
	}
	after_body := e.out.str()
	e.out = saved
	e.locations = saved_locations
	if after_body.len > 0 {
		after << after_body
	}
	mut forward_after := ''
	if after.len > 0 {
		body := after.join('\n')
		forward_after = 'fn [${ctx.captures(body)}] (mut vml_root_node ui2.VmlWidgetNode[${root}]) ! {\n${body}}'
	}
	return forward, forward_after
}

// ---------------------------------------------------------------- expressions

// expr lowers a value expression.
fn (mut e Emitter) expr(x &IExpr, ctx &Ctx) string {
	match x.kind {
		.literal {
			return if x.literal == .string { vml_quote(x.value) } else { x.value }
		}
		.color {
			return 'u32(0x${x.name[1..]})'
		}
		.enum_name {
			return '.' + x.name
		}
		.app_field {
			return 'app.${x.name}'
		}
		.binding {
			value := ctx.values[binding_key(x.binding)] or {
				return '\$compile_error(' + vml_quote('VML name `${x.binding.name}` is not available here') + ')'
			}
			return value.read
		}
		.member {
			return '${member_base(e.expr(x.args[0], ctx))}.${x.name}'
		}
		.length {
			return '${member_base(e.expr(x.args[0], ctx))}.len'
		}
		.to_str {
			return '${member_base(e.expr(x.args[0], ctx))}.str()'
		}
		.token {
			namespace := x.name.all_before(':')
			getter := match namespace {
				'color' { 'color_token' }
				'spacing' { 'spacing_token' }
				'radius' { 'radius_token' }
				else { 'font_size_token' }
			}
			return '${ctx.owner}.${getter}(' + vml_quote(x.name.all_after(':')) + ') or { panic(err) }'
		}
		.geometry {
			value := ctx.values[binding_key(x.binding)] or {
				return '\$compile_error(' + vml_quote('VML element `${x.binding.name}` is not available here') + ')'
			}
			return '(${value.node}.geometry() or { panic(err) }).${x.name}'
		}
		.external {
			return x.name
		}
		.not_ {
			return '(!${e.expr(x.args[0], ctx)})'
		}
		.negate {
			return '(-${e.expr(x.args[0], ctx)})'
		}
		.binary, .and_, .or_ {
			op := match x.kind {
				.and_ { '&&' }
				.or_ { '||' }
				else { x.name }
			}
			return '(${e.expr(x.args[0], ctx)} ${op} ${e.expr(x.args[1], ctx)})'
		}
		.conditional {
			return '(if ${vml_condition(e.expr(x.args[0], ctx))} { ${e.expr(x.args[1], ctx)} } else { ${e.expr(x.args[2],
				ctx)} })'
		}
		.array {
			return '[' + x.args.map(e.expr(it, ctx)).join(', ') + ']'
		}
		.interp {
			mut value := "'"
			for part in x.args {
				if part.kind == .literal && part.literal == .string {
					value += vml_interpolation_text(part.value)
				} else {
					value += r'$' + '{' + e.expr(part, ctx) + '}'
				}
			}
			return value + "'"
		}
		.app_call {
			return 'app.${x.name}(${e.args(x.args, ctx)})' + fallible(x)
		}
		.fn_call, .emit {
			value := ctx.values[binding_key(x.binding)] or { return x.binding.name }
			return '${value.read}(${e.args(x.args, ctx)})'
		}
		.ref_call {
			value := ctx.values[binding_key(x.binding)] or { return x.binding.name }
			return '${value.read}.${x.name}(${e.args(x.args, ctx)})' + fallible(x)
		}
		.module_call {
			return '${x.name}(${e.args(x.args, ctx)})' + fallible(x)
		}
		.helper {
			// A helper outside a helper value: a module function of that name.
			return '${x.name}(${e.args(x.args, ctx)})' + fallible(x)
		}
		.index {
			return '${member_base(e.expr(x.args[0], ctx))}[${e.expr(x.args[1], ctx)}]'
		}
		.method_call {
			if x.name.len == 0 {
				return '${e.expr(x.args[0], ctx)}(${e.args(x.args[1..], ctx)})' + fallible(x)
			}
			return '${member_base(e.expr(x.args[0], ctx))}.${x.name}(${e.args(x.args[1..],
				ctx)})' + fallible(x)
		}
		.or_else {
			return '(${e.expr(x.args[0], ctx)} or { ${e.expr(x.args[1], ctx)} })'
		}
		.app_method {
			return 'app.${x.name}'
		}
		.fn_ref, .event_ref {
			value := ctx.values[binding_key(x.binding)] or { return x.binding.name }
			return value.read
		}
		.module_fn {
			return x.name
		}
		.assign_app, .assign_binding, .assign_place, .block {
			return e.action(x, ctx)
		}
	}
}

fn fallible(x &IExpr) string {
	return if x.fallible { ' or { panic(err) }' } else { '' }
}

fn (mut e Emitter) args(args []&IExpr, ctx &Ctx) string {
	return args.map(e.expr(it, ctx)).join(', ')
}

// member_base parenthesizes a value that is not a plain name before `.field`.
fn member_base(value string) string {
	for ch in value {
		if !(ch.is_letter() || ch.is_digit() || ch == `_` || ch == `.`) {
			return '(${value})'
		}
	}
	return value
}

// helper_value lowers a value of helper namespace `namespace` (`ui2.style`):
// a list or a helper call is composed, a conditional chooses between values.
// constant_helper is a helper value, hoisted into a module constant when it
// reads nothing and cannot fail: the constant is computed once when the
// program starts, not at every build, and equal values of a file share one.
fn (mut e Emitter) constant_helper(x &IExpr, namespace string, ctx &Ctx) string {
	code := e.helper_value(x, namespace, ctx)
	if x.kind !in [.array, .helper] || !ir_constant(x) {
		return code
	}
	if name := e.constants[code] {
		return name
	}
	name := '${e.guard_prefix.replace('vml_check_', 'vmlk_')}_${e.constant_decls.len}'
	e.constants[code] = name
	e.constant_decls << Constant{
		name:     name
		code:     code
		location: e.location
	}
	return name
}

fn (mut e Emitter) helper_value(x &IExpr, namespace string, ctx &Ctx) string {
	if x.kind == .conditional {
		return '(if ${vml_condition(e.expr(x.args[0], ctx))} { ${e.helper_value(x.args[1], namespace,
			ctx)} } else { ${e.helper_value(x.args[2], namespace, ctx)} })'
	}
	if x.kind in [.array, .helper] {
		return '${namespace}_compose(' + e.helper_entries(x, namespace, ctx).join(', ') + ')'
	}
	return e.expr(x, ctx)
}

fn (mut e Emitter) helper_entries(x &IExpr, namespace string, ctx &Ctx) []string {
	if x.kind == .array {
		mut entries := []string{}
		for item in x.args {
			entries << e.helper_entries(item, namespace, ctx)
		}
		return entries
	}
	return [e.helper_entry(x, namespace, ctx)]
}

fn (mut e Emitter) helper_entry(x &IExpr, namespace string, ctx &Ctx) string {
	match x.kind {
		.array {
			return '${namespace}_compose(' + e.helper_entries(x, namespace, ctx).join(', ') + ')'
		}
		.conditional {
			return '(if ${vml_condition(e.expr(x.args[0], ctx))} { ${e.helper_entry(x.args[1], namespace,
				ctx)} } else { ${e.helper_entry(x.args[2], namespace, ctx)} })'
		}
		.helper {
			mut args := []string{cap: x.args.len}
			for arg in x.args {
				if arg.kind == .array {
					args << '[' + e.helper_entries(arg, namespace, ctx).join(', ') + ']'
				} else {
					args << e.expr(arg, ctx)
				}
			}
			return '${namespace}_${x.name}(${args.join(', ')})' + fallible(x)
		}
		else {
			return e.expr(x, ctx)
		}
	}
}

// ---------------------------------------------------------------- statements

// action lowers a statement: an assignment, a block, a component event emit
// (whose payload is checked against its declared types) or an expression.
fn (mut e Emitter) action(x &IExpr, ctx &Ctx) string {
	match x.kind {
		.block {
			return x.args.map(e.action(it, ctx)).join('\n')
		}
		.assign_app, .assign_binding {
			return e.write(x, e.expr(x.args[0], ctx), ctx)
		}
		.assign_place {
			return e.write(x, e.expr(x.args[1], ctx), ctx)
		}
		.emit {
			params := x.binding.params
			mut statements := []string{}
			mut payload := []string{}
			for index, parameter in params {
				if index >= x.args.len {
					break
				}
				argument := 'vml_payload_${index}'
				statements << argument + ' := ' + e.payload_value(x.args[index], parameter.typ, ctx)
				statements << '\$if ' + argument + ' !is ' + parameter.typ +
					' { \$compile_error(' + vml_quote('event `${x.binding.name}` payload `${parameter.name}` requires exact type ${parameter.typ}') +
					') }'
				payload << argument
			}
			value := ctx.values[binding_key(x.binding)] or {
				return x.binding.name
			}
			statements << '${value.read}(${payload.join(', ')})'
			return '{\n' + statements.join('\n') + '\n}'
		}
		else {
			return e.expr(x, ctx)
		}
	}
}

// write assigns `value` to a writable target with the target's operator: a
// top-level `app` field, a state or a bindable input (whose setter also
// writes the caller's target), or a path below the model or below a state or
// input, which is written by reading, changing and setting the whole value.
fn (mut e Emitter) write(target &IExpr, value string, ctx &Ctx) string {
	op := if target.op.len > 0 { target.op } else { '=' }
	match target.kind {
		.assign_app {
			return 'app.${target.name} ${op} ${value}'
		}
		.assign_binding {
			slot := ctx.values[binding_key(target.binding)] or {
				return '\$compile_error(' + vml_quote('VML target `${target.binding.name}` is not available here') + ')'
			}
			setter := value_setter(slot) or {
				return '\$compile_error(' + vml_quote('VML target `${target.binding.name}` is read-only') + ')'
			}
			current := '${slot.signal}.peek() or { panic(err) }'
			return match op {
				'=' { '${setter}(${value}) or { panic(err) }' }
				'<<' { '{\nmut vml_value := ${current}\nvml_value << ${value}\n${setter}(vml_value) or { panic(err) }\n}' }
				else { '${setter}((${current}) ${op[..1]} (${value})) or { panic(err) }' }
			}
		}
		.assign_place {
			place := target.args[0]
			if target.binding.name.len == 0 {
				return '${e.expr(place, ctx)} ${op} ${value}'
			}
			slot := ctx.values[binding_key(target.binding)] or {
				return '\$compile_error(' + vml_quote('VML target `${target.binding.name}` is not available here') + ')'
			}
			setter := value_setter(slot) or {
				return '\$compile_error(' + vml_quote('VML target `${target.binding.name}` is read-only') + ')'
			}
			mut pctx := ctx.clone()
			pctx.values[binding_key(target.binding)] = Value{
				read: 'vml_value'
			}
			return '{\nmut vml_value := ${slot.signal}.peek() or { panic(err) }\n${e.expr(place,
				pctx)} ${op} ${value}\n${setter}(vml_value) or { panic(err) }\n}'
		}
		else {
			return '\$compile_error(' + vml_quote('VML target is read-only or unknown; use state or an explicit bind connection') + ')'
		}
	}
}

// value_setter is the function that writes a writable value.
fn value_setter(slot Value) ?string {
	if slot.setter.len > 0 {
		return slot.setter
	}
	if slot.signal.len > 0 {
		return '${slot.signal}.set'
	}
	return none
}

// place_root is the value a field or index path starts from.
fn place_root(place &IExpr) &IExpr {
	mut base := unsafe { place }
	for base.kind in [.member, .index] {
		base = base.args[0]
	}
	return base
}

// payload_value lowers an event payload: a bare enum value takes the declared
// payload type, and empty or enum arrays the declared element type.
fn (mut e Emitter) payload_value(x &IExpr, expected string, ctx &Ctx) string {
	if x.kind == .enum_name {
		return expected + '.' + x.name
	}
	if x.kind == .conditional {
		return '(if ' + vml_condition(e.expr(x.args[0], ctx)) + ' { ' +
			e.payload_value(x.args[1], expected, ctx) + ' } else { ' +
			e.payload_value(x.args[2], expected, ctx) + ' })'
	}
	if x.kind == .array && expected.starts_with('[]') {
		return vml_array_literal(expected[2..], x.args.map(e.payload_value(it, expected[2..],
			ctx)))
	}
	return e.expr(x, ctx)
}

// ---------------------------------------------------------------- checks

// mutable_check rejects a write to an `app` field that is not public and
// mutable.
fn (mut e Emitter) mutable_check(target string) {
	if !e.once('mutable:' + target) {
		return
	}
	field_name := target.all_after('app.')
	e.writeln('\t\$for field in app.fields {')
	e.writeln('\t\t\$if field.name == ' + vml_quote(field_name) + ' {')
	e.writeln('\t\t\t\$if !field.is_pub || !field.is_mut { \$compile_error(' +
		vml_quote('VML target `${target}` must be public and mutable') + ') }')
	e.writeln('\t\t}')
	e.writeln('\t}')
}

// write_checks guards that a write to the model writes a public mutable
// top-level field.
fn (mut e Emitter) write_checks(target &IExpr) {
	if target.kind == .assign_app {
		e.mutable_check('app.' + target.name)
	} else if target.kind == .assign_place && target.binding.name.len == 0 {
		root := place_root(target.args[0])
		if root.kind == .app_field {
			e.mutable_check('app.' + root.name)
		}
	}
}

// app_action_checks guards that actions write public mutable `app` fields and
// call public `app` methods with their declared arity.
fn (mut e Emitter) app_action_checks(x &IExpr) {
	e.write_checks(x)
	if x.kind in [.app_call, .app_method] {
		arity := if x.kind == .app_call { x.args.len.str() } else { '' }
		if e.once('method:${x.name}:${arity}') {
			e.writeln('\t\$for method in app.methods {')
			e.writeln('\t\$if method.name == ' + vml_quote(x.name) + ' {')
			e.writeln('\t\$if !method.is_pub { \$compile_error(' +
				vml_quote('VML action method `${x.name}` must be public') + ') }')
			if x.kind == .app_call {
				e.writeln('\t\$if method.args.len != ${x.args.len} { \$compile_error(' +
					vml_quote('VML action `${x.name}` argument count does not match its declared signature') +
					') }')
			}
			e.writeln('\t}\n}')
		}
	}
	for arg in x.args {
		e.app_action_checks(arg)
	}
}

// model_path_checks guards that `app.*` and item paths read public fields. The
// guards never run; V checks them for the actual model types.
fn (mut e Emitter) model_path_checks(x &IExpr, ctx &Ctx) {
	if x.kind == .member {
		mut names := []string{}
		mut base := unsafe { x }
		for base.kind == .member {
			names.insert(0, base.name)
			base = base.args[0]
		}
		mut value := ''
		mut model_path := ''
		if base.kind == .app_field {
			value = 'app'
			names.insert(0, base.name)
			model_path = 'app.' + names.join('.')
		} else if base.kind == .binding && base.binding.kind == .item {
			slot := ctx.values[binding_key(base.binding)] or { Value{} }
			value = slot.read
			model_path = 'item.' + names.join('.')
		}
		if value.len > 0 {
			for name in names {
				e.field_guard(value, name, model_path)
				value += '.' + name
			}
			return
		}
	} else if x.kind == .app_field {
		e.field_guard('app', x.name, 'app.${x.name}')
	}
	for arg in x.args {
		e.model_path_checks(arg, ctx)
	}
}

fn (mut e Emitter) once(key string) bool {
	if key in e.checks {
		return false
	}
	e.checks[key] = true
	return true
}

fn (mut e Emitter) field_guard(value string, field_name string, model_path string) {
	if !e.once('field:${value}:${field_name}') {
		return
	}
	name := '${e.guard_prefix}_field_${e.guards.len}'
	e.guards << VmlGuard{
		name:       name
		field_name: field_name
		model_path: model_path
		location:   e.location
	}
	e.uses_unreachable = true
	e.writeln('\tif ${e.guard_prefix}_unreachable() { ${name}(${value}) }')
}

// write_list_guard lets V validate declared list types even for empty lists.
fn (mut e Emitter) write_list_guard(value string, suffix string, array bool) {
	name := '${e.guard_prefix}_${suffix}_' + if array { 'array' } else { 'key' }
	e.guards << VmlGuard{
		name:     name
		array:    array
		location: e.location
	}
	e.uses_unreachable = true
	e.writeln('\tif ${e.guard_prefix}_unreachable() { ${name}(${value}) }')
}

fn (mut e Emitter) write_list_guards() {
	if e.guards.len > 0 || e.uses_unreachable {
		e.writeln('fn ${e.guard_prefix}_unreachable() bool { return false }')
	}
	for guard in e.guards {
		e.location = guard.location
		if guard.ref_method.len > 0 {
			types := ref_command_targets[guard.ref_method] or { []string{} }
			test := types.map('T is ${runtime_module}.${it}').join(' || ')
			e.writeln('fn ${guard.name}[T](value &${runtime_module}.VmlRef[T]) {')
			e.writeln('\t_ = value')
			e.writeln('\t\$if ${test} {} \$else { \$compile_error(' +
				vml_quote('this element does not support `${guard.ref_method}`') + ') }')
			e.writeln('}')
			continue
		}
		e.writeln('fn ${guard.name}[T](value T) {')
		e.writeln('\t_ = value')
		if guard.field_name.len > 0 {
			e.writeln('\t\$if T is \$pointer { ${guard.name}(unsafe { *value }) } \$else \$if T !is \$interface {')
			e.writeln('\t\t\$for field in T.fields {')
			e.writeln('\t\t\t\$if field.name == ${vml_quote(guard.field_name)} {')
			e.writeln('\t\t\t\t\$if !field.is_pub { \$compile_error(' +
				vml_quote('VML model path `${guard.model_path}` must use public fields') + ') }')
			e.writeln('\t\t\t}')
			e.writeln('\t\t}')
			e.writeln('\t}')
		} else if guard.array {
			e.writeln("\t\$if T !is \$array { \$compile_error('a VML `for` iterates an array') }")
		}
		e.writeln('}')
	}
}

// write_generated generates the document at `path` and writes its V files
// into `config.dir` as `<name><suffix>` (`_vml.v` when empty). It returns the
// written paths; a file whose text did not change is left alone.
pub fn write_generated(path string, config GenConfig, suffix string) ![]string {
	files := generate_files(path, config)!
	ending := if suffix.len > 0 { suffix } else { '_vml.v' }
	mut written := []string{}
	for file in files {
		output := os.join_path(config.dir, file.name + ending)
		current := os.read_file(output) or { '' }
		if current != file.code {
			os.write_file(output, file.code)!
		}
		written << output
	}
	return written
}
