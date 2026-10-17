module ui2

import math

// The kit's display components: Badge, Avatar, Tag, Separator, Kbd, Link,
// Alert, Empty, GroupBox, and DescriptionList with its DescriptionItem. They
// keep no state, read the tokens once per build and draw with few elements.
// The helpers at the end are shared with the feedback, disclosure and
// navigation components.

// ── Badge ───────────────────────────────────────────────────────────

// BadgeProps is the `Badge` tag: a count in a bubble at the top right of its
// children, or a dot with `dot`. A zero count hides the bubble, and a count
// past `max` reads `max+`. Without children the bubble stands alone.
pub struct BadgeProps {
	CommonProps
pub mut:
	count int
	max   int = 99
	dot   bool
	tone  Tone = .danger
}

pub fn (p BadgeProps) vml_container() {}

// A Badge lays its children out under its bubble, so it is rebuilt when one
// of them changes.
pub fn (p BadgeProps) vml_structure() VmlStructure {
	return .sourced
}

pub fn (p BadgeProps) vml_themed() {}

pub fn (p BadgeProps) child_placement(placement VmlPlacement) VmlPlacement {
	return .preferred
}

pub fn (p BadgeProps) build(ctx VmlBuildContext) !Element {
	t := ctx.tokens()
	fill, on_fill := t.tone_colors(p.tone)
	text := badge_text(p.count, p.max)
	side := if p.dot { 8.0 } else { 18.0 }
	bubble := if p.dot {
		view(ctx.part_id('badge'), rect(0, 0, side, side), BoxStyle{
			bg:     fill
			radius: side / 2
		}, [])
	} else {
		flex_with_rules(FlexConfig{
			id:          ctx.part_id('badge')
			frame:       rect(0, 0, 0, side)
			orientation: .horizontal
			padding:     LayoutPadding{
				left:  6
				right: 6
			}
			justify:     .center
			align:       .center
			box:         BoxStyle{
				bg:     fill
				radius: side / 2
			}
		}, [label('', text, Rect{}, TextStyle{
			color: on_fill
			size:  t.font_caption
			bold:  true
		})], [FlexRule{}])!
	}
	anchored := ctx.children.len > 0
	mut children := []Element{cap: ctx.children.len + 1}
	mut rules := []StackRule{cap: ctx.children.len + 1}
	for index, child in ctx.children {
		children << child
		rules << ctx.child_layout(index).stack_rule()
	}
	children << Element{
		...bubble
		hidden:              !p.dot && p.count <= 0
		translate_x:         if anchored { side / 2 } else { 0 }
		translate_y:         if anchored { -side / 2 } else { 0 }
		accessibility_role:  'status'
		accessibility_label: text
	}
	rules << StackRule{
		align_x: .end
		align_y: .start
	}
	root := stack_with_rules(StackConfig{
		id:    ctx.id
		frame: ctx.frame
	}, children, rules)!
	return vml_handled(root, ctx, p.element_callback())
}

// ── Avatar ──────────────────────────────────────────────────────────

// AvatarProps is the `Avatar` tag: a circle the control height of its size
// across, showing the image at `src`, or else the initials of `name`.
pub struct AvatarProps {
	CommonProps
pub mut:
	name string
	src  string
	size ControlSize = .medium
}

pub fn (p AvatarProps) vml_structure() VmlStructure {
	return .generated
}

pub fn (p AvatarProps) vml_themed() {}

pub fn (p AvatarProps) build(ctx VmlBuildContext) !Element {
	t := ctx.tokens()
	m := t.metrics(p.size)
	side := m.height
	content := if p.src.len > 0 {
		Element{
			...image('', p.src, rect(0, 0, side, side))
			key: 'image'
			box: BoxStyle{
				radius: side / 2
			}
		}
	} else {
		Element{
			...label('', avatar_initials(p.name), Rect{}, TextStyle{
				color:  t.text
				size:   m.font_size
				weight: 600
			})
			key: 'initials'
		}
	}
	root := flex_with_rules(FlexConfig{
		id:          ctx.id
		frame:       rect(ctx.frame.x, ctx.frame.y, p.width or { side }, p.height or { side })
		orientation: .horizontal
		justify:     .center
		align:       .center
		box:         BoxStyle{
			bg:     t.surface_muted
			radius: side / 2
		}
	}, [content], [FlexRule{}])!
	return vml_handled(Element{
		...root
		accessibility_role:  'img'
		accessibility_label: p.name
	}, ctx, p.element_callback())
}

// ── Tag ─────────────────────────────────────────────────────────────

// TagProps is the `Tag` tag: a short label in a tinted box, with an optional
// leading icon. `outline` draws the tone as a border on the page color.
pub struct TagProps {
	CommonProps
pub mut:
	text    DisplayText = ''
	tone    Tone        = .neutral
	outline bool
	size    ControlSize = .medium
	icon    IconName
}

pub fn (p TagProps) vml_structure() VmlStructure {
	return .generated
}

pub fn (p TagProps) vml_themed() {}

pub fn (p TagProps) build(ctx VmlBuildContext) !Element {
	t := ctx.tokens()
	i := int(p.size)
	font := t.control_font[i] - 2
	fill, foreground, border := kit_tag_colors(t, p.tone, p.outline)
	mut content := []Element{cap: 2}
	if p.icon != .none {
		content << Element{
			...kit_icon('', p.icon, font, foreground)
			key: 'icon'
		}
	}
	caption := p.text.str()
	content << Element{
		...label('', caption, Rect{}, TextStyle{
			color:  foreground
			size:   font
			weight: 500
		})
		key: 'text'
	}
	root := flex_with_rules(FlexConfig{
		id:          ctx.id
		frame:       ctx.frame
		orientation: .horizontal
		gap:         t.space_xsmall
		padding:     LayoutPadding{
			left:   t.control_padding[i]
			right:  t.control_padding[i]
			top:    2
			bottom: 2
		}
		align:       .center
		box:         kit_bordered_box(fill, border, t.radius_small)
	}, content, []FlexRule{len: content.len})!
	return vml_handled(Element{
		...root
		accessibility_label: caption
	}, ctx, p.element_callback())
}

// kit_tag_colors are a tag's fill, text and border: a pale tint of the tone,
// or its border on the page color when outlined. Neutral is the muted fill.
fn kit_tag_colors(t KitTokens, tone Tone, outline bool) (u32, u32, u32) {
	if tone == .neutral {
		return if outline { t.surface } else { t.surface_muted }, t.text, t.border
	}
	color, _ := t.tone_colors(tone)
	fill := if outline { t.surface } else { kit_mix(color, t.surface, 0.85) }
	foreground := kit_legible(color, fill, t.text)
	return fill, foreground, if outline { foreground } else { kit_mix(color, t.surface, 0.6) }
}

// ── Separator ───────────────────────────────────────────────────────

// SeparatorProps is the `Separator` tag: a one-unit rule across its parent,
// or down it when vertical. A horizontal separator with `text` shows the
// text between two rules.
pub struct SeparatorProps {
	CommonProps
pub mut:
	orientation LayoutOrientation
	text        DisplayText = ''
}

pub fn (p SeparatorProps) vml_structure() VmlStructure {
	return .generated
}

pub fn (p SeparatorProps) vml_themed() {}

pub fn (p SeparatorProps) build(ctx VmlBuildContext) !Element {
	t := ctx.tokens()
	caption := p.text.str()
	if p.orientation == .vertical {
		return vml_handled(Element{
			...view(ctx.id, rect(ctx.frame.x, ctx.frame.y, p.width or { 1 }, ctx.frame.height),
				BoxStyle{ bg: t.border }, [])
			accessibility_role: 'separator'
		}, ctx, p.element_callback())
	}
	if caption.len == 0 {
		return vml_handled(Element{
			...view(ctx.id, rect(ctx.frame.x, ctx.frame.y, ctx.frame.width, p.height or { 1 }),
				BoxStyle{ bg: t.border }, [])
			accessibility_role: 'separator'
		}, ctx, p.element_callback())
	}
	rule := FlexRule{
		grow: 1
	}
	root := flex_with_rules(FlexConfig{
		id:          ctx.id
		frame:       ctx.frame
		orientation: .horizontal
		gap:         t.space_small
		align:       .center
	}, [
		view('', rect(0, 0, 0, 1), BoxStyle{ bg: t.border }, []),
		label('', caption, Rect{}, TextStyle{
			color: t.muted
			size:  t.font_caption
		}),
		view('', rect(0, 0, 0, 1), BoxStyle{ bg: t.border }, []),
	], [rule, FlexRule{}, rule])!
	return vml_handled(Element{
		...root
		accessibility_role:  'separator'
		accessibility_label: caption
	}, ctx, p.element_callback())
}

// ── Kbd ─────────────────────────────────────────────────────────────

// KbdProps is the `Kbd` tag: a key or shortcut drawn as a keycap.
pub struct KbdProps {
	CommonProps
pub mut:
	text DisplayText = ''
}

pub fn (p KbdProps) vml_structure() VmlStructure {
	return .generated
}

pub fn (p KbdProps) vml_themed() {}

pub fn (p KbdProps) build(ctx VmlBuildContext) !Element {
	t := ctx.tokens()
	caption := p.text.str()
	root := flex_with_rules(FlexConfig{
		id:          ctx.id
		frame:       ctx.frame
		orientation: .horizontal
		padding:     LayoutPadding{
			left:  t.space_xsmall + 2
			right: t.space_xsmall + 2
			top:   1
		}
		justify:     .center
		align:       .center
		box:         BoxStyle{
			bg:            t.surface_muted
			radius:        t.radius_small
			border_color:  t.border
			border_left:   1
			border_top:    1
			border_right:  1
			border_bottom: 2
		}
	}, [label('', caption, Rect{}, TextStyle{
		color:           t.text
		size:            t.font_caption
		tabular_figures: true
	})], [FlexRule{}])!
	return vml_handled(Element{
		...root
		accessibility_label: caption
	}, ctx, p.element_callback())
}

// ── Link ────────────────────────────────────────────────────────────

// LinkProps is the `Link` tag: underlined text in the accent color that
// runs `on_click`, focusable like a button.
pub struct LinkProps {
	CommonProps
pub mut:
	text DisplayText = ''
}

pub fn (p LinkProps) vml_structure() VmlStructure {
	return .generated
}

pub fn (p LinkProps) vml_themed() {}

// A link is focusable, which needs an id.
pub fn (p LinkProps) control_id_required() bool {
	return true
}

pub fn (p LinkProps) build(ctx VmlBuildContext) !Element {
	t := ctx.tokens()
	enabled := p.enabled or { true }
	caption := p.text.str()
	root := flex_with_rules(FlexConfig{
		id:          ctx.id
		frame:       ctx.frame
		orientation: .horizontal
		align:       .center
		box:         BoxStyle{
			transparent: true
			radius:      t.radius_small
		}
	}, [label('', caption, Rect{}, TextStyle{
		color:     if enabled { kit_legible(t.accent, t.surface, t.text) } else { t.disabled_text }
		size:      t.font_body
		underline: true
	})], [FlexRule{}])!
	callback := p.element_callback()
	return vml_handled(Element{
		...with_button_behavior(Element{
			...root
			accessibility_role:  'link'
			accessibility_label: caption
		})
		cursor:            'pointing_hand'
		interaction_style: kit_focus_interaction(t)
	}, ctx, if callback == unsafe { nil } { kit_ignore_event } else { callback })
}

// ── Alert ───────────────────────────────────────────────────────────

// AlertProps is the `Alert` tag: a tinted box with the tone's icon, a title,
// a description and its children (actions, say) below them. `icon` replaces
// the tone's icon.
pub struct AlertProps {
	CommonProps
pub mut:
	title string
	text  DisplayText = ''
	tone  Tone        = .info
	icon  IconName
}

pub fn (p AlertProps) vml_container() {}

// An Alert places its children below its text, so it is rebuilt when one of
// them changes.
pub fn (p AlertProps) vml_structure() VmlStructure {
	return .sourced
}

pub fn (p AlertProps) vml_themed() {}

pub fn (p AlertProps) child_placement(placement VmlPlacement) VmlPlacement {
	return .preferred
}

pub fn (p AlertProps) build(ctx VmlBuildContext) !Element {
	t := ctx.tokens()
	m := t.metrics(.medium)
	fill, accent, border := kit_alert_colors(t, p.tone)
	icon := if p.icon != .none { p.icon } else { kit_tone_icon(p.tone) }
	mut body := []Element{cap: ctx.children.len + 2}
	mut rules := []FlexRule{cap: ctx.children.len + 2}
	if p.title.len > 0 {
		body << Element{
			...label('', p.title, Rect{}, TextStyle{
				color:  if p.tone == .neutral { t.text } else { accent }
				size:   m.font_size
				weight: 600
			})
			key: 'title'
		}
		rules << FlexRule{}
	}
	text := p.text.str()
	if text.len > 0 {
		body << Element{
			...kit_paragraph(text, m.font_size, t.text)
			key: 'text'
		}
		rules << FlexRule{}
	}
	for index, child in ctx.children {
		body << child
		rules << ctx.child_layout(index).flex_rule()
	}
	column := flex_with_rules(FlexConfig{
		id:          ctx.part_id('body')
		orientation: .vertical
		gap:         t.space_xsmall
	}, body, rules)!
	root := flex_with_rules(FlexConfig{
		id:          ctx.id
		frame:       ctx.frame
		orientation: .horizontal
		gap:         t.space_small
		padding:     kit_padding(t.space_medium, t.space_medium)
		align:       .start
		box:         kit_bordered_box(fill, border, t.radius_medium)
	}, [kit_icon('', icon, m.icon, accent), column], [FlexRule{}, FlexRule{
		grow:   1
		shrink: 1
	}])!
	return vml_handled(Element{
		...root
		accessibility_role:  'alert'
		accessibility_label: if p.title.len > 0 { p.title } else { text }
	}, ctx, p.element_callback())
}

// kit_alert_colors are an alert's fill, its icon and title color, and its
// border: tints of the tone over the page color.
fn kit_alert_colors(t KitTokens, tone Tone) (u32, u32, u32) {
	if tone == .neutral {
		return t.surface_muted, t.muted, t.border
	}
	color, _ := t.tone_colors(tone)
	fill := kit_mix(color, t.surface, 0.9)
	return fill, kit_legible(color, fill, t.text), kit_mix(color, t.surface, 0.6)
}

// kit_tone_icon is the icon a status in a tone shows.
fn kit_tone_icon(tone Tone) IconName {
	return match tone {
		.success { .circle_check }
		.warning { .triangle_alert }
		.danger { .circle_x }
		else { .info }
	}
}

// ── Empty ───────────────────────────────────────────────────────────

// EmptyProps is the `Empty` tag: the placeholder of a list or page without
// content, an icon over a title and a description, with its children (an
// action, say) below, all centered.
pub struct EmptyProps {
	CommonProps
pub mut:
	title string
	text  DisplayText = ''
	icon  IconName    = .folder
}

pub fn (p EmptyProps) vml_container() {}

// Empty places its children below its text, so it is rebuilt when one of
// them changes.
pub fn (p EmptyProps) vml_structure() VmlStructure {
	return .sourced
}

pub fn (p EmptyProps) vml_themed() {}

pub fn (p EmptyProps) child_placement(placement VmlPlacement) VmlPlacement {
	return .preferred
}

pub fn (p EmptyProps) build(ctx VmlBuildContext) !Element {
	t := ctx.tokens()
	m := t.metrics(.large)
	mut content := []Element{cap: ctx.children.len + 3}
	mut rules := []FlexRule{cap: ctx.children.len + 3}
	if p.icon != .none {
		content << Element{
			...kit_icon('', p.icon, icon_pixel_size(.large) * 1.5, t.muted)
			key: 'icon'
		}
		rules << FlexRule{}
	}
	if p.title.len > 0 {
		content << Element{
			...label('', p.title, Rect{}, TextStyle{
				color:  t.text
				size:   m.font_size
				weight: 600
				align:  .center
			})
			key: 'title'
		}
		rules << FlexRule{}
	}
	text := p.text.str()
	if text.len > 0 {
		content << Element{
			...kit_paragraph(text, t.control_font[int(ControlSize.medium)], t.muted)
			key: 'text'
		}
		rules << FlexRule{}
	}
	for index, child in ctx.children {
		content << child
		rules << ctx.child_layout(index).flex_rule()
	}
	root := flex_with_rules(FlexConfig{
		id:          ctx.id
		frame:       ctx.frame
		orientation: .vertical
		gap:         t.space_small
		padding:     kit_padding(t.space_large, t.space_large)
		justify:     .center
		align:       .center
	}, content, rules)!
	return vml_handled(Element{
		...root
		accessibility_label: p.title
	}, ctx, p.element_callback())
}

// ── GroupBox ────────────────────────────────────────────────────────

// GroupBoxProps is the `GroupBox` tag: its children stacked in a bordered
// box under a title.
pub struct GroupBoxProps {
	CommonProps
pub mut:
	title string
}

pub fn (p GroupBoxProps) vml_container() {}

// A GroupBox places its children after its title, so it is rebuilt when one
// of them changes.
pub fn (p GroupBoxProps) vml_structure() VmlStructure {
	return .sourced
}

pub fn (p GroupBoxProps) vml_themed() {}

pub fn (p GroupBoxProps) child_placement(placement VmlPlacement) VmlPlacement {
	return .preferred
}

pub fn (p GroupBoxProps) build(ctx VmlBuildContext) !Element {
	t := ctx.tokens()
	mut content := []Element{cap: ctx.children.len + 1}
	mut rules := []FlexRule{cap: ctx.children.len + 1}
	if p.title.len > 0 {
		content << Element{
			...label('', p.title, Rect{}, TextStyle{
				color:  t.muted
				size:   t.font_caption
				weight: 600
			})
			key: 'title'
		}
		rules << FlexRule{}
	}
	for index, child in ctx.children {
		content << child
		rules << ctx.child_layout(index).flex_rule()
	}
	root := flex_with_rules(FlexConfig{
		id:          ctx.id
		frame:       ctx.frame
		orientation: .vertical
		gap:         t.space_small
		padding:     kit_padding(t.space_medium, t.space_medium)
		box:         kit_bordered_box(t.surface, t.border, t.radius_medium)
	}, content, rules)!
	return vml_handled(Element{
		...root
		accessibility_role:  'group'
		accessibility_label: p.title
	}, ctx, p.element_callback())
}

// ── DescriptionList ─────────────────────────────────────────────────

// DescriptionListProps is the `DescriptionList` tag: one row per
// DescriptionItem child, its label in a column `label_width` wide beside its
// value. `bordered` boxes the list and rules its rows.
pub struct DescriptionListProps {
	CommonProps
pub mut:
	label_width f64  = 120
	bordered    bool = true
}

pub fn (p DescriptionListProps) vml_container() {}

// A DescriptionList reads its items' labels, so it is rebuilt when one of
// them changes.
pub fn (p DescriptionListProps) vml_structure() VmlStructure {
	return .sourced
}

pub fn (p DescriptionListProps) vml_themed() {}

pub fn (p DescriptionListProps) child_placement(placement VmlPlacement) VmlPlacement {
	return .preferred
}

pub fn (p DescriptionListProps) validate() ! {
	p.CommonProps.validate()!
	if !math.is_finite(p.label_width) || p.label_width < 0 {
		return error('DescriptionList `label_width` must be finite and not negative')
	}
}

pub fn (p DescriptionListProps) build(ctx VmlBuildContext) !Element {
	t := ctx.tokens()
	mut rows := []Element{cap: ctx.children.len}
	for index, child in ctx.children {
		record := ctx.child_record[DescriptionItemRecord](index) or {
			return error('DescriptionList takes DescriptionItem children')
		}
		row := flex_with_rules(FlexConfig{
			orientation: .horizontal
			gap:         t.space_medium
			padding:     kit_padding(t.space_medium, t.space_small)
			align:       .start
			box:         BoxStyle{
				transparent:  true
				border_color: t.border
				border_top:   if p.bordered && index > 0 { 1 } else { 0 }
			}
		}, [
			label('', record.label, rect(0, 0, p.label_width, 0), TextStyle{
				color: t.muted
				size:  t.control_font[int(ControlSize.medium)]
			}),
			child,
		], [FlexRule{}, ctx.child_layout(index).flex_rule()])!
		rows << Element{
			...row
			key: kit_source_key(child, index)
		}
	}
	root := flex_with_rules(FlexConfig{
		id:          ctx.id
		frame:       ctx.frame
		orientation: .vertical
		box:         if p.bordered {
			kit_bordered_box(t.surface, t.border, t.radius_medium)
		} else {
			BoxStyle{
				transparent: true
			}
		}
	}, rows, []FlexRule{len: rows.len})!
	return vml_handled(Element{
		...root
		accessibility_role: 'list'
	}, ctx, p.element_callback())
}

// DescriptionItemProps is the `DescriptionItem` tag, one row of a
// DescriptionList: `label`, and its value, `text` followed by its children.
pub struct DescriptionItemProps {
	CommonProps
pub mut:
	label string
	text  DisplayText = ''
}

// DescriptionItemRecord is what a DescriptionItem tells its list.
pub struct DescriptionItemRecord {
pub:
	label string
}

pub fn (p DescriptionItemProps) vml_container() {}

// An item places its children after its text, so it is rebuilt when one of
// them changes.
pub fn (p DescriptionItemProps) vml_structure() VmlStructure {
	return .sourced
}

pub fn (p DescriptionItemProps) vml_themed() {}

pub fn (p DescriptionItemProps) child_placement(placement VmlPlacement) VmlPlacement {
	return .preferred
}

pub fn (p DescriptionItemProps) build(ctx VmlBuildContext) !Element {
	t := ctx.tokens()
	mut content := []Element{cap: ctx.children.len + 1}
	mut rules := []FlexRule{cap: ctx.children.len + 1}
	text := p.text.str()
	if text.len > 0 {
		content << Element{
			...kit_paragraph(text, t.control_font[int(ControlSize.medium)], t.text)
			key: 'text'
		}
		rules << FlexRule{}
	}
	for index, child in ctx.children {
		content << child
		rules << ctx.child_layout(index).flex_rule()
	}
	root := flex_with_rules(FlexConfig{
		id:          ctx.id
		frame:       ctx.frame
		orientation: .vertical
		gap:         t.space_xsmall
	}, content, rules)!
	return with_record(vml_handled(Element{
		...root
		accessibility_role:  'listitem'
		accessibility_label: p.label
	}, ctx, p.element_callback()), DescriptionItemRecord{
		label: p.label
	})
}

// ── Shared parts ────────────────────────────────────────────────────

// kit_source_key keys a part that wraps the source child at index with that
// child's identity, so the part follows its child when the sources reorder:
// a source keeps the parent it was first placed in.
fn kit_source_key(child Element, index int) string {
	node := child.compiled_node
	return if node != unsafe { nil } { node.local_id } else { index.str() }
}

// kit_focus_interaction is the focus ring of a focusable kit part that has
// no hover or pressed fill of its own.
fn kit_focus_interaction(t KitTokens) InteractionStyle {
	return InteractionStyle{
		focus: BoxStylePatch{
			outline_color:  t.focus_ring
			outline_width:  2
			outline_offset: 2
		}
	}
}

// kit_row_interaction is the hover and pressed fill of a row-like part, such
// as a disclosure header or a tree row, with the focus ring.
fn kit_row_interaction(t KitTokens) InteractionStyle {
	return InteractionStyle{
		hover:   BoxStylePatch{
			bg:          t.hover
			transparent: false
		}
		pressed: BoxStylePatch{
			bg:          t.pressed
			transparent: false
		}
		focus:   BoxStylePatch{
			outline_color:  t.focus_ring
			outline_width:  2
			outline_offset: 0
		}
	}
}

// kit_bordered_box is a filled box with a one-unit border.
fn kit_bordered_box(fill u32, border u32, radius f64) BoxStyle {
	return BoxStyle{
		bg:            fill
		radius:        radius
		border_color:  border
		border_left:   1
		border_top:    1
		border_right:  1
		border_bottom: 1
	}
}

// kit_padding is the same padding on the left and right, and on the top and
// bottom.
fn kit_padding(x f64, y f64) LayoutPadding {
	return LayoutPadding{
		left:   x
		right:  x
		top:    y
		bottom: y
	}
}

// kit_paragraph is text that wraps onto as many lines as its width needs.
fn kit_paragraph(text string, size f64, color u32) Element {
	return label('', text, Rect{}, TextStyle{
		color: color
		size:  size
		lines: 0
	})
}
