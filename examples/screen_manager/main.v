module main

import ui2

const screen_manager_width = 440
const screen_manager_height = 320

pub struct ScreenManagerDemo {
pub mut:
	current string
}

pub fn (mut app ScreenManagerDemo) show_home() {
	app.current = 'home'
}

pub fn (mut app ScreenManagerDemo) show_details() {
	app.current = 'details'
}

fn main() {
	mut app := ScreenManagerDemo{}
	ui2.run_compiled_vml[ScreenManagerDemo](
		build:  build_screen_manager
		model:  &app
		title:  'Screen Manager'
		width:  screen_manager_width
		height: screen_manager_height
	) or { panic(err) }
}

fn build_screen_manager(mut app ScreenManagerDemo) ui2.Element {
	return $vml('screen_manager.vml')
}

fn screen_manager_tree(mut app ScreenManagerDemo, frame ui2.Rect) ui2.Element {
	return $vml('screen_manager.vml', frame)
}
