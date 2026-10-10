module main

import ui2

const rectangles_width = 360
const rectangles_height = 180

pub struct RectanglesDemo {}

fn main() {
	mut app := RectanglesDemo{}
	ui2.run_compiled_vml[RectanglesDemo](
		build:  build_rectangles
		model:  &app
		title:  'Rectangles'
		width:  rectangles_width
		height: rectangles_height
	) or { panic(err) }
}

fn build_rectangles(mut app RectanglesDemo) ui2.Element {
	return $vml('rectangles.vml')
}

fn rectangles_tree(mut app RectanglesDemo, frame ui2.Rect) ui2.Element {
	return $vml('rectangles.vml', frame)
}
