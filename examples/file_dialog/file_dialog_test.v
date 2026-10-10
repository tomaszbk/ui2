module main

import ui2

fn test_file_dialog_example_declares_native_actions() {
	mut compiled_model_0 := FileDialogDemo{}
	root := file_dialog_tree(mut compiled_model_0, ui2.rect(0, 0, file_dialog_width, file_dialog_height))
	ui2.validate_element_tree(root) or { panic(err) }
	assert root.id == 'root'
}
