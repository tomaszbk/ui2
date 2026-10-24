module vml

import strings

fn (mut c VmlCompiler) writeln(line string) {
	c.out.writeln(line)
	for _ in 0 .. line.count('\n') + 1 { c.locations << c.location }
}

// Generic guards let V validate declared list and key types even for empty lists.
// They never run: the call sits behind a generated non-constant false, so V
// type-checks it without reporting a constant condition in generated code.
fn (mut c VmlCompiler) write_list_guard(value string, suffix string, array bool) {
	name := '${c.guard_prefix}_${suffix}_' + if array { 'array' } else { 'key' }
	c.guards << VmlGuard{ name: name, array: array, location: c.location }
	c.writeln('\tif ${c.guard_prefix}_unreachable() { ${name}(${value}) }')
}

// once reports whether the compile-time check `key` is new. The checks only
// instantiate generic guards or comptime loops, so one per document suffices.
fn (mut c VmlCompiler) once(key string) bool {
	if key in c.emitted_checks { return false }
	c.emitted_checks[key] = true
	return true
}

fn (mut c VmlCompiler) write_field_guard(value string, field_name string, model_path string) {
	if !c.once('field:${value}:${field_name}') { return }
	name := '${c.guard_prefix}_field_${c.guards.len}'
	c.guards << VmlGuard{ name: name, field_name: field_name, model_path: model_path, location: c.location }
	c.writeln('\tif ${c.guard_prefix}_unreachable() { ${name}(${value}) }')
}

fn (mut c VmlCompiler) write_list_guards() {
	if c.guards.len > 0 || c.uses_unreachable {
		c.writeln('fn ${c.guard_prefix}_unreachable() bool { return false }')
	}
	for guard in c.guards {
		c.location = guard.location
		c.writeln('fn ${guard.name}[T](value T) {')
		c.writeln('\t_ = value')
		if guard.field_name.len > 0 {
			// Reflection marks interface fields as private although they are public contracts.
			// Follow pointer schemas without reading a value: these guards are never executed.
			c.writeln('\t$if T is $pointer { ${guard.name}(unsafe { *value }) } $else $if T !is $interface {')
			c.writeln('\t\t$for field in T.fields {')
			c.writeln('\t\t\t$if field.name == ${vml_quote(guard.field_name)} {')
			c.writeln('\t\t\t\t$if !field.is_pub { $compile_error(' + vml_quote('VML model path `${guard.model_path}` must use public fields') + ') }')
			c.writeln('\t\t\t}')
			c.writeln('\t\t}')
			c.writeln('\t}')
		} else if guard.array {
			c.writeln("\t$if T !is $array { $compile_error('Repeater model must be an array') }")
		} else {
			c.writeln("\t$if T !is string && T !is $int && T !is $float && T !is bool { $compile_error('Repeater key must be a scalar value') }")
		}
		c.writeln('}')
	}
}

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
