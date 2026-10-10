module main

import ui2

const relative_width = 400
const relative_height = 250

pub struct RelativeLayoutDemo {}

fn main() {
	mut app := RelativeLayoutDemo{}
	ui2.run_compiled_vml[RelativeLayoutDemo](
		build:  build_relative_layout
		model:  &app
		title:  'Relative Layout'
		width:  relative_width
		height: relative_height
	) or { panic(err) }
}

fn build_relative_layout(mut app RelativeLayoutDemo) ui2.Element {
	return $vml('relative_layout.vml')
}

fn relative_layout_tree(mut app RelativeLayoutDemo, frame ui2.Rect) ui2.Element {
	return $vml('relative_layout.vml', frame)
}
