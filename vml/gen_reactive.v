module vml


// vml_property_is_reactive reports whether a property reads a source that can
// change after the build: the app, theme tokens, scope specials or element
// geometry. Other properties are static fields of the props literal.
fn vml_property_is_reactive(property Property, scope VmlScope) bool {
	if property.expr.kind == .literal { return false }
	if vml_style_uses_theme(property.expr) { return true }
	if expr_uses_path(property.expr, 'app') { return true }
	for member, _ in scope.special {
		if !member.starts_with('__') && expr_uses_path(property.expr, member) { return true }
	}
	for id, _ in scope.ids {
		if expr_uses_path(property.expr, id) { return true }
	}
	return false
}

// scope_captures lists every capture a closure over `scope` may need;
// `finish_scope_captures` keeps the ones its body uses.
fn (c &VmlCompiler) scope_captures(scope VmlScope) []string {
	mut captures := []string{}
	if c.uses_app { captures << 'mut app' }
	for name, value in scope.special {
		if name.starts_with('__signal_') {
			if ('mut ' + value) !in captures { captures << 'mut ' + value }
		} else if !name.starts_with('__') && value.starts_with('vml_') && !value.contains('.') && value !in captures {
			captures << value
		}
	}
	for _, node in scope.ids {
		if node !in captures { captures << node }
	}
	return captures
}

// Lowered identifiers reflect the actual lexical scope, including nested item
// aliases and callbacks. Scan the completed body so quoted ids and comments do
// not turn unused outer bindings into captures.
fn (mut c VmlCompiler) finish_scope_captures(capture_start int, body_start int, candidates []string) {
	body := c.out.spart(body_start, c.out.len - body_start)
	captures := vml_used_captures(body, candidates)
	// Replacing only the capture list keeps the generated source-line mapping.
	tail := c.out.cut_to(capture_start)
	c.out.write_string('[' + captures.join(', ') + ']' + tail[2..])
}

// vml_used_captures keeps the candidates whose names the generated `body`
// reads as identifiers: not after a `.`, not inside string text or a comment,
// but inside `${...}` interpolations.
fn vml_used_captures(body string, candidates []string) []string {
	names := vml_identifiers(body)
	mut captures := []string{}
	for candidate in candidates {
		name := candidate.trim_string_left('mut ')
		if name in names && candidate !in captures { captures << candidate }
	}
	return captures
}

// vml_identifiers scans generated V for the identifiers it names. It only
// needs to understand the code the generator writes: quoted strings with
// `${}` interpolation, line comments and member access.
fn vml_identifiers(code string) map[string]bool {
	mut names := map[string]bool{}
	mut i := 0
	mut previous_dot := false
	// Each open string interpolation remembers the quote and brace depth to
	// return to when its `}` closes.
	mut quotes := []u8{}
	mut depths := []int{}
	mut depth := 0
	for i < code.len {
		ch := code[i]
		if quotes.len > 0 && (depths.len == 0 || depths.last() < 0) {
			// Inside string text.
			if ch == `\\` {
				i += 2
				continue
			}
			if ch == quotes.last() {
				quotes.delete_last()
				if depths.len > 0 { depths.delete_last() }
				i++
				previous_dot = false
				continue
			}
			if ch == `$` && i + 1 < code.len && code[i + 1] == `{` {
				depths[depths.len - 1] = depth
				i += 2
				continue
			}
			i++
			continue
		}
		if ch == `'` || ch == `"` {
			quotes << ch
			depths << -1
			i++
			continue
		}
		if ch == `/` && i + 1 < code.len && code[i + 1] == `/` {
			for i < code.len && code[i] != `\n` { i++ }
			continue
		}
		if ch == `{` {
			depth++
		} else if ch == `}` {
			if depths.len > 0 && depths.last() == depth {
				// Closes the interpolation: back to string text.
				depths[depths.len - 1] = -1
				i++
				continue
			}
			depth--
		}
		if ch.is_letter() || ch == `_` {
			start := i
			for i < code.len && (code[i].is_letter() || code[i].is_digit() || code[i] == `_`) { i++ }
			if !previous_dot { names[code[start..i]] = true }
			previous_dot = false
			continue
		}
		if ch != ` ` && ch != `\t` && ch != `\n` { previous_dot = ch == `.` }
		i++
	}
	return names
}
