// vtest vflags: -d ui2_custom_rendering
module main

import ui2

fn profile_dialog_find(element ui2.Element, id string) !ui2.Element {
	if element.id == id { return element }
	for child in element.children {
		if found := profile_dialog_find(child, id) { return found }
	}
	return error('missing profile dialog control `${id}`')
}

fn test_profile_dialog_edits_saves_and_reopens_the_retained_field() ! {
	mut app := ProfileDialogDemo{}
	initial := profile_dialog_tree(mut app, ui2.rect(0, 0, profile_dialog_width, profile_dialog_height))
	defer { initial.compiled_node.dispose_document() or { panic(err) } }
	dialog := profile_dialog_find(initial, 'editor')!.compiled_node
	field := profile_dialog_find(initial, 'name')!.compiled_node
	open := profile_dialog_find(initial, 'open_editor')!.compiled_node
	save := profile_dialog_find(initial, 'save')!.compiled_node
	assert dialog.element().hidden
	open.element().on_event(ui2.ElementEvent{ kind: .click, id: open.element().id })
	assert app.editing && !dialog.element().hidden
	assert profile_dialog_find(dialog.element(), 'editor_title')!.text == 'Edit profile'
	field.element().on_event(ui2.ElementEvent{ kind: .change, id: field.element().id, text: 'José ñ' })
	assert app.name == 'José ñ'
	assert field.element().text == 'José ñ'
	save.element().on_event(ui2.ElementEvent{ kind: .click, id: save.element().id })
	assert !app.editing && dialog.element().hidden
	open.element().on_event(ui2.ElementEvent{ kind: .click, id: open.element().id })
	assert profile_dialog_find(dialog.element(), 'name')!.compiled_node == field
	assert field.element().text == 'José ñ'
	config := dialog.element().overlay or { panic('missing dialog config') }
	config.on_dismiss(ui2.ElementEvent{ kind: .dismiss, id: 'editor', dismiss_reason: .escape })
	assert !app.editing && dialog.element().hidden
}
