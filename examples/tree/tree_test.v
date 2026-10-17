module main

import ui2

fn tree_row_texts(files ui2.Element) []string {
	return files.children.map(it.children.last().text)
}

fn test_tree_demo_expands_folders_and_selects_files() {
	mut app := TreeDemo{}
	initial := tree_document(mut app, ui2.rect(0, 0, tree_width, tree_height))
	files := initial.children[0].children[1]
	// Documentation starts collapsed and src expanded.
	assert tree_row_texts(files) == ['Documentation', 'src', 'main.v', 'app.v', 'License']
	docs := files.children[0]
	docs.on_event(ui2.ElementEvent{ kind: .click, id: docs.id })
	assert app.docs_open && app.selected == 'docs'

	expanded := tree_document(mut app, ui2.rect(0, 0, tree_width, tree_height))
	rows := expanded.children[0].children[1]
	assert tree_row_texts(rows) == ['Documentation', 'Welcome', 'Installation', 'src', 'main.v',
		'app.v', 'License']
	installation := rows.children[2]
	installation.on_event(ui2.ElementEvent{ kind: .click, id: installation.id })
	assert app.selected == 'installation'

	selected := tree_document(mut app, ui2.rect(0, 0, tree_width, tree_height))
	assert selected.children[0].children[1].children[2].accessibility_value == 'selected'
	assert selected.children[0].children[2].text == 'Selected: installation'
}
