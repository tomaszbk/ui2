module main

import ui2

const dropdown_width = 360
const dropdown_height = 220

pub struct DropdownDemo {
pub mut:
	selection string = 'Select an option'
	message   string = 'Choose an action from the menu.'
}

pub fn (mut app DropdownDemo) selection_changed() {
	app.message = match app.selection {
		'Delete all users' { 'Delete all users selected.' }
		'Export users' { 'Export users selected.' }
		'Exit' { 'Exit selected.' }
		else { 'Choose an action from the menu.' }
	}
}

fn main() {
	mut app := DropdownDemo{}
	ui2.run_compiled_vml[DropdownDemo](
		build:  build_dropdown
		model:  &app
		title:  'Dropdown'
		width:  dropdown_width
		height: dropdown_height
	) or { panic(err) }
}

fn build_dropdown(mut app DropdownDemo) ui2.Element {
	return $vml('dropdown.vml')
}

fn dropdown_tree(mut app DropdownDemo, frame ui2.Rect) ui2.Element {
	return $vml('dropdown.vml', frame)
}
