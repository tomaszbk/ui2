// SPDX-License-Identifier: Apache-2.0
// Includes pagination behavior tests adapted from GPUI Kit (Longbridge,
// copyright 2024 - 2026); other component tests are new. See third_party/gpui-kit.
module ui2

import math

@[heap]
struct CatalogLog {
mut:
	events []string
}

// catalog_click delivers a click to el's callback the way the renderer would,
// and fails the test when el has none.
fn catalog_click(el Element) {
	assert voidptr(el.on_event) != unsafe { nil }, 'no callback on ${el.id}'
	el.on_event(ElementEvent{
		kind: .click
		id:   el.id
	})
}

fn catalog_ignore(_ ElementEvent) {}

fn test_component_metrics_and_theme() {
	assert component_metrics(.small).height < component_metrics(.medium).height
	assert component_metrics(.medium).height < component_metrics(.large).height
	light := component_theme(false)
	dark := component_theme(true)
	assert light.background != dark.background
	bg, fg := dark.colors(.primary)
	assert bg == dark.primary
	assert fg == dark.primary_foreground
}

fn test_component_inset_clamps_in_the_original_coordinate_space() {
	normal := component_inset(rect(10, 20, 100, 40), 8) or { panic(err) }
	assert normal == rect(18, 28, 84, 24)
	small := component_inset(rect(10, 20, 4, 2), 8) or { panic(err) }
	assert small == rect(12, 21, 0, 0)
	zero := component_inset(rect(10, 20, 0, 0), 8) or { panic(err) }
	assert zero == rect(10, 20, 0, 0)
	if _ := component_inset(rect(0, 0, 10, 10), -1) {
		assert false, 'negative padding accepted'
	}
}

fn test_component_frames_reject_negative_and_non_finite_geometry() {
	for frame in [rect(0, 0, -1, 10), rect(0, math.inf(1), 10, 10), rect(0, 0, math.nan(), 10),
		rect(1e308, 0, 1e308, 1)] {
		if _ := badge(BadgeConfig{ frame: frame }) {
			assert false, 'invalid frame accepted'
		}
	}
	if _ := component_inset(rect(0, 0, 10, 10), math.nan()) {
		assert false, 'NaN padding accepted'
	}
}

fn test_badge_counter_zero_and_dot() {
	assert badge_text(101, 99) == '99+'
	assert badge_text(3, 0) == '3'
	assert badge_text(-1, 99) == ''
	counter := badge(id: 'badge', frame: rect(0, 0, 80, 24), count: 101) or { panic(err) }
	assert counter.children[0].text == '99+'
	assert counter.accessibility_label == '101'
	hidden_badge := badge(count: 0) or { panic(err) }
	assert hidden_badge.hidden
	visible_badge := badge(count: 0, show_zero: true) or { panic(err) }
	assert !visible_badge.hidden
	dot := badge(count: 0, dot: true) or { panic(err) }
	assert !dot.hidden
	assert dot.children.len == 0
}

fn test_avatar_initials_and_image_selection() {
	assert avatar_initials('  Ada  Lovelace ') == 'AL'
	assert avatar_initials('Ada') == 'A'
	assert avatar_initials('张 三') == '张三'
	assert avatar_initials(' \t\n ') == '?'
	assert avatar_initials('e\u0301mile zola') == 'E\u0301Z'
	fallback := avatar(name: 'Ada Lovelace', frame: rect(0, 0, 40, 40)) or { panic(err) }
	assert fallback.children[0].kind == .label
	assert fallback.children[0].text == 'AL'
	picture := avatar(name: 'Ada', image_path: 'ada.png') or { panic(err) }
	assert picture.children[0].kind == .image
	assert picture.children[0].image_path == 'ada.png'
}

fn test_tag_close_callback_and_disabled_state() {
	mut log := &CatalogLog{}
	el := tag(
		id:       'filter'
		text:     'Open'
		frame:    rect(0, 0, 120, 32)
		on_close: fn [mut log] (event ElementEvent) {
			log.events << 'close:${event.id}'
		}
		enabled:  false
	) or { panic(err) }
	assert el.children.len == 2
	assert el.children[1].id == 'filter:component:close'
	assert !el.children[1].enabled
	catalog_click(el.children[1])
	assert log.events == ['close:filter:component:close']
	// Only clicks reach on_close; hover and focus changes do not.
	el.children[1].on_event(ElementEvent{ kind: .pointer_enter, id: el.children[1].id })
	assert log.events.len == 1
	fixed_tag := tag(text: 'Fixed') or { panic(err) }
	assert fixed_tag.children.len == 1
	if _ := tag(on_close: catalog_ignore) {
		assert false, 'dismissible tag accepted without identity'
	}
}

fn test_separator_and_circular_skeleton_geometry() {
	horizontal := separator(frame: rect(8, 9, 100, 10), thickness: 2) or { panic(err) }
	assert horizontal.children[0].frame == rect(0, 4, 100, 2)
	vertical := separator(frame: rect(0, 0, 4, 50), orientation: .vertical, thickness: 20) or { panic(err) }
	assert vertical.children[0].frame == rect(0, 0, 4, 50)
	circle := skeleton(frame: rect(10, 20, 100, 40), circle: true) or { panic(err) }
	assert circle.children[0].frame == rect(30, 0, 40, 40)
	assert circle.children[0].box.radius == 20
	small_skeleton := skeleton(frame: rect(0, 0, 2, 2), radius: 30) or { panic(err) }
	assert small_skeleton.box.radius == 1
	if _ := skeleton(radius: -1) {
		assert false, 'negative radius accepted'
	}
	if _ := separator(thickness: math.inf(1)) {
		assert false, 'infinite thickness accepted'
	}
}

fn test_keyboard_hint_and_application_owned_link() {
	hint := kbd(keys: ['Ctrl', 'K']) or { panic(err) }
	assert hint.children[0].text == 'Ctrl + K'
	assert hint.children[0].kind == .label
	mut log := &CatalogLog{}
	el := link(
		id:       'help-link'
		text:     'Help'
		on_event: fn [mut log] (event ElementEvent) {
			log.events << event.id
		}
		enabled:  false
	) or { panic(err) }
	assert el.kind == .button
	assert el.accessibility_role == 'link'
	assert !el.enabled
	catalog_click(el)
	assert log.events == ['help-link']
	if _ := link(id: ' ') {
		assert false, 'link accepted without identity'
	}
}

fn test_alert_and_empty_state_actions() {
	mut log := &CatalogLog{}
	message := inline_alert(
		id:          'message'
		title:       'Saved'
		description: 'All changes saved.'
		frame:       rect(0, 0, 200, 80)
		on_dismiss:  fn [mut log] (_ ElementEvent) {
			log.events << 'dismiss'
		}
		enabled:     false
	) or { panic(err) }
	assert message.accessibility_role == 'alert'
	assert !message.children[2].enabled
	catalog_click(message.children[2])
	permanent := inline_alert(title: 'Saved', description: 'All changes saved.') or { panic(err) }
	assert permanent.children.len == 2
	assert permanent.children.all(it.kind == .label)
	if _ := inline_alert(on_dismiss: catalog_ignore) {
		assert false, 'dismissible alert accepted without identity'
	}
	empty := empty_state(
		id:          'empty'
		title:       'No results'
		action_text: 'Reset'
		on_action:   fn [mut log] (_ ElementEvent) {
			log.events << 'reset'
		}
	) or { panic(err) }
	catalog_click(empty.children[2])
	assert log.events == ['dismiss', 'reset']
	no_action := empty_state(title: 'No results') or { panic(err) }
	assert no_action.children.len == 2
}

fn test_group_box_local_content_and_duplicate_identity() {
	child := label('name', 'Name', rect(0, 0, 80, 20), TextStyle{})
	el := group_box(id: 'group', title: 'Profile', frame: rect(10, 20, 200, 120), children: [child]) or { panic(err) }
	assert el.children[1].frame == rect(8, 40, 184, 72)
	assert el.children[1].children[0].frame == child.frame
	if _ := group_box(id: 'name', children: [child]) {
		assert false, 'duplicate root/child identity accepted'
	}
}

fn test_description_list_empty_and_column_validation() {
	empty_list := description_list(DescriptionListConfig{}) or { panic(err) }
	assert empty_list.children.len == 0
	el := description_list(
		frame:          rect(0, 0, 106, 40)
		label_fraction: 0.4
		items:          [DescriptionItem{'Name', 'Ada'}, DescriptionItem{'Status', 'Active'}]
	) or { panic(err) }
	assert el.children[0].frame == rect(0, 0, 40, 20)
	assert el.children[1].frame == rect(46, 0, 60, 20)
	for fraction in [-0.1, 1.1, math.nan()] {
		if _ := description_list(label_fraction: fraction) {
			assert false, 'invalid label fraction accepted'
		}
	}
}

@[heap]
struct CatalogToggles {
mut:
	values []bool
}

fn test_collapsible_is_controlled_and_unmounts_closed_content() {
	child := label('body', 'Content', rect(0, 0, 100, 20), TextStyle{})
	mut toggles := &CatalogToggles{}
	closed := collapsible(
		id:        'details'
		title:     'Details'
		children:  [child]
		on_toggle: fn [mut toggles] (open bool) {
			toggles.values << open
		}
	) or { panic(err) }
	assert closed.children.len == 1
	assert closed.children[0].accessibility_value == 'collapsed'
	catalog_click(closed.children[0])
	opened := collapsible(
		id:        'details'
		open:      true
		frame:     rect(0, 0, 200, 100)
		enabled:   false
		children:  [child]
		on_toggle: fn [mut toggles] (open bool) {
			toggles.values << open
		}
	) or { panic(err) }
	assert opened.children.len == 2
	assert opened.children[1].frame == rect(0, 32, 200, 68)
	assert !opened.children[0].enabled
	catalog_click(opened.children[0])
	// The header asks for the opposite of the open value it was built with.
	assert toggles.values == [true, false]
	uncontrolled := collapsible(id: 'details', title: 'Details') or { panic(err) }
	assert voidptr(uncontrolled.children[0].on_event) == unsafe { nil }
}

fn test_breadcrumb_identity_current_location_and_disabled_items() {
	mut log := &CatalogLog{}
	items := [
		BreadcrumbItem{
			id:       'home'
			label:    'Home'
			on_event: fn [mut log] (event ElementEvent) {
				log.events << 'item:${event.id}'
			}
		},
		BreadcrumbItem{
			id:      'projects'
			label:   'Projects'
			enabled: false
		},
		BreadcrumbItem{
			id:    'current'
			label: 'Current'
		},
	]
	el := breadcrumb(
		id:          'nav'
		frame:       rect(0, 0, 300, 32)
		items:       items
		on_navigate: fn [mut log] (id string) {
			log.events << 'navigate:${id}'
		}
	) or { panic(err) }
	assert el.children.len == 5
	catalog_click(el.children[0])
	assert log.events == ['item:${el.children[0].id}', 'navigate:home']
	// Disabled items and the current location take no clicks.
	assert !el.children[2].enabled
	assert voidptr(el.children[2].on_event) == unsafe { nil }
	assert voidptr(el.children[4].on_event) == unsafe { nil }
	assert el.children[4].kind == .label
	assert el.children[4].accessibility_value == 'current'
	// Items are packed from the left and sized to their labels, so each separator
	// sits right after the item before it.
	assert el.children[0].frame.x == 0
	assert el.children[1].frame.x == el.children[0].frame.width
	assert el.children[2].frame.width > el.children[0].frame.width
	last := el.children[4].frame
	assert last.x + last.width < 300
	reordered := breadcrumb(id: 'nav', items: [items[1], items[0], items[2]]) or { panic(err) }
	assert reordered.children[2].id == el.children[0].id
	if _ := breadcrumb(id: 'nav', items: [items[0], items[0]]) {
		assert false, 'duplicate breadcrumb identity accepted'
	}
}

fn test_pagination_normalization_and_navigation_guards() {
	first := pagination_state(0, 0)
	assert first.current_page() == 1
	assert first.total_pages() == 1
	assert (first.previous_page() or { -1 }) == -1
	assert (first.next_page() or { -1 }) == -1
	last := pagination_state(20, 10)
	assert last.current_page() == 10
	assert (last.previous_page() or { -1 }) == 9
	assert (last.next_page() or { -1 }) == -1
	disabled := last.with_disabled(true)
	assert (disabled.previous_page() or { -1 }) == -1
	assert (disabled.request_page(1) or { -1 }) == -1
	assert (last.request_page(10) or { -1 }) == -1
	assert (last.request_page(11) or { -1 }) == -1
	assert PaginationState{}.current_page() == 1
}

fn test_pagination_upstream_page_window() {
	items := pagination_state(5, 10).with_visible_pages(7).items()
	assert items == [PaginationItem{ page: 1 }, PaginationItem{ kind: .ellipsis, start: 2, end: 3 },
		PaginationItem{ page: 3 }, PaginationItem{ page: 4 }, PaginationItem{ page: 5 },
		PaginationItem{ page: 6 }, PaginationItem{ page: 7 },
		PaginationItem{ kind: .ellipsis, start: 8, end: 10 }, PaginationItem{ page: 10 }]
}

fn test_pagination_windows_cover_every_page_without_hiding_current() {
	for total in 2 .. 80 {
		for current in 1 .. total + 1 {
			for visible in 0 .. 16 {
				state := pagination_state(current, total).with_visible_pages(visible)
				items := state.items()
				assert items.len <= state.visible + 2
				mut next := 1
				mut found := false
				for item in items {
					if item.kind == .page {
						assert item.page == next
						found = found || item.page == current
						next++
					} else {
						assert item.start == next
						assert item.end > item.start
						next = item.end
					}
				}
				assert next == total + 1
				assert found
			}
		}
	}
}

@[heap]
struct CatalogPages {
mut:
	pages []int
}

fn test_pagination_large_datasets_and_page_callbacks() {
	state := pagination_state(1, 2147483647).with_visible_pages(2147483647)
	assert state.items().len <= pagination_max_visible_pages + 2
	mut log := &CatalogPages{}
	on_page := fn [mut log] (page int) {
		log.pages << page
	}
	click := ElementEvent{
		kind: .click
	}
	last_page := pagination_page_callback(state, 2147483647, on_page)
	last_page(click)
	assert log.pages == [2147483647]
	// Pages outside the range, the current page and a disabled control ask for
	// nothing, and only clicks count.
	for page in [0, 1, -2, -2147483647] {
		outside := pagination_page_callback(state, page, on_page)
		outside(click)
	}
	disabled := pagination_page_callback(state.with_disabled(true), 2, on_page)
	disabled(click)
	second := pagination_page_callback(state, 2, on_page)
	second(ElementEvent{ kind: .pointer_enter })
	assert log.pages == [2147483647]
	assert voidptr(pagination_page_callback(state, 2, unsafe { nil })) == unsafe { nil }
	last := pagination_state(2147483647, 2147483647)
	assert (last.next_page() or { -1 }) == -1
}

fn test_pagination_rendering_and_compact_mode() {
	mut log := &CatalogPages{}
	el := pagination(
		id:      'pages'
		frame:   rect(0, 0, 400, 40)
		state:   pagination_state(1, 10)
		on_page: fn [mut log] (page int) {
			log.pages << page
		}
	) or { panic(err) }
	validate_element_tree(el) or { panic(err) }
	assert !el.children[0].enabled
	assert el.children[el.children.len - 1].enabled
	catalog_click(el.children[el.children.len - 1])
	assert log.pages == [2]
	// The current page stays enabled so the renderer does not dim its title;
	// its callback is what turns a click on it into nothing.
	current := el.children[1]
	assert current.text == '1'
	assert current.enabled
	assert current.accessibility_value == 'current'
	assert current.box.bg == ComponentTheme{}.primary
	catalog_click(current)
	assert log.pages == [2]
	disabled := pagination(id: 'pages', state: pagination_state(1, 10).with_disabled(true)) or {
		panic(err)
	}
	assert !disabled.children[1].enabled
	assert disabled.children[1].box.bg != ComponentTheme{}.primary
	compact := pagination(
		id:      'pages'
		compact: true
		state:   pagination_state(3, 10).with_disabled(true)
	) or { panic(err) }
	assert compact.children.len == 2
	assert !compact.children[0].enabled
	assert !compact.children[1].enabled
}

fn catalog_assert_local_geometry(el Element) {
	component_validate_frame(el.frame) or { panic(err) }
	for child in el.children {
		assert child.frame.x >= -1e-9 && child.frame.y >= -1e-9
		assert child.frame.x + child.frame.width <= el.frame.width + 1e-9
		assert child.frame.y + child.frame.height <= el.frame.height + 1e-9
		catalog_assert_local_geometry(child)
	}
}

fn test_catalog_generated_geometry_handles_tiny_frames() {
	for extent in [0.0, 0.5, 1.0, 8.0, 32.0, 200.0] {
		frame := rect(10, 20, extent, extent / 2)
		elements := [badge(frame: frame) or { panic(err) }, avatar(frame: frame) or { panic(err) },
			tag(id: 'tag', frame: frame, on_close: catalog_ignore) or { panic(err) },
			separator(frame: frame) or { panic(err) },
			skeleton(frame: frame, circle: true) or { panic(err) },
			kbd(frame: frame, keys: ['Ctrl', 'K']) or { panic(err) },
			link(id: 'link', frame: frame) or { panic(err) }, inline_alert(
				id:          'alert'
				frame:       frame
				title:       'Title'
				description: 'Message'
				on_dismiss:  catalog_ignore
			) or { panic(err) },
			empty_state(id: 'empty', frame: frame, on_action: catalog_ignore) or { panic(err) },
			group_box(frame: frame, title: 'Group') or { panic(err) },
			description_list(frame: frame, items: [DescriptionItem{'A', 'B'}]) or { panic(err) },
			collapsible(id: 'collapse', frame: frame, open: true) or { panic(err) }, breadcrumb(
				id:    'nav'
				frame: frame
				items: [BreadcrumbItem{ id: 'a' }, BreadcrumbItem{ id: 'b' }]
			) or { panic(err) },
			pagination(id: 'pages', frame: frame, state: pagination_state(5, 20)) or { panic(err) }]
		for el in elements {
			catalog_assert_local_geometry(el)
		}
	}
}
