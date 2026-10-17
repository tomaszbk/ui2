// vtest vflags: -d vml_props
module ui2

// The kit's navigation components built through the generic node runtime:
// their parts, the selection they show, and the changes their parts and
// keys emit.

fn kit_key(el Element, key string) {
	el.on_event(ElementEvent{ kind: .key_down, id: el.id, key: key })
}

fn kit_tabs_document() !Element {
	return props_document(pn(ColumnProps{},
		children: [
			pn(TabsProps{ value: 'password' },
				id:       'settings'
				children: [
					pn(TabProps{ value: 'account', text: 'Account', icon: .circle_user },
						children: [
							pn(LabelProps{ text: 'Profile' }),
						]
					),
					pn(TabProps{ value: 'password', text: 'Password' },
						children: [
							pn(LabelProps{ text: 'Change it' }),
						]
					),
					pn(TabProps{ text: 'Billing', enabled: false }),
					pn(TabProps{ text: 'Team' }),
				]
			),
			pn(TabsProps{ variant: .segmented, size: .small },
				id:       'view'
				children: [
					pn(TabProps{ text: 'List' }),
					pn(TabProps{ text: 'Grid' }),
				]
			),
		]
	), rect(0, 0, 400, 300))!
}

fn test_tabs_show_the_panel_of_the_selected_tab() ! {
	tree := kit_tabs_document()!
	t := kit_tokens(default_theme())
	settings := tree.children[0]
	list := settings.children[0]
	assert list.id.ends_with('settings__list') && list.accessibility_role == 'tablist'
	assert list.focus_policy == .focusable && list.keys == ['left', 'right', 'home', 'end']
	assert list.box.border_bottom == 1 && list.frame.width == 400
	assert list.children.len == 4
	account := list.children[0]
	assert account.accessibility_role == 'tab' && account.focus_policy == .unfocusable
	assert account.children.map(it.key) == ['icon', 'text']
	assert account.children[1].text_style.color == t.muted
	password := list.children[1]
	assert password.accessibility_value == 'selected' && password.box.border_bottom == 2
	assert password.children[0].text_style.color == t.text
	assert !list.children[2].enabled
	panels := settings.children[1]
	assert panels.id.ends_with('settings__panels')
	assert panels.children.map(it.hidden) == [true, false, true, true]
	assert panels.children[1].accessibility_role == 'tabpanel'
	assert panels.children[1].children[0].text == 'Change it'
	// The panel fills the width, under the list.
	assert panels.children[1].frame.width == 400
	// Without a value, the first tab is selected. A segmented list hugs its
	// triggers in a muted box.
	view := tree.children[1]
	segmented := view.children[0]
	assert segmented.box.bg == t.surface_muted && segmented.frame.width < 400
	assert segmented.children[0].box.shadow == t.card_shadow()
	assert segmented.children[1].box.transparent
	assert view.children[1].children.map(it.hidden) == [false, true]
}

fn test_tabs_select_from_clicks_and_keys() ! {
	tree := kit_tabs_document()!
	mut root := tree.compiled_node
	root.mount()!
	settings := root.element().children[0]
	account := settings.children[0].children[0]
	account.on_event(ElementEvent{ kind: .click, id: account.id })
	after := root.element().children[0]
	assert after.children[0].children[0].accessibility_value == 'selected'
	assert after.children[1].children.map(it.hidden) == [false, true, true, true]
	// The keys skip the disabled tab and wrap.
	kit_key(after.children[0], 'left')
	wrapped := root.element().children[0]
	assert wrapped.children[1].children.map(it.hidden) == [true, true, true, false]
	kit_key(wrapped.children[0], 'left')
	assert root.element().children[0].children[1].children.map(it.hidden) == [true, false, true,
		true]
	kit_key(root.element().children[0].children[0], 'home')
	assert root.element().children[0].children[1].children.map(it.hidden) == [false, true, true,
		true]
	root.dispose_document()!
}

fn test_tabs_reject_other_children() {
	props_document(pn(TabsProps{},
		id:       'bad'
		children: [
			pn(LabelProps{ text: 'not a tab' }),
		]
	), rect(0, 0, 200, 200)) or {
		assert err.msg().contains('Tab children')
		return
	}
	assert false
}
