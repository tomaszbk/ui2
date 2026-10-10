// ui2 profiles: custom (custom font family)
module main

import ui2

const chunkview_width = 820
const chunkview_height = 560

pub struct ChunkviewDemo {
pub mut:
	first_open  bool      = true
	second_open bool      = true
	alignment   string    = 'Center'
	text_align  ui2.Align = .center
	status      string    = 'Both styled chunks are visible.'
}

pub fn (mut app ChunkviewDemo) sections_changed() {
	app.status = if app.first_open && app.second_open {
		'Both styled chunks are visible.'
	} else if app.first_open {
		'Only the first styled chunk is visible.'
	} else if app.second_open {
		'Only the second styled chunk is visible.'
	} else {
		'Both styled chunks are hidden.'
	}
}

pub fn (mut app ChunkviewDemo) alignment_changed() {
	app.text_align = match app.alignment {
		'Left' { ui2.Align.left }
		'Right' { ui2.Align.right }
		else { ui2.Align.center }
	}
}

pub fn (mut app ChunkviewDemo) reset_chunks() {
	app.first_open = true
	app.second_open = true
	app.alignment = 'Center'
	app.text_align = .center
	app.sections_changed()
}

fn main() {
	mut app := ChunkviewDemo{}
	ui2.run_compiled_vml[ChunkviewDemo](
		build:  build_demo_chunkview
		model:  &app
		title:  'Chunk View'
		width:  chunkview_width
		height: chunkview_height
	) or {
		panic(err)
	}
}

fn build_demo_chunkview(mut app ChunkviewDemo) ui2.Element {
	return $vml('demo_chunkview.vml')
}

fn demo_chunkview_tree(mut app ChunkviewDemo, frame ui2.Rect) ui2.Element {
	return $vml('demo_chunkview.vml', frame)
}
