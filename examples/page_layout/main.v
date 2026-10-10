module main

import ui2

const page_width = 420
const page_height = 280

pub struct PageLayoutDemo {
pub mut:
	page int
}

pub fn (mut app PageLayoutDemo) previous() {
	app.page = (app.page + 2) % 3
}

pub fn (mut app PageLayoutDemo) next() {
	app.page = (app.page + 1) % 3
}

fn main() {
	mut app := PageLayoutDemo{}
	ui2.run_compiled_vml[PageLayoutDemo](
		build:  build_page_layout
		model:  &app
		title:  'Page Layout'
		width:  page_width
		height: page_height
	) or { panic(err) }
}

fn build_page_layout(mut app PageLayoutDemo) ui2.Element {
	return $vml('page_layout.vml')
}

fn page_layout_tree(mut app PageLayoutDemo, frame ui2.Rect) ui2.Element {
	return $vml('page_layout.vml', frame)
}
