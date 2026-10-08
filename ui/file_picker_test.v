module ui2

import os

@[heap]
struct PickerResults {
mut:
	events []FilePickerResult
}

fn file_picker_test_dir(name string) string {
	dir := os.join_path(os.temp_dir(), 'ui2_file_picker_test', name)
	os.rmdir_all(dir) or {}
	os.mkdir_all(os.join_path(dir, 'sub')) or { panic(err) }
	for entry_name, content in {
		'a.V':       'a'
		'b.txt':     'b'
		'c.v':       'c'
		'.hidden.v': 'hidden'
	} {
		os.write_file(os.join_path(dir, entry_name), content) or { panic(err) }
	}
	return dir
}

fn picker_find(element Element, id string) ?Element {
	if element.id == id { return element }
	for child in element.children { if found := picker_find(child, id) { return found } }
	return none
}

fn picker_emit(mut picker FilePicker, suffix string, event ElementEvent) {
	tree := picker.render(rect(0, 0, 640, 480))
	control := picker_find(tree, picker.config.id + '__' + suffix) or { panic('missing ' + suffix) }
	assert voidptr(control.on_event) != unsafe { nil }
	control.on_event(event)
}

fn test_file_picker_filters_and_navigates_through_attached_callbacks() {
	dir := file_picker_test_dir('navigation')
	defer { os.rmdir_all(dir) or {} }
	mut picker := new_file_picker(
		id:     'choose'
		dialog: FileDialogConfig{ directory: dir, filters: [FileDialogFilter{ extensions: ['*.v'] }] }
	) or { panic(err) }
	assert picker.entries.map(it.name) == ['sub', 'a.V', 'c.v']
	picker.open() or { panic(err) }
	picker_emit(mut picker, 'entry_0', ElementEvent{ kind: .tap })
	assert picker.directory == os.real_path(os.join_path(dir, 'sub'))
	assert picker.entries.len == 0
	picker_emit(mut picker, 'up', ElementEvent{ kind: .tap })
	assert picker.directory == os.real_path(dir)
	picker_emit(mut picker, 'path', ElementEvent{ kind: .change, text: 'sub' })
	picker_emit(mut picker, 'go', ElementEvent{ kind: .tap })
	assert picker.directory == os.real_path(os.join_path(dir, 'sub'))
	picker_emit(mut picker, 'path', ElementEvent{ kind: .submit, text: 'missing' })
	assert picker.status.len > 0
	assert picker.directory == os.real_path(os.join_path(dir, 'sub'))
}

fn test_file_picker_wildcard_filter_shows_every_file() {
	assert file_picker_matches_filter('anything.bin', [FileDialogFilter{
		extensions: [
			'*.v',
			'*.*',
		]
	}])
	assert !file_picker_matches_filter('anything.bin', [FileDialogFilter{ extensions: ['*.v'] }])
}

fn test_file_picker_open_selection_and_typed_completion() {
	dir := file_picker_test_dir('selection')
	defer { os.rmdir_all(dir) or {} }
	mut results := &PickerResults{}
	mut picker := new_file_picker(
		id:        'files'
		dialog:    FileDialogConfig{ directory: dir, multiple: true }
		on_result: fn [mut results] (result FilePickerResult) { results.events << result }
	) or { panic(err) }
	picker.open() or { panic(err) }
	picker_emit(mut picker, 'accept', ElementEvent{ kind: .tap })
	assert picker.status.len > 0 && picker.visible
	assert results.events.len == 0
	picker_emit(mut picker, 'entry_1', ElementEvent{ kind: .tap })
	picker_emit(mut picker, 'entry_2', ElementEvent{ kind: .tap })
	assert picker.selected.len == 2
	picker_emit(mut picker, 'entry_1', ElementEvent{ kind: .tap })
	assert picker.selected.len == 1
	picker_emit(mut picker, 'accept', ElementEvent{ kind: .tap })
	assert results.events[0].kind == .selected
	assert results.events[0].paths == [os.join_path(os.real_path(dir), 'b.txt')]
	assert !picker.visible
	picker.open() or { panic(err) }
	picker_emit(mut picker, 'cancel', ElementEvent{ kind: .tap })
	assert results.events[1].kind == .cancelled && results.events[1].paths.len == 0
}

fn test_file_picker_save_validation_and_overwrite_confirmation() {
	dir := file_picker_test_dir('save')
	defer { os.rmdir_all(dir) or {} }
	mut results := &PickerResults{}
	mut save := new_file_picker(
		id:        'save'
		dialog:    FileDialogConfig{ kind: .save, directory: dir }
		on_result: fn [mut results] (result FilePickerResult) { results.events << result }
	) or { panic(err) }
	save.open() or { panic(err) }
	picker_emit(mut save, 'filename', ElementEvent{ kind: .change, text: '../escape' })
	picker_emit(mut save, 'accept', ElementEvent{ kind: .tap })
	assert results.events.len == 0 && save.status.len > 0
	picker_emit(mut save, 'filename', ElementEvent{ kind: .submit, text: 'report.txt' })
	assert results.events[0].paths == [os.join_path(os.real_path(dir), 'report.txt')]
	save.open() or { panic(err) }
	picker_emit(mut save, 'filename', ElementEvent{ kind: .change, text: 'b.txt' })
	picker_emit(mut save, 'accept', ElementEvent{ kind: .tap })
	assert results.events.len == 1 && save.status.contains('replace')
	picker_emit(mut save, 'accept', ElementEvent{ kind: .tap })
	assert results.events[1].paths == [os.join_path(os.real_path(dir), 'b.txt')]
}

fn test_file_picker_folder_result_and_valid_tree() {
	dir := file_picker_test_dir('folder')
	defer { os.rmdir_all(dir) or {} }
	mut results := &PickerResults{}
	mut folder := new_file_picker(
		id:        'folder'
		dialog:    FileDialogConfig{ kind: .folder, directory: dir }
		on_result: fn [mut results] (result FilePickerResult) { results.events << result }
	) or { panic(err) }
	assert folder.entries.map(it.name) == ['sub']
	folder.open() or { panic(err) }
	validate_element_tree(folder.render(rect(0, 0, 640, 480))) or { panic(err) }
	picker_emit(mut folder, 'entry_0', ElementEvent{ kind: .tap })
	picker_emit(mut folder, 'accept', ElementEvent{ kind: .tap })
	assert results.events[0].paths == [os.real_path(os.join_path(dir, 'sub'))]
}

fn test_file_picker_retained_entry_callback_does_not_follow_reordered_index() {
	dir := file_picker_test_dir('captured')
	defer { os.rmdir_all(dir) or {} }
	mut picker := new_file_picker(id: 'picker', dialog: FileDialogConfig{ directory: dir }) or { panic(err) }
	picker.open() or { panic(err) }
	entry := picker_find(picker.render(rect(0, 0, 640, 480)), 'picker__entry_1') or { panic('missing entry') }
	picker.entries.reverse_in_place()
	entry.on_event(ElementEvent{ kind: .tap })
	assert picker.selected == [os.join_path(os.real_path(dir), 'a.V')]
	picker.load_directory(os.join_path(dir, 'sub')) or { panic(err) }
	entry.on_event(ElementEvent{ kind: .tap })
	assert picker.selected.len == 0
}
