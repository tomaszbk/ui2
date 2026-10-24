module main

// vml: switch.vml

import ui2

const switch_width = 320
const switch_height = 160

pub struct SwitchDemo {
pub mut:
	enabled bool = true
}

fn main() {
	mut app := SwitchDemo{}
	ui2.run_compiled_vml[SwitchDemo](
		build:  build_switch
		model:  &app
		title:  'Switch'
		width:  switch_width
		height: switch_height
	) or { panic(err) }
}

fn build_switch(mut app SwitchDemo) ui2.Element {
	return switch_vml(mut app)
}

fn switch_tree(mut app SwitchDemo, frame ui2.Rect) ui2.Element {
	return switch_vml_framed(mut app, frame)
}
