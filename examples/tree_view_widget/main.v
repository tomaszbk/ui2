module main

import ui2

const tree_view_widget_width = 460
const tree_view_widget_height = 360

pub struct TreeViewWidgetDemo {
pub mut:
	docs_open bool
	selected  string = 'welcome'
}

pub fn (mut app TreeViewWidgetDemo) toggle_docs() {
	app.docs_open = !app.docs_open
}

pub fn (mut app TreeViewWidgetDemo) select_welcome() {
	app.selected = 'welcome'
}

pub fn (mut app TreeViewWidgetDemo) select_installation() {
	app.selected = 'installation'
}

pub fn (mut app TreeViewWidgetDemo) select_license() {
	app.selected = 'license'
}

fn main() {
	mut app := TreeViewWidgetDemo{}
	ui2.run_compiled_vml[TreeViewWidgetDemo](
		build:  build_tree_view_widget
		model:  &app
		title:  'Tree View'
		width:  tree_view_widget_width
		height: tree_view_widget_height
	) or { panic(err) }
}

fn build_tree_view_widget(mut app TreeViewWidgetDemo) ui2.Element {
	return $vml('tree_view_widget.vml')
}

fn tree_view_widget_tree(mut app TreeViewWidgetDemo, frame ui2.Rect) ui2.Element {
	return $vml('tree_view_widget.vml', frame)
}
