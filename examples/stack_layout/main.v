module main

import ui2

const stack_width = 380
const stack_height = 240

pub struct StackLayoutDemo {}

fn main() {
	mut app := StackLayoutDemo{}
	ui2.run_compiled_vml[StackLayoutDemo](
		build:  build_stack_layout
		model:  &app
		title:  'Stack Layout'
		width:  stack_width
		height: stack_height
	) or { panic(err) }
}

fn build_stack_layout(mut app StackLayoutDemo) ui2.Element {
	return $vml('stack_layout.vml')
}

fn stack_layout_tree(mut app StackLayoutDemo, frame ui2.Rect) ui2.Element {
	return $vml('stack_layout.vml', frame)
}
