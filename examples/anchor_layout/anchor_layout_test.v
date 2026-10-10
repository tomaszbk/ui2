module main

import ui2

fn find_anchor_element(element ui2.Element, id string) ?ui2.Element {
	if element.id == id {
		return element
	}
	for child in element.children {
		if found := find_anchor_element(child, id) {
			return found
		}
	}
	return none
}

fn test_anchor_layout_demo_places_each_control() {
	mut compiled_model_0 := AnchorLayoutDemo{}
	root := anchor_layout_tree(mut compiled_model_0, ui2.rect(0, 0, anchor_width, anchor_height))
	top_left := find_anchor_element(root, 'top_left') or { panic('missing top-left layout') }
	centered := find_anchor_element(root, 'centered') or { panic('missing centered layout') }
	bottom_right := find_anchor_element(root, 'bottom_right') or {
		panic('missing bottom-right layout')
	}
	assert top_left.children[0].frame == ui2.rect(10, 10, 88, 34)
	assert centered.children[0].frame == ui2.rect(36, 33, 88, 34)
	assert bottom_right.children[0].frame == ui2.rect(218, 56, 112, 34)
}
