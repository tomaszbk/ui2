module vml

import os

// Library is a document with its component definitions kept apart:
// `parse_library` does not expand invocations. Each invocation keeps its
// properties, id and slot content (its children), and `component_ref` names
// its definition in `components`, keyed `file#Name`. Definitions keep their
// `Slot` elements, so a consumer can build one definition once and fill its
// slots per invocation.
@[heap]
pub struct Library {
pub mut:
	root       &Node = unsafe { nil }
	components map[string]&Node
}

// parse_library parses the document at `path` and the documents it imports,
// like `parse_file`, without expanding component invocations.
pub fn parse_library(path string, config ParseConfig) !&Library {
	mut library := &Library{}
	library.root = library_file(path, '', [], config, mut library)!
	return library
}

// parse_library_source parses `source` as the document at `path`, like
// `parse_library`. Without a path its imports resolve in the working
// directory and its locations name no file.
pub fn parse_library_source(source string, path string, config ParseConfig) !&Library {
	mut library := &Library{}
	file := if path.len > 0 { os.real_path(path) } else { '' }
	library.root = library_document(source, file, '', [], config, mut library)!
	return library
}

// component_key is the key of a definition: the real path of its file and its
// name.
pub fn component_key(file string, name string) string {
	return '${file}#${name}'
}

fn library_file(path string, expected_module string, stack []string, config ParseConfig, mut library Library) !&Node {
	file := os.real_path(path)
	mut next_stack := stack.clone()
	next_stack << file
	if file in stack {
		return error('${file}:1:1: cyclic VML import: ${next_stack.join(' -> ')}')
	}
	source := read_source(file, config) or { return error('${file}:1:1: ${err}') }
	return library_document(source, file, expected_module, next_stack, config, mut library)
}

fn library_document(source string, file string, expected_module string, stack []string, config ParseConfig, mut library Library) !&Node {
	tokens := tokenize(source) or {
		return error(if file.len > 0 { '${file}: ${err}' } else { err.msg() })
	}
	mut parser := Parser{
		tokens:          tokens
		file:            file
		config:          config
		keep_components: true
	}
	imports := parser.parse_directives()!
	mut root := parser.parse_document()!
	if expected_module != '' && root.component_name != expected_module {
		return error('${file}:1:1: VML import `${expected_module}` requires `component ${expected_module}(...)`')
	}
	parser.take(.eof) or { return error('${file}: ${err}') }
	set_source(mut root, file)
	mut refs := map[string]string{}
	for name, _ in parser.local_definitions {
		refs[name] = component_key(file, name)
	}
	for name in imports {
		import_path := resolve_import(os.dir(file), name.text, config) or {
			return error('${file}:${name.line}:${name.column}: ${err}')
		}
		imported := library_file(import_path, name.text, stack, config, mut library)!
		refs[name.text] = component_key(os.real_path(import_path), imported.component_name)
	}
	for name, definition in parser.local_definitions {
		mut def := definition
		set_source(mut def, file)
		annotate_invocations(mut def, refs)!
		if validate := config.validate_document {
			validate(def, true)!
		}
		library.components[component_key(file, name)] = def
	}
	if root.tag != component_tag {
		if key := refs[root.tag] {
			root.component_ref = key
		}
		annotate_invocations(mut root, refs)!
		if validate := config.validate_document {
			validate(root, expected_module != '')!
		}
	}
	return root
}

// annotate_invocations marks the invocations under `node` with the key of
// their definition and checks their slot content against nothing yet: the
// definition's slots are checked where the invocation is resolved.
fn annotate_invocations(mut node Node, refs map[string]string) ! {
	for mut child in node.children {
		if key := refs[child.tag] {
			child.component_ref = key
		}
		annotate_invocations(mut child, refs)!
	}
}
