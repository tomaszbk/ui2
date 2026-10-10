module main

import ui2

fn test_carousel_demo_loops_through_slides() {
	mut app := CarouselDemo{}
	initial := carousel_tree(mut app, ui2.rect(0, 0, carousel_width, carousel_height))
	gallery := initial.children[0].children[2]
	assert !gallery.children[0].hidden
	assert gallery.children[1].hidden
	control := initial.children[0].children[4]
	control.on_event(ui2.ElementEvent{ kind: .tap, id: control.id })
	assert app.index == 1

	rebuilt := carousel_tree(mut app, ui2.rect(0, 0, carousel_width, carousel_height))
	assert rebuilt.children[0].children[2].children[0].hidden
	assert !rebuilt.children[0].children[2].children[1].hidden
	assert rebuilt.children[0].children[2].children[1].children[0].children[0].text == 'Forest'
}
