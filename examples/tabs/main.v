module main

import ui2

const tabs_width = 640
const tabs_height = 400

pub struct TabPage {
pub:
	id         int
	title      string
	heading    string
	body       string
	background u32
}

pub struct TabsDemo {
pub:
	pages []TabPage
pub mut:
	active_tab int    = 1
	status     string = 'tab1 selected.'
}

fn initial_tabs() TabsDemo {
	return TabsDemo{
		pages: [
			TabPage{ id: 1, title: 'tab1', heading: 'Buttons', body: 'The original first page contains two buttons.', background: u32(0xf3e8ff) },
			TabPage{ id: 2, title: 'tab2', heading: 'Color preview', body: 'The original second page connects a color box to a rectangle.', background: u32(0xdbeafe) },
			TabPage{ id: 3, title: 'tab3', heading: 'Double list', body: 'The original third page embeds a double-list component.', background: u32(0xccfbf1) },
		]
	}
}

pub fn (mut app TabsDemo) select_tab(id int) {
	for page in app.pages {
		if page.id == id {
			app.active_tab = id
			app.status = '${page.title} selected.'
			return
		}
	}
}

fn main() {
	mut app := initial_tabs()
	ui2.run_compiled_vml[TabsDemo](
		build:  build_tabs
		model:  &app
		title:  'Tabs'
		width:  tabs_width
		height: tabs_height
	) or { panic(err) }
}

fn build_tabs(mut app TabsDemo) ui2.Element {
	return $vml('tabs.vml')
}

fn tabs_tree(mut app TabsDemo, frame ui2.Rect) ui2.Element {
	return $vml('tabs.vml', frame)
}
