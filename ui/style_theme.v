module ui2

// A theme supplies semantic tokens. Omitted local values inherit from the
// nearest component ancestor, then the built-in defaults. Replacing a local
// theme drops its old overrides, so inheritance remains predictable.
pub struct Theme {
pub:
	colors     map[string]u32
	spacing    map[string]f64
	radii      map[string]f64
	font_sizes map[string]f64
}

// default_theme is the light theme. Besides the general tokens it holds the
// kit's: surface and popover colors, the `on_*` text colors of filled tones,
// the interaction and control colors, and the control metrics (kit_tokens.v).
pub fn default_theme() Theme {
	return Theme{
		colors:     {
			'surface':       u32(0xffffff)
			'surface_muted': u32(0xf1f5f9)
			'popover':       u32(0xffffff)
			'accent':        u32(0x2563eb)
			'on_accent':     u32(0xffffff)
			'text':          u32(0x172033)
			'muted':         u32(0x64748b)
			'border':        u32(0xcbd5e1)
			'input':         u32(0xffffff)
			'input_border':  u32(0xcbd5e1)
			'success':       u32(0x15803d)
			'on_success':    u32(0xffffff)
			'warning':       u32(0xfbbf24)
			'on_warning':    u32(0x172033)
			'danger':        u32(0xb91c1c)
			'on_danger':     u32(0xffffff)
			'info':          u32(0x0369a1)
			'on_info':       u32(0xffffff)
			'focus_ring':    u32(0x2563eb)
			'hover':         u32(0xe4e8ed)
			'pressed':       u32(0xd7dbe1)
			'selection':     u32(0xdbeafe)
			'track':         u32(0xe2e8f0)
			'disabled_text': u32(0x94a3b8)
			'tooltip':       u32(0x172033)
			'on_tooltip':    u32(0xf8fafc)
			'backdrop':      u32(0x0f172a)
			'shadow':        u32(0)
			'black':         u32(0)
			'white':         u32(0xffffff)
			'red':           u32(0xdc2626)
			'green':         u32(0x22c55e)
			'blue':          u32(0x2563eb)
		}
		spacing:    {
			'none':                  f64(0)
			'xsmall':                f64(4)
			'small':                 f64(8)
			'medium':                f64(12)
			'large':                 f64(24)
			'control_small':         f64(6)
			'control_medium':        f64(8)
			'control_large':         f64(12)
			'gap_small':             f64(4)
			'gap_medium':            f64(6)
			'gap_large':             f64(8)
			'control_height_small':  f64(24)
			'control_height_medium': f64(32)
			'control_height_large':  f64(40)
		}
		radii:      {
			'none':           f64(0)
			'small':          f64(4)
			'medium':         f64(8)
			'large':          f64(12)
			'full':           f64(9999)
			'control_small':  f64(4)
			'control_medium': f64(6)
			'control_large':  f64(8)
			'popover':        f64(8)
			'dialog':         f64(12)
		}
		font_sizes: {
			'caption':        f64(12)
			'body':           f64(15)
			'title':          f64(24)
			'heading':        f64(32)
			'control_small':  f64(12)
			'control_medium': f64(14)
			'control_large':  f64(16)
		}
	}
}

// dark_theme is default_theme with the dark palette.
pub fn dark_theme() Theme {
	light := default_theme()
	mut colors := light.colors.clone()
	for name, value in {
		'surface':       u32(0x172033)
		'surface_muted': u32(0x263449)
		'popover':       u32(0x1e293b)
		'accent':        u32(0x93c5fd)
		'on_accent':     u32(0x172033)
		'text':          u32(0xf8fafc)
		'muted':         u32(0xb4c0d0)
		'border':        u32(0x475569)
		'input':         u32(0x0f172a)
		'input_border':  u32(0x475569)
		'success':       u32(0x86efac)
		'on_success':    u32(0x172033)
		'warning':       u32(0xfbbf24)
		'on_warning':    u32(0x172033)
		'danger':        u32(0xfca5a5)
		'on_danger':     u32(0x172033)
		'info':          u32(0x7dd3fc)
		'on_info':       u32(0x172033)
		'focus_ring':    u32(0x93c5fd)
		'hover':         u32(0x334054)
		'pressed':       u32(0x3f4c5e)
		'selection':     u32(0x1e3a8a)
		'track':         u32(0x334155)
		'disabled_text': u32(0x64748b)
		'tooltip':       u32(0xf8fafc)
		'on_tooltip':    u32(0x172033)
		'backdrop':      u32(0)
	} {
		colors[name] = value
	}
	return Theme{
		...light
		colors: colors
	}
}

fn (theme Theme) validate() ! {
	for name, _ in theme.colors {
		if name.trim_space().len == 0 { return error('theme color token requires a name') }
	}
	for family in [theme.spacing, theme.radii, theme.font_sizes]! {
		for name, value in family {
			if name.trim_space().len == 0 || !layout_finite(value) || value < 0 {
				return error('theme numeric tokens require a name and a finite non-negative value')
			}
		}
	}
}

fn (theme Theme) number_tokens() map[string]f64 {
	mut result := map[string]f64{}
	for name, value in theme.spacing { result['spacing:' + name] = value }
	for name, value in theme.radii { result['radius:' + name] = value }
	for name, value in theme.font_sizes { result['font_size:' + name] = value }
	return result
}

fn (component &CompiledVmlComponent) resolved_color_token(name string) !u32 {
	if value := component.theme.colors[name] { return value }
	if component.parent != unsafe { nil } { return component.parent.resolved_color_token(name) }
	if value := default_theme().colors[name] { return value }
	return error('unknown color token `${name}`')
}

fn (component &CompiledVmlComponent) resolved_number_token(key string) !f64 {
	family, name := key.all_before(':'), key.all_after(':')
	match family {
		'spacing' {
			if value := component.theme.spacing[name] { return value }
		}
		'radius' {
			if value := component.theme.radii[name] { return value }
		}
		'font_size' {
			if value := component.theme.font_sizes[name] { return value }
		}
		else { return error('unknown theme token family `${family}`') }
	}
	if component.parent != unsafe { nil } { return component.parent.resolved_number_token(key) }
	if value := default_theme().number_tokens()[key] { return value }
	return error('unknown theme token `${family}.${name}`')
}

// The compiler prepares only tokens used by this owner before creating pure
// style memos. Components without themed presentation allocate no token sources.
pub fn (mut component CompiledVmlComponent) prepare_theme_tokens(names []string) ! {
	component.require_alive()!
	for key in names {
		if key.starts_with('color:') {
			name := key.all_after(':')
			if name in component.theme_colors { continue }
			value := component.resolved_color_token(name)!
			component.theme_colors[name] = new_signal(mut component.scope, value,
				name: '@color.' + name
			)!
		} else {
			if key in component.theme_numbers { continue }
			value := component.resolved_number_token(key)!
			signal := new_signal(mut component.scope, value, name: '@' + key)!
			component.theme_numbers[key] = signal
			name := key.all_after(':')
			match key.all_before(':') {
				'spacing' { component.theme_spacing[name] = signal }
				'radius' { component.theme_radii[name] = signal }
				'font_size' { component.theme_font_sizes[name] = signal }
				else {}
			}
		}
	}
}

// Getters only read prepared signals. They are safe inside pure style memos,
// and each consumer subscribes to exactly the semantic tokens it reads.
pub fn (mut component CompiledVmlComponent) color_token(name string) !u32 {
	component.require_alive()!
	if name !in component.theme_colors { component.prepare_theme_tokens(['color:' + name])! }
	mut signal := component.theme_colors[name] or { return error('unknown color token `${name}`') }
	return signal.get()!
}

fn (mut component CompiledVmlComponent) number_token(family string, name string) !f64 {
	component.require_alive()!
	mut signal := unsafe { &Signal[f64](nil) }
	match family {
		'spacing' { signal = component.theme_spacing[name] or { unsafe { nil } } }
		'radius' { signal = component.theme_radii[name] or { unsafe { nil } } }
		'font_size' { signal = component.theme_font_sizes[name] or { unsafe { nil } } }
		else { return error('unknown theme token family `${family}`') }
	}
	if signal == unsafe { nil } {
		key := family + ':' + name
		component.prepare_theme_tokens([key])!
		signal = component.theme_numbers[key] or { return error('unknown theme token `${family}.${name}`') }
	}
	return signal.get()!
}

pub fn (mut component CompiledVmlComponent) spacing_token(name string) !f64 {
	return component.number_token('spacing', name)
}

pub fn (mut component CompiledVmlComponent) radius_token(name string) !f64 {
	return component.number_token('radius', name)
}

pub fn (mut component CompiledVmlComponent) font_size_token(name string) !f64 {
	return component.number_token('font_size', name)
}

fn (mut component CompiledVmlComponent) update_theme_tokens() ! {
	// Themed widgets read the kit tokens through the cache and rebuild on the
	// revision, in the same batch as the token signals.
	component.kit_tokens_cache = unsafe { nil }
	if component.theme_revision != unsafe { nil } {
		component.theme_revision.set(component.theme_revision.peek()! + 1)!
	}
	for name, mut signal in component.theme_colors {
		signal.set(component.resolved_color_token(name)!)!
	}
	for key, mut signal in component.theme_numbers {
		signal.set(component.resolved_number_token(key)!)!
	}
	for _, mut child in component.children {
		if !child.is_disposed() { child.update_theme_tokens()! }
	}
}

fn (component &CompiledVmlComponent) theme_token_sources_valid() ! {
	for name, _ in component.theme_colors { component.resolved_color_token(name)! }
	for key, _ in component.theme_numbers { component.resolved_number_token(key)! }
	for _, child in component.children {
		if !child.is_disposed() { child.theme_token_sources_valid()! }
	}
}

pub fn (mut component CompiledVmlComponent) set_theme(theme Theme) ! {
	component.require_alive()!
	component.runtime.require_action()!
	theme.validate()!
	owned := Theme{ colors: theme.colors.clone(), spacing: theme.spacing.clone(), radii: theme.radii.clone(), font_sizes: theme.font_sizes.clone() }
	previous := component.theme
	component.theme = owned
	component.theme_token_sources_valid() or {
		component.theme = previous
		return error('theme replacement would remove a used token: ' + err.msg())
	}
	component.runtime.batch(fn [mut component] () ! {
		component.update_theme_tokens()!
	})!
}

// Applications can configure a compiled document or a component subtree from
// its returned Element without retaining compiler-generated owner variables.
pub fn set_vml_theme(element Element, theme Theme) ! {
	if element.compiled_node == unsafe { nil } {
		return error('theme requires a compiled VML element')
	}
	mut component := element.compiled_node.component
	component.set_theme(theme)!
}
