module main

import ui2

fn find_resizable_rectangles_element(element ui2.Element, id string) ?ui2.Element {
	if element.id == id {
		return element
	}
	for child in element.children {
		if found := find_resizable_rectangles_element(child, id) {
			return found
		}
	}
	return none
}

fn test_resizable_rectangles_has_original_color_order() {
	mut app := initial_resizable_rectangles()
	assert app.colors.len == 4
	assert app.colors.map(it.name) == ['Red', 'Green', 'Blue', 'Pink']
}

fn test_resizable_rectangles_share_extra_width() {
	mut app := initial_resizable_rectangles()
	initial_root := rectangles_resizable_tree(mut app, ui2.rect(0, 0, resizable_rectangles_width, resizable_rectangles_height))
	wide_root := rectangles_resizable_tree(mut app, ui2.rect(0, 0, 760, resizable_rectangles_height))
	initial_card := find_resizable_rectangles_element(initial_root, 'card') or {
		panic('missing initial card')
	}
	wide_card := find_resizable_rectangles_element(wide_root, 'card') or {
		panic('missing wide card')
	}
	assert initial_card.children[0].children.len == 6
	assert wide_card.children[0].children.len == 6
	assert wide_card.children[0].children[2].frame.width > initial_card.children[0].children[2].frame.width
	assert wide_card.children[0].children[2].box.radius == 10
	assert wide_card.children[0].children[2].children[0].children[0].frame.y > 0
	assert wide_card.children[0].children[2].children[0].children[0].frame.height == 20
	assert wide_card.children[0].children[5].key == '4'
}
