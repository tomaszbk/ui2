module main

import ui2

fn test_carousel_demo_loops_through_slides() {
	mut app := ui2.new_vml_app(carousel_vml_source, CarouselDemo{}) or { panic(err) }
	initial := app.build(ui2.rect(0, 0, carousel_width, carousel_height)) or { panic(err) }
	gallery := initial.children[0].children[2]
	assert !gallery.children[0].hidden
	assert gallery.children[1].hidden
	control := initial.children[0].children[4]
	control.on_event(ui2.ElementEvent{ kind: .tap, id: control.id })
	assert app.state().index == 1

	rebuilt := app.build(ui2.rect(0, 0, carousel_width, carousel_height)) or { panic(err) }
	assert rebuilt.children[0].children[2].children[0].hidden
	assert !rebuilt.children[0].children[2].children[1].hidden
	assert rebuilt.children[0].children[2].children[1].children[0].children[0].text == 'Forest'
}
