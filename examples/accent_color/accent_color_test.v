module main

import ui2

fn find_accent_element(element ui2.Element, id string) ?ui2.Element {
	if element.id == id {
		return element
	}
	for child in element.children {
		if found := find_accent_element(child, id) {
			return found
		}
	}
	return none
}

fn test_accent_derives_a_shade_a_tint_and_a_readable_font_color() {
	mut app := accent_color_demo()
	assert app.accent == '#642896'
	assert app.shade == '#210D32'
	assert app.tint == '#A642FA'
	// A dark accent takes a white caption.
	assert app.on_dark
	assert app.font_color == '#FFFFFF'
	app.set_channel('red', 240)
	app.set_channel('green', 240)
	app.set_channel('blue', 240)
	assert app.accent == '#F0F0F0'
	assert !app.on_dark
	assert app.font_color == '#111111'
	// The tint saturates instead of wrapping around.
	assert app.tint == '#FFFFFF'
}

fn test_accent_channels_clamp_and_track_their_fraction() {
	mut app := accent_color_demo()
	app.set_fraction('red', 0.5)
	assert app.red == 128
	assert app.red_ratio == 128.0 / 255.0
	app.set_fraction('green', -3)
	assert app.green == 0
	app.set_fraction('blue', 9)
	assert app.blue == 255
	app.set_channel('red', 400)
	assert app.red == 255
	app.reset()
	assert app.red == 100 && app.green == 40 && app.blue == 150
	assert app.status == 'Accent reset to #642896.'
}

fn test_accent_pointer_lands_on_the_channel_it_was_dragged_over() {
	mut app := accent_color_demo()
	track_width := accent_track_width(ui2.rect(0, 0, accent_color_width, accent_color_height))
	assert track_width == accent_color_width - 232
	app.track_channel('green', ui2.ElementEvent{ kind: .pointer_drag, id: 'track_green', x: track_root_x + track_width / 2, y: 120 }, track_width)
	assert app.green == 128
	assert app.red == 100
	// A press to the left of the track floors the channel instead of going negative.
	app.track_channel('blue', ui2.ElementEvent{ kind: .pointer_down, id: 'track_blue', x: 0, y: 160 }, track_width)
	assert app.blue == 0
}

fn test_accent_vml_paints_every_swatch_and_the_demo_stack() {
	app := accent_color_demo()
	frame := ui2.rect(0, 0, accent_color_width, accent_color_height)
	root := ui2.element_from_vml_model_with_callbacks(accent_color_vml_source, app, frame, accent_color_callbacks()) or { panic(err) }
	ui2.validate_element_tree(root) or { panic(err) }
	track := find_accent_element(root, 'track_red') or { panic('missing red track') }
	assert track.draggable && track.id == 'track_red' && voidptr(track.on_event) != unsafe { nil }
	assert track.frame.x == track_root_x - 16
	assert track.frame.width == accent_track_width(frame)
	assert (find_accent_element(root, 'accent_preview') or { panic('missing preview') }).box.bg == 0x642896
	assert (find_accent_element(root, 'demo_stack') or { panic('missing stack') }).box.bg == 0xA642FA
	assert (find_accent_element(root, 'accent_action') or { panic('missing button') }).box.bg == 0x642896
	assert (find_accent_element(root, 'subscribe') or { panic('missing checkbox') }).checked
}
