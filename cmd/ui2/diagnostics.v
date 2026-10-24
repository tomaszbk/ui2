module main

import strings

// rewrite_vml_diagnostics words the compiler diagnostics located in a VML
// document in VML terms (see vml_message); other lines pass through.
fn rewrite_vml_diagnostics(output string) string {
	mut lines := []string{}
	for line in output.split_into_lines() {
		lines << rewrite_vml_diagnostic(line)
	}
	return lines.join('
')
}

fn rewrite_vml_diagnostic(line string) string {
	marker := '.vml:'
	at := line.index(marker) or { return line }
	for kind in [' error: ', ' warning: ', ' notice: '] {
		k := line.index_after(kind, at) or { continue }
		message_start := k + kind.len
		return line[..message_start] + vml_message(line[message_start..])
	}
	return line
}

// vml_message words a diagnostic located in a VML document in VML terms. The
// generic lowering builds each tag `X` as the props type `ui2.XProps`, so V names
// that type and its fields: `type \`ui2.SliderProps\` has no field named \`maxx\``
// reads `element \`Slider\` has no property named \`maxx\``.
fn vml_message(message string) string {
	if !message.contains('Props`') {
		return message
	}
	mut result := strings.new_builder(message.len)
	mut rest := message
	mut renamed := false
	for {
		start := rest.index('`') or { break }
		end := rest.index_after('`', start + 1) or { break }
		name := rest[start + 1..end]
		base := name.all_after_last('.')
		mut before := rest[..start]
		mut element := false
		if base.len > 'Props'.len && base.ends_with('Props') && base[0].is_capital() {
			for word in ['in struct literal of type ', 'struct literal of type ', 'type ', 'struct '] {
				if before.ends_with(word) {
					before = before[..before.len - word.len] + if word.starts_with('in ') {
						'of element '
					} else {
						'element '
					}
					element = true
					break
				}
			}
		}
		if element {
			module_prefix := if name.contains('.') && !name.starts_with('ui2.') {
				name.all_before_last('.') + '.'
			} else {
				''
			}
			result.write_string(before)
			result.write_string('`' + module_prefix + base.trim_string_right('Props') + '`')
			renamed = true
		} else {
			result.write_string(rest[..end + 1])
		}
		rest = rest[end + 1..]
	}
	result.write_string(rest)
	if !renamed {
		return message
	}
	return result.str().replace('has no field named', 'has no property named').replace('unknown field',
		'unknown property').replace('to field `', 'to property `')
}
