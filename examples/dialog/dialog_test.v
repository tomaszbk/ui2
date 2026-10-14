// vtest vflags: -d ui2_custom_rendering
module main

import ui2

fn dialog_find(element ui2.Element, id string) !ui2.Element {
	if element.id == id { return element }
	for child in element.children {
		if found := dialog_find(child, id) { return found }
	}
	return error('missing dialog control `${id}`')
}

fn test_dialog_opens_confirms_and_dismisses_without_replacing_content() ! {
	mut app := DialogDemo{}
	initial := dialog_tree(mut app, ui2.rect(0, 0, dialog_width, dialog_height))
	defer { initial.compiled_node.dispose_document() or { panic(err) } }
	dialog := dialog_find(initial, 'confirmation')!.compiled_node
	confirm := dialog_find(initial, 'confirm')!.compiled_node
	cancel := dialog_find(initial, 'cancel')!.compiled_node
	open := dialog_find(initial, 'open_confirmation')!.compiled_node
	assert dialog.element().hidden
	open.element().on_event(ui2.ElementEvent{ kind: .click, id: open.element().id })
	assert app.confirming && !dialog.element().hidden
	assert (dialog.element().overlay or { panic('missing dialog config') }).kind == .dialog
	assert dialog.element().frame.width == 340 && dialog.element().frame.height == 190
	assert dialog_find(dialog.element(), 'confirmation_title')!.text == 'Confirm action'
	confirm.element().on_event(ui2.ElementEvent{ kind: .click, id: confirm.element().id })
	assert !app.confirming && dialog.element().hidden
	assert app.status == 'Action confirmed.'
	open.element().on_event(ui2.ElementEvent{ kind: .click, id: open.element().id })
	cancel.element().on_event(ui2.ElementEvent{ kind: .click, id: cancel.element().id })
	assert app.status == 'Action cancelled.' && dialog.element().hidden
	open.element().on_event(ui2.ElementEvent{ kind: .click, id: open.element().id })
	config := dialog.element().overlay or { panic('missing dialog config') }
	config.on_dismiss(ui2.ElementEvent{ kind: .dismiss, id: 'confirmation', dismiss_reason: .outside_pointer })
	assert app.status == 'Action cancelled.' && dialog.element().hidden
	open.element().on_event(ui2.ElementEvent{ kind: .click, id: open.element().id })
	assert dialog_find(dialog.element(), 'confirm')!.compiled_node == confirm
	assert dialog_find(dialog.element(), 'cancel')!.compiled_node == cancel
}
