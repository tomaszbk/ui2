module ui2

// The kit's navigation components: Tabs with its Tab panels. A Tabs keeps
// one tab stop: its list takes the arrow keys and selects the neighboring
// tab, and its triggers take clicks.

// ── Tabs ────────────────────────────────────────────────────────────

// TabsVariant is how a Tabs draws its triggers: an accent line under the
// selected one, a filled pill, or a segmented control.
pub enum TabsVariant {
	underline
	pill
	segmented
}

// TabsProps is the `Tabs` tag: a trigger per Tab child above the panel of
// the selected one, named by `value` (the first enabled tab when no tab
// has it). The other panels are hidden, not removed, so they keep their
// state. Selecting a tab emits a change whose text is the tab's value, and
// `value` is bindable. Left, Right, Home and End select from the keyboard
// while the trigger list has focus.
pub struct TabsProps {
	CommonProps
pub mut:
	value   string
	variant TabsVariant
	size    ControlSize = .medium
}

pub fn (p TabsProps) vml_container() {}

// Tabs reads its tabs' titles, so it is rebuilt when one of them changes.
pub fn (p TabsProps) vml_structure() VmlStructure {
	return .sourced
}

pub fn (p TabsProps) vml_themed() {}

pub fn (p TabsProps) child_placement(placement VmlPlacement) VmlPlacement {
	return .preferred
}

// The trigger list is focusable, which needs an id.
pub fn (p TabsProps) control_id_required() bool {
	return true
}

pub fn (mut p TabsProps) apply_event(event ElementEvent) {
	if event.kind == .change && event.text.len > 0 {
		p.value = event.text
	}
}

pub fn (p TabsProps) build(ctx VmlBuildContext) !Element {
	t := ctx.tokens()
	m := t.metrics(p.size)
	enabled := p.enabled or { true }
	mut records := []TabRecord{cap: ctx.children.len}
	for index in 0 .. ctx.children.len {
		records << ctx.child_record[TabRecord](index) or { return error('Tabs takes Tab children') }
	}
	values := records.map(it.value)
	usable := records.map(enabled && it.enabled)
	mut selected := values.index(p.value)
	if selected < 0 {
		selected = usable.index(true)
	}
	emitter := ctx.emitter(p.element_callback())
	mut triggers := []Element{cap: records.len}
	for index, record in records {
		value := record.value
		active := index == selected
		triggers << kit_tab_trigger(t, m, ctx.part_id('tab_${index}'), record, p.variant,
			active, usable[index], fn [emitter, value, active] (event ElementEvent) {
				if event.kind == .click && !active {
					emitter.emit(ElementEvent{
						kind: .change
						id:   event.id
						text: value
					})
				}
			})!
	}
	list := flex_with_rules(FlexConfig{
		id:          ctx.part_id('list')
		orientation: .horizontal
		gap:         if p.variant == .underline { 0 } else { t.space_xsmall }
		padding:     if p.variant == .segmented { kit_padding(3, 3) } else { LayoutPadding{} }
		align:       .center
		box:         match p.variant {
			.underline {
				BoxStyle{
					transparent:   true
					border_color:  t.border
					border_bottom: 1
				}
			}
			.pill {
				BoxStyle{
					transparent: true
					radius:      m.height / 2
				}
			}
			.segmented {
				BoxStyle{
					bg:     t.surface_muted
					radius: m.radius
				}
			}
		}
	}, triggers, []FlexRule{len: triggers.len})!
	// The panels share one cell: each source keeps its own stack rule, which
	// follows the cell's stretch.
	mut panels := []Element{cap: ctx.children.len}
	for index, child in ctx.children {
		panels << Element{
			...child
			hidden: child.hidden || index != selected
		}
	}
	panel_stack := stack_with_rules(StackConfig{
		id:      ctx.part_id('panels')
		align_x: .stretch
		align_y: .stretch
	}, panels, []StackRule{len: panels.len})!
	root := flex_with_rules(FlexConfig{
		id:          ctx.id
		frame:       ctx.frame
		orientation: .vertical
		gap:         t.space_medium
	}, [
		Element{
			...list
			enabled:            enabled
			focus_policy:       .focusable
			keys:               ['left', 'right', 'home', 'end']
			accessibility_role: 'tablist'
			interaction_style:  kit_focus_interaction(t)
			on_event:           fn [emitter, values, usable, selected] (event ElementEvent) {
				if event.kind != .key_down {
					return
				}
				index := roving_index(usable, selected, event.key, true) or { return }
				emitter.emit(ElementEvent{
					kind: .change
					id:   event.id
					text: values[index]
				})
			}
		},
		panel_stack,
	], [
		FlexRule{
			align_self: if p.variant == .underline { LayoutAlignment.auto } else { .start }
		},
		FlexRule{
			grow: 1
		},
	])!
	return vml_handled(root, ctx, p.element_callback())
}

// kit_tab_trigger is one trigger of a Tabs list: the tab's icon and text,
// drawn selected or not in the list's variant. The list holds the focus, so
// a trigger only takes clicks.
fn kit_tab_trigger(t KitTokens, m ControlMetrics, id string, record TabRecord, variant TabsVariant, active bool, enabled bool, on_click ElementCallback) !Element {
	foreground := if !enabled {
		t.disabled_text
	} else if !active {
		t.muted
	} else if variant == .pill {
		t.on_accent
	} else {
		t.text
	}
	mut content := []Element{cap: 2}
	if record.icon != .none {
		content << Element{
			...kit_icon('', record.icon, m.icon, foreground)
			key: 'icon'
		}
	}
	content << Element{
		...label('', record.text, Rect{}, TextStyle{
			color:  foreground
			size:   m.font_size
			weight: 500
		})
		key: 'text'
	}
	box := match variant {
		.underline {
			BoxStyle{
				transparent:   true
				border_color:  t.accent
				border_bottom: if active { 2 } else { 0 }
			}
		}
		.pill {
			BoxStyle{
				bg:          t.accent
				transparent: !active
				radius:      m.height / 2
			}
		}
		.segmented {
			BoxStyle{
				bg:          t.surface
				transparent: !active
				radius:      m.radius - 2
				shadow:      if active { t.card_shadow() } else { BoxShadow{} }
			}
		}
	}
	row := flex_with_rules(FlexConfig{
		id:          id
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
		box:         box
	}, content, []FlexRule{len: content.len})!
	return Element{
		...with_button_behavior(Element{
			...row
			accessibility_label: record.text
		})
		enabled:             enabled
		focus_policy:        .unfocusable
		accessibility_role:  'tab'
		accessibility_value: if active { 'selected' } else { '' }
		cursor:              'pointing_hand'
		interaction_style:   if enabled && !active {
			InteractionStyle{
				hover:   BoxStylePatch{
					bg:          t.hover
					transparent: false
				}
				pressed: BoxStylePatch{
					bg:          t.pressed
					transparent: false
				}
			}
		} else {
			InteractionStyle{}
		}
		on_event:            on_click
	}
}

// TabProps is the `Tab` tag, one panel of a Tabs: its trigger shows `icon`
// and `text`, and its children are laid out in a column like Column's.
// `value` names it to the Tabs and defaults to `text`.
pub struct TabProps {
	CommonProps
	VmlFlexFields
pub mut:
	value string
	text  DisplayText = ''
	icon  IconName
}

// TabRecord is what a Tab tells its Tabs.
pub struct TabRecord {
pub:
	value   string
	text    string
	icon    IconName
	enabled bool = true
}

pub fn (p TabProps) vml_container() {}

pub fn (p TabProps) child_placement(placement VmlPlacement) VmlPlacement {
	return .preferred
}

pub fn (p TabProps) build(ctx VmlBuildContext) !Element {
	text := p.text.str()
	return with_record(Element{
		...p.VmlFlexFields.build_flex(p.CommonProps, .vertical, ctx)!
		accessibility_role:  'tabpanel'
		accessibility_label: text
	}, TabRecord{
		value:   if p.value.len > 0 { p.value } else { text }
		text:    text
		icon:    p.icon
		enabled: p.enabled or { true }
	})
}
