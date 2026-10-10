module main

import os

fn compiled_diagnostic(source string, index int) !string {
	directory := os.join_path(os.temp_dir(), 'ui2-vml-diagnostics-${os.getpid()}', index.str())
	os.mkdir_all(directory)!
	defer { os.rmdir_all(directory) or {} }
	mut document := source
	if source.starts_with('component Item(') {
		boundary := source.last_index(' Screen ') or { panic('missing contract instance') }
		os.write_file(os.join_path(directory, 'item.vml'), source[..boundary])!
		document = 'import Item\n' + source[boundary + 1..]
	}
	os.write_file(os.join_path(directory, 'invalid.vml'), document)!
	main_path := os.join_path(directory, 'main.v')
	os.write_file(main_path, 'module main\nimport ui2\npub struct App {\npub:\n readonly_text string\npub mut:\n count int\n name string\n checked bool\n level f64\n rows []int\n string_offset string\n bool_offset bool\n}\npub fn (mut app App) action() {}\nfn wrong_payload(value int) {}\nfn wrong_return() int { return 1 }\nfn main() { mut app := &App{} _ = \$vml("invalid.vml") }\n')!
	module_path := [os.dir(@VMODROOT), '@vlib', '@vmodules'].join(os.path_delimiter)
	result := os.exec([@VEXE, '-b', 'c', '-path', module_path, '-d', 'ui2_custom_rendering', '-o',
		os.join_path(directory, 'invalid'), main_path])
	if index == -1 {
		assert result.exit_code == 0, result.output
		return result.output
	}
	assert result.exit_code != 0, 'invalid VML compiled: ${source}'
	assert result.output.contains('invalid.vml') || result.output.contains('item.vml'), result.output
	return result.output
}

fn test_compiled_vml_diagnoses_removed_syntax_and_invalid_types_at_source() {
	compiled_diagnostic('Screen { Label(text: app.count, align: right) TextInput(bind.text: app.name) TextArea { Run(text: "rich") } Button(text: "Add", on_tap: app.action()) }', -1)!
	for index, source in [
		'Label { text: "former syntax" }',
		'Label(text: "bad", units: "logical")',
		'TextField {}',
		'TextInput(multiline: true)',
		'TextInput(multiline: false)',
		'TextArea(multiline: true)',
		'TextArea(password: true)',
		'TextArea(on_submit: app.action)',
		'ScrollView {}',
		'Rectangle {}',
		'BoxLayout {}',
		'GridLayout {}',
		'AnchorLayout {}',
		'FloatLayout {}',
		'RelativeLayout {}',
		'StackLayout {}',
		'PageLayout {}',
		'AdaptiveLayout {}',
		'FlexLayout {}',
		'LayoutVariation {}',
		'View(x: 0, y: 0)',
		'Column { View(width: app.count, x: 0) }',
		'Column { Repeater(model: [1, 2]) { View(x: 2) } }',
		'Label(align: .right)',
		'Label(align: "right")',
		'Label(align: app.name)',
		'Label(id: unquoted)',
		'View(adaptive: true)',
		'View(size_hint_x: 1)',
		'View(layout_x: end)',
		'View(pos_hint_center_x: 0.5)',
		'View(anchor_x: left)',
		'Label(width: "30")',
		'Label(width: true)',
		'Button(enabled: 1)',
		'TextInput(bind.text: app.count)',
		'TextInput(bind.text: app.readonly_text)',
		'TextInput(hint_text: "Name")',
		'TextInput(on_text: app.action)',
		'TextInput(on_text_validate: app.action)',
		'TextInput(editable: false)',
		'TextInput(emit_change: true)',
		'TextInput { Run(text: "rich") }',
		'Checkbox(bind.checked: app.name)',
		'Slider(bind.value: app.name)',
		'Button(on_tap: app.unknown())',
		'Button(on_tap: app.action(1))',
		'Button(on_tap: wrong_payload)',
		'Button(on_tap: wrong_return)',
		'Button(on_tap: "save")',
		'Button(on_tap: true)',
		'Label(text: app.unknown)',
		'Label(font_size: true)',
		'View(scale_x: 0)',
		'View(translate_x: "12")',
		'View(translate_y: true)',
		'View(translate_x: app.name)',
		'View(translate_x: app.checked)',
		'View(width: app.checked + 1)',
		'Label { Run(units: "logical", text: "bad") }',
		'Label(units: "legacy", text: "bad")',
		'Screen(units: "logical") { Label(text: "bad") }',
		'Label(text: "bad", units: "pixels")',
		'Label(units: "", text: "bad")',
		'View(x: 0)',
		'Screen { Label(y: 0) }',
		'Column { View(x: 12) }',
		'Stack { View(x: 1) }',
		'Grid(columns: 1) { View(y: 2) }',
		'Column { Repeater(model: app.rows) { View(x: 2) } }',
		'Screen(id: "root") { View(width: root.width - 32) }',
		'Column(id: "panel") { View(height: panel.height / 2) }',
		'Column(id: "root", gap: root.width / 10) { View() }',
		'Grid(id: "root", columns: 2, padding: root.height / 20) { View() }',
		'Row(id: "root") { View(min_width: root.width / 2) }',
	] {
		compiled_diagnostic(source, index)!
	}
}

fn test_component_contract_rejects_unknown_inputs_readonly_writes_and_bad_events() {
	compiled_diagnostic('component Item(title string) { Label(text: title) } Screen { Item(title: "valid") }', -1)!
	for index, source in [
		'component Item(title string) { Label(text: title) } Screen { Item(unknown: "x") }',
		'component Item(title string) { Label(text: title) } Screen { Item {} }',
		'component Item(title string) { Button(on_tap: title = "x") } Screen { Item(title: "a") }',
		'component Item() { state count := 0 computed doubled := count * 2 Button(on_tap: doubled = 4) } Screen { Item {} }',
		'component Item(changed event(value int)) { Button(on_tap: changed("wrong")) } Screen { Item {} }',
		'component Item(changed event(value int)) { Button(on_tap: changed(true)) } Screen { Item {} }',
		'component Item(changed event(value int)) { Button(on_tap: changed(1)) } Screen { Item(on_changed: "changed") }',
		'component Item(title string) { Label(id: "title", text: title) } Screen { Item(title: "a") }',
		'component Item(title string) { state title := "other" Label(text: title) } Screen { Item(title: "a") }',
		'component Item(title string) { TextInput(bind.text: title) } Screen { Item(bind.title: app.name) }',
		'component Item(bind title string) { TextInput(bind.text: title) } Screen { Item(bind.title: app.count * 2) }',
		'component Item(changed event(value string)) { Button(on_tap: changed("x")) } Screen { Item(on_changed: wrong_payload) }',
		'component Item() { state count := 0 computed bad := app.action() Label(text: bad) } Screen { Item {} }',
		'component Item() { ref input TextInput Label(ref: input, text: "wrong kind") } Screen { Item {} }',
		'component Item() { ref input TextInput Label(text: input) } Screen { Item {} }',
		'component Item() { ref input TextInput TextInput(bind.text: input) } Screen { Item {} }',
		'component Item(title string) { fn reset(title int) {} Label(text: title) } Screen { Item(title: "x") }',
		'component Item(visible bool) { View(width: visible) } Screen { Item(visible: false) }',
		'component Item() { state checked := false View(width: checked) } Screen { Item {} }',
		'component Item() { computed checked := app.checked View(width: checked) } Screen { Item {} }',
		'component Item() { state label := "12" View(width: label) } Screen { Item {} }',
	] {
		compiled_diagnostic(source, 100 + index)!
	}
}
