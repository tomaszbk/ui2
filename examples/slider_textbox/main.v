module main

import ui2

const slider_textbox_width = 620
const slider_textbox_height = 560

@[heap]
pub struct SliderTextboxDemo {
pub mut:
	horizontal_value int
	horizontal_text  string
	horizontal_valid bool = true
	vertical_value   int
	vertical_text    string
	vertical_valid   bool   = true
	status           string = 'Drag either slider or type a value.'
}

const slider_textbox_state = &SliderTextboxDemo{}

fn parse_slider_integer(value string) ?int {
	trimmed := value.trim_space()
	if trimmed.len == 0 {
		return none
	}
	start := if trimmed[0] == `-` { 1 } else { 0 }
	if start == trimmed.len {
		return none
	}
	for character in trimmed[start..] {
		if !character.is_digit() {
			return none
		}
	}
	return trimmed.int()
}

fn slider_textbox_demo() SliderTextboxDemo {
	mut app := SliderTextboxDemo{}
	app.set_horizontal(40)
	app.set_vertical(-60)
	app.status = 'Drag either slider or type a value.'
	return app
}

fn (mut app SliderTextboxDemo) set_horizontal(value int) {
	clamped := if value < -20 {
		-20
	} else if value > 100 {
		100
	} else {
		value
	}
	app.horizontal_value = clamped
	app.horizontal_text = clamped.str()
	app.horizontal_valid = true
	app.status = 'Horizontal value: ${clamped}'
}

fn (mut app SliderTextboxDemo) set_vertical(value int) {
	clamped := if value < -100 {
		-100
	} else if value > -20 {
		-20
	} else {
		value
	}
	app.vertical_value = clamped
	app.vertical_text = clamped.str()
	app.vertical_valid = true
	app.status = 'Vertical value: ${clamped}'
}

fn (mut app SliderTextboxDemo) apply_horizontal_text(value string) {
	app.horizontal_text = value
	parsed := parse_slider_integer(value) or {
		app.horizontal_valid = false
		app.status = 'Horizontal value must be between −20 and 100.'
		return
	}
	if parsed < -20 || parsed > 100 {
		app.horizontal_valid = false
		app.status = 'Horizontal value must be between −20 and 100.'
		return
	}
	app.set_horizontal(parsed)
}

fn (mut app SliderTextboxDemo) apply_vertical_text(value string) {
	app.vertical_text = value
	parsed := parse_slider_integer(value) or {
		app.vertical_valid = false
		app.status = 'Vertical value must be between −100 and −20.'
		return
	}
	if parsed < -100 || parsed > -20 {
		app.vertical_valid = false
		app.status = 'Vertical value must be between −100 and −20.'
		return
	}
	app.set_vertical(parsed)
}

fn (mut app SliderTextboxDemo) reset() {
	app.set_horizontal(40)
	app.set_vertical(-60)
	app.status = 'Both controls reset to their midpoint.'
}

fn slider_textbox_callbacks() map[string]ui2.ElementCallback {
	return {
		'reset':             fn (_event ui2.ElementEvent) {
			mut state := unsafe { slider_textbox_state }
			state.reset()
			ui2.refresh()
		}
		'horizontal_input':  fn (event ui2.ElementEvent) {
			mut state := unsafe { slider_textbox_state }
			state.apply_horizontal_text(event.text)
			ui2.refresh()
		}
		'vertical_input':    fn (event ui2.ElementEvent) {
			mut state := unsafe { slider_textbox_state }
			state.apply_vertical_text(event.text)
			ui2.refresh()
		}
		'horizontal_slider': fn (event ui2.ElementEvent) {
			mut state := unsafe { slider_textbox_state }
			state.set_horizontal(int(event.value))
			ui2.refresh()
		}
		'vertical_slider':   fn (event ui2.ElementEvent) {
			mut state := unsafe { slider_textbox_state }
			state.set_vertical(int(event.value))
			ui2.refresh()
		}
	}
}

fn main() {
	mut state := unsafe { slider_textbox_state }
	unsafe {
		*state = slider_textbox_demo()
	}
	ui2.run_compiled_vml[SliderTextboxDemo](
		build:  build_slider_textbox
		model:  slider_textbox_state
		title:  'Slider & Textbox'
		width:  slider_textbox_width
		height: slider_textbox_height
	) or { panic(err) }
}

fn build_slider_textbox(mut app SliderTextboxDemo) ui2.Element {
	callbacks := slider_textbox_callbacks()
	callback_reset := callbacks['reset'] or { panic('missing reset callback') }
	callback_horizontal_input := callbacks['horizontal_input'] or { panic('missing horizontal_input callback') }
	callback_horizontal_slider := callbacks['horizontal_slider'] or { panic('missing horizontal_slider callback') }
	callback_vertical_input := callbacks['vertical_input'] or { panic('missing vertical_input callback') }
	callback_vertical_slider := callbacks['vertical_slider'] or { panic('missing vertical_slider callback') }
	return $vml('slider_textbox.vml')
}

fn slider_textbox_tree(mut app SliderTextboxDemo, frame ui2.Rect) ui2.Element {
	callbacks := slider_textbox_callbacks()
	callback_reset := callbacks['reset'] or { panic('missing reset callback') }
	callback_horizontal_input := callbacks['horizontal_input'] or { panic('missing horizontal_input callback') }
	callback_horizontal_slider := callbacks['horizontal_slider'] or { panic('missing horizontal_slider callback') }
	callback_vertical_input := callbacks['vertical_input'] or { panic('missing vertical_input callback') }
	callback_vertical_slider := callbacks['vertical_slider'] or { panic('missing vertical_slider callback') }
	return $vml('slider_textbox.vml', frame)
}
