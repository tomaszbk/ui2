module main

import ui2

const tree_width = 460
const tree_height = 360

pub struct TreeDemo {
pub mut:
	docs_open bool
	selected  string = 'welcome'
}

fn main() {
	mut app := TreeDemo{}
	ui2.run_compiled_vml[TreeDemo](
		build:  build_tree
		model:  &app
		title:  'Tree'
		width:  tree_width
		height: tree_height
	) or { panic(err) }
}

fn build_tree(mut app TreeDemo) ui2.Element {
	return $vml('tree.vml')
}

fn tree_document(mut app TreeDemo, frame ui2.Rect) ui2.Element {
	return $vml('tree.vml', frame)
}
