module vml

import strings

// vml_write_mapped writes generated lines, each preceded by a `#line`
// directive whenever its VML location changes, so V reports errors in the
// generated code at the document line that produced it. V accepts the
// directive only between statements, so lines that continue a statement
// (closing braces and parentheses) keep the previous mapping.
fn vml_write_mapped(mut out strings.Builder, text string, locations []Location) {
	lines := text.split_into_lines()
	// After `#line N "file"`, V numbers the following physical lines N + 1,
	// N + 2, ...: track the line V assumes and correct it where it drifts.
	mut mapped_path := ''
	mut mapped_line := 0
	for index, line in lines {
		location := if index < locations.len { locations[index] } else { Location{} }
		trimmed := line.trim_space()
		starts_statement := trimmed.len > 0 && trimmed[0] !in [`}`, `)`, `]`, `,`, `.`]
		if starts_statement && location.path.len > 0 && location.line > 0
			&& (location.path != mapped_path || location.line != mapped_line) {
			out.writeln('#line ${location.line} "${location.path.replace('"', '\\"')}"')
			mapped_path = location.path
			mapped_line = location.line
		}
		out.writeln(line)
		mapped_line += line.count('\n') + 1
	}
}

// vml_generic_closures gives the builder's type parameter to every closure
// that captures `app`: a closure over a generic value is generic itself.
fn vml_generic_closures(code string) string {
	mut out := strings.new_builder(code.len + 64)
	mut i := 0
	for i < code.len {
		at := code.index_after('fn [', i) or { -1 }
		if at < 0 {
			out.write_string(code[i..])
			break
		}
		close := code.index_after(']', at + 4) or { -1 }
		if close < 0 {
			out.write_string(code[i..])
			break
		}
		captures := code[at + 4..close]
		out.write_string(code[i..close + 1])
		names := captures.split(',').map(it.trim_space().trim_string_left('mut ').trim_string_left('&'))
		if 'app' in names {
			out.write_string(' [A]')
		}
		i = close + 1
	}
	return out.str()
}
