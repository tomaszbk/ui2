module main

import ui2

const toggle_width = 340
const toggle_height = 180

pub struct ToggleButtonDemo {
pub mut:
	bold   bool = true
	italic bool
}

fn main() {
	mut app := ToggleButtonDemo{}
	ui2.run_compiled_vml[ToggleButtonDemo](
		build:  build_toggle_button
		model:  &app
		title:  'Toggle Button'
		width:  toggle_width
		height: toggle_height
	) or { panic(err) }
}

fn build_toggle_button(mut app ToggleButtonDemo) ui2.Element {
	return $vml('toggle_button.vml')
}

fn toggle_button_tree(mut app ToggleButtonDemo, frame ui2.Rect) ui2.Element {
	return $vml('toggle_button.vml', frame)
}
