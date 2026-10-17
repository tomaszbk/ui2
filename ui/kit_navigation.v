module ui2

// The kit's navigation components: Tabs with its Tab panels, Breadcrumb
// with its BreadcrumbItem parts, Pagination, Tree with its TreeItem
// children, and Carousel with its CarouselSlide children. A Tabs, a Tree
// and a Carousel keep one tab stop: it takes the arrow keys and selects the
// neighboring tab, row or slide, and the triggers and rows inside take
// clicks.

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

// ── Tree ────────────────────────────────────────────────────────────

// TreeProps is the `Tree` tag: a row per shown TreeItem, indented by its
// depth, with the item named by `value` selected. Clicking a row selects it
// and expands or collapses it when it has children. Selecting emits a
// change whose text is the item's value, and `value` is bindable. While the
// tree has focus, the arrow keys, Home and End select and expand
// (tree_key_move), and Enter and Space expand.
pub struct TreeProps {
	CommonProps
pub mut:
	value string
}

pub fn (p TreeProps) vml_container() {}

// A Tree makes its rows from its items' records, so it is rebuilt when one
// of them changes.
pub fn (p TreeProps) vml_structure() VmlStructure {
	return .sourced
}

pub fn (p TreeProps) vml_themed() {}

pub fn (p TreeProps) child_placement(placement VmlPlacement) VmlPlacement {
	return .preferred
}

// The tree is focusable, which needs an id.
pub fn (p TreeProps) control_id_required() bool {
	return true
}

pub fn (mut p TreeProps) apply_event(event ElementEvent) {
	if event.kind == .change && event.text.len > 0 {
		p.value = event.text
	}
}

pub fn (p TreeProps) build(ctx VmlBuildContext) !Element {
	t := ctx.tokens()
	m := t.metrics(.medium)
	enabled := p.enabled or { true }
	mut items := []TreeItemRecord{cap: ctx.children.len}
	for index in 0 .. ctx.children.len {
		items << ctx.child_record[TreeItemRecord](index) or {
			return error('Tree takes TreeItem children')
		}
	}
	rows := tree_rows(items)
	selected := rows.map(it.item.value).index(p.value)
	emitter := ctx.emitter(p.element_callback())
	mut children := []Element{cap: rows.len}
	for index, row in rows {
		children << kit_tree_row(t, m, ctx.part_id('row_${index}'), row, index == selected,
			enabled, emitter)!
	}
	root := flex_with_rules(FlexConfig{
		id:          ctx.id
		frame:       ctx.frame
		orientation: .vertical
		padding:     kit_padding(0, t.space_xsmall)
		box:         BoxStyle{
			transparent: true
			radius:      t.radius_small
		}
	}, children, []FlexRule{len: children.len})!
	callback := p.element_callback()
	return vml_handled(Element{
		...root
		focus_policy:       .focusable
		keys:               ['up', 'down', 'left', 'right', 'home', 'end', 'enter', 'space']
		accessibility_role: 'tree'
		interaction_style:  kit_focus_interaction(t)
	}, ctx, fn [callback, emitter, rows, selected] (event ElementEvent) {
		if callback != unsafe { nil } {
			callback(event)
		}
		if event.kind != .key_down {
			return
		}
		move := tree_key_move(rows, selected, event.key)
		if move.row >= 0 {
			emitter.emit(ElementEvent{
				kind: .change
				id:   event.id
				text: rows[move.row].item.value
			})
		}
		if move.toggle && selected >= 0 {
			item := rows[selected].item
			item.toggle.emit(ElementEvent{
				kind:    .change
				checked: !item.expanded
			})
		}
	})
}

// kit_tree_row is one row of a Tree: a chevron for an item with children
// (a spacer for one without), its icon and its text, indented by depth. The
// tree holds the focus, so a row only takes clicks.
fn kit_tree_row(t KitTokens, m ControlMetrics, id string, row TreeRow, selected bool, enabled bool, tree VmlEmitter) !Element {
	item := row.item
	usable := enabled && item.enabled
	foreground := if usable { t.text } else { t.disabled_text }
	parent := item.children.len > 0
	mut content := []Element{cap: 3}
	content << if parent {
		Element{
			...kit_icon('', if item.expanded { IconName.chevron_down } else { .chevron_right },
				m.icon, if usable { t.muted } else { t.disabled_text })
			key:                 'chevron'
			accessibility_label: ''
		}
	} else {
		Element{
			...kit_icon('', .none, m.icon, foreground)
			key: 'spacer'
		}
	}
	if item.icon != .none {
		content << Element{
			...kit_icon('', item.icon, m.icon, foreground)
			key: 'icon'
		}
	}
	content << Element{
		...label('', item.text, Rect{}, TextStyle{
			color:  foreground
			size:   m.font_size
			weight: if selected { 500 } else { 400 }
		})
		key: 'text'
	}
	mut rules := []FlexRule{len: content.len}
	rules[rules.len - 1] = FlexRule{
		grow:   1
		shrink: 1
	}
	el := flex_with_rules(FlexConfig{
		id:          id
		orientation: .horizontal
		gap:         t.space_xsmall
		padding:     LayoutPadding{
			left:   t.space_small + f64(row.depth) * (m.icon + t.space_xsmall)
			right:  t.space_small
			top:    t.space_xsmall
			bottom: t.space_xsmall
		}
		align:       .center
		box:         BoxStyle{
			bg:          t.selection
			transparent: !selected
			radius:      t.radius_small
		}
	}, content, rules)!
	value := item.value
	expanded := item.expanded
	toggle := item.toggle
	mut state := []string{cap: 2}
	if selected {
		state << 'selected'
	}
	if parent {
		state << if expanded { 'expanded' } else { 'collapsed' }
	}
	return Element{
		...with_button_behavior(Element{
			...el
			accessibility_role:  'treeitem'
			accessibility_label: item.text
		})
		enabled:             usable
		focus_policy:        .unfocusable
		accessibility_value: state.join(', ')
		interaction_style:   if usable { kit_row_interaction(t) } else { InteractionStyle{} }
		on_event:            fn [tree, toggle, value, selected, parent, expanded] (event ElementEvent) {
			if event.kind != .click {
				return
			}
			if !selected {
				tree.emit(ElementEvent{
					kind: .change
					id:   event.id
					text: value
				})
			}
			if parent {
				toggle.emit(ElementEvent{
					kind:    .change
					checked: !expanded
				})
			}
		}
	}
}

// TreeItemProps is the `TreeItem` tag, one item of a Tree: `icon` and
// `text`, and its child TreeItems, shown while it is `expanded`. `value`
// names it to the Tree and defaults to `text`. Expanding or collapsing it
// emits a change whose checked is the new state, and `expanded` is
// bindable.
pub struct TreeItemProps {
	CommonProps
pub mut:
	value    string
	text     DisplayText = ''
	icon     IconName
	expanded bool
}

// TreeItemRecord is what a TreeItem tells its Tree: its row, its children,
// and how the Tree expands or collapses it.
pub struct TreeItemRecord {
pub:
	value    string
	text     string
	icon     IconName
	expanded bool
	enabled  bool = true
	children []TreeItemRecord
	toggle   VmlEmitter
}

pub fn (p TreeItemProps) vml_container() {}

// An item reads its children's records, so it is rebuilt when one of them
// changes.
pub fn (p TreeItemProps) vml_structure() VmlStructure {
	return .sourced
}

pub fn (mut p TreeItemProps) apply_event(event ElementEvent) {
	if event.kind == .change {
		p.expanded = event.checked
	}
}

// An item is not shown itself: the Tree draws a row from its record. Its
// element only carries the record and its children's elements.
pub fn (p TreeItemProps) build(ctx VmlBuildContext) !Element {
	mut children := []TreeItemRecord{cap: ctx.children.len}
	for index in 0 .. ctx.children.len {
		children << ctx.child_record[TreeItemRecord](index) or {
			return error('TreeItem takes TreeItem children')
		}
	}
	text := p.text.str()
	return with_record(vml_handled(view(ctx.id, ctx.frame, BoxStyle{
		transparent: true
	}, ctx.children), ctx, p.element_callback()), TreeItemRecord{
		value:    if p.value.len > 0 { p.value } else { text }
		text:     text
		icon:     p.icon
		expanded: p.expanded
		enabled:  p.enabled or { true }
		children: children
		toggle:   ctx.emitter(p.element_callback())
	})
}

// ── Carousel ────────────────────────────────────────────────────────

// CarouselProps is the `Carousel` tag: one CarouselSlide child at a time,
// the one at `index`, above previous and next buttons and a dot per slide.
// With `loop` the buttons wrap around. Showing another slide emits a change
// whose value is its index, and `index` is bindable. While the carousel has
// focus, Left and Right show the previous and next slide, Home and End the
// first and last.
pub struct CarouselProps {
	CommonProps
pub mut:
	index int
	loop  bool
}

pub fn (p CarouselProps) vml_container() {}

// A Carousel shows one of its slides, so it is rebuilt when they change.
pub fn (p CarouselProps) vml_structure() VmlStructure {
	return .sourced
}

pub fn (p CarouselProps) vml_themed() {}

pub fn (p CarouselProps) child_placement(placement VmlPlacement) VmlPlacement {
	return .preferred
}

// The carousel is focusable, which needs an id.
pub fn (p CarouselProps) control_id_required() bool {
	return true
}

pub fn (mut p CarouselProps) apply_event(event ElementEvent) {
	if event.kind == .change {
		p.index = int(event.value)
	}
}

pub fn (p CarouselProps) build(ctx VmlBuildContext) !Element {
	t := ctx.tokens()
	count := ctx.children.len
	enabled := p.enabled or { true }
	current := carousel_index(p.index, count, p.loop)
	previous := carousel_previous(current, count, p.loop)
	next := carousel_next(current, count, p.loop)
	emitter := ctx.emitter(p.element_callback())
	// The slides share one cell; a slide's own motion crossfades it with the
	// one it replaces.
	mut slides := []Element{cap: count}
	mut slide_label := ''
	for index, child in ctx.children {
		record := ctx.child_record[CarouselSlideRecord](index) or {
			return error('Carousel takes CarouselSlide children')
		}
		if index == current {
			slide_label = record.label
		}
		slides << Element{
			...child
			hidden: child.hidden || index != current
		}
	}
	viewport := stack_with_rules(StackConfig{
		id:      ctx.part_id('viewport')
		align_x: .stretch
		align_y: .stretch
	}, slides, []StackRule{len: slides.len})!
	controls := flex_with_rules(FlexConfig{
		id:          ctx.part_id('controls')
		orientation: .horizontal
		gap:         t.space_small
		justify:     .center
		align:       .center
	}, [
		kit_button(ctx, 'previous', ButtonProps{
			icon:                .chevron_left
			variant:             .outline
			size:                .small
			enabled:             enabled && previous != current
			accessibility_label: 'Previous slide'
			on_click:            kit_slide_choice(emitter, previous)
		})!,
		kit_carousel_dots(t, ctx.part_id('dots'), count, current)!,
		kit_button(ctx, 'next', ButtonProps{
			icon:                .chevron_right
			variant:             .outline
			size:                .small
			enabled:             enabled && next != current
			accessibility_label: 'Next slide'
			on_click:            kit_slide_choice(emitter, next)
		})!,
	], []FlexRule{len: 3})!
	root := flex_with_rules(FlexConfig{
		id:          ctx.id
		frame:       ctx.frame
		orientation: .vertical
		gap:         t.space_small
		box:         BoxStyle{
			transparent: true
			radius:      t.radius_medium
		}
	}, [viewport, controls], [FlexRule{
		grow:   1
		shrink: 1
	}, FlexRule{}])!
	callback := p.element_callback()
	return vml_handled(Element{
		...root
		focus_policy:        .focusable
		keys:                ['left', 'right', 'home', 'end']
		accessibility_role:  'group'
		accessibility_value: kit_slide_value(current, count, slide_label)
		interaction_style:   kit_focus_interaction(t)
	}, ctx, fn [callback, emitter, current, previous, next, count] (event ElementEvent) {
		if callback != unsafe { nil } {
			callback(event)
		}
		if event.kind != .key_down || count == 0 {
			return
		}
		target := match event.key {
			'left' { previous }
			'right' { next }
			'home' { 0 }
			'end' { count - 1 }
			else { current }
		}
		if target != current {
			emitter.emit(ElementEvent{
				kind:  .change
				id:    event.id
				value: f64(target)
			})
		}
	})
}

// kit_slide_value is a carousel's accessibility value: which slide it shows,
// and that slide's label when it has one.
fn kit_slide_value(current int, count int, name string) string {
	if count == 0 {
		return 'No slides'
	}
	position := 'Slide ${current + 1} of ${count}'
	return if name.len > 0 { '${position}: ${name}' } else { position }
}

// kit_slide_choice is the click handler of a carousel button: it emits the
// change to slide index.
fn kit_slide_choice(emitter VmlEmitter, index int) ElementCallback {
	return fn [emitter, index] (event ElementEvent) {
		if event.kind == .click {
			emitter.emit(ElementEvent{
				kind:  .change
				id:    event.id
				value: f64(index)
			})
		}
	}
}

// kit_carousel_dots is a carousel's position: a dot per slide, the current
// one in the accent color, drawn as two vector shapes.
fn kit_carousel_dots(t KitTokens, id string, count int, current int) !Element {
	side := 6.0
	gap := 6.0
	mut others := VectorPath{}
	mut active := VectorPath{}
	for index in 0 .. count {
		dot := kit_arc_path(f64(index) * (side + gap) + side / 2, side / 2, side / 2, 0, 1)
		if index == current {
			active.commands << dot.commands
			active.close()
		} else {
			others.commands << dot.commands
			others.close()
		}
	}
	mut shapes := []VectorShape{cap: 2}
	if others.commands.len > 0 {
		shapes << prepare_vector_shape(others, VectorStyle{
			fill: t.track
		})!
	}
	if active.commands.len > 0 {
		shapes << prepare_vector_shape(active, VectorStyle{
			fill: t.accent
		})!
	}
	width := if count > 0 { f64(count) * (side + gap) - gap } else { 0.0 }
	return Element{
		...vector_canvas(
			id:     id
			frame:  rect(0, 0, width, side)
			shapes: shapes
		)!
		accessibility_role: 'img'
	}
}

// CarouselSlideProps is the `CarouselSlide` tag, one slide of a Carousel:
// its children laid out in a column like Column's. It fades and slides in
// from the right when it is shown, and out to the left when it is hidden.
// Its `accessibility_label` names it in the Carousel's value.
pub struct CarouselSlideProps {
	CommonProps
	VmlFlexFields
}

// CarouselSlideRecord is what a CarouselSlide tells its Carousel.
pub struct CarouselSlideRecord {
pub:
	label string
}

pub fn (p CarouselSlideProps) vml_container() {}

pub fn (p CarouselSlideProps) child_placement(placement VmlPlacement) VmlPlacement {
	return .preferred
}

pub fn (p CarouselSlideProps) build(ctx VmlBuildContext) !Element {
	slide := p.VmlFlexFields.build_flex(p.CommonProps, .vertical, ctx)!
	return with_record(with_motion(slide, kit_motion_slide()), CarouselSlideRecord{
		label: p.accessibility_label or { '' }
	})
}

// kit_motion_slide fades a slide in from the right when it is shown, and out
// to the left when it is hidden.
fn kit_motion_slide() MotionConfig {
	return motion_compose(motion_enter(MotionStyle{ opacity: 0, translate_x: 24 }), motion_exit(MotionStyle{
		opacity:     0
		translate_x: -24
	}), motion_duration(0.25), motion_easing(.out_cubic))
}
