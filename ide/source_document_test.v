module main

fn test_designer_projects_named_arguments_with_strings_comments_and_fractional_geometry() {
	source := '// before root\nScreen(id: "MyForm", width: 320.5, height: 240, background: #123ABC) { Absolute {\n// before child\nLabel(id: "caption", text: "Hola ñ, \\"quoted\\"\\nnext", x: 1.25, y: 2.5, width: 30, height: 40)\n} }'
	document := document_from_vml(source)!
	assert document.form_name == 'MyForm'
	assert document.form_width == 320.5
	assert document.form_background == 0x123abc
	assert document.components[0].text == 'Hola ñ, "quoted"\nnext'
	assert document.components[0].x == 1.25
	assert document.components[0].y == 2.5
}

fn test_designer_refuses_lossy_dynamic_unknown_and_duplicate_arguments() {
	for source in [
		'Screen(width: 300, width: 400) { Absolute {} }',
		'Screen(adaptive: true) { Absolute {} }',
		'Screen { Absolute { Label(id: "title", text: "\${app.title}") } }',
		'Screen { Absolute { Button(id: "run", on_tap: app.run()) } }',
		'Screen { Absolute { Label(id: "a", x: app.offset) } }',
		'Screen { id: "old" Absolute {} }',
		'Screen { Absolute { TextInput(multiline: false) } }',
	] {
		if _ := document_from_vml(source) {
			assert false, source
		}
	}
}

fn test_designer_round_trips_distinct_text_input_and_text_area_controls() {
	source := 'Screen { Absolute { TextInput(id: "name", placeholder: "Name") TextArea(id: "notes", text: "One\\nTwo") } }'
	document := document_from_vml(source)!
	assert document.components.map(it.kind) == ['text_field', 'text_area']
	assert component_vml(document.components[0]).trim_space().starts_with('TextInput(')
	assert component_vml(document.components[1]).trim_space().starts_with('TextArea(')
	assert document.components[1].text == 'One\nTwo'
}
