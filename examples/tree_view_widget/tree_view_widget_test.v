module main

import ui2

fn test_tree_view_widget_demo_expands_and_selects_nodes() {
	mut app := ui2.new_vml_app(tree_view_widget_vml_source, TreeViewWidgetDemo{}) or {
		panic(err)
	}
	initial := app.build(ui2.rect(0, 0, tree_view_widget_width, tree_view_widget_height)) or {
		panic(err)
	}
	mut tree := initial.children[0].children[1].children[0].children[0]
	assert tree.children.len == 2
	control_1 := tree.children[0].children[0]
	control_1.on_event(ui2.ElementEvent{ kind: .tap, id: control_1.id })
	assert app.state().docs_open

	expanded := app.build(ui2.rect(0, 0, tree_view_widget_width, tree_view_widget_height)) or {
		panic(err)
	}
	tree = expanded.children[0].children[1].children[0].children[0]
	assert tree.children.len == 4
	control_2 := tree.children[2].children[1]
	control_2.on_event(ui2.ElementEvent{ kind: .tap, id: control_2.id })
	assert app.state().selected == 'installation'

	selected := app.build(ui2.rect(0, 0, tree_view_widget_width, tree_view_widget_height)) or {
		panic(err)
	}
	assert selected.children[0].children[1].children[0].children[0].children[2].children[1].accessibility_value == 'selected'
}
