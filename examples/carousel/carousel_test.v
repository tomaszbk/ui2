module main

import ui2

fn carousel_gallery(mut app CarouselDemo) ui2.Element {
	return carousel_tree(mut app, ui2.rect(0, 0, carousel_width, carousel_height)).children[0].children[1]
}

fn test_carousel_demo_loops_through_slides() {
	mut app := CarouselDemo{}
	gallery := carousel_gallery(mut app)
	assert gallery.accessibility_value == 'Slide 1 of 3: Ocean'
	slides := gallery.children[0]
	assert slides.children.map(it.hidden) == [false, true, true]
	// The previous button loops around to the last slide.
	controls := gallery.children[1]
	previous := controls.children[0]
	assert previous.enabled
	previous.on_event(ui2.ElementEvent{ kind: .click, id: previous.id })
	assert app.index == 2

	last := carousel_gallery(mut app)
	assert last.children[0].children.map(it.hidden) == [true, true, false]
	assert last.children[0].children[2].children[0].text == 'Sunset'
	next := last.children[1].children[2]
	next.on_event(ui2.ElementEvent{ kind: .click, id: next.id })
	assert app.index == 0
}

fn test_carousel_demo_follows_the_arrow_keys() {
	mut app := CarouselDemo{}
	gallery := carousel_gallery(mut app)
	assert gallery.focus_policy == .focusable
	gallery.on_event(ui2.ElementEvent{ kind: .key_down, id: gallery.id, key: 'right' })
	assert app.index == 1
	moved := carousel_gallery(mut app)
	moved.on_event(ui2.ElementEvent{ kind: .key_down, id: moved.id, key: 'end' })
	assert app.index == 2
	status := carousel_tree(mut app, ui2.rect(0, 0, carousel_width, carousel_height)).children[0].children[2]
	assert status.text == '3 / 3'
}
