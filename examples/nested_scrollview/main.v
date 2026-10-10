module main

import ui2

const nested_scrollview_width = 620
const nested_scrollview_height = 400

pub struct NestedScrollBox {
pub:
	id      int
	title   string
	content string
}

pub struct NestedScrollviewDemo {
pub:
	boxes []NestedScrollBox
}

fn initial_nested_scrollview() NestedScrollviewDemo {
	mut boxes := []NestedScrollBox{cap: 12}
	for index in 0 .. 12 {
		number := index + 1
		boxes << NestedScrollBox{
			id:      number
			title:   'Box ${number}'
			content: 'line 1\nline 2\nline 3\nline 4\nline 5\nline 6\nline 7\nline 8'
		}
	}
	return NestedScrollviewDemo{
		boxes: boxes
	}
}

fn main() {
	mut app := initial_nested_scrollview()
	ui2.run_compiled_vml[NestedScrollviewDemo](
		build:  build_nested_scrollview
		model:  &app
		title:  'Nested Scrollviews'
		width:  nested_scrollview_width
		height: nested_scrollview_height
	) or { panic(err) }
}

fn build_nested_scrollview(mut app NestedScrollviewDemo) ui2.Element {
	return $vml('nested_scrollview.vml')
}

fn nested_scrollview_tree(mut app NestedScrollviewDemo, frame ui2.Rect) ui2.Element {
	return $vml('nested_scrollview.vml', frame)
}
