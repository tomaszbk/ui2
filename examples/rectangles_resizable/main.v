module main

import ui2

const resizable_rectangles_width = 560
const resizable_rectangles_height = 220

pub struct ResizableColorBox {
pub:
	id         int
	name       string
	color      u32
	text_color u32
}

pub struct ResizableRectanglesDemo {
pub:
	colors []ResizableColorBox
}

fn initial_resizable_rectangles() ResizableRectanglesDemo {
	return ResizableRectanglesDemo{
		colors: [
			ResizableColorBox{ id: 1, name: 'Red', color: u32(0xff6464), text_color: u32(0x5f1111) },
			ResizableColorBox{ id: 2, name: 'Green', color: u32(0x64ff64), text_color: u32(0x14532d) },
			ResizableColorBox{ id: 3, name: 'Blue', color: u32(0x6464ff), text_color: u32(0xffffff) },
			ResizableColorBox{ id: 4, name: 'Pink', color: u32(0xff64ff), text_color: u32(0x701a75) },
		]
	}
}

fn main() {
	mut app := initial_resizable_rectangles()
	ui2.run_compiled_vml[ResizableRectanglesDemo](
		build:  build_rectangles_resizable
		model:  &app
		title:  'Resizable Rectangles'
		width:  resizable_rectangles_width
		height: resizable_rectangles_height
	) or { panic(err) }
}

fn build_rectangles_resizable(mut app ResizableRectanglesDemo) ui2.Element {
	return $vml('rectangles_resizable.vml')
}

fn rectangles_resizable_tree(mut app ResizableRectanglesDemo, frame ui2.Rect) ui2.Element {
	return $vml('rectangles_resizable.vml', frame)
}
