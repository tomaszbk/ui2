module main

import os
import ui2.vml

fn compiled_diagnostic(source string, index int) !string {
	directory := os.join_path(os.temp_dir(), 'ui2-vml-diagnostics-${os.getpid()}', index.str())
	os.mkdir_all(directory)!
	defer { os.rmdir_all(directory) or {} }
	mut document := source
	if source.starts_with('component Item(') {
		boundary := source.last_index(' Screen ') or { panic('missing contract instance') }
		os.write_file(os.join_path(directory, 'item.vml'), source[..boundary])!
		document = source[boundary + 1..]
	}
	invalid_path := os.join_path(directory, 'invalid.vml')
	os.write_file(invalid_path, document)!
	// Language errors are the generator's; type errors are V's in the
	// generated builder, mapped to the document by its `#line` directives.
	vml.write_generated(invalid_path, vml.GenConfig{ module: 'main', dir: directory }, '') or {
		assert index != -1, err.msg()
		assert err.msg().contains('invalid.vml') || err.msg().contains('item.vml'), err.msg()
		return err.msg()
	}
	generated := os.read_file(os.join_path(directory, 'invalid_vml.v'))!
	call := if generated.contains('invalid_vml[A](mut app A)') { 'invalid_vml(mut app)' } else { 'invalid_vml()' }
	main_path := os.join_path(directory, 'main.v')
	os.write_file(main_path, 'module main\nimport ui2\npub struct App {\npub:\n readonly_text string\npub mut:\n count int\n name string\n checked bool\n level f64\n rows []int\n string_offset string\n bool_offset bool\n}\npub fn (mut app App) action() {}\nfn wrong_payload(value int) {}\nfn wrong_return() int { return 1 }\nfn main() { mut app := &App{} _ = app _ = ${call} }\n')!
	module_path := [os.dir(@VMODROOT), '@vlib', '@vmodules'].join(os.path_delimiter)
	result := os.exec([@VEXE, '-b', 'c', '-path', module_path, '-d', 'ui2_custom_rendering', '-o',
		os.join_path(directory, 'invalid'), directory])
	if index == -1 {
		assert result.exit_code == 0, result.output
		return result.output
	}
	assert result.exit_code != 0, 'invalid VML compiled: ${source}'
	assert result.output.contains('invalid.vml') || result.output.contains('item.vml'), result.output
	return result.output
}

fn test_compiled_vml_diagnoses_removed_syntax_and_invalid_types_at_source() {
	compiled_diagnostic('Screen { Label(text: app.count, style: [text_align(right)]) TextInput(bind.text: app.name) TextArea { Run(text: "rich") } Button(text: "Add", on_click: app.action()) }', -1)!
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
		'Column { for item in [1, 2] key item { View(x: 2) } }',
		'Label(style: [text_align(.right)])',
		'Label(style: [text_align("right")])',
		'Label(style: [text_align(app.name)])',
		'Label(id: "quoted")',
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
		'Checkbox(bind.checked: app.name)',
		'Slider(bind.value: app.name)',
		'Button(on_click: app.unknown())',
		'Button(on_click: app.action(1))',
		'Button(on_click: wrong_payload)',
		'Button(on_click: wrong_return)',
		'Button(on_click: "save")',
		'Button(on_click: true)',
		'Label(text: app.unknown)',
		'Label(style: [font_size(true)])',
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
		'Column { for row in app.rows key row { View(x: 2) } }',
	] {
		compiled_diagnostic(source, index)!
	}
}

// Each tag is a props type of ui2, so V checks element names, property names
// and value types; positions are checked against the parent, the document
// included. Literal ranges, part placement, layout reads of an ancestor's
// geometry and properties inside interaction patches are not compile-time
// checks of the generic lowering.
fn test_compiled_vml_checks_props_types_at_source() {
	for index, source in [
		'Label(tracking: 2)',
		'Label(style: [tabular_figures(false ? true : 1)])',
		'Label(text: true)',
		'TextInput(placeholder: 123)',
		'View(opacity: "0.5")',
		'View(opacity: true)',
		'Dialog(open: 1)',
		'Dialog(owner: 1)',
		'Popover(anchor: true)',
		'Dialog(dismiss_on_escape: "yes")',
		'Dialog(tooltip_delay: "slow")',
		'Dialog(placement: "top")',
		'Dialog(placement: .top)',
		'Popup {}',
		'ModalView {}',
		'Label(overlay: 1)',
		'Column { Label { View() } }',
	] {
		compiled_diagnostic(source, 300 + index)!
	}
}

fn test_component_contract_rejects_unknown_inputs_readonly_writes_and_bad_events() {
	compiled_diagnostic('component Item(title string) { Label(text: title) } Screen { Item(title: "valid") }', -1)!
	for index, source in [
		'component Item(title string) { Label(text: title) } Screen { Item(unknown: "x") }',
		'component Item(title string) { Label(text: title) } Screen { Item {} }',
		'component Item(title string) { Button(on_click: title = "x") } Screen { Item(title: "a") }',
		'component Item() { state count := 0 computed doubled := count * 2 Button(on_click: doubled = 4) } Screen { Item {} }',
		'component Item(changed event(value int)) { Button(on_click: changed("wrong")) } Screen { Item {} }',
		'component Item(changed event(value int)) { Button(on_click: changed(true)) } Screen { Item {} }',
		'component Item(changed event(value int)) { Button(on_click: changed(1)) } Screen { Item(on_changed: "changed") }',
		'component Item(title string) { Label(id: title, text: title) } Screen { Item(title: "a") }',
		'component Item(title string) { state title := "other" Label(text: title) } Screen { Item(title: "a") }',
		'component Item(title string) { TextInput(bind.text: title) } Screen { Item(bind.title: app.name) }',
		'component Item(bind title string) { TextInput(bind.text: title) } Screen { Item(bind.title: app.count * 2) }',
		'component Item(changed event(value string)) { Button(on_click: changed("x")) } Screen { Item(on_changed: wrong_payload) }',
		'component Item() { state count := 0 computed bad := app.action() Label(text: bad) } Screen { Item {} }',
		'component Item() { Column { Label(id: input, text: "wrong kind") Button(on_click: input.set_text("x")) } } Screen { Item {} }',
		'component Item() { Column { TextInput(id: input) Label(text: input) Button(on_click: input.focus()) } } Screen { Item {} }',
		'component Item() { Column { for item in app.rows key item { TextInput(id: input) } Button(on_click: input.focus()) } } Screen { Item {} }',
		'component Item(title string) { fn reset(title int) {} Label(text: title) } Screen { Item(title: "x") }',
		'component Item(visible bool) { View(width: visible) } Screen { Item(visible: false) }',
		'component Item() { state checked := false View(width: checked) } Screen { Item {} }',
		'component Item() { computed checked := app.checked View(width: checked) } Screen { Item {} }',
		'component Item() { state label := "12" View(width: label) } Screen { Item {} }',
	] {
		compiled_diagnostic(source, 100 + index)!
	}
}

fn test_style_contract_rejects_aliases_cycles_collisions_and_wrong_value_types() {
	compiled_diagnostic('style card = [background(color.surface), padding(12), radius(8)] View(style: [card, background(color.accent)]) { Label(text: "Content") }', -1)!
	for index, source in [
		'View(background: #ffffff)',
		'View(bg: #ffffff)',
		'Label(color: #000000)',
		'TextInput(pad_left: 0)',
		'View(style: [bg(#ffffff)])',
		'View(style: [padding("12")])',
		'View(style: [radius(true)])',
		'Label(style: [weight("bold")])',
		'Label(style: [foreground(app.name)])',
		'View(style: [app.name])',
		'style first = [second] style second = [first] View(style: [first])',
		'style card = [radius(8)] style card = [radius(4)] View(style: [card])',
		'style card = [radius(8)] View(id: card, style: [card])',
		'component Item(title string) { style title = [radius(8)] View(style: [title]) } Screen { Item(title: "x") }',
	] {
		compiled_diagnostic(source, 200 + index)!
	}
}
