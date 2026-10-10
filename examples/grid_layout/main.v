module main

import ui2

const grid_width = 360
const grid_height = 260

pub struct GridLayoutDemo {}

fn main() {
	mut app := GridLayoutDemo{}
	ui2.run_compiled_vml[GridLayoutDemo](
		build:  build_grid_layout
		model:  &app
		title:  'Grid Layout'
		width:  grid_width
		height: grid_height
	) or { panic(err) }
}

fn build_grid_layout(mut app GridLayoutDemo) ui2.Element {
	return $vml('grid_layout.vml')
}

fn grid_layout_tree(mut app GridLayoutDemo, frame ui2.Rect) ui2.Element {
	return $vml('grid_layout.vml', frame)
}
