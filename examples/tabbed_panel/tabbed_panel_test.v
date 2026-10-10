module main

import ui2

fn test_tabbed_panel_demo_switches_active_content() {
	mut app := TabbedPanelDemo{}
	initial := tabbed_panel_tree(mut app, ui2.rect(0, 0, tabbed_width, tabbed_height))
	settings := initial.children[0].children[1]
	assert settings.children[0].children[0].children[0].text == 'Account overview'

	security := settings.children[3]
	control := security
	control.on_event(ui2.ElementEvent{ kind: .tap, id: control.id })
	assert app.current == 2
	rebuilt := tabbed_panel_tree(mut app, ui2.rect(0, 0, tabbed_width, tabbed_height))
	assert rebuilt.children[0].children[1].children[0].children[0].children[0].text == 'Security options'
}
