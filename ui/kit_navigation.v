module ui2

// The kit's navigation components: Tabs with its Tab panels, Breadcrumb
// with its BreadcrumbItem parts, and Pagination. A Tabs keeps one tab stop:
// its list takes the arrow keys and selects the neighboring tab, and its
// triggers take clicks.

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

// ── Breadcrumb ──────────────────────────────────────────────────────

// BreadcrumbProps is the `Breadcrumb` tag: the path to the current page as
// a row of BreadcrumbItem links between chevrons. The last item is the
// current page and is not a link.
pub struct BreadcrumbProps {
	CommonProps
}

// A Breadcrumb makes its links from its items.
pub fn (p BreadcrumbProps) vml_structure() VmlStructure {
	return .generated
}

pub fn (p BreadcrumbProps) vml_themed() {}

// The links are focusable, which needs an id.
pub fn (p BreadcrumbProps) control_id_required() bool {
	return true
}

pub fn (p BreadcrumbProps) build(ctx VmlBuildContext) !Element {
	t := ctx.tokens()
	size := t.control_font[int(ControlSize.medium)]
	items := ctx.records[BreadcrumbItemRecord]()
	mut children := []Element{cap: items.len * 2}
	for index, item in items {
		if index > 0 {
			children << Element{
				...kit_icon('', .chevron_right, size, t.muted)
				key:                 'sep_${index}'
				accessibility_label: ''
			}
		}
		current := index == items.len - 1
		link := !current && item.enabled && item.on_click != unsafe { nil }
		foreground := if current {
			t.text
		} else if item.enabled {
			t.muted
		} else {
			t.disabled_text
		}
		mut content := []Element{cap: 2}
		if item.icon != .none {
			content << Element{
				...kit_icon('', item.icon, size, foreground)
				key: 'icon'
			}
		}
		content << Element{
			...label('', item.text, Rect{}, TextStyle{
				color:  foreground
				size:   size
				weight: if current { 500 } else { 400 }
			})
			key: 'text'
		}
		row := flex_with_rules(FlexConfig{
			id:          ctx.part_id('item_${index}')
			orientation: .horizontal
			gap:         t.space_xsmall
			align:       .center
			box:         BoxStyle{
				transparent: true
				radius:      t.radius_small
			}
		}, content, []FlexRule{len: content.len})!
		on_click := item.on_click
		children << if link {
			Element{
				...with_button_behavior(Element{
					...row
					accessibility_role:  'link'
					accessibility_label: item.text
				})
				cursor:            'pointing_hand'
				interaction_style: kit_focus_interaction(t)
				on_event:          fn [on_click] (event ElementEvent) {
					if event.kind == .click {
						on_click(event)
					}
				}
			}
		} else {
			Element{
				...row
				enabled:             item.enabled
				accessibility_label: item.text
				accessibility_value: if current { 'current' } else { '' }
			}
		}
	}
	root := flex_with_rules(FlexConfig{
		id:          ctx.id
		frame:       ctx.frame
		orientation: .horizontal
		gap:         t.space_xsmall + 2
		align:       .center
	}, children, []FlexRule{len: children.len})!
	return vml_handled(Element{
		...root
		accessibility_role:  'navigation'
		accessibility_label: 'Breadcrumb'
	}, ctx, p.element_callback())
}

// BreadcrumbItemProps is the `BreadcrumbItem` tag, one step of a
// Breadcrumb: `icon` and `text`, a link that runs `on_click` unless it is
// the last step.
pub struct BreadcrumbItemProps {
pub mut:
	text     DisplayText = ''
	icon     IconName
	enabled  bool            = true
	on_click ElementCallback = unsafe { nil }
}

// BreadcrumbItemRecord is what a BreadcrumbItem tells its Breadcrumb.
pub struct BreadcrumbItemRecord {
pub:
	text     string
	icon     IconName
	enabled  bool            = true
	on_click ElementCallback = unsafe { nil }
}

pub fn (p BreadcrumbItemProps) part(ctx VmlBuildContext) !VmlPart {
	return VmlRecordPart{
		record: BreadcrumbItemRecord{
			text:     p.text.str()
			icon:     p.icon
			enabled:  p.enabled
			on_click: p.on_click
		}
	}
}

// ── Pagination ──────────────────────────────────────────────────────

// PaginationProps is the `Pagination` tag: previous and next buttons around
// buttons for the first and last page and up to `visible_pages` pages around
// `page`, with ellipses for the pages between. Choosing a page emits a
// change whose value is the page, and `page` is bindable.
pub struct PaginationProps {
	CommonProps
pub mut:
	page          int         = 1
	total_pages   int         = 1
	visible_pages int         = 5
	size          ControlSize = .small
}

// Pagination makes its buttons from its page count.
pub fn (p PaginationProps) vml_structure() VmlStructure {
	return .generated
}

pub fn (p PaginationProps) vml_themed() {}

pub fn (p PaginationProps) control_size() ControlSize {
	return p.size
}

// The buttons are focusable, which needs an id.
pub fn (p PaginationProps) control_id_required() bool {
	return true
}

pub fn (mut p PaginationProps) apply_event(event ElementEvent) {
	if event.kind == .change && event.value >= 1 {
		p.page = int(event.value)
	}
}

pub fn (p PaginationProps) build(ctx VmlBuildContext) !Element {
	t := ctx.tokens()
	m := t.metrics(p.size)
	enabled := p.enabled or { true }
	state := pagination_state(p.page, p.total_pages).with_visible_pages(p.visible_pages).with_disabled(!enabled)
	emitter := ctx.emitter(p.element_callback())
	previous := state.previous_page() or { 0 }
	next := state.next_page() or { 0 }
	items := state.items()
	mut children := []Element{cap: items.len + 2}
	mut rules := []FlexRule{cap: items.len + 2}
	children << kit_button(ctx, 'previous', ButtonProps{
		icon:                .chevron_left
		variant:             .ghost
		size:                p.size
		enabled:             previous > 0
		accessibility_label: 'Previous page'
		on_click:            kit_page_choice(emitter, previous)
	})!
	rules << FlexRule{}
	for index, item in items {
		id := ctx.part_id('item_${index}')
		if item.kind == .ellipsis {
			children << Element{
				...flex_with_rules(FlexConfig{
					id:          id
					orientation: .horizontal
					justify:     .center
					align:       .center
					box:         BoxStyle{
						transparent: true
					}
				}, [
					Element{
						...kit_icon('', .ellipsis, m.icon, t.muted)
						key: 'ellipsis'
					},
				], [FlexRule{}])!
				accessibility_label: 'Pages ${item.start} to ${item.end - 1}'
			}
		} else {
			current := item.page == state.current_page()
			children << kit_button(ctx, 'item_${index}', ButtonProps{
				text:                item.page
				variant:             if current { ButtonVariant.outline } else { .ghost }
				size:                p.size
				enabled:             enabled
				accessibility_label: 'Page ${item.page}'
				accessibility_value: if current { 'current' } else { '' }
				on_click:            kit_page_choice(emitter, if current { 0 } else { item.page })
			})!
		}
		rules << FlexRule{
			minimum_width: m.height
		}
	}
	children << kit_button(ctx, 'next', ButtonProps{
		icon:                .chevron_right
		variant:             .ghost
		size:                p.size
		enabled:             next > 0
		accessibility_label: 'Next page'
		on_click:            kit_page_choice(emitter, next)
	})!
	rules << FlexRule{}
	root := flex_with_rules(FlexConfig{
		id:          ctx.id
		frame:       ctx.frame
		orientation: .horizontal
		gap:         t.space_xsmall
		align:       .center
	}, children, rules)!
	return vml_handled(Element{
		...root
		accessibility_role:  'navigation'
		accessibility_label: 'Pagination'
		accessibility_value: 'Page ${state.current_page()} of ${state.total_pages()}'
	}, ctx, p.element_callback())
}

// kit_page_choice is the click handler of a pagination button: it emits the
// change to page, or nothing for page zero.
fn kit_page_choice(emitter VmlEmitter, page int) ElementCallback {
	return fn [emitter, page] (event ElementEvent) {
		if event.kind == .click && page > 0 {
			emitter.emit(ElementEvent{
				kind:  .change
				id:    event.id
				value: f64(page)
			})
		}
	}
}
