// vtest vflags: -d vml_props
module ui2

// The kit's disclosure components built through the generic node runtime:
// their headers, which items are shown, and the changes a header emits.

fn kit_click(el Element) {
	el.on_event(ElementEvent{ kind: .click, id: el.id })
}

fn test_collapsible_shows_its_children_while_open() ! {
	tree := props_document(pn(ColumnProps{},
		children: [
			pn(CollapsibleProps{ text: 'Details', icon: .info },
				id:       'more'
				children: [
					pn(LabelProps{ text: 'Hidden until opened' }),
				]
			),
		]
	), rect(0, 0, 300, 200))!
	mut root := tree.compiled_node
	root.mount()!
	t := kit_tokens(default_theme())
	more := root.element().children[0]
	assert more.accessibility_role == 'group' && more.accessibility_label == 'Details'
	header := more.children[0]
	assert header.id.ends_with('more__trigger') && header.button_behavior
	assert header.accessibility_value == 'collapsed'
	assert header.children.map(it.key) == ['icon', 'title', 'chevron']
	assert header.children[1].text == 'Details' && header.children[1].text_style.color == t.text
	assert header.children[2].image_path == 'symbol:' + IconName.chevron_down.symbol()
	content := more.children[1]
	assert content.hidden && content.children[0].text == 'Hidden until opened'
	// The content fades in, and the box slides to its new height.
	reveal := content.motion or { MotionConfig{} }
	entering := reveal.enter.opacity or { 1 }
	assert entering == 0
	assert (more.motion or { MotionConfig{} }).layout == .box
	kit_click(header)
	opened := root.element().children[0]
	assert !opened.children[1].hidden
	assert opened.children[0].accessibility_value == 'expanded'
	assert opened.children[0].children[2].image_path == 'symbol:' + IconName.chevron_up.symbol()
	kit_click(opened.children[0])
	assert root.element().children[0].children[1].hidden
	root.dispose_document()!
}

fn test_accordion_opens_one_item_at_a_time() ! {
	tree := props_document(pn(ColumnProps{},
		children: [
			pn(AccordionProps{ value: 'profile' },
				id:       'settings'
				children: [
					pn(AccordionItemProps{ value: 'profile', title: 'Profile' },
						children: [
							pn(LabelProps{ text: 'Your public profile' }),
						]
					),
					pn(AccordionItemProps{ title: 'Security', icon: .padlock },
						children: [
							pn(LabelProps{ text: 'Passwords' }),
						]
					),
					pn(AccordionItemProps{ title: 'Billing', enabled: false }),
				]
			),
		]
	), rect(0, 0, 320, 400))!
	mut root := tree.compiled_node
	root.mount()!
	t := kit_tokens(default_theme())
	settings := root.element().children[0]
	// A header before each item.
	assert settings.children.len == 6
	assert settings.box.border_top == 1 && settings.box.radius == t.radius_medium
	profile := settings.children[0]
	assert profile.id.ends_with('settings__trigger_0')
	assert profile.accessibility_value == 'expanded' && profile.box.border_top == 0
	assert !settings.children[1].hidden && settings.children[1].children[0].text == 'Your public profile'
	security := settings.children[2]
	assert security.box.border_top == 1 && security.children.map(it.key) == ['icon', 'title', 'chevron']
	assert settings.children[3].hidden
	billing := settings.children[4]
	assert !billing.enabled && billing.children[0].text_style.color == t.disabled_text
	// An item without a value is named by its title.
	kit_click(security)
	after := root.element().children[0]
	assert after.children[1].hidden && !after.children[3].hidden
	assert after.children[2].accessibility_value == 'expanded'
	// Clicking the open item closes it.
	kit_click(after.children[2])
	closed := root.element().children[0]
	assert closed.children[1].hidden && closed.children[3].hidden
	root.dispose_document()!
}

fn test_multiple_accordion_keeps_items_open() ! {
	tree := props_document(pn(ColumnProps{},
		children: [
			pn(AccordionProps{ multiple: true, values: ['a'], bordered: false },
				id:       'faq'
				children: [
					pn(AccordionItemProps{ value: 'a', title: 'A' }),
					pn(AccordionItemProps{ value: 'b', title: 'B' }),
				]
			),
		]
	), rect(0, 0, 320, 400))!
	mut root := tree.compiled_node
	root.mount()!
	faq := root.element().children[0]
	assert faq.box.border_top == 0 && faq.children[2].box.border_top == 0
	assert !faq.children[1].hidden && faq.children[3].hidden
	kit_click(faq.children[2])
	both := root.element().children[0]
	assert !both.children[1].hidden && !both.children[3].hidden
	kit_click(both.children[0])
	last := root.element().children[0]
	assert last.children[1].hidden && !last.children[3].hidden
	root.dispose_document()!
}

fn test_accordion_toggles_its_value() {
	mut single := AccordionProps{}
	single.apply_event(ElementEvent{ kind: .change, text: 'a' })
	assert single.value == 'a' && single.values == ['a']
	single.apply_event(ElementEvent{ kind: .change, text: 'b' })
	assert single.value == 'b' && single.values == ['b']
	single.apply_event(ElementEvent{ kind: .change, text: 'b' })
	assert single.value == '' && single.values.len == 0
	mut multiple := AccordionProps{
		multiple: true
	}
	multiple.apply_event(ElementEvent{ kind: .change, text: 'a' })
	multiple.apply_event(ElementEvent{ kind: .change, text: 'b' })
	assert multiple.values == ['a', 'b']
	multiple.apply_event(ElementEvent{ kind: .change, text: 'a' })
	assert multiple.values == ['b']
}

fn test_accordion_rejects_other_children() {
	props_document(pn(AccordionProps{},
		id:       'bad'
		children: [
			pn(LabelProps{ text: 'not an item' }),
		]
	), rect(0, 0, 200, 200)) or {
		assert err.msg().contains('AccordionItem')
		return
	}
	assert false
}
