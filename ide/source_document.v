module main

// This is the designer's lossless projection of its literal form format. It
// never evaluates expressions or constructs UI; previews use the V compiler.
struct DesignerNode {
	tag      string
	id       string
	props    map[string]string
	children []DesignerNode
}

fn (node &DesignerNode) prop(name string) string { return node.props[name] or { '' } }

fn (node &DesignerNode) prop_or(name string, fallback string) string {
	return node.props[name] or { fallback }
}

fn (node &DesignerNode) prop_bool(name string) bool { return node.prop(name) == 'true' }

struct DesignerSource {
	source string
mut:
	pos   int
	depth int
}

fn (mut reader DesignerSource) whitespace() {
	for reader.pos < reader.source.len {
		if reader.source[reader.pos].is_space() {
			reader.pos++
			continue
		}
		if reader.source[reader.pos..].starts_with('//') {
			for reader.pos < reader.source.len && reader.source[reader.pos] != `\n` { reader.pos++ }
			continue
		}
		break
	}
}

fn (mut reader DesignerSource) take(character u8) ! {
	reader.whitespace()
	if reader.pos >= reader.source.len || reader.source[reader.pos] != character {
		return error('expected `${character.ascii_str()}` at byte ${reader.pos}; the visual designer accepts literal named arguments')
	}
	reader.pos++
}

fn (mut reader DesignerSource) name() !string {
	reader.whitespace()
	start := reader.pos
	for reader.pos < reader.source.len {
		character := reader.source[reader.pos]
		if !character.is_alnum() && character != `_` { break }
		reader.pos++
	}
	value := reader.source[start..reader.pos]
	if !valid_identifier(value) { return error('expected an identifier at byte ${start}') }
	return value
}

fn (mut reader DesignerSource) value(property string) !string {
	reader.whitespace()
	if reader.pos >= reader.source.len { return error('missing `${property}` value') }
	if reader.source[reader.pos] == `"` || reader.source[reader.pos] == `'` {
		quote := reader.source[reader.pos]
		reader.pos++
		mut value := []u8{}
		for reader.pos < reader.source.len {
			character := reader.source[reader.pos]
			reader.pos++
			if character == quote {
				text := value.bytestr()
				if text.contains('\${') {
					return error('`${property}` is dynamic; keep this document in source mode')
				}
				return text
			}
			if character == `\\` {
				if reader.pos >= reader.source.len { return error('unfinished string escape') }
				escaped := reader.source[reader.pos]
				reader.pos++
				match escaped {
					`n` { value << `\n` }
					`t` { value << `\t` }
					`r` { value << `\r` }
					`\\`, `"`, `'` { value << escaped }
					else { return error('unsupported string escape in `${property}`') }
				}
			} else {
				value << character
			}
		}
		return error('unfinished string in `${property}`')
	}
	start := reader.pos
	for reader.pos < reader.source.len && reader.source[reader.pos] !in [`,`, `)`] { reader.pos++ }
	value := reader.source[start..reader.pos].trim_space()
	if property.starts_with('on_') {
		if !valid_identifier(value) {
			return error('`${property}` must reference a named callback in the visual designer')
		}
	} else if property in ['hidden', 'checked', 'clickable'] {
		if value !in ['true', 'false'] { return error('`${property}` must be a boolean literal') }
	} else if property in ['background', 'color'] {
		parse_color_property(value) or { return error('`${property}` must be a #RRGGBB literal') }
	} else {
		parse_f64_property(value) or { return error('`${property}` must be a literal; keep expressions in source mode') }
	}
	return value
}

fn (mut reader DesignerSource) node() !DesignerNode {
	if reader.depth >= 64 { return error('designer nesting exceeds 64 levels') }
	reader.depth++
	defer { reader.depth-- }
	tag := reader.name()!
	mut props := map[string]string{}
	reader.whitespace()
	if reader.pos < reader.source.len && reader.source[reader.pos] == `(` {
		reader.pos++
		reader.whitespace()
		for reader.pos < reader.source.len && reader.source[reader.pos] != `)` {
			name := reader.name()!
			if name in props { return error('duplicate `${name}` argument on ${tag}') }
			reader.take(`:`)!
			props[name] = reader.value(name)!
			reader.whitespace()
			if reader.pos < reader.source.len && reader.source[reader.pos] == `)` { break }
			reader.take(`,`)!
			reader.whitespace()
		}
		reader.take(`)`)!
	}
	allowed := match tag {
		'Screen' { ['id', 'width', 'height', 'background'] }
		'Absolute' { []string{} }
		'Option' { ['text'] }
		else {
			['id', 'x', 'y', 'width', 'height', 'hidden', 'text', 'placeholder', 'source', 'background',
				'color', 'font_size', 'checked', 'corner_radius', 'on_tap', 'on_change', 'clickable']
		}
	}
	for property, _ in props {
		if property !in allowed {
			return error('`${property}` on ${tag} is not editable by the visual designer')
		}
	}
	mut children := []DesignerNode{}
	reader.whitespace()
	if reader.pos < reader.source.len && reader.source[reader.pos] == `{` {
		reader.pos++
		reader.whitespace()
		for reader.pos < reader.source.len && reader.source[reader.pos] != `}` {
			children << reader.node()!
			reader.whitespace()
		}
		reader.take(`}`)!
	}
	return DesignerNode{ tag: tag, id: props['id'] or { '' }, props: props, children: children }
}

fn designer_document(source string) !DesignerNode {
	mut reader := DesignerSource{ source: source }
	root := reader.node()!
	reader.whitespace()
	if reader.pos != source.len {
		return error('unexpected source at byte ${reader.pos}; use source mode for components and expressions')
	}
	return root
}
