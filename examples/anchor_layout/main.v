module main

import ui2

const anchor_width = 380
const anchor_height = 320

pub struct AnchorLayoutDemo {}

fn main() {
	mut app := AnchorLayoutDemo{}
	ui2.run_compiled_vml[AnchorLayoutDemo](
		build:  build_anchor_layout
		model:  &app
		title:  'Anchor Layout'
		width:  anchor_width
		height: anchor_height
	) or { panic(err) }
}

fn build_anchor_layout(mut app AnchorLayoutDemo) ui2.Element {
	return $vml('anchor_layout.vml')
}

fn anchor_layout_tree(mut app AnchorLayoutDemo, frame ui2.Rect) ui2.Element {
	return $vml('anchor_layout.vml', frame)
}
