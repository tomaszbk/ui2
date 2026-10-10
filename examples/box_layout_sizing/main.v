module main

import ui2

const box_sizing_width = 410
const box_sizing_height = 220

pub struct BoxLayoutSizingDemo {}

fn main() {
	mut app := BoxLayoutSizingDemo{}
	ui2.run_compiled_vml[BoxLayoutSizingDemo](
		build:  build_box_layout_sizing
		model:  &app
		title:  'Box Layout Sizing'
		width:  box_sizing_width
		height: box_sizing_height
	) or { panic(err) }
}

fn build_box_layout_sizing(mut app BoxLayoutSizingDemo) ui2.Element {
	return $vml('box_layout_sizing.vml')
}

fn box_layout_sizing_tree(mut app BoxLayoutSizingDemo, frame ui2.Rect) ui2.Element {
	return $vml('box_layout_sizing.vml', frame)
}
