module ui2

import os

fn test_linux_dialogs_pass_literal_arguments_and_preserve_results() {
	root := os.join_path(os.vtmp_dir(), 'ui2_dialog_argv_${os.getpid()}')
	os.mkdir_all(root)!
	defer { os.rmdir_all(root) or {} }
	trace := os.join_path(root, 'arguments')
	for tool in ['zenity', 'kdialog'] {
		path := os.join_path(root, tool)
		os.write_file(path, r'#!/bin/sh
printf "%s\000" "$@" > "$UI2_DIALOG_TRACE"
printf "%s" "$UI2_DIALOG_OUTPUT"
exit "$UI2_DIALOG_STATUS"
')!
		os.chmod(path, 0o755)!
	}
	variables := ['PATH', 'DISPLAY', 'WAYLAND_DISPLAY', 'XDG_CURRENT_DESKTOP', 'UI2_DIALOG_TRACE',
		'UI2_DIALOG_OUTPUT', 'UI2_DIALOG_STATUS']
	previous := variables.map(os.getenv(it))
	defer {
		for i, name in variables {
			os.setenv(name, previous[i], true)
		}
	}
	os.setenv('PATH', root, true)
	os.setenv('DISPLAY', ':fixture', true)
	os.setenv('WAYLAND_DISPLAY', '', true)
	os.setenv('UI2_DIALOG_TRACE', trace, true)
	os.setenv('UI2_DIALOG_OUTPUT', '', true)
	os.setenv('UI2_DIALOG_STATUS', '0', true)
	title := r'Quotes "double"; $(echo wrong) `echo wrong` & | * ' + "'single'"
	text := 'First line\nSecond line with spaces and "quotes"'
	cfg := MessageBoxConfig{
		title:   title
		text:    text
		buttons: .yes_no_cancel
	}
	os.setenv('XDG_CURRENT_DESKTOP', 'GNOME', true)
	assert native_message_box(cfg) == .yes
	assert linux_dialog_test_arguments(trace) == ['--question', '--title=' + title,
		'--text=' + title + '\n\n' + text, '--ok-label=Yes', '--cancel-label=Cancel',
		'--extra-button=No']
	os.setenv('UI2_DIALOG_STATUS', '1', true)
	os.setenv('UI2_DIALOG_OUTPUT', 'No\n', true)
	assert native_message_box(cfg) == .no
	os.setenv('UI2_DIALOG_OUTPUT', '', true)
	assert native_message_box(cfg) == .cancel

	os.setenv('XDG_CURRENT_DESKTOP', 'KDE', true)
	for status, expected in [MessageBoxResult.yes, .no, .cancel] {
		os.setenv('UI2_DIALOG_STATUS', status.str(), true)
		assert native_message_box(cfg) == expected
		assert linux_dialog_test_arguments(trace) == ['--title', title, '--yesnocancel',
			title + '\n\n' + text, '--yes-label', 'Yes', '--no-label', 'No', '--cancel-label',
			'Cancel']
	}
	for i, buttons in [MessageBoxButtons.ok, .ok_cancel, .yes_no, .retry_cancel] {
		for desktop in ['GNOME', 'KDE'] {
			os.setenv('XDG_CURRENT_DESKTOP', desktop, true)
			os.setenv('UI2_DIALOG_STATUS', '1', true)
			assert native_message_box(MessageBoxConfig{ buttons: buttons }) == [
				MessageBoxResult.ok,
				.cancel,
				.no,
				.cancel,
			][i]
		}
	}
	os.setenv('UI2_DIALOG_STATUS', '0', true)
	for i, style in [MessageBoxStyle.info, .warning, .error, .question] {
		os.setenv('XDG_CURRENT_DESKTOP', 'KDE', true)
		assert native_message_box(MessageBoxConfig{ style: style }) == .ok
		assert linux_dialog_test_arguments(trace) == ['--title', '',
			['--msgbox', '--sorry', '--error', '--msgbox'][i], '']
		os.setenv('XDG_CURRENT_DESKTOP', 'GNOME', true)
		assert native_message_box(MessageBoxConfig{ style: style }) == .ok
		assert linux_dialog_test_arguments(trace) == [
			['--info', '--warning', '--error', '--question'][i],
			'--title=',
			'--text=',
			'--ok-label=OK',
		]
	}

	selected := [root + '/one "quoted"; file.txt', root + "/two 'quoted' & file.md"]
	os.setenv('UI2_DIALOG_OUTPUT', selected.join('\r\n') + '\r\n', true)
	file_cfg := FileDialogConfig{
		title:     title
		directory: root + "/a 'quoted' directory; &"
		filename:  'draft "name".txt'
		multiple:  true
		filters:   [FileDialogFilter{ name: 'Text "files"; |', extensions: ['txt', '.md', '*.txt'] }]
	}
	start := file_cfg.directory + '/' + file_cfg.filename
	for desktop in ['GNOME', 'KDE'] {
		os.setenv('XDG_CURRENT_DESKTOP', desktop, true)
		os.setenv('UI2_DIALOG_OUTPUT', selected.join('\r\n') + '\r\n', true)
		assert native_file_dialog(file_cfg) == selected
		if desktop == 'GNOME' {
			assert linux_dialog_test_arguments(trace) == ['--file-selection', '--multiple',
				'--separator=\n', '--title=' + title, '--filename=' + start,
				'--file-filter=Text "files"; | | *.txt *.md']
		} else {
			assert linux_dialog_test_arguments(trace) == ['--title', title, '--getopenfilename',
				start, '*.txt *.md|Text "files"; |', '--multiple', '--separate-output']
		}
		os.setenv('UI2_DIALOG_OUTPUT', selected[0] + '\n', true)
		assert native_file_dialog(save_file_dialog_config(file_cfg)) == [selected[0]]
		args := linux_dialog_test_arguments(trace)
		assert '--multiple' !in args
		assert if desktop == 'GNOME' {
			'--save' in args && '--confirm-overwrite' in args
		} else {
			'--getsavefilename' in args
		}
		assert native_file_dialog(open_folder_dialog_config(file_cfg)) == [selected[0]]
		folder_args := linux_dialog_test_arguments(trace)
		assert '--multiple' !in folder_args
		assert if desktop == 'GNOME' {
			'--directory' in folder_args && !folder_args.any(it.starts_with('--file-filter='))
		} else {
			folder_args == ['--title', title, '--getexistingdirectory', file_cfg.directory]
		}
		os.setenv('UI2_DIALOG_STATUS', '1', true)
		assert native_file_dialog(file_cfg).len == 0
		os.setenv('UI2_DIALOG_STATUS', '0', true)
	}
}

fn linux_dialog_test_arguments(path string) []string {
	output := os.read_file(path) or { panic(err) }
	assert output.ends_with('\x00')
	return output[..output.len - 1].split('\x00')
}
