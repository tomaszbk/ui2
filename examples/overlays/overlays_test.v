// vtest vflags: -d ui2_custom_rendering
module main

import ui2

fn overlays_find(element ui2.Element, id string) !ui2.Element {
	if element.id == id { return element }
	for child in element.children {
		if found := overlays_find(child, id) { return found }
	}
	return error('missing overlay demo control `${id}`')
}

fn overlays_click(element ui2.Element) {
	element.on_event(ui2.ElementEvent{ kind: .click, id: element.id })
}

fn test_overlay_demo_retains_nested_editor_and_routes_all_five_surfaces() ! {
	mut app := &OverlayDemo{ reduced_motion: true }
	initial := build_overlays(mut app)
	defer { initial.compiled_node.dispose_document() or { panic(err) } }
	root := initial.compiled_node
	editor := overlays_find(initial, 'editor')!.compiled_node
	draft := overlays_find(initial, 'draft')!.compiled_node
	nested := overlays_find(initial, 'nested_editor')!.compiled_node
	assert !editor.element().hidden && nested.element().hidden
	assert draft.element().text == 'Mañana, un café con Sofía.'
	draft.element().on_event(ui2.ElementEvent{ kind: .change, id: 'draft', text: 'Niña, café y mañana.' })
	assert app.draft == 'Niña, café y mañana.'
	overlays_click(overlays_find(root.element(), 'nested_trigger')!)
	assert app.nested_open && !nested.element().hidden
	overlays_click(overlays_find(root.element(), 'nested_confirm')!)
	assert !app.nested_open && nested.element().hidden
	assert overlays_find(root.element(), 'draft')!.compiled_node == draft
	assert draft.element().text == app.draft
	overlays_click(overlays_find(root.element(), 'editor_close')!)
	assert !app.dialog_open && editor.element().hidden
	overlays_click(overlays_find(root.element(), 'dialog_trigger')!)
	assert !editor.element().hidden
	assert overlays_find(root.element(), 'draft')!.compiled_node == draft
	overlays_click(overlays_find(root.element(), 'save_draft')!)
	assert app.status == 'Saved: Niña, café y mañana.'
	assert editor.element().hidden

	popover := overlays_find(root.element(), 'details')!.compiled_node
	overlays_click(overlays_find(root.element(), 'popover_trigger')!)
	assert app.popover_open && !popover.element().hidden
	popover_config := popover.element().overlay or { panic('missing popover') }
	assert popover_config.anchor == 'popover_trigger'
	popover_config.on_dismiss(ui2.ElementEvent{ kind: .dismiss, id: 'details', dismiss_reason: .outside_pointer })
	assert !app.popover_open && popover.element().hidden

	menu := overlays_find(root.element(), 'draft_menu')!.compiled_node
	overlays_click(overlays_find(root.element(), 'menu_trigger')!)
	assert app.menu_open && !menu.element().hidden
	overlays_click(overlays_find(root.element(), 'menu_duplicate')!)
	assert !app.menu_open && menu.element().hidden
	assert app.status == 'Duplicated: Niña, café y mañana.'

	context := overlays_find(root.element(), 'quick_menu')!.compiled_node
	context_config := context.element().overlay or { panic('missing context menu') }
	context_config.on_open(ui2.ElementEvent{ kind: .open, id: 'quick_menu', x: 230.5, y: 280.25 })
	assert app.context_open && !context.element().hidden
	point := (context.element().overlay or { panic('missing context menu') }).point or { panic('missing pointer point') }
	assert point == ui2.OverlayPoint{ x: 230.5, y: 280.25 }
	overlays_click(overlays_find(root.element(), 'context_pin')!)
	assert !app.context_open && context.element().hidden
	assert app.status == 'Pinned: Niña, café y mañana.'

	tip := overlays_find(root.element(), 'help')!.compiled_node
	tip_config := tip.element().overlay or { panic('missing tooltip') }
	assert tip_config.tooltip_delay == 0.45
	tip_config.on_open(ui2.ElementEvent{ kind: .open, id: 'help' })
	assert app.tip_open && !tip.element().hidden
	assert tip.element().focus_policy == .unfocusable
	tip_config.on_dismiss(ui2.ElementEvent{ kind: .dismiss, id: 'help', dismiss_reason: .pointer_leave })
	assert !app.tip_open && tip.element().hidden
	assert overlays_find(root.element(), 'draft')!.compiled_node == draft
}
