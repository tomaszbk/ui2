module ui2

import math

// KitTokens are a theme's kit tokens resolved into typed fields. A component
// reads them with ctx.tokens() once per build, never through the theme maps;
// its owner resolves them once per theme change. The names and defaults are
// the theme's (default_theme, dark_theme).
pub struct KitTokens {
pub:
	// Colors. `on_*` is the text drawn over the color of the same name.
	surface       u32
	surface_muted u32
	popover       u32
	text          u32
	muted         u32 // secondary text
	border        u32
	input         u32
	input_border  u32
	accent        u32
	on_accent     u32
	success       u32
	on_success    u32
	warning       u32
	on_warning    u32
	danger        u32
	on_danger     u32
	info          u32
	on_info       u32
	focus_ring    u32
	hover         u32
	pressed       u32
	selection     u32
	track         u32
	disabled_text u32
	tooltip       u32
	on_tooltip    u32
	backdrop      u32
	shadow        u32
	// Spacing, radii and type sizes.
	space_xsmall   f64
	space_small    f64
	space_medium   f64
	space_large    f64
	radius_small   f64
	radius_medium  f64
	radius_large   f64
	radius_full    f64
	radius_popover f64
	radius_dialog  f64
	font_caption   f64
	font_body      f64
	font_title     f64
	font_heading   f64
	// Control metrics by ControlSize: small, medium, large.
	control_height  [3]f64
	control_padding [3]f64
	control_gap     [3]f64
	control_radius  [3]f64
	control_font    [3]f64
	// dark is true when the surface is dark. It sets the scrim opacity and
	// the shadow strength.
	dark bool
}

// ControlMetrics are the sizes of a control at one ControlSize. height is a
// floor: a control is at least that tall in a Flex parent (VmlSizedControl),
// and padding_y centers one line of text in it.
pub struct ControlMetrics {
pub:
	height    f64
	font_size f64
	padding_x f64 // 1.5 times the control padding token, as GPUI Kit's buttons
	padding_y f64
	gap       f64
	radius    f64
	icon      f64 // an icon beside the control's text
}

// VmlThemed marks a widget whose build reads ctx.tokens(): it rebuilds, and
// its layout floor is read again, when its owner's theme changes.
pub interface VmlThemed {
	vml_themed()
}

// VmlSizedControl marks a widget that is a control of a ControlSize: in a
// Flex parent it is at least the control height of its size tall, unless its
// height is authored, so controls of one size line up in a row.
pub interface VmlSizedControl {
	control_size() ControlSize
}

const kit_default_tokens = kit_tokens(default_theme())

// tokens are the kit tokens of the owner the widget is built in, or the
// defaults without one. Declare vml_themed() on a widget that reads them.
pub fn (ctx VmlBuildContext) tokens() KitTokens {
	if ctx.owner == unsafe { nil } {
		return kit_default_tokens
	}
	mut owner := ctx.owner
	return owner.kit_tokens()
}

// kit_tokens resolves a theme's kit tokens; a token the theme leaves out has
// its default_theme value.
pub fn kit_tokens(theme Theme) KitTokens {
	// A reader, not closures: kit_default_tokens is a constant, and closures
	// cannot run while constants are initialized.
	r := KitThemeReader{
		theme:    theme
		defaults: default_theme()
	}
	surface := r.color('surface')
	return KitTokens{
		surface:         surface
		surface_muted:   r.color('surface_muted')
		popover:         r.color('popover')
		text:            r.color('text')
		muted:           r.color('muted')
		border:          r.color('border')
		input:           r.color('input')
		input_border:    r.color('input_border')
		accent:          r.color('accent')
		on_accent:       r.color('on_accent')
		success:         r.color('success')
		on_success:      r.color('on_success')
		warning:         r.color('warning')
		on_warning:      r.color('on_warning')
		danger:          r.color('danger')
		on_danger:       r.color('on_danger')
		info:            r.color('info')
		on_info:         r.color('on_info')
		focus_ring:      r.color('focus_ring')
		hover:           r.color('hover')
		pressed:         r.color('pressed')
		selection:       r.color('selection')
		track:           r.color('track')
		disabled_text:   r.color('disabled_text')
		tooltip:         r.color('tooltip')
		on_tooltip:      r.color('on_tooltip')
		backdrop:        r.color('backdrop')
		shadow:          r.color('shadow')
		space_xsmall:    r.spacing('xsmall')
		space_small:     r.spacing('small')
		space_medium:    r.spacing('medium')
		space_large:     r.spacing('large')
		radius_small:    r.radius('small')
		radius_medium:   r.radius('medium')
		radius_large:    r.radius('large')
		radius_full:     r.radius('full')
		radius_popover:  r.radius('popover')
		radius_dialog:   r.radius('dialog')
		font_caption:    r.font('caption')
		font_body:       r.font('body')
		font_title:      r.font('title')
		font_heading:    r.font('heading')
		control_height:  [r.spacing('control_height_small'), r.spacing('control_height_medium'),
			r.spacing('control_height_large')]!
		control_padding: [r.spacing('control_small'), r.spacing('control_medium'),
			r.spacing('control_large')]!
		control_gap:     [r.spacing('gap_small'), r.spacing('gap_medium'), r.spacing('gap_large')]!
		control_radius:  [r.radius('control_small'), r.radius('control_medium'),
			r.radius('control_large')]!
		control_font:    [r.font('control_small'), r.font('control_medium'), r.font('control_large')]!
		dark:            kit_luminance(surface) < 0.5
	}
}

struct KitThemeReader {
	theme    Theme
	defaults Theme
}

fn (r &KitThemeReader) color(name string) u32 {
	return r.theme.colors[name] or { r.defaults.colors[name] or { 0 } }
}

fn (r &KitThemeReader) spacing(name string) f64 {
	return r.theme.spacing[name] or { r.defaults.spacing[name] or { 0 } }
}

fn (r &KitThemeReader) radius(name string) f64 {
	return r.theme.radii[name] or { r.defaults.radii[name] or { 0 } }
}

fn (r &KitThemeReader) font(name string) f64 {
	return r.theme.font_sizes[name] or { r.defaults.font_sizes[name] or { 0 } }
}

// metrics are the control sizes of a ControlSize.
pub fn (t KitTokens) metrics(size ControlSize) ControlMetrics {
	i := int(size)
	height := t.control_height[i]
	font_size := t.control_font[i]
	return ControlMetrics{
		height:    height
		font_size: font_size
		padding_x: t.control_padding[i] * 1.5
		padding_y: if height > font_line_height(font_size) {
			(height - font_line_height(font_size)) / 2
		} else {
			0.0
		}
		gap:       t.control_gap[i]
		radius:    t.control_radius[i]
		icon:      math.round(font_size * 1.15)
	}
}

// tone_colors are the fill of a tone and the text drawn over it. Neutral is
// the muted surface with the normal text.
pub fn (t KitTokens) tone_colors(tone Tone) (u32, u32) {
	return match tone {
		.neutral { t.surface_muted, t.text }
		.primary { t.accent, t.on_accent }
		.info { t.info, t.on_info }
		.success { t.success, t.on_success }
		.warning { t.warning, t.on_warning }
		.danger { t.danger, t.on_danger }
	}
}

// popup_shadow is the drop shadow of a floating surface: a popover, menu,
// hover card, dialog or sheet. It is stronger on a dark surface.
pub fn (t KitTokens) popup_shadow() BoxShadow {
	return box_shadow(t.shadow, if t.dark { 0.4 } else { 0.16 }, 24, 8)
}

// card_shadow is the lighter shadow of a surface that floats close to the
// page, such as a toast.
pub fn (t KitTokens) card_shadow() BoxShadow {
	return box_shadow(t.shadow, if t.dark { 0.32 } else { 0.12 }, 16, 4)
}

// scrim_opacity is the opacity of a modal backdrop in the backdrop color.
pub fn (t KitTokens) scrim_opacity() f64 {
	return if t.dark { 0.6 } else { 0.4 }
}

// kit_theme is the theme a component's kit tokens resolve against: each
// ancestor's local theme from the root down, then its own.
fn (component &CompiledVmlComponent) kit_theme() Theme {
	mut chain := []&CompiledVmlComponent{}
	mut current := unsafe { component }
	for current != unsafe { nil } {
		chain << current
		current = current.parent
	}
	mut colors := map[string]u32{}
	mut spacing := map[string]f64{}
	mut radii := map[string]f64{}
	mut font_sizes := map[string]f64{}
	for i := chain.len - 1; i >= 0; i-- {
		theme := chain[i].theme
		for name, value in theme.colors {
			colors[name] = value
		}
		for name, value in theme.spacing {
			spacing[name] = value
		}
		for name, value in theme.radii {
			radii[name] = value
		}
		for name, value in theme.font_sizes {
			font_sizes[name] = value
		}
	}
	return Theme{
		colors:     colors
		spacing:    spacing
		radii:      radii
		font_sizes: font_sizes
	}
}

// kit_tokens are the component's kit tokens, resolved on first use after a
// theme change (update_theme_tokens drops the cache).
fn (mut component CompiledVmlComponent) kit_tokens() KitTokens {
	if component.kit_tokens_cache == unsafe { nil } {
		component.kit_tokens_cache = &KitTokens{
			...kit_tokens(component.kit_theme())
		}
	}
	return *component.kit_tokens_cache
}

// theme_revision_signal is the component's theme revision, created by the
// first themed widget. Like a node's geometry signal it is created outside
// any running computation, so it belongs to the component.
fn (mut component CompiledVmlComponent) theme_revision_signal() !&Signal[u64] {
	if component.theme_revision == unsafe { nil } {
		mut runtime := component.runtime
		running := runtime.stack
		runtime.stack = []&SignalNode{}
		signal := new_signal(mut component.scope, u64(0), name: '@theme')
		runtime.stack = running
		component.theme_revision = signal!
	}
	return component.theme_revision
}
