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

@[heap]
struct KitNavigationLog {
mut:
	lines []string
}

fn test_breadcrumb_links_every_step_but_the_last() ! {
	mut log := &KitNavigationLog{}
	tree := props_document(pn(ColumnProps{ align_items: .start },
		children: [
			pn(BreadcrumbProps{},
				id:       'path'
				children: [
					pn(BreadcrumbItemProps{
						text:     'Home'
						icon:     .folder
						on_click: fn [mut log] (event ElementEvent) {
							log.lines << 'home ${event.kind}'
						}
					}),
					pn(BreadcrumbItemProps{ text: 'Archive', enabled: false }),
					pn(BreadcrumbItemProps{ text: 'Report' }),
				]
			),
		]
	), rect(0, 0, 400, 100))!
	t := kit_tokens(default_theme())
	path := tree.children[0]
	assert path.accessibility_role == 'navigation'
	// Three steps between two chevrons.
	assert path.children.map(it.key) == ['', 'sep_1', '', 'sep_2', '']
	home := path.children[0]
	assert home.id.ends_with('path__item_0') && home.button_behavior
	assert home.accessibility_role == 'link' && home.children.map(it.key) == ['icon', 'text']
	assert home.children[1].text_style.color == t.muted
	home.on_event(ElementEvent{ kind: .click, id: home.id })
	assert log.lines == ['home click']
	archive := path.children[2]
	assert !archive.button_behavior && !archive.enabled
	assert archive.children[0].text_style.color == t.disabled_text
	report := path.children[4]
	assert report.accessibility_value == 'current' && report.children[0].text_style.color == t.text
}

fn test_pagination_shows_pages_around_the_current_one() ! {
	tree := props_document(pn(ColumnProps{ align_items: .start },
		children: [
			pn(PaginationProps{ page: 6, total_pages: 20 }, id: 'pages'),
			pn(PaginationProps{ page: 1, total_pages: 3 }, id: 'short'),
		]
	), rect(0, 0, 600, 100))!
	mut root := tree.compiled_node
	root.mount()!
	pages := root.element().children[0]
	assert pages.accessibility_value == 'Page 6 of 20'
	// Previous, 1, …, 5, 6, 7, …, 20, next.
	assert pages.children.len == 9
	assert pages.children[0].enabled && pages.children[0].accessibility_label == 'Previous page'
	assert pages.children[1].accessibility_label == 'Page 1'
	assert pages.children[2].children.map(it.key) == ['ellipsis']
	assert pages.children[4].accessibility_value == 'current'
	assert pages.children[7].accessibility_label == 'Page 20'
	short := root.element().children[1]
	assert short.children.len == 5 && !short.children[0].enabled && short.children[4].enabled
	// Choosing a page, or the next one, moves the window.
	next := pages.children[8]
	next.on_event(ElementEvent{ kind: .click, id: next.id })
	assert root.element().children[0].accessibility_value == 'Page 7 of 20'
	last := root.element().children[0].children[7]
	last.on_event(ElementEvent{ kind: .click, id: last.id })
	moved := root.element().children[0]
	assert moved.accessibility_value == 'Page 20 of 20' && !moved.children.last().enabled
	assert moved.children[2].children.map(it.key) == ['ellipsis']
	root.dispose_document()!
}

fn test_pagination_takes_whole_pages() {
	mut p := PaginationProps{}
	p.apply_event(ElementEvent{ kind: .change, value: 4 })
	assert p.page == 4
	p.apply_event(ElementEvent{ kind: .change, value: 0 })
	assert p.page == 4
}

fn kit_tree_document() !Element {
	return props_document(pn(ColumnProps{},
		children: [
			pn(TreeProps{ value: 'main.v' },
				id:       'files'
				children: [
					pn(TreeItemProps{ text: 'src', icon: .folder, expanded: true },
						children: [
							pn(TreeItemProps{ text: 'main.v' }),
							pn(TreeItemProps{ text: 'ui', icon: .folder },
								children: [
									pn(TreeItemProps{ text: 'app.v' }),
								]
							),
						]
					),
					pn(TreeItemProps{ text: 'locked', enabled: false }),
					pn(TreeItemProps{ value: 'readme', text: 'README.md' }),
				]
			),
		]
	), rect(0, 0, 300, 400))!
}

fn kit_tree_texts(tree Element) []string {
	return tree.children.map(it.children.last().text)
}

fn test_tree_draws_a_row_per_shown_item() ! {
	tree := kit_tree_document()!
	t := kit_tokens(default_theme())
	files := tree.children[0]
	assert files.accessibility_role == 'tree' && files.focus_policy == .focusable
	assert files.keys.len == 8
	assert kit_tree_texts(files) == ['src', 'main.v', 'ui', 'locked', 'README.md']
	src := files.children[0]
	assert src.id.ends_with('files__row_0') && src.accessibility_role == 'treeitem'
	assert src.focus_policy == .unfocusable && src.accessibility_value == 'expanded'
	assert src.children.map(it.key) == ['chevron', 'icon', 'text']
	assert src.children[0].image_path == 'symbol:' + IconName.chevron_down.symbol()
	main := files.children[1]
	assert main.children.map(it.key) == ['spacer', 'text']
	assert main.accessibility_value == 'selected' && !main.box.transparent
	assert main.box.bg == t.selection
	// A child row is indented by one icon and gap.
	assert main.layout.flex.padding.left - src.layout.flex.padding.left == 20
	ui := files.children[2]
	assert ui.accessibility_value == 'collapsed'
	assert ui.children[0].image_path == 'symbol:' + IconName.chevron_right.symbol()
	assert !files.children[3].enabled
}

fn test_tree_selects_and_expands_from_clicks_and_keys() ! {
	tree := kit_tree_document()!
	mut root := tree.compiled_node
	root.mount()!
	// A click on a parent selects it and expands it.
	ui := root.element().children[0].children[2]
	ui.on_event(ElementEvent{ kind: .click, id: ui.id })
	files := root.element().children[0]
	assert kit_tree_texts(files) == ['src', 'main.v', 'ui', 'app.v', 'locked', 'README.md']
	assert files.children[2].accessibility_value == 'selected, expanded'
	// Down selects the next row; Left from it goes back to its parent.
	kit_key(files, 'down')
	assert root.element().children[0].children[3].accessibility_value == 'selected'
	kit_key(root.element().children[0], 'left')
	assert root.element().children[0].children[2].accessibility_value == 'selected, expanded'
	// Left again collapses it; End skips nothing and selects the last row.
	kit_key(root.element().children[0], 'left')
	assert kit_tree_texts(root.element().children[0]) == ['src', 'main.v', 'ui', 'locked', 'README.md']
	kit_key(root.element().children[0], 'end')
	assert root.element().children[0].children[4].accessibility_value == 'selected'
	root.dispose_document()!
}

fn test_tree_items_take_tree_item_children() {
	props_document(pn(TreeProps{},
		id:       'bad'
		children: [
			pn(TreeItemProps{ text: 'a' },
				children: [
					pn(LabelProps{ text: 'not an item' }),
				]
			),
		]
	), rect(0, 0, 200, 200)) or {
		assert err.msg().contains('TreeItem children')
		return
	}
	assert false
}

fn kit_carousel_document(loop bool) !Element {
	return props_document(pn(ColumnProps{},
		children: [
			pn(CarouselProps{ index: 1, loop: loop },
				id:       'gallery'
				children: [
					pn(CarouselSlideProps{ accessibility_label: 'One' },
						children: [
							pn(LabelProps{ text: 'one' }),
						]
					),
					pn(CarouselSlideProps{},
						children: [
							pn(LabelProps{ text: 'two' }),
						]
					),
					pn(CarouselSlideProps{ accessibility_label: 'Three' }),
				]
			),
		]
	), rect(0, 0, 300, 300))!
}

fn test_carousel_shows_one_slide_above_its_controls() ! {
	tree := kit_carousel_document(false)!
	gallery := tree.children[0]
	assert gallery.accessibility_role == 'group' && gallery.focus_policy == .focusable
	assert gallery.keys == ['left', 'right', 'home', 'end']
	assert gallery.accessibility_value == 'Slide 2 of 3'
	viewport := gallery.children[0]
	assert viewport.id.ends_with('gallery__viewport')
	assert viewport.children.map(it.hidden) == [true, false, true]
	assert viewport.children[1].children[0].text == 'two'
	// A slide fades in from the right and out to the left.
	slide := viewport.children[1].motion or { MotionConfig{} }
	entering := slide.enter.translate_x or { 0 }
	leaving := slide.exit.translate_x or { 0 }
	assert entering == 24 && leaving == -24
	controls := gallery.children[1]
	assert controls.id.ends_with('gallery__controls') && controls.children.len == 3
	assert controls.children[0].accessibility_label == 'Previous slide'
	assert controls.children[1].accessibility_role == 'img'
	assert controls.children[2].accessibility_label == 'Next slide'
	assert controls.children[0].enabled && controls.children[2].enabled
}

fn test_carousel_moves_from_its_buttons_and_keys() ! {
	tree := kit_carousel_document(false)!
	mut root := tree.compiled_node
	root.mount()!
	next := root.element().children[0].children[1].children[2]
	next.on_event(ElementEvent{ kind: .click, id: next.id })
	last := root.element().children[0]
	assert last.accessibility_value == 'Slide 3 of 3: Three'
	assert last.children[0].children.map(it.hidden) == [true, true, false]
	// Without loop, the last slide has no next one.
	assert !last.children[1].children[2].enabled
	kit_key(last, 'right')
	assert root.element().children[0].accessibility_value == 'Slide 3 of 3: Three'
	kit_key(root.element().children[0], 'home')
	first := root.element().children[0]
	assert first.accessibility_value == 'Slide 1 of 3: One' && !first.children[1].children[0].enabled
	kit_key(first, 'left')
	assert root.element().children[0].accessibility_value == 'Slide 1 of 3: One'
	root.dispose_document()!
}

fn test_looping_carousel_wraps_around() ! {
	tree := kit_carousel_document(true)!
	mut root := tree.compiled_node
	root.mount()!
	kit_key(root.element().children[0], 'right')
	kit_key(root.element().children[0], 'right')
	wrapped := root.element().children[0]
	assert wrapped.accessibility_value == 'Slide 1 of 3: One'
	assert wrapped.children[1].children[0].enabled
	kit_key(wrapped, 'left')
	assert root.element().children[0].accessibility_value == 'Slide 3 of 3: Three'
	root.dispose_document()!
}

fn test_carousel_takes_whole_slides() {
	mut p := CarouselProps{}
	p.apply_event(ElementEvent{ kind: .change, value: 2 })
	assert p.index == 2
	props_document(pn(CarouselProps{},
		id:       'bad'
		children: [
			pn(LabelProps{ text: 'not a slide' }),
		]
	), rect(0, 0, 200, 200)) or {
		assert err.msg().contains('CarouselSlide children')
		return
	}
	assert false
}
