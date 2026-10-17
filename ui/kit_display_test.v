// vtest vflags: -d vml_props
module ui2

// The kit's display components built through the generic node runtime:
// their parts, colors from the tokens, and the records a list reads.

@[heap]
struct KitDisplayLog {
mut:
	lines []string
}

fn test_badge_shows_its_count_at_the_corner_of_its_children() ! {
	tree := props_document(pn(RowProps{ align_items: .start, gap: 24 },
		children: [
			pn(BadgeProps{ count: 3 },
				id:       'mail'
				children: [
					pn(IconProps{ name: .bell }),
				]
			),
			pn(BadgeProps{ count: 120, tone: .primary }, id: 'many'),
			pn(BadgeProps{ dot: true },
				id:       'dot'
				children: [
					pn(IconProps{ name: .bell }),
				]
			),
			pn(BadgeProps{},
				id:       'none'
				children: [
					pn(IconProps{ name: .bell }),
				]
			),
		]
	), rect(0, 0, 400, 100))!
	t := kit_tokens(default_theme())
	mail := tree.children[0]
	assert mail.layout.kind == .stack
	assert mail.children.len == 2
	assert mail.children[0].accessibility_role == 'img'
	bubble := mail.children[1]
	assert bubble.id.ends_with('mail__badge')
	assert !bubble.hidden && bubble.box.bg == t.danger
	assert bubble.children[0].text == '3'
	assert bubble.translate_x > 0 && bubble.translate_y < 0
	// The bubble sits at the top right of the icon.
	assert bubble.frame.x + bubble.frame.width == mail.frame.width && bubble.frame.y == 0
	// Alone, the bubble is not offset.
	many := tree.children[1]
	assert many.children.len == 1 && many.children[0].children[0].text == '99+'
	assert many.children[0].box.bg == t.accent && many.children[0].translate_x == 0
	dot := tree.children[2].children[1]
	assert dot.children.len == 0 && dot.frame.width == 8
	assert tree.children[3].children[1].hidden
}

fn test_avatar_shows_initials_or_an_image_in_a_circle() ! {
	tree := props_document(pn(RowProps{ align_items: .start },
		children: [
			pn(AvatarProps{ name: 'Ada Lovelace' }, id: 'ada'),
			pn(AvatarProps{ name: 'Grace', src: 'grace.png', size: .large }, id: 'grace'),
		]
	), rect(0, 0, 400, 100))!
	t := kit_tokens(default_theme())
	ada := tree.children[0]
	assert ada.frame.width == 32 && ada.frame.height == 32
	assert ada.box.radius == 16 && ada.box.bg == t.surface_muted
	assert ada.children[0].text == 'AL'
	assert ada.accessibility_label == 'Ada Lovelace'
	grace := tree.children[1]
	assert grace.frame.width == 40
	assert grace.children[0].kind == .image && grace.children[0].image_path == 'grace.png'
}

fn test_tags_tint_their_tone() ! {
	tree := props_document(pn(RowProps{ align_items: .start, gap: 8 },
		children: [
			pn(TagProps{ text: 'Draft' }, id: 'draft'),
			pn(TagProps{ text: 'Paid', tone: .success, icon: .check }, id: 'paid'),
			pn(TagProps{ text: 'Late', tone: .danger, outline: true }, id: 'late'),
		]
	), rect(0, 0, 400, 100))!
	t := kit_tokens(default_theme())
	draft := tree.children[0]
	assert draft.box.bg == t.surface_muted && draft.children[0].text_style.color == t.text
	assert draft.accessibility_label == 'Draft'
	paid := tree.children[1]
	assert paid.children.len == 2 && paid.children[0].kind == .image
	assert paid.box.bg == kit_mix(t.success, t.surface, 0.85)
	assert kit_contrast(paid.children[1].text_style.color, paid.box.bg) >= 4.5
	late := tree.children[2]
	assert late.box.bg == t.surface && late.box.border_color == late.children[0].text_style.color
}

fn test_separators_rule_their_parent() ! {
	tree := props_document(pn(ColumnProps{ gap: 8 },
		children: [
			pn(SeparatorProps{}, id: 'line'),
			pn(SeparatorProps{ text: 'or' }, id: 'labeled'),
			pn(RowProps{ height: 40 },
				children: [
					pn(SeparatorProps{ orientation: .vertical }, id: 'upright'),
				]
			),
		]
	), rect(0, 0, 300, 200))!
	t := kit_tokens(default_theme())
	line := tree.children[0]
	assert line.frame.width == 300 && line.frame.height == 1
	assert line.box.bg == t.border && line.accessibility_role == 'separator'
	labeled := tree.children[1]
	assert labeled.children.len == 3 && labeled.children[1].text == 'or'
	assert labeled.children[0].frame.width == labeled.children[2].frame.width
	upright := tree.children[2].children[0]
	assert upright.frame.width == 1 && upright.frame.height == 40
}

fn test_kbd_and_link() ! {
	mut log := &KitDisplayLog{}
	tree := props_document(pn(RowProps{ align_items: .start, gap: 8 },
		children: [
			pn(KbdProps{ text: 'cmd+k' }, id: 'shortcut'),
			pn(LinkProps{
				text:     'Docs'
				on_click: fn [mut log] (event ElementEvent) {
					log.lines << 'click ${event.kind}'
				}
			}, id: 'docs'),
			pn(LinkProps{ text: 'Off', enabled: false }),
		]
	), rect(0, 0, 400, 100))!
	t := kit_tokens(default_theme())
	kbd := tree.children[0]
	assert kbd.children[0].text == 'cmd+k' && kbd.box.border_bottom == 2
	link := tree.children[1]
	assert link.button_behavior && link.accessibility_role == 'link'
	assert link.children[0].text_style.underline
	assert link.children[0].text_style.color == kit_legible(t.accent, t.surface, t.text)
	ring := link.interaction_style.focus.outline_color or { 0 }
	assert ring == t.focus_ring
	link.on_event(ElementEvent{ kind: .click, id: link.id })
	assert log.lines == ['click click']
	// A link without an id gets one: it is focusable.
	off := tree.children[2]
	assert off.id.len > 0 && !off.enabled
	assert off.children[0].text_style.color == t.disabled_text
}

fn test_alert_and_empty_lay_out_their_text_and_children() ! {
	tree := props_document(pn(ColumnProps{ gap: 8 },
		children: [
			pn(AlertProps{ title: 'Saved', text: 'Your changes are live.', tone: .success },
				id:       'saved'
				children: [
					pn(ButtonProps{ text: 'Undo' }),
				]
			),
			pn(AlertProps{ text: 'Heads up' }, id: 'plain'),
			pn(EmptyProps{ title: 'No files', text: 'Upload one to start.' },
				id:       'empty'
				children: [
					pn(ButtonProps{ text: 'Upload', variant: .primary }),
				]
			),
		]
	), rect(0, 0, 400, 400))!
	t := kit_tokens(default_theme())
	saved := tree.children[0]
	assert saved.accessibility_role == 'alert' && saved.accessibility_label == 'Saved'
	assert saved.box.bg == kit_mix(t.success, t.surface, 0.9)
	assert saved.children[0].image_path == 'symbol:' + IconName.circle_check.symbol()
	body := saved.children[1]
	assert body.children.map(it.text) == ['Saved', 'Your changes are live.', '']
	assert body.children[2].accessibility_label == 'Undo'
	assert body.children[1].text_style.lines == 0
	plain := tree.children[1]
	assert plain.children[0].accessibility_label == IconName.info.title()
	assert plain.children[1].children.len == 1
	empty := tree.children[2]
	assert empty.layout.flex.align == .center
	assert empty.children.map(it.kind) == [Kind.image, Kind.label, Kind.label, Kind.view]
	assert empty.children[1].text == 'No files'
}

fn test_group_box_and_description_list() ! {
	tree := props_document(pn(ColumnProps{ gap: 8 },
		children: [
			pn(GroupBoxProps{ title: 'Account' },
				id:       'account'
				children: [
					pn(LabelProps{ text: 'Plan: Pro' }),
				]
			),
			pn(DescriptionListProps{ label_width: 90 },
				id:       'details'
				children: [
					pn(DescriptionItemProps{ label: 'Name', text: 'Ada' }),
					pn(DescriptionItemProps{ label: 'Status' },
						children: [
							pn(TagProps{ text: 'Active', tone: .success }),
						]
					),
				]
			),
		]
	), rect(0, 0, 400, 400))!
	t := kit_tokens(default_theme())
	group := tree.children[0]
	assert group.children.map(it.text) == ['Account', 'Plan: Pro']
	assert group.box.border_top == 1 && group.accessibility_role == 'group'
	details := tree.children[1]
	assert details.children.len == 2
	name := details.children[0]
	assert name.id.ends_with('details__row_0')
	assert name.children[0].text == 'Name' && name.children[0].frame.width == 90
	assert name.children[0].text_style.color == t.muted
	assert name.children[1].children[0].text == 'Ada'
	status := details.children[1]
	assert status.box.border_top == 1
	assert status.children[1].children[0].accessibility_label == 'Active'
	assert status.children[1].frame.x == 90 + t.space_medium + t.space_medium
}
