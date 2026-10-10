module main

import os
import ui2

const file_dialog_width = 620
const file_dialog_height = 290

pub struct FileDialogDemo {
pub mut:
	selection string = 'Choose a file, a destination, or a folder.'
}

pub fn (mut app FileDialogDemo) open_source() {
	paths := ui2.open_file_dialog(
		title:   'Open a V source file'
		filters: [
			ui2.FileDialogFilter{
				name:       'V source'
				extensions: ['v', 'vv']
			},
		]
	)
	app.selection = if paths.len > 0 { 'Open: ${paths[0]}' } else { 'Open cancelled.' }
}

pub fn (mut app FileDialogDemo) save_text() {
	paths := ui2.save_file_dialog(
		title:    'Save text file'
		filename: 'notes.txt'
		filters:  [ui2.FileDialogFilter{
			name:       'Text'
			extensions: ['txt']
		}]
	)
	app.selection = if paths.len > 0 { 'Save: ${paths[0]}' } else { 'Save cancelled.' }
}

pub fn (mut app FileDialogDemo) choose_folder() {
	paths := ui2.open_folder_dialog(
		title:     'Choose a folder'
		directory: os.home_dir()
	)
	app.selection = if paths.len > 0 {
		'Folder: ${paths[0]}'
	} else {
		'Folder selection cancelled.'
	}
}

fn main() {
	mut app := FileDialogDemo{}
	ui2.run_compiled_vml[FileDialogDemo](
		build:  build_file_dialog
		model:  &app
		title:  'Native file dialog'
		width:  file_dialog_width
		height: file_dialog_height
	) or { panic(err) }
}

fn build_file_dialog(mut app FileDialogDemo) ui2.Element {
	return $vml('file_dialog.vml')
}

fn file_dialog_tree(mut app FileDialogDemo, frame ui2.Rect) ui2.Element {
	return $vml('file_dialog.vml', frame)
}
