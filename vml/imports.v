module vml

import os

// Components of other files. A tag names a component of another file in three
// ways, like V names functions of other modules:
// * `Name`, a component of the document's own folder (`name.vml` or
//   `Name.vml` declaring `component Name(...)`), with no import;
// * `Name` after `import widgets { Name }`, a component of the module folder
//   `widgets`;
// * `widgets.Name` after `import widgets`.
// A module path `a.b` is the folder `a/b` under the project root (the nearest
// folder above the document with a `v.mod`), then under the V modules folder
// (`~/.vmodules`). A component file must end with `component Name(...)`. A
// dotted tag whose prefix is not an imported module names a V widget of that
// module (`pkg.Gauge`, built from `pkg.GaugeProps`).

// Import is one `import path` or `import path { Name, ... }` directive.
pub struct Import {
pub:
	path   string
	alias  string
	names  []string
	line   int
	column int
}

// ComponentFile is the file and name of a component a tag names.
struct ComponentFile {
	path string
	name string
}

// parse_file parses the document at `path` and, recursively, the documents
// whose components it uses, and expands their invocations. `Node.source` is
// set to the real path of each document, and `config.validate_document` runs
// for every document.
pub fn parse_file(path string, config ParseConfig) !&Node {
	return parse_file_in(path, '', [], config)
}

fn parse_file_in(path string, expected_component string, stack []string, config ParseConfig) !&Node {
	file := os.real_path(path)
	mut next_stack := stack.clone()
	next_stack << file
	if file in stack {
		return error('${file}:1:1: cyclic VML import: ${next_stack.join(' -> ')}')
	}
	source := read_source(file, config) or { return error('${file}:1:1: ${err}') }
	tokens := tokenize(source) or { return error('${file}: ${err}') }
	mut parser := Parser{ tokens: tokens, file: file, config: config }
	imports := parser.parse_directives()!
	mut root := parser.parse_document()!
	if expected_component != '' && root.component_name != expected_component {
		return error('${file}:1:1: `${expected_component}` requires `component ${expected_component}(...)`')
	}
	parser.take(.eof) or { return error('${file}: ${err}') }
	set_source(mut root, file)
	// Local components are expanded: the tags left name other files' components.
	files := component_files(file, [root], map[string]&Node{}, imports, config)!
	mut modules := map[string]&Node{}
	for tag, component in files {
		modules[tag] = parse_file_in(component.path, component.name, next_stack, config)!
	}
	root = expand_imports(root, modules)!
	if validate := config.validate_document { validate(root, expected_component != '')! }
	return root
}

// parse_directives parses the leading `import` directives. `module`
// directives are rejected.
pub fn (mut parser Parser) parse_directives() ![]Import {
	mut imports := []Import{}
	for parser.at().text in ['module', 'import'] {
		directive := parser.take(.name)!
		name := parser.take(.name)!
		if directive.text == 'module' {
			return error('${parser.file}:${directive.line}:${directive.column}: module declarations were replaced by component signatures')
		}
		segments := name.text.split('.')
		if segments.any(it.len == 0 || !is_module_name(it)) {
			if segments.len == 1 && name.text.len > 0 && name.text[0].is_capital() {
				return error('${parser.file}:${name.line}:${name.column}: components of the same folder need no import; `import` names a module folder, as in `import widgets { ${name.text} }`')
			}
			return error('${parser.file}:${name.line}:${name.column}: invalid VML module `${name.text}`')
		}
		mut names := []string{}
		if parser.at().kind == .lbrace {
			parser.pos++
			for parser.at().kind != .rbrace {
				component := parser.take(.name)!
				if component.text.contains('.') || !component.text[0].is_capital() {
					return error('${parser.file}:${component.line}:${component.column}: `import ${name.text} { ... }` lists component names')
				}
				if component.text in names {
					return error('${parser.file}:${component.line}:${component.column}: duplicate VML import `${component.text}`')
				}
				names << component.text
				if parser.at().kind != .comma { break }
				parser.pos++
			}
			parser.take(.rbrace)!
		}
		alias := segments.last()
		if imports.any(it.alias == alias) {
			return error('${parser.file}:${name.line}:${name.column}: duplicate VML import `${name.text}`')
		}
		imports << Import{ path: name.text, alias: alias, names: names, line: name.line, column: name.column }
	}
	return imports
}

fn is_module_name(name string) bool {
	return name.len > 0 && !name[0].is_capital() && !name[0].is_digit()
		&& name.bytes().all(it.is_alnum() || it == `_`)
}

// component_files maps the tags used in `nodes` that name components of other
// files to those files. Tags of local definitions name those definitions.
fn component_files(file string, nodes []&Node, local map[string]&Node, imports []Import, config ParseConfig) !map[string]ComponentFile {
	mut tags := map[string]Location{}
	for node in nodes { collect_tags(node, mut tags) }
	mut files := map[string]ComponentFile{}
	mut selected := map[string]Import{}
	mut qualified := map[string]Import{}
	for directive in imports {
		for name in directive.names {
			if name in local {
				return error('${file}:${directive.line}:${directive.column}: imported `${name}` collides with the local component `${name}`')
			}
			selected[name] = directive
		}
		if directive.names.len == 0 { qualified[directive.alias] = directive }
	}
	for tag, location in tags {
		if tag in local { continue }
		if tag.contains('.') {
			alias := tag.all_before_last('.')
			directive := qualified[alias] or { continue }
			name := tag.all_after_last('.')
			path := module_component(file, directive, name, config) or {
				return error('${file}:${location.line}:${location.column}: ${err}')
			}
			files[tag] = ComponentFile{ path: path, name: name }
		} else if directive := selected[tag] {
			path := module_component(file, directive, tag, config) or {
				return error('${file}:${location.line}:${location.column}: ${err}')
			}
			files[tag] = ComponentFile{ path: path, name: tag }
		} else if file.len > 0 {
			for candidate in component_candidates(os.dir(file), tag) {
				// A file of the folder that is not that component (a screen
				// `grid.vml` next to a `Grid` use) leaves the tag to the widget.
				if candidate != file && source_exists(candidate, config)
					&& declares_component(candidate, tag, config) {
					files[tag] = ComponentFile{ path: candidate, name: tag }
					break
				}
			}
		}
	}
	for directive in imports {
		for name in directive.names {
			if name !in files {
				// An unused selected component must still exist.
				module_component(file, directive, name, config) or {
					return error('${file}:${directive.line}:${directive.column}: ${err}')
				}
			}
		}
	}
	return files
}

// collect_tags records the first use of every tag of a document.
fn collect_tags(node &Node, mut tags map[string]Location) {
	if node.tag != component_tag && !is_structural(node.tag) && node.tag != 'Slot'
		&& node.tag !in tags && node.tag.len > 0 && node.tag.all_after_last('.')[0].is_capital() {
		tags[node.tag] = Location{ path: node.source, line: node.line, column: node.column }
	}
	for child in node.children { collect_tags(child, mut tags) }
}

// module_component finds the file of component `name` of an imported module.
fn module_component(file string, directive Import, name string, config ParseConfig) !string {
	mut tried := []string{}
	for folder in module_folders(file, directive.path, config) {
		for candidate in component_candidates(folder, name) {
			if source_exists(candidate, config) { return candidate }
			tried << candidate
		}
	}
	return error('VML module `${directive.path}` has no component `${name}` (looked for ${tried.join(', ')})')
}

// module_folders are the folders a module path names, in lookup order: under
// the project root, then under the V modules folder.
fn module_folders(file string, path string, config ParseConfig) []string {
	relative := path.replace('.', os.path_separator)
	mut folders := []string{}
	start := if file.len > 0 { os.dir(file) } else { os.getwd() }
	mut dir := start
	for {
		if source_exists(os.join_path(dir, 'v.mod'), config) {
			folders << os.join_path(dir, relative)
			break
		}
		parent := os.dir(dir)
		if parent == dir || parent.len == 0 { break }
		dir = parent
	}
	if folders.len == 0 { folders << os.join_path(start, relative) }
	folders << os.join_path(os.vmodules_dir(), relative)
	return folders
}

// component_candidates are the files component `name` can live in within
// `folder`: `todo_item.vml` or `TodoItem.vml` for `TodoItem`.
fn component_candidates(folder string, name string) []string {
	mut snake := ''
	for index, ch in name {
		if ch >= `A` && ch <= `Z` {
			if index > 0 { snake += '_' }
			snake += [ch].bytestr().to_lower()
		} else {
			snake += [ch].bytestr()
		}
	}
	return [os.join_path(folder, '${snake}.vml'), os.join_path(folder, '${name}.vml')]
}

fn declares_component(path string, name string, config ParseConfig) bool {
	source := read_source(path, config) or { return false }
	return source.contains('component ${name}(')
}

fn read_source(path string, config ParseConfig) !string {
	if read := config.read_file {
		return read(path)
	}
	return os.read_file(path)
}

fn source_exists(path string, config ParseConfig) bool {
	if is_file := config.is_file {
		return is_file(path)
	}
	return os.is_file(path)
}

// import_candidates returns, for each module import of `source`, the folders
// its components are looked up in, for cache dependency tracking.
pub fn import_candidates(source string, directory string) ![][]string {
	mut parser := Parser{ tokens: tokenize(source)! }
	imports := parser.parse_directives()!
	file := os.join_path(directory, '__document__.vml')
	mut result := [][]string{}
	for directive in imports { result << module_folders(file, directive.path, ParseConfig{}) }
	return result
}

// Remap only the reused definition, before caller overrides/children are added.
// Expression copies keep separate invocations independent and retain locations.
fn expand_imports(node &Node, modules map[string]&Node) !&Node {
	mut result := clone_node(node)
	if imported := modules[node.tag] {
		result = clone_node(imported)
		result.imported = true
		result.properties = node.properties.clone()
		result.id = node.id
		mut content := map[string][]&Node{}
		for input in result.inputs { if input.typ == 'slot' { content[input.name] = []&Node{} } }
		if node.children.len > 0 && content.len == 0 {
			return error('component `${node.tag}` does not declare a content slot')
		}
		if node.children.any(it.tag == 'Slot') {
			for child in node.children {
				if child.tag != 'Slot' {
					return error('named slot content requires Slot(name: "name") blocks')
				}
				name := if property := find_property(child, 'name') {
					property.expr.value
				} else {
					'content'
				}
				if name !in content { return error('unknown component slot `${name}`') }
				mut values := content[name] or { []&Node{} }
				for value in child.children {
					values << expand_imports(value, modules)!
				}
				content[name] = values
			}
		} else if node.children.len > 0 {
			if 'content' !in content {
				return error('implicit content requires a slot named `content`')
			}
			mut values := content['content'] or { []&Node{} }
			for child in node.children { values << expand_imports(child, modules)! }
			content['content'] = values
		}
		result.children[0] = expand_slots(result.children[0], content)!
		return result
	}
	mut children := []&Node{}
	for child in result.children { children << expand_imports(child, modules)! }
	result.children = children
	return result
}

fn expand_slots(node &Node, content map[string][]&Node) !&Node {
	mut result := clone_node(node)
	mut children := []&Node{}
	for child in result.children {
		if child.tag == 'Slot' {
			name := if property := find_property(child, 'name') {
				property.expr.value
			} else {
				'content'
			}
			supplied := content[name] or { return error('unknown slot `${name}`') }
			for value in supplied {
				children << &Node{ ...clone_node(value), caller_content: true }
			}
		} else if child.tag == component_tag {
			children << child
		} else {
			children << expand_slots(child, content)!
		}
	}
	result.children = children
	return result
}
