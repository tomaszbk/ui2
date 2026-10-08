module ui2

import os

// FilePickerConfig configures the in-window picker. It uses the same modes and
// filters as the synchronous platform dialogs, but never starts another process.
pub struct FilePickerConfig {
pub:
	id          string = 'file_picker'
	dialog      FileDialogConfig
	show_hidden bool
	on_result   fn (FilePickerResult) = unsafe { nil }
}

pub struct FilePickerEntry {
pub:
	name      string
	path      string
	directory bool
}

pub enum FilePickerResultKind {
	selected
	cancelled
}

pub struct FilePickerResult {
pub:
	kind  FilePickerResultKind
	paths []string
}

// FilePicker owns directory and selection state. Keep it alive between builds,
// add render() as the last child of a screen. Controls carry their callbacks.
@[heap]
pub struct FilePicker {
pub:
	config FilePickerConfig
pub mut:
	directory  string
	path_input string
	entries    []FilePickerEntry
	selected   []string
	filename   string
	status     string
	visible    bool
	// The first Save on an existing file requests confirmation. A second Save
	// on that same path accepts it.
	overwrite_path string
}

pub fn new_file_picker(config FilePickerConfig) !&FilePicker {
	if config.id.len == 0 {
		return error('file picker id cannot be empty')
	}
	mut picker := &FilePicker{
		config:   config
		filename: config.dialog.filename
	}
	start := if config.dialog.directory.len > 0 { config.dialog.directory } else { os.getwd() }
	picker.load_directory(start)!
	return picker
}

// open refreshes the directory before showing the picker. It returns an error
// if the location is no longer readable, leaving the previous state intact.
pub fn (mut picker FilePicker) open() ! {
	picker.load_directory(picker.directory)!
	picker.visible = true
}

pub fn (mut picker FilePicker) load_directory(path string) ! {
	absolute_path := os.abs_path(path)
	if !os.is_dir(absolute_path) {
		return error('not a directory: ${absolute_path}')
	}
	real := os.real_path(absolute_path)
	mut names := os.ls(real)!
	names.sort()
	mut entries := []FilePickerEntry{}
	for want_directory in [true, false] {
		for name in names {
			if !picker.config.show_hidden && name.starts_with('.') {
				continue
			}
			full_path := os.join_path(real, name)
			is_directory := os.is_dir(full_path)
			if is_directory != want_directory {
				continue
			}
			if !is_directory {
				if picker.config.dialog.kind == .folder
					|| !file_picker_matches_filter(name, picker.config.dialog.filters) {
					continue
				}
			}
			entries << FilePickerEntry{
				name:      name
				path:      full_path
				directory: is_directory
			}
		}
	}
	picker.directory = real
	picker.path_input = real
	picker.entries = entries
	picker.selected = []string{}
	picker.status = ''
	picker.overwrite_path = ''
}

fn file_picker_matches_filter(name string, filters []FileDialogFilter) bool {
	if filters.len == 0 {
		return true
	}
	for filter in filters {
		for extension in filter.extensions {
			if extension.trim_space() in ['*', '*.*'] {
				return true
			}
		}
	}
	extensions := file_dialog_extensions(filters)
	if extensions.len == 0 {
		return true
	}
	lower := name.to_lower()
	for extension in extensions {
		if lower.ends_with('.' + extension.to_lower()) {
			return true
		}
	}
	return false
}

pub fn (mut picker FilePicker) select_entry(index int) ! {
	if index < 0 || index >= picker.entries.len {
		return error('file picker entry is out of range')
	}
	entry := picker.entries[index]
	if entry.directory {
		picker.load_directory(entry.path)!
		return
	}
	if picker.config.dialog.kind == .folder {
		return
	}
	if picker.config.dialog.kind == .save {
		picker.filename = entry.name
		picker.selected = [entry.path]
		picker.overwrite_path = ''
		return
	}
	if picker.config.dialog.multiple {
		for selected_index, path in picker.selected {
			if path == entry.path {
				picker.selected.delete(selected_index)
				return
			}
		}
		picker.selected << entry.path
	} else {
		picker.selected = [entry.path]
	}
}

// accept validates the current choice and returns absolute_path paths. A save
// destination may be new; an existing directory is never accepted as a file.
pub fn (mut picker FilePicker) accept() ![]string {
	match picker.config.dialog.kind {
		.folder { return [picker.directory] }
		.open {
			if picker.selected.len == 0 {
				return error('Select a file first.')
			}
			for path in picker.selected {
				if !os.is_file(path) {
					return error('Selected file is no longer available: ${path}')
				}
			}
			return picker.selected.clone()
		}
		.save {
			name := picker.filename.trim_space()
			if name.len == 0 || name == '.' || name == '..' || name.contains('/')
				|| name.contains('\\') {
				return error('Enter a filename without path separators.')
			}
			path := os.join_path(picker.directory, name)
			if os.is_dir(path) {
				return error('The destination is a directory.')
			}
			return [path]
		}
	}
}

fn (mut picker FilePicker) finish_selection() {
	if !picker.visible { return }
	paths := picker.accept() or {
		picker.status = err.msg()
		return
	}
	if picker.config.dialog.kind == .save && os.exists(paths[0]) && picker.overwrite_path != paths[0] {
		picker.overwrite_path = paths[0]
		picker.status = 'File exists. Press Save again to replace it.'
		return
	}
	picker.visible = false
	if voidptr(picker.config.on_result) != unsafe { nil } {
		picker.config.on_result(FilePickerResult{ kind: .selected, paths: paths })
	}
}

fn (mut picker FilePicker) cancel_selection() {
	if !picker.visible { return }
	picker.visible = false
	if voidptr(picker.config.on_result) != unsafe { nil } {
		picker.config.on_result(FilePickerResult{ kind: .cancelled })
	}
}

fn (mut picker FilePicker) navigate_input(value string) {
	path := if os.is_abs_path(value) { value } else { os.join_path(picker.directory, value) }
	picker.load_directory(path) or { picker.status = err.msg() }
}

pub fn (picker &FilePicker) path_id() string {
	return picker.config.id + '__path'
}

pub fn (picker &FilePicker) filename_id() string {
	return picker.config.id + '__filename'
}

// render builds a modal picker inside the supplied screen bounds. The picker
// works with the custom renderer and with native ui2 controls.
pub fn (mut picker FilePicker) render(frame Rect) Element {
	mut width := frame.width - 32
	if width > 720 { width = 720 }
	if width < 0 { width = 0 }
	mut height := frame.height - 32
	if height > 560 { height = 560 }
	if height < 0 { height = 0 }
	left := (frame.width - width) / 2
	top := (frame.height - height) / 2
	padding := f64(16)
	inner_width := if width > padding * 2 { width - padding * 2 } else { 0.0 }
	button_width := f64(72)
	button_height := f64(32)
	mut children := []Element{}
	title := if picker.config.dialog.title.len > 0 {
		picker.config.dialog.title
	} else {
		match picker.config.dialog.kind {
			.open { 'Open file' }
			.save { 'Save file' }
			.folder { 'Choose folder' }
		}
	}
	children << label(picker.config.id + '__title', title, rect(padding, 12, inner_width, 28),
		TextStyle{ size: 19, bold: true, color: 0x111827 })
	children << with_event(button(picker.config.id + '__up', 'Up', rect(padding, 52, 56, button_height),
		BoxStyle{ bg: 0xe2e8f0, radius: 5 }, TextStyle{ color: 0x1e293b }), fn [mut picker] (event ElementEvent) {
		if event.kind == .tap {
			picker.load_directory(os.dir(picker.directory)) or { picker.status = err.msg() }
		}
	})
	children << with_event(button(picker.config.id + '__home', 'Home', rect(padding + 64, 52, 64,
		button_height), BoxStyle{ bg: 0xe2e8f0, radius: 5 }, TextStyle{ color: 0x1e293b }), fn [mut picker] (event ElementEvent) {
		if event.kind == .tap {
			picker.load_directory(os.home_dir()) or { picker.status = err.msg() }
		}
	})
	path_width := if inner_width > 202 { inner_width - 202 } else { 0.0 }
	children << text_input(TextInputConfig{
		id:          picker.path_id()
		placeholder: 'Directory'
		text:        picker.path_input
		multiline:   false
		frame:       rect(padding + 136, 52, path_width, button_height)
		box:         BoxStyle{ bg: 0xffffff, border_color: 0xcbd5e1, border_left: 1, border_top: 1, border_right: 1, border_bottom: 1 }
		text_style:  TextStyle{ color: 0x111827, size: 13 }
		on_event:    fn [mut picker] (event ElementEvent) {
			match event.kind {
				.change { picker.path_input = event.text }
				.submit { picker.navigate_input(event.text) }
				else {}
			}
		}
	}) or { panic(err) }
	children << with_event(button(picker.config.id + '__go', 'Go', rect(width - padding - 58, 52, 58,
		button_height), BoxStyle{ bg: 0xe2e8f0, radius: 5 }, TextStyle{ color: 0x1e293b }), fn [mut picker] (event ElementEvent) {
		if event.kind == .tap { picker.navigate_input(picker.path_input) }
	})
	list_top := f64(96)
	footer_height := if picker.config.dialog.kind == .save { f64(132) } else { f64(92) }
	list_height := if height > list_top + footer_height {
		height - list_top - footer_height
	} else {
		0.0
	}
	mut rows := []Element{}
	for index, entry in picker.entries {
		mut selected := false
		for path in picker.selected {
			if path == entry.path {
				selected = true
				break
			}
		}
		row_color := if selected {
			u32(0xbfdbfe)
		} else if index % 2 == 0 {
			u32(0xffffff)
		} else {
			u32(0xf8fafc)
		}
		prefix := if entry.directory { '[DIR] ' } else { '      ' }
		rows << Element{
			...with_event(button('${picker.config.id}__entry_${index}', prefix + entry.name,
				rect(0, f64(index) * 34, inner_width, 34), BoxStyle{ bg: row_color },
				TextStyle{ color: 0x111827, size: 14, align: .left }), fn [mut picker, entry] (event ElementEvent) {
				if event.kind != .tap || !picker.visible { return }
				for current_index, current in picker.entries {
					if current.path == entry.path {
						picker.select_entry(current_index) or { picker.status = err.msg() }
						return
					}
				}
			})
			accessibility_role:  'listitem'
			accessibility_label: entry.name
			accessibility_value: if selected { 'selected' } else { '' }
		}
	}
	children << scroll(picker.config.id + '__list', rect(padding, list_top, inner_width,
		list_height), 0xffffff, rows)
	if picker.config.dialog.kind == .save {
		children << label(picker.config.id + '__filename_label', 'File name',
			rect(padding, height - 120, 90, 32), TextStyle{ color: 0x334155 })
		children << text_input(TextInputConfig{
			id:          picker.filename_id()
			placeholder: 'File name'
			text:        picker.filename
			multiline:   false
			frame:       rect(padding + 94, height - 120, inner_width - 94, 32)
			box:         BoxStyle{ bg: 0xffffff, border_color: 0xcbd5e1, border_left: 1, border_top: 1, border_right: 1, border_bottom: 1 }
			text_style:  TextStyle{ color: 0x111827 }
			on_event:    fn [mut picker] (event ElementEvent) {
				match event.kind {
					.change {
						picker.filename = event.text
						picker.overwrite_path = ''
						picker.status = ''
					}
					.submit {
						picker.filename = event.text
						picker.finish_selection()
					}
					else {}
				}
			}
		}) or { panic(err) }
	}
	children << label(picker.config.id + '__status', picker.status,
		rect(padding, height - 80, inner_width - 180, 28), TextStyle{ color: 0xb91c1c, size: 12 })
	children << with_event(button(picker.config.id + '__cancel', 'Cancel',
		rect(width - padding - button_width * 2 - 8, height - 56, button_width,
			button_height), BoxStyle{ bg: 0xe2e8f0, radius: 5 }, TextStyle{ color: 0x1e293b }), fn [mut picker] (event ElementEvent) {
		if event.kind == .tap { picker.cancel_selection() }
	})
	accept_title := if picker.config.dialog.kind == .save {
		'Save'
	} else if picker.config.dialog.kind == .folder {
		'Choose'
	} else {
		'Open'
	}
	children << with_event(button(picker.config.id + '__accept', accept_title,
		rect(width - padding - button_width, height - 56, button_width, button_height),
		BoxStyle{ bg: 0x2563eb, radius: 5 }, TextStyle{ color: 0xffffff }), fn [mut picker] (event ElementEvent) {
		if event.kind == .tap { picker.finish_selection() }
	})
	panel := view(picker.config.id + '__panel', rect(left, top, width, height),
		BoxStyle{ bg: 0xffffff, radius: 10 }, children)
	return Element{
		...clickable_view(picker.config.id, frame, BoxStyle{ bg: 0x94a3b8 }, [panel])
		hidden: !picker.visible
	}
}
