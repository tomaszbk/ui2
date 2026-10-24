module main

// vml: tabs.vml

import ui2

const tabs_width = 640
const tabs_height = 400

pub struct TabsDemo {
pub mut:
	tab string = 'account'
}

fn main() {
	mut app := TabsDemo{}
	ui2.run_compiled_vml[TabsDemo](
		build:  build_tabs
		model:  &app
		title:  'Tabs'
		width:  tabs_width
		height: tabs_height
	) or { panic(err) }
}

fn build_tabs(mut app TabsDemo) ui2.Element {
	return tabs_vml(mut app)
}

fn tabs_tree(mut app TabsDemo, frame ui2.Rect) ui2.Element {
	return tabs_vml_framed(mut app, frame)
}
