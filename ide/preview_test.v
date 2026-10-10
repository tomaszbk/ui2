module main

import ui2
import os

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
	parsed := designer_document(app.source_text)!
	assert parsed.children.len == 1
	assert parsed.children[0].tag == 'Absolute'
	doc := document_from_vml(app.source_text)!
	assert component_frame(doc.components[0]) == ui2.rect(24.5, 42.25, 112.75, 36.5)
	app.compile_preview()!
	defer { app.dispose_preview() }
	root := app.preview_element(ui2.rect(0, 0, app.form_width, app.form_height))!
	assert preview_test_find(root, app.components[0].name)?.frame == component_frame(app.components[0])
}

fn test_preview_reuses_owner_and_failed_compile_preserves_live_document() ! {
	mut app := new_ide_app('.')
	app.add_component('button', 24, 48)
	app.compile_preview()!
	defer { app.dispose_preview() }
	frame := ui2.rect(0, 0, app.form_width, app.form_height)
	first := app.preview_element(frame)!
	second := app.preview_element(frame)!
	assert first.compiled_node == second.compiled_node
	assert first.compiled_node.component.runtime.stats() == second.compiled_node.component.runtime.stats()
	app.source_text = 'Button { text: "removed syntax" }'
	if _ := app.compile_preview() {
		assert false
	}
	assert app.preview_element(frame)!.compiled_node == first.compiled_node
	app.source_text = 'Screen { Absolute { Button(id: "replacement", text: "New") } }'
	app.compile_preview()!
	assert first.compiled_node.component.is_disposed()
	replacement := app.preview_element(frame)!
	assert replacement.compiled_node != first.compiled_node
	assert preview_test_find(replacement, 'replacement')?.text == 'New'
}

fn test_preview_compiles_relative_component_imports_and_reloads_dependencies() ! {
	project := os.join_path(os.temp_dir(), 'ui2-designer-imports-${os.getpid()}')
	os.mkdir_all(project)!
	defer { os.rmdir_all(project) or {} }
	component := os.join_path(project, 'badge.vml')
	os.write_file(component, 'component Badge() { state count := 0 Column { Label(text: "First") Button(text: count, on_tap: count++) } }')!
	source := 'import Badge\nScreen { Badge() }'
	os.write_file(os.join_path(project, 'form.vml'), source)!
	mut app := new_ide_app(project)
	app.open_document('form.vml')!
	assert app.source_only
	assert app.active_tab == 'source'
	assert app.source_text == source
	app.compile_preview()!
	defer { app.dispose_preview() }
	frame := ui2.rect(0, 0, 300, 200)
	first := app.preview_element(frame)!
	assert first.children[0].children[0].text == 'First'
	first.children[0].children[1].on_event(ui2.ElementEvent{ kind: .tap })
	assert app.preview_element(frame)!.children[0].children[1].text == '1'
	os.write_file(component, 'component Badge() { Label(text: "Second") }')!
	app.compile_preview()!
	assert first.compiled_node.component.is_disposed()
	assert first.compiled_node.component.runtime.stats() == ui2.SignalStats{}
	second := app.preview_element(frame)!
	assert second.children[0].text == 'Second'
	assert second.compiled_node != first.compiled_node
	first.children[0].children[1].on_event(ui2.ElementEvent{ kind: .tap })
	assert app.preview_element(frame)!.children[0].text == 'Second'
	app.source_text += '\n// preserve source edits'
	app.source_modified = true
	app.save_document()!
	assert os.read_file(os.join_path(project, 'form.vml'))! == app.source_text
	assert os.ls(project)!.len == 2
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
	root := build_ide(ui2.rect(0, 0, ide_width, ide_height), mut app)
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
		root := build_ide(ui2.rect(0, 0, 900, 700), mut app)
		ui2.validate_element_tree(root)!
		if tab != 'source' { _ := preview_test_find(root, 'preview_toolbar')? }
	}
}

fn test_designer_rejects_removed_adaptive_format_without_rewriting_document() {
	mut app := new_ide_app('.')
	app.add_component('button', 24, 48)
	before := app.snapshot()
	if _ := app.apply_source('Screen(adaptive: true, width: 760, height: 520) { Button {} }') {
		assert false
	}
	assert app.snapshot() == before
}
