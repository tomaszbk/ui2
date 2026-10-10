module main

import ui2

const tabbed_width = 440
const tabbed_height = 300

pub struct TabbedPanelDemo {
pub mut:
	current int
}

pub fn (mut app TabbedPanelDemo) show_overview() {
	app.current = 0
}

pub fn (mut app TabbedPanelDemo) show_activity() {
	app.current = 1
}

pub fn (mut app TabbedPanelDemo) show_security() {
	app.current = 2
}

fn main() {
	mut app := TabbedPanelDemo{}
	ui2.run_compiled_vml[TabbedPanelDemo](
		build:  build_tabbed_panel
		model:  &app
		title:  'Tabbed Panel'
		width:  tabbed_width
		height: tabbed_height
	) or { panic(err) }
}

fn build_tabbed_panel(mut app TabbedPanelDemo) ui2.Element {
	return $vml('tabbed_panel.vml')
}

fn tabbed_panel_tree(mut app TabbedPanelDemo, frame ui2.Rect) ui2.Element {
	return $vml('tabbed_panel.vml', frame)
}
