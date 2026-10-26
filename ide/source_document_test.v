// vtest vflags: -d vml_interpreter
module main

fn test_designer_projects_named_arguments_with_strings_comments_and_fractional_geometry() {
	source := '// before root\nScreen(id: MyForm, width: 320.5, height: 240, style: [background(#123ABC)]) { Absolute {\n// before child\nLabel(id: caption, text: "Hola ñ, \\"quoted\\"\\nnext", x: 1.25, y: 2.5, width: 30, height: 40)\n} }'
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
		'Screen { Absolute { Label(id: title, text: "\${app.title}") } }',
		'Screen { Absolute { Button(id: run, on_click: app.run()) } }',
		'Screen { Absolute { Label(id: a, x: app.offset) } }',
		'Screen { id: old Absolute {} }',
		'Screen { Absolute { TextInput(multiline: false) } }',
		'Screen(background: #123ABC) { Absolute {} }',
		'Screen { Absolute { Label(font_size: 18) } }',
		'Screen { Absolute { Label(style: [foreground(app.color)]) } }',
		'Screen { Absolute { Label(style: [caption]) } }',
		'Screen { Absolute { Button(style: [hover([background(#000000)])]) } }',
		'Screen { Absolute { Label(style: [background(#000000)]) } }',
	] {
		if _ := document_from_vml(source) {
			assert false, source
		}
	}
}

fn test_designer_styles_compose_literals_and_preserve_explicit_zero_values() {
	source := 'Screen(style: [background(#FFFFFF), background(#000000)]) { Absolute { Button(id: save, style: [background(#123ABC), foreground(#000000), font_size(18.25), radius(8), radius(0)]) } }'
	document := document_from_vml(source)!
	assert document.form_background == 0
	assert document.components[0].background == 0x123abc
	assert document.components[0].color == 0
	assert document.components[0].font_size == 18.25
	assert document.components[0].radius? == 0
	mut app := new_ide_app('.')
	app.restore(document)
	assert app.source_text.contains('style: [background(#000000)]')
	assert app.source_text.contains('foreground(#000000), font_size(18.25)'), app.source_text
	round_trip := document_from_vml(app.source_text)!
	assert round_trip.components == document.components
	assert round_trip.form_background == document.form_background
}

fn test_designer_round_trips_distinct_text_input_and_text_area_controls() {
	source := 'Screen { Absolute { TextInput(id: name, placeholder: "Name") TextArea(id: notes, text: "One\\nTwo") } }'
	document := document_from_vml(source)!
	assert document.components.map(it.kind) == ['text_field', 'text_area']
	assert component_vml(document.components[0]).trim_space().starts_with('TextInput(')
	assert component_vml(document.components[1]).trim_space().starts_with('TextArea(')
	assert document.components[1].text == 'One\nTwo'
}
