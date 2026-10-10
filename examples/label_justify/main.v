module main

import ui2

const label_justify_width = 520
const label_justify_height = 330

pub struct LabelJustifyDemo {}

fn main() {
	mut app := LabelJustifyDemo{}
	ui2.run_compiled_vml[LabelJustifyDemo](
		build:  build_label_justify
		model:  &app
		title:  'Label Justify'
		width:  label_justify_width
		height: label_justify_height
	) or { panic(err) }
}

fn build_label_justify(mut app LabelJustifyDemo) ui2.Element {
	return $vml('label_justify.vml')
}

fn label_justify_tree(mut app LabelJustifyDemo, frame ui2.Rect) ui2.Element {
	return $vml('label_justify.vml', frame)
}
