module main

import ui2

const float_width = 400
const float_height = 260

pub struct FloatLayoutDemo {}

fn main() {
	mut app := FloatLayoutDemo{}
	ui2.run_compiled_vml[FloatLayoutDemo](
		build:  build_float_layout
		model:  &app
		title:  'Float Layout'
		width:  float_width
		height: float_height
	) or { panic(err) }
}

fn build_float_layout(mut app FloatLayoutDemo) ui2.Element {
	return $vml('float_layout.vml')
}

fn float_layout_tree(mut app FloatLayoutDemo, frame ui2.Rect) ui2.Element {
	return $vml('float_layout.vml', frame)
}
