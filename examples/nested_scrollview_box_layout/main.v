module main

import ui2

const nested_box_width = 660
const nested_box_height = 430

pub struct ScrollGridBox {
pub:
	id      int
	row     int
	column  int
	content string
}

pub struct NestedScrollBoxLayoutDemo {
pub:
	boxes []ScrollGridBox
}

fn initial_nested_scroll_box_layout() NestedScrollBoxLayoutDemo {
	mut boxes := []ScrollGridBox{cap: 25}
	for row in 0 .. 5 {
		for column in 0 .. 5 {
			boxes << ScrollGridBox{
				id:      row * 5 + column
				row:     row
				column:  column
				content: 'box ${row}${column}\nline 2\nline 3\nline 4\nline 5\nline 6\nline 7\nline 8'
			}
		}
	}
	return NestedScrollBoxLayoutDemo{ boxes: boxes }
}

fn main() {
	mut app := initial_nested_scroll_box_layout()
	ui2.run_compiled_vml[NestedScrollBoxLayoutDemo](
		build:  build_nested_scrollview_box_layout
		model:  &app
		title:  'Nested Scrollviews in Box Layout'
		width:  nested_box_width
		height: nested_box_height
	) or { panic(err) }
}

fn build_nested_scrollview_box_layout(mut app NestedScrollBoxLayoutDemo) ui2.Element {
	return $vml('nested_scrollview_box_layout.vml')
}

fn nested_scrollview_box_layout_tree(mut app NestedScrollBoxLayoutDemo, frame ui2.Rect) ui2.Element {
	return $vml('nested_scrollview_box_layout.vml', frame)
}
