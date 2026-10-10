module main

import ui2

const demo_label_width = 420
const demo_label_height = 220

pub struct DemoLabel {}

fn main() {
	mut app := DemoLabel{}
	ui2.run_compiled_vml[DemoLabel](
		build:  build_demo_label
		model:  &app
		title:  'Label'
		width:  demo_label_width
		height: demo_label_height
	) or { panic(err) }
}

fn build_demo_label(mut app DemoLabel) ui2.Element {
	return $vml('demo_label.vml')
}

fn demo_label_tree(mut app DemoLabel, frame ui2.Rect) ui2.Element {
	return $vml('demo_label.vml', frame)
}
