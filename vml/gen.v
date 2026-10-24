module vml

import os
import strings

// The VML generator: it lowers a parsed document to ordinary V source. The
// generator knows the VML language (elements, properties, components,
// repeaters, helper values, tokens) but no widget: tag `Slider` lowers to the
// props type `ui2.SliderProps`, every property to a field of it, and ui2's
// generic node runtime (`vml_document`, `vml_root`, `vml_child`, `prop`,
// `bind`, `vml_repeat`) builds, retains and updates the tree. V type-checks
// tags, property names and values against the props types in the generated
// file, and `#line` directives make its errors point at the `.vml` source.
//
// A document becomes one generic builder, `pub fn <name>_vml[A](mut app A,
// frame ?ui2.Rect) ui2.Element`, so the generator never needs the model's
// type: V checks `app.x` against the model each caller passes. A document
// reads only `app`, its own members and ui2's helpers.

// GenConfig selects where generated code lives.
pub struct GenConfig {
pub:
	// module is the V module of the generated file (the module of the files
	// next to the document).
	module string = 'main'
	// name is the builder's name without its `_vml` suffix; the document's
	// file name by default.
	name string
	// dir is the directory of the generated file. Document paths in the
	// generated code are relative to it, so the code does not depend on the
	// machine that generated it.
	dir string
}

// generate_file parses the document at `path` with its imports and returns
// the generated V source.
pub fn generate_file(path string, config GenConfig) !string {
	root := parse_file(path, validate_document: validate_vml_document)!
	name := if config.name.len > 0 { config.name } else { builder_base_name(path) }
	return generate(root, GenConfig{ ...config, name: name })
}

// generate lowers a parsed document to a V file holding its builder.
pub fn generate(root &Node, config GenConfig) !string {
	if config.name.len == 0 {
		return error('the generated builder needs a name')
	}
	mut compiler := VmlCompiler{
		uses_app:     node_uses_path(root, 'app')
		guard_prefix: 'vml_check_${config.name}'
	}
	code := compiler.file(root, config)!
	if config.dir.len == 0 {
		return code
	}
	return code.replace(os.real_path(config.dir) + os.path_separator, '')
}

// builder_base_name is the identifier a document's builder is named after:
// `screens/app-main.vml` is `app_main`.
pub fn builder_base_name(path string) string {
	base := os.file_name(path).all_before_last('.')
	mut out := strings.new_builder(base.len)
	for ch in base.to_lower() {
		out.write_u8(if ch.is_letter() || ch.is_digit() { ch } else { `_` })
	}
	name := out.str()
	return if name.len > 0 && name[0].is_digit() { 'vml_' + name } else { name }
}

fn validate_vml_document(root &Node, imported bool) ! {
	_ = imported
	validate_vml_node(root)!
}

// validate_vml_node checks the language rules V cannot check in the lowered
// code: binding targets are paths, and a Repeater has a model and a key.
fn validate_vml_node(node &Node) ! {
	for property in node.properties {
		// Event payloads keep V's `.name`; property values are typed by their field.
		if !property.name.starts_with('on_') {
			if dotted := vml_dotted_enum(property.expr) {
				return error('${property.expr.source}:${dotted.line}:${dotted.column}: VML enum values omit the dot: use `${dotted.value[1..]}`')
			}
		}
		if property.name.starts_with('bind.') && property.expr.kind != .path {
			return error('${property.expr.source}:${property.expr.line}:${property.expr.column}: `${property.name}` must target a writable path')
		}
	}
	if node.tag == 'Repeater' {
		for property in node.properties {
			if property.name !in ['model', 'key'] {
				return error('${property.expr.source}:${property.expr.line}:${property.expr.column}: unsupported `${property.name}` on Repeater')
			}
		}
		if find_property(node, 'model') == none {
			return error('${node.source}:${node.line}:${node.column}: Repeater requires `model`')
		}
		if find_property(node, 'key') == none {
			return error('${node.source}:${node.line}:${node.column}: Repeater requires a stable `key`')
		}
	}
	for child in node.children {
		validate_vml_node(child)!
	}
}

// vml_dotted_enum returns the first `.name` value in `expr`: VML enum values are
// bare names that their property types (`text_align(right)`).
fn vml_dotted_enum(expr &Expr) ?&Expr {
	if expr.kind == .path && expr.value.starts_with('.') {
		return expr
	}
	for child in [expr.left, expr.right, expr.third] {
		if !isnil(child) {
			if found := vml_dotted_enum(child) {
				return found
			}
		}
	}
	for arg in expr.args {
		if found := vml_dotted_enum(arg) {
			return found
		}
	}
	return none
}

// VmlScope is what a VML expression can name: specials (inputs, state,
// computed values, functions, events, refs, `item`, `index`), element ids
// (the node variable whose geometry `id.width` reads) and writable targets.
struct VmlScope {
mut:
	ids              map[string]string
	special          map[string]string
	writable         map[string]string
	event_parameters map[string][]Parameter
	component        string
}

struct VmlGuard {
	field_name string
	model_path string
	name       string
	array      bool
	location   Location
}

struct VmlCompiler {
	guard_prefix string
	uses_app     bool
mut:
	uses_unreachable bool
	emitted_checks   map[string]bool
	lowered_node     string
	slot_scopes      map[string]VmlScope
	out              strings.Builder
	guards           []VmlGuard
	location         Location
	locations        []Location
}

fn vml_clone_scope(scope VmlScope) VmlScope {
	return VmlScope{
		ids:              scope.ids.clone()
		special:          scope.special.clone()
		writable:         scope.writable.clone()
		event_parameters: scope.event_parameters.clone()
		component:        scope.component
	}
}

fn vml_var(path string) string {
	return path.replace('.', '_').replace('-', '_')
}

fn vml_quote(value string) string {
	return "'" + value.replace('\\', '\\\\').replace("'", "\\'").replace('\n', '\\n').replace('\r', '\\r').replace('\t', '\\t').replace(r'$', r'\$') + "'"
}

fn vml_interpolation_text(value string) string {
	return value.replace('\\', '\\\\').replace("'", "\\'").replace('\n', '\\n').replace('\r', '\\r').replace('\t', '\\t').replace(r'$', r'\$')
}

fn vml_stringify(expression string) string {
	return "'" + r'$' + '{' + expression + "}'"
}

fn vml_array_literal(elem_type string, values []string) string {
	return if values.len == 0 { '[]${elem_type}{}' } else { '[${values.join(', ')}]' }
}

// vml_condition drops the parentheses that enclose a whole lowered condition:
// V rejects `if (a < b) {` under -W.
fn vml_condition(expression string) string {
	if expression.len < 2 || expression[0] != `(` || expression[expression.len - 1] != `)` {
		return expression
	}
	mut depth := 0
	mut quote := u8(0)
	for i, ch in expression {
		if quote != 0 {
			if ch == quote && expression[i - 1] != `\\` { quote = 0 }
			continue
		}
		if ch == `'` || ch == `"` {
			quote = ch
		} else if ch == `(` {
			depth++
		} else if ch == `)` {
			depth--
			// The opening parenthesis closes before the end: `(a) + (b)`.
			if depth == 0 && i < expression.len - 1 { return expression }
		}
	}
	return expression[1..expression.len - 1]
}

// resolve_path maps a VML path to V: specials to their getters and
// `id.x/y/width/height` to the node's reactive geometry. It reports whether
// the path was bound; an unbound dotted path is kept for V to resolve.
fn (c &VmlCompiler) resolve_path(path string, scope VmlScope) (string, bool) {
	parts := path.split('.')
	if replacement := scope.special[parts[0]] {
		return replacement + if parts.len > 1 { '.' + parts[1..].join('.') } else { '' }, true
	}
	if node := scope.ids[parts[0]] {
		if parts.len == 2 && parts[1] in ['x', 'y', 'width', 'height'] {
			return '(' + node + '.geometry() or { panic(err) }).' + parts[1], true
		}
	}
	return path, path.contains('.')
}

// vml_node_output_scope is the scope following siblings see: an imported
// document's ids stay private, except the id of its root.
fn vml_node_output_scope(node &Node, incoming VmlScope, scope VmlScope) VmlScope {
	if !node.imported { return scope }
	mut exported := vml_clone_scope(incoming)
	if node.id.len > 0 {
		if variable := scope.ids[node.id] { exported.ids[node.id] = variable }
	}
	return exported
}
