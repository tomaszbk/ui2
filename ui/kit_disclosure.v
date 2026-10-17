module ui2

// The kit's disclosure components: Collapsible, and Accordion with its
// AccordionItem. A header part opens and closes its content; the content
// fades in when it opens, hides at once when it closes, and the boxes around
// it slide to their new size.

// ── Collapsible ─────────────────────────────────────────────────────

// CollapsibleProps is the `Collapsible` tag: a header with `text` that shows
// and hides the children below it. `open` is bindable.
pub struct CollapsibleProps {
	CommonProps
pub mut:
	open bool
	text DisplayText = ''
	icon IconName
}

pub fn (p CollapsibleProps) vml_container() {}

// A Collapsible places its children under its header, so it is rebuilt when
// one of them changes.
pub fn (p CollapsibleProps) vml_structure() VmlStructure {
	return .sourced
}

pub fn (p CollapsibleProps) vml_themed() {}

pub fn (p CollapsibleProps) child_placement(placement VmlPlacement) VmlPlacement {
	return .preferred
}

// The header is focusable, which needs an id.
pub fn (p CollapsibleProps) control_id_required() bool {
	return true
}

pub fn (mut p CollapsibleProps) apply_event(event ElementEvent) {
	if event.kind == .change {
		p.open = event.checked
	}
}

pub fn (p CollapsibleProps) build(ctx VmlBuildContext) !Element {
	t := ctx.tokens()
	emitter := ctx.emitter(p.element_callback())
	open := p.open
	title := p.text.str()
	header := kit_disclosure_header(t, ctx.part_id('trigger'), title, p.icon, open, p.enabled or {
		true
	}, fn [emitter, open] (event ElementEvent) {
		if event.kind == .click {
			emitter.emit(ElementEvent{
				kind:    .change
				id:      event.id
				checked: !open
			})
		}
	})!
	mut rules := []FlexRule{cap: ctx.children.len}
	for index in 0 .. ctx.children.len {
		rules << ctx.child_layout(index).flex_rule()
	}
	content := flex_with_rules(FlexConfig{
		id:          ctx.part_id('content')
		orientation: .vertical
		gap:         t.space_small
		padding:     LayoutPadding{
			left:   t.space_medium
			right:  t.space_medium
			bottom: t.space_small
		}
	}, ctx.children, rules)!
	root := flex_with_rules(FlexConfig{
		id:          ctx.id
		frame:       ctx.frame
		orientation: .vertical
	}, [header, Element{
		...with_motion(content, kit_motion_reveal())
		hidden: !open
	}], [FlexRule{}, FlexRule{}])!
	return vml_handled(with_motion(Element{
		...root
		accessibility_role:  'group'
		accessibility_label: title
	}, kit_motion_resize()), ctx, p.element_callback())
}

// ── Accordion ───────────────────────────────────────────────────────

// AccordionProps is the `Accordion` tag: a header per AccordionItem child
// that opens the item below it. One item is open at a time, named by
// `value`; with `multiple`, any number are, named by `values`. Opening an
// item emits a change whose text is the item's value, and both `value` and
// `values` are bindable. `bordered` boxes the accordion and rules its items.
pub struct AccordionProps {
	CommonProps
pub mut:
	value    string
	values   []string
	multiple bool
	bordered bool = true
}

pub fn (p AccordionProps) vml_container() {}

// An Accordion reads its items' titles, so it is rebuilt when one of them
// changes.
pub fn (p AccordionProps) vml_structure() VmlStructure {
	return .sourced
}

pub fn (p AccordionProps) vml_themed() {}

pub fn (p AccordionProps) child_placement(placement VmlPlacement) VmlPlacement {
	return .preferred
}

// The headers are focusable, which needs an id.
pub fn (p AccordionProps) control_id_required() bool {
	return true
}

// apply_event toggles the item a change names. A single accordion closes the
// open item; a multiple one keeps the others open.
pub fn (mut p AccordionProps) apply_event(event ElementEvent) {
	if event.kind != .change || event.text.len == 0 {
		return
	}
	if p.multiple {
		p.values = if event.text in p.values {
			p.values.filter(it != event.text)
		} else {
			mut values := p.values.clone()
			values << event.text
			values
		}
		return
	}
	p.value = if p.value == event.text { '' } else { event.text }
	p.values = if p.value.len > 0 { [p.value] } else { []string{} }
}

pub fn (p AccordionProps) build(ctx VmlBuildContext) !Element {
	t := ctx.tokens()
	emitter := ctx.emitter(p.element_callback())
	enabled := p.enabled or { true }
	mut children := []Element{cap: ctx.children.len * 2}
	mut rules := []FlexRule{cap: ctx.children.len * 2}
	for index, child in ctx.children {
		record := ctx.child_record[AccordionItemRecord](index) or {
			return error('Accordion takes AccordionItem children')
		}
		value := if record.value.len > 0 { record.value } else { index.str() }
		open := if p.multiple { value in p.values } else { value == p.value }
		header := kit_disclosure_header(t, ctx.part_id('trigger_${index}'), record.title,
			record.icon, open, enabled && record.enabled, fn [emitter, value] (event ElementEvent) {
				if event.kind == .click {
					emitter.emit(ElementEvent{
						kind: .change
						id:   event.id
						text: value
					})
				}
			})!
		// The headers rule the items apart and slide when an item above them
		// opens or closes.
		children << with_motion(Element{
			...header
			box: BoxStyle{
				transparent:  true
				border_color: t.border
				border_top:   if p.bordered && index > 0 { 1 } else { 0 }
			}
		}, kit_motion_follow())
		rules << FlexRule{}
		children << Element{
			...child
			hidden: child.hidden || !open
		}
		rules << ctx.child_layout(index).flex_rule()
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
	}, children, rules)!
	return vml_handled(with_motion(Element{
		...root
		accessibility_role: 'group'
	}, kit_motion_resize()), ctx, p.element_callback())
}

// AccordionItemProps is the `AccordionItem` tag, one section of an
// Accordion: its header shows `icon` and `title`, and its children are laid
// out in a column like Column's. `value` names it to the Accordion and
// defaults to `title`.
pub struct AccordionItemProps {
	CommonProps
	VmlFlexFields
pub mut:
	value string
	title string
	icon  IconName
}

// AccordionItemRecord is what an AccordionItem tells its Accordion.
pub struct AccordionItemRecord {
pub:
	value   string
	title   string
	icon    IconName
	enabled bool = true
}

pub fn (p AccordionItemProps) vml_container() {}

pub fn (p AccordionItemProps) vml_themed() {}

pub fn (p AccordionItemProps) child_placement(placement VmlPlacement) VmlPlacement {
	return .preferred
}

pub fn (p AccordionItemProps) build(ctx VmlBuildContext) !Element {
	t := ctx.tokens()
	mut rules := []FlexRule{cap: ctx.children.len}
	for index in 0 .. ctx.children.len {
		rules << ctx.child_layout(index).flex_rule()
	}
	base := flex_with_rules(FlexConfig{
		id:          ctx.id
		frame:       ctx.frame
		orientation: .vertical
		gap:         p.gap or { p.spacing or { t.space_small } }
		line_gap:    p.line_gap
		wrap:        p.wrap
		justify:     p.justify
		align:       p.align_items
		padding:     LayoutPadding{
			left:   t.space_medium
			right:  t.space_medium
			bottom: t.space_medium
		}
	}, ctx.children, rules)!
	return with_record(with_motion(Element{
		...vml_layout_element(base, p.CommonProps, ctx)
		accessibility_role:  'region'
		accessibility_label: p.title
	}, kit_motion_reveal()), AccordionItemRecord{
		value:   if p.value.len > 0 { p.value } else { p.title }
		title:   p.title
		icon:    p.icon
		enabled: p.enabled or { true }
	})
}

// ── Shared parts ────────────────────────────────────────────────────

// kit_disclosure_header is the row that opens and closes a disclosure: an
// optional icon, the title, and a chevron that points down while closed and
// up while open. It is a button: a click, or Enter or Space while it has
// focus, runs on_click.
fn kit_disclosure_header(t KitTokens, id string, title string, icon IconName, open bool, enabled bool, on_click ElementCallback) !Element {
	m := t.metrics(.medium)
	foreground := if enabled { t.text } else { t.disabled_text }
	mut children := []Element{cap: 3}
	mut rules := []FlexRule{cap: 3}
	if icon != .none {
		children << Element{
			...kit_icon('', icon, m.icon, foreground)
			key: 'icon'
		}
		rules << FlexRule{}
	}
	children << Element{
		...label('', title, Rect{}, TextStyle{
			color:  foreground
			size:   m.font_size
			weight: 500
		})
		key: 'title'
	}
	rules << FlexRule{
		grow: 1
	}
	children << Element{
		...kit_icon('', if open { IconName.chevron_up } else { .chevron_down }, m.icon, if enabled {
			t.muted
		} else {
			t.disabled_text
		})
		key: 'chevron'
	}
	rules << FlexRule{}
	row := flex_with_rules(FlexConfig{
		id:          id
		orientation: .horizontal
		gap:         t.space_small
		padding:     kit_padding(t.space_medium, t.space_small + 2)
		align:       .center
		box:         BoxStyle{
			transparent: true
			radius:      t.radius_small
		}
	}, children, rules)!
	return Element{
		...with_button_behavior(Element{
			...row
			accessibility_label: title
		})
		enabled:             enabled
		accessibility_value: if open { 'expanded' } else { 'collapsed' }
		cursor:              'pointing_hand'
		interaction_style:   kit_row_interaction(t)
		on_event:            on_click
	}
}

// kit_motion_reveal fades content in when it is shown. It hides at once, so
// the content never overlaps what moves up into its place.
fn kit_motion_reveal() MotionConfig {
	return motion_compose(motion_enter(MotionStyle{ opacity: 0 }), motion_enter_duration(0.2),
		motion_exit_duration(0), motion_easing(.out_cubic))
}

// kit_motion_resize slides a box to its new size when its content opens or
// closes.
fn kit_motion_resize() MotionConfig {
	return motion_compose(motion_layout(.box), motion_transition(0.2), motion_easing(.out_cubic))
}

// kit_motion_follow slides a part to its new place when content above it
// opens or closes.
fn kit_motion_follow() MotionConfig {
	return motion_compose(motion_layout(.position), motion_transition(0.2), motion_easing(.out_cubic))
}
