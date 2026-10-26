module vml

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
