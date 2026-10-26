module vml

import os
import strings

// The generator's configuration and the helpers the emitter (emit.v) shares.
// Tag `Slider` lowers to the props type `ui2.SliderProps`, every property to a
// field of it, and ui2's generic node runtime (`vml_document`, `vml_child`,
// `prop`, `bind`, `vml_repeat`) builds, retains and updates the tree.

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
// code: binding targets are paths, and enum values are bare names.
fn validate_vml_node(node &Node) ! {
	for property in node.properties {
		// Event payloads keep V's `.name`; property values are typed by their field.
		if !property.name.starts_with('on_') {
			if dotted := vml_dotted_enum(property.expr) {
				return error('${property.expr.source}:${dotted.line}:${dotted.column}: VML enum values omit the dot: use `${dotted.value[1..]}`')
			}
		}
		if property.name.starts_with('bind.') && property.expr.kind !in [.path, .index, .selector] {
			return error('${property.expr.source}:${property.expr.line}:${property.expr.column}: `${property.name}` must target a writable path')
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

// VmlGuard is a never-run generic function that makes V check a model path
// or a repeater list for the types each caller passes.
struct VmlGuard {
	ref_method string // the ref method whose target support the guard checks
	field_name string
	model_path string
	name       string
	array      bool
	location   Location
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
