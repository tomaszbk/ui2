module main

import ui2

const change_title_width = 520
const change_title_height = 250

pub struct ChangeTitleDemo {
pub mut:
	title         string = 'Name'
	applied_title string = 'Name'
	valid         bool   = true
	status        string = 'Enter a new window title.'
}

pub fn (mut app ChangeTitleDemo) apply_title() {
	title := app.title.trim_space()
	if title.len == 0 {
		app.valid = false
		app.status = 'The window title cannot be empty.'
		return
	}
	app.title = title
	app.applied_title = title
	app.valid = true
	app.status = 'Window title changed to “${title}”.'
	apply_window_title(title)
}

fn main() {
	mut app := ChangeTitleDemo{}
	ui2.run_compiled_vml[ChangeTitleDemo](
		build:  build_change_title
		model:  &app
		title:  'Name'
		width:  change_title_width
		height: change_title_height
	) or { panic(err) }
}

fn build_change_title(mut app ChangeTitleDemo) ui2.Element {
	return $vml('change_title.vml')
}

fn change_title_tree(mut app ChangeTitleDemo, frame ui2.Rect) ui2.Element {
	return $vml('change_title.vml', frame)
}
