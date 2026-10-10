module main

import ui2

const scrollview_width = 720
const scrollview_height = 430

pub struct ScrollviewDemo {
pub:
	info string
	text string
}

fn initial_scrollview() ScrollviewDemo {
	mut lines := []string{cap: 100}
	for index in 0 .. 100 {
		lines << 'line ${index:02}  ·  V UI scrollable content'
	}
	return ScrollviewDemo{
		info: 'Both panes use native multiline scrolling.\n\nThe right pane contains 100 generated lines. Each pane keeps its own scroll position while the window resizes.'
		text: lines.join('\n')
	}
}

fn main() {
	mut app := initial_scrollview()
	ui2.run_compiled_vml[ScrollviewDemo](
		build:  build_scrollview
		model:  &app
		title:  'Scrollview'
		width:  scrollview_width
		height: scrollview_height
	) or { panic(err) }
}

fn build_scrollview(mut app ScrollviewDemo) ui2.Element {
	return $vml('scrollview.vml')
}

fn scrollview_tree(mut app ScrollviewDemo, frame ui2.Rect) ui2.Element {
	return $vml('scrollview.vml', frame)
}
