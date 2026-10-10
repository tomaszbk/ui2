module main

import ui2

fn find_rectangle_element(element ui2.Element, id string) ?ui2.Element {
	if element.id == id {
		return element
	}
	for child in element.children {
		if found := find_rectangle_element(child, id) {
			return found
		}
	}
	return none
}

fn test_rectangles_vml_preserves_the_original_palette() {
	mut compiled_model_0 := RectanglesDemo{}
	root := rectangles_tree(mut compiled_model_0, ui2.rect(0, 0, rectangles_width, rectangles_height))
	ui2.validate_element_tree(root) or { panic(err) }

	red := find_rectangle_element(root, 'red') or { panic('missing red rectangle') }
	assert red.box.bg == 0xff6464
	assert red.frame.width == 64
	assert red.frame.height == 64
	assert (find_rectangle_element(root, 'green') or { panic('missing green rectangle') }).box.bg == 0x64ff64
	assert (find_rectangle_element(root, 'blue') or { panic('missing blue rectangle') }).box.bg == 0x6464ff
	assert (find_rectangle_element(root, 'magenta') or { panic('missing magenta rectangle') }).box.bg == 0xff64ff
}
