module main

import ui2

fn preview_test_find(element ui2.Element, id string) ?ui2.Element {
	if element.id == id { return element }
	for child in element.children {
		if found := preview_test_find(child, id) { return found }
	}
	return none
}

fn test_absolute_designer_round_trips_fractional_geometry_and_runtime_frames() {
	mut app := new_ide_app('.')
	app.snap_to_grid = false
	app.add_component('button', 24.5, 42.25)
	app.components[0].width = 112.75
	app.components[0].height = 36.5
	app.sync_source()
	parsed := ui2.parse_vml(app.source_text)!
	assert parsed.children.len == 1
	assert parsed.children[0].tag == 'Absolute'
	doc := document_from_vml(app.source_text)!
	assert component_frame(doc.components[0]) == ui2.rect(24.5, 42.25, 112.75, 36.5)
	root := ui2.element_from_vml(app.source_text, ui2.rect(0, 0, app.form_width, app.form_height))!
	assert preview_test_find(root, app.components[0].name)?.frame == component_frame(app.components[0])
}

fn test_preview_sizes_preserve_saved_design_history_and_pending_source() {
	mut app := new_ide_app('.')
	app.snap_to_grid = false
	app.add_component('button', 624, 460)
	before := app.snapshot()
	source := app.source_text
	undo := app.undo_stack.len
	app.dirty = false
	app.set_preview_size(390, 844)
	assert app.canvas_width() == 390
	assert app.canvas_height() == 844
	assert app.snapshot() == before
	assert app.source_text == source
	assert !app.dirty
	assert app.undo_stack.len == undo
	assert !app.geometry_editable()
	assert !app.set_geometry_property('property_width', '200')
	app.nudge_selected(8, 8)
	assert app.snapshot() == before
	app.reset_preview()
	assert app.geometry_editable()
	assert app.canvas_width() == app.form_width
	assert app.set_geometry_property('property_x', '600.5')
	app.undo()
	assert app.snapshot() == before
	app.redo()
	assert app.components[0].x == 600.5
}

fn test_designer_visibility_and_disabled_preview_actions_preserve_editing() {
	mut app := new_ide_app('.')
	app.add_component('button', 24, 48)
	app.handle_preview_event('component_hidden')
	assert app.components[0].hidden
	assert document_from_vml(app.source_text)!.components[0].hidden
	app.active_tab = 'preview'
	root := build_ide(ui2.rect(0, 0, ide_width, ide_height), app)
	assert preview_test_find(root, 'preview_1') == none
	app.source_text += '\nButton { // unfinished source edit'
	app.source_modified = true
	before := app.snapshot()
	source := app.source_text
	app.handle_preview_event('component_hidden')
	assert app.snapshot() == before
	assert app.source_text == source
	assert app.source_modified
}

fn test_preview_toolbar_and_layout_inspector_produce_valid_trees() {
	mut app := new_ide_app('.')
	app.add_component('button', 24, 48)
	app.inspector_tab = 'layout'
	for tab in ['designer', 'preview', 'source'] {
		app.active_tab = tab
		root := build_ide(ui2.rect(0, 0, 900, 700), app)
		ui2.validate_element_tree(root)!
		if tab != 'source' { _ := preview_test_find(root, 'preview_toolbar')? }
	}
}

fn test_designer_rejects_removed_adaptive_format_without_rewriting_document() {
	mut app := new_ide_app('.')
	app.add_component('button', 24, 48)
	before := app.snapshot()
	if _ := app.apply_source('Screen { adaptive: true width: 760 height: 520 Button {} }') {
		assert false
	}
	assert app.snapshot() == before
}
