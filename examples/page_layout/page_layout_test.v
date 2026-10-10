module main

import ui2

fn find_page_element(element ui2.Element, id string) ?ui2.Element {
	if element.id == id {
		return element
	}
	for child in element.children {
		if found := find_page_element(child, id) {
			return found
		}
	}
	return none
}

fn test_page_layout_demo_navigates_through_model_actions() {
	mut app := PageLayoutDemo{}
	initial := page_layout_tree(mut app, ui2.rect(0, 0, page_width, page_height))
	pager := find_page_element(initial, 'pager') or { panic('missing pager') }
	assert pager.children[0].frame == ui2.rect(0, 0, 380, 160)

	next := find_page_element(initial, 'next') or { panic('missing next action') }
	control := next
	control.on_event(ui2.ElementEvent{ kind: .tap, id: control.id })
	assert app.page == 1
	rebuilt := page_layout_tree(mut app, ui2.rect(0, 0, page_width, page_height))
	pager_after := find_page_element(rebuilt, 'pager') or { panic('missing rebuilt pager') }
	assert pager_after.children[0].frame == ui2.rect(0, 0, 380, 160)
}
