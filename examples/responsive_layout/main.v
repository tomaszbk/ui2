module main

import os
import ui2

pub struct Project {
pub:
	id          int
	title       string
	description string
}

pub struct ResponsiveApp {
pub mut:
	created  int
	projects []Project = [
		Project{ id: 1, title: 'Design system', description: 'Shared controls and typography' },
		Project{ id: 2, title: 'Desktop app', description: 'One layout across window sizes' },
	]
}

pub fn (mut app ResponsiveApp) create_project() {
	app.created++
}

fn main() {
	mut app := ResponsiveApp{}
	ui2.run_compiled_vml[ResponsiveApp](
		build:  build_responsive_layout
		model:  &app
		title:  'UI2 · Responsive layout'
		width:  if '--compact' in os.args { 390 } else { 1000 }
		height: 780
	) or { panic(err) }
}

fn build_responsive_layout(mut app ResponsiveApp) ui2.Element {
	return $vml('responsive_layout.vml')
}

fn responsive_layout_tree(mut app ResponsiveApp, frame ui2.Rect) ui2.Element {
	return $vml('responsive_layout.vml', frame)
}
