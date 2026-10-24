module ui2

// ButtonVariant is GPUI Kit's button emphasis. Secondary, the default, is the
// muted fill with a border; outline is the page color with a border; ghost
// has no fill or border until hovered or selected; link reads as a link.
pub enum ButtonVariant {
	primary
	secondary
	outline
	ghost
	link
	danger
	success
	warning
}

// ButtonVariantColors are a variant's colors in one state. Other controls use
// them to match the buttons beside them.
pub struct ButtonVariantColors {
pub:
	fill       u32
	foreground u32
	border     u32
	hover      u32  // the fill under the pointer
	pressed    u32  // the fill while pressed
	divider    u32  // between attached buttons
	filled     bool // false leaves the parent's background showing
	bordered   bool
	underline  bool
}

// button_variant_colors resolves a variant against the tokens.
pub fn button_variant_colors(t KitTokens, variant ButtonVariant, selected bool, enabled bool) ButtonVariantColors {
	mut colors := match variant {
		.secondary, .outline {
			ButtonVariantColors{
				fill:       if selected {
					t.pressed
				} else if variant == .outline {
					t.surface
				} else {
					t.surface_muted
				}
				foreground: t.text
				border:     t.border
				hover:      t.hover
				pressed:    t.pressed
				divider:    t.border
				filled:     true
				bordered:   true
			}
		}
		.ghost {
			ButtonVariantColors{
				fill:       t.pressed
				foreground: t.text
				border:     t.border
				hover:      t.hover
				pressed:    t.pressed
				divider:    t.border
				filled:     selected
			}
		}
		.link {
			ButtonVariantColors{
				fill:       t.surface
				foreground: kit_legible(t.accent, t.surface, t.text)
				border:     t.surface
				divider:    t.border
				underline:  true
			}
		}
		else {
			tone, on_tone := match variant {
				.primary { t.accent, t.on_accent }
				.danger { t.danger, t.on_danger }
				.success { t.success, t.on_success }
				else { t.warning, t.on_warning }
			}
			fill := if selected { kit_mix(tone, t.text, 0.25) } else { tone }
			ButtonVariantColors{
				fill:       fill
				foreground: on_tone
				border:     fill
				hover:      kit_mix(tone, t.text, 0.12)
				pressed:    kit_mix(tone, t.text, 0.24)
				divider:    kit_mix(tone, on_tone, 0.35)
				filled:     true
				bordered:   true
			}
		}
	}
	if !enabled {
		colors = ButtonVariantColors{
			...colors
			fill:       kit_mix(colors.fill, t.surface, 0.6)
			border:     kit_mix(colors.border, t.surface, 0.5)
			divider:    kit_mix(colors.divider, t.surface, 0.5)
			foreground: t.disabled_text
		}
	}
	return colors
}

// ButtonProps is the `Button` tag: a caption with an optional leading and
// trailing icon, and element children after the caption. `loading` shows a
// spinner in place of the icon and ignores clicks. Inside a MessageBox it is
// one of the box's actions.
pub struct ButtonProps {
	CommonProps
pub mut:
	text     DisplayText   = ''
	variant  ButtonVariant = .secondary
	size     ControlSize   = .medium
	icon     IconName
	icon_end IconName
	loading  bool
	selected bool
}

pub fn (p ButtonProps) vml_container() {}

// A Button places its authored children between its icons and caption, so it
// is rebuilt when one of them changes.
pub fn (p ButtonProps) vml_structure() VmlStructure {
	return .sourced
}

pub fn (p ButtonProps) vml_themed() {}

pub fn (p ButtonProps) control_size() ControlSize {
	return p.size
}

pub fn (p ButtonProps) build(ctx VmlBuildContext) !Element {
	el := kit_button_element(ctx.tokens(), ctx.id, ctx.frame, p, ctx.children, ctx.child_layouts)!
	return vml_handled(el, ctx, el.on_event)
}

// part makes a Button inside a MessageBox one of its actions.
pub fn (p ButtonProps) part(ctx VmlBuildContext) !VmlPart {
	return MessageBoxAction{
		id:       ctx.id
		on_event: p.on_click
		title:    p.text.str()
	}
}

// kit_button is a button a component builds as one of its parts, with the id
// ctx.part_id(part). Its CommonProps give it callbacks and accessibility; a
// part's on_click usually captures ctx.emitter.
pub fn kit_button(ctx VmlBuildContext, part string, p ButtonProps) !Element {
	el := kit_button_element(ctx.tokens(), ctx.part_id(part), Rect{}, p, [], [])!
	projected := vml_project_fast(Element{
		...el
		hidden:  p.hidden or { false }
		enabled: p.enabled or { true }
	}, p.CommonProps)
	return if p.style == StylePatch{} { projected } else { apply_style(projected, p.style)! }
}

fn kit_button_element(t KitTokens, id string, frame Rect, p ButtonProps, children []Element, layouts []VmlLayoutItem) !Element {
	if backend_native_controls {
		return kit_native_button(t, id, frame, p, children)
	}
	m := t.metrics(p.size)
	enabled := p.enabled or { true }
	c := button_variant_colors(t, p.variant, p.selected, enabled)
	text_style := apply_text_style(TextStyle{
		color:     c.foreground
		size:      m.font_size
		underline: c.underline
	}, p.style)!
	mut content := []Element{cap: children.len + 3}
	mut rules := []FlexRule{cap: children.len + 3}
	if p.loading {
		content << kit_spinner_element('', m.icon, text_style.color)
		rules << FlexRule{}
	} else if p.icon != .none {
		content << kit_icon('', p.icon, m.icon, text_style.color)
		rules << FlexRule{}
	}
	caption := p.text.str()
	if caption.len > 0 {
		content << label('', caption, Rect{}, text_style)
		rules << FlexRule{}
	}
	for index, child in children {
		content << child
		rules << if index < layouts.len { layouts[index].flex_rule() } else { FlexRule{} }
	}
	if p.icon_end != .none {
		content << kit_icon('', p.icon_end, m.icon, text_style.color)
		rules << FlexRule{}
	}
	root := flex_with_rules(FlexConfig{
		id:          id
		frame:       frame
		orientation: .horizontal
		gap:         m.gap
		padding:     LayoutPadding{
			left:   m.padding_x
			right:  m.padding_x
			top:    m.padding_y
			bottom: m.padding_y
		}
		justify:     .center
		align:       .center
		box:         BoxStyle{
			bg:            c.fill
			transparent:   !c.filled
			radius:        m.radius
			border_color:  c.border
			border_left:   if c.bordered { 1 } else { 0 }
			border_top:    if c.bordered { 1 } else { 0 }
			border_right:  if c.bordered { 1 } else { 0 }
			border_bottom: if c.bordered { 1 } else { 0 }
		}
	}, content, rules)!
	// A view takes the pointer only with a callback, and a loading button
	// keeps taking it so a click does not reach what lies beneath.
	callback := p.element_callback()
	return Element{
		...with_button_behavior(Element{
			...root
			accessibility_label: caption
		})
		on_event:          if p.loading || voidptr(callback) == unsafe { nil } {
			kit_ignore_event
		} else {
			callback
		}
		interaction_style: if enabled && !p.loading {
			kit_button_interaction(t, c)
		} else {
			InteractionStyle{}
		}
	}
}

// kit_native_button is a Button where the operating system draws controls
// (backend_native_controls): the platform's push button with the caption, at
// the size's font. The OS bezel stands in for every variant's colors, as it
// does for the hover, pressed and focus states. What a push button cannot
// show (icons, a spinner, a selected state, children) is a diagnostic.
fn kit_native_button(t KitTokens, id string, frame Rect, p ButtonProps, children []Element) !Element {
	which := if id.len > 0 { ' (${id})' } else { '' }
	if p.icon != .none || p.icon_end != .none || p.loading || children.len > 0 {
		return error('a native Button shows its caption only; icons, loading and children require ${native_profile_remedy}${which}')
	}
	if p.selected {
		return error('a native Button has no selected state; use a ToggleButton or ${native_profile_remedy}${which}')
	}
	m := t.metrics(p.size)
	enabled := p.enabled or { true }
	caption := p.text.str()
	el := with_native_style(button(id, caption, frame, BoxStyle{}, apply_text_style(TextStyle{
		color: t.text
		size:  m.font_size
	}, p.style)!))
	callback := p.element_callback()
	return Element{
		...el
		enabled:             enabled
		accessibility_label: caption
		on_event:            if voidptr(callback) == unsafe { nil } { kit_ignore_event } else { callback }
	}
}

// kit_button_interaction is a button's hover and pressed fill and its focus
// ring.
fn kit_button_interaction(t KitTokens, c ButtonVariantColors) InteractionStyle {
	ring := BoxStylePatch{
		outline_color:  t.focus_ring
		outline_width:  2
		outline_offset: 2
	}
	if c.underline {
		return InteractionStyle{
			focus: ring
		}
	}
	return InteractionStyle{
		hover:   BoxStylePatch{
			bg:          c.hover
			transparent: false
		}
		pressed: BoxStylePatch{
			bg:          c.pressed
			transparent: false
		}
		focus:   ring
	}
}

fn kit_ignore_event(_ ElementEvent) {}
