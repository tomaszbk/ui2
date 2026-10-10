module main

import ui2

const box_layout_width = 520
const box_layout_height = 360

pub struct BoxLayoutDemo {}

fn main() {
	mut app := BoxLayoutDemo{}
	ui2.run_compiled_vml[BoxLayoutDemo](
		build:  build_box_layout
		model:  &app
		title:  'Box Layout'
		width:  box_layout_width
		height: box_layout_height
	) or { panic(err) }
}

fn build_box_layout(mut app BoxLayoutDemo) ui2.Element {
	return $vml('box_layout.vml')
}

fn box_layout_tree(mut app BoxLayoutDemo, frame ui2.Rect) ui2.Element {
	return $vml('box_layout.vml', frame)
}
