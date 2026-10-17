// vtest vflags: -d vml_props
module ui2

// Golden equivalence of the control props (Label, Run, TextInput, TextArea,
// Image, Button, Checkbox, Dropdown, Option, Progress, Slider, Switch,
// ToggleButton, MessageBox) with the compiled lowering, including event
// dispatch.

fn props_controls_compiled(mut app PropsApp, frame Rect) Element {
	return $vml('fixtures/props_controls.vml', frame)
}

fn props_controls_tree(mut app PropsApp) PNode {
	return pn(ScreenProps{},
		id:       'root'
		children: [
			pn(ColumnProps{ gap: 4 },
				id:       'controls'
				children: [
					pn(LabelProps{ text: 'Plain', height: 20 }, id: 'plain_label'),
					pn(LabelProps{
						text:   app.count
						height: 20
						style:  style_list([style_foreground(0x334155), style_font_size(15)])
					}, id: 'number_label'),
					pn(LabelProps{
						height: 40
						style:  style_list([style_font_size(16), style_foreground(0x111111)])
					},
						id:       'rich'
						children: [
							pn(RunProps{ text: 'Bold ', style: style_list([style_weight(700)]) }),
							pn(RunProps{ text: app.name }),
							pn(RunProps{
								text:  ' end'
								style: style_list([
									style_font_size(12),
									style_foreground(0xFF0000),
								])
							}),
						]
					),
					pn(TextInputProps{
						text:        app.name
						placeholder: 'Name'
						height:      30
						on_change:   fn [mut app] (e ElementEvent) {
							app.name = e.text
						}
						on_submit:   props_hit(mut app, 'submit')
					}, id: 'name', bind: true),
					pn(TextInputProps{
						text:        'pw'
						password:    true
						readonly:    true
						keyboard:    .decimal
						enabled:     false
						autocorrect: false
						height:      30
						style:       style_list([style_background(0xFFFFFF),
							style_foreground(0x111111)])
					}, id: 'secret'),
					pn(TextAreaProps{
						text:           app.notes
						placeholder:    'Notes'
						disable_scroll: true
						height:         60
						on_change:      fn [mut app] (e ElementEvent) {
							app.notes = e.text
						}
					}, id: 'notes', bind: true),
					pn(TextAreaProps{
						readonly: true
						keyboard: .decimal
						height:   40
						style:    style_list([style_font_size(13)])
					},
						id:       'rich_area'
						children: [
							pn(RunProps{ text: 'alpha ' }),
							pn(RunProps{ text: 'beta', style: style_list([style_italic(true)]) }),
						]
					),
					pn(ImageProps{ source: 'assets/logo.png', width: 32, height: 32 }, id: 'logo'),
					pn(ImageProps{ path: 'assets/old.png', width: 16, height: 16 }),
					pn(ButtonProps{
						text:     'Go'
						height:   30
						on_click: props_hit(mut app, 'go')
						style:    style_list([style_background(0x2563EB), style_foreground(0xFFFFFF),
							style_radius(6)])
					}, id: 'go'),
					pn(ButtonProps{ height: 40 },
						id:       'rich_button'
						children: [
							pn(LabelProps{ text: 'Inside', width: 60, height: 20 }),
						]
					),
					pn(CheckboxProps{
						text:      'Agree'
						checked:   app.agree
						height:    24
						on_change: fn [mut app] (e ElementEvent) {
							app.agree = e.checked
						}
					}, id: 'agree', bind: true),
					pn(CheckboxProps{ text: 'Static', checked: true, height: 24 }),
					pn(DropdownProps{
						text:      app.color
						height:    30
						on_change: fn [mut app] (e ElementEvent) {
							app.color = e.text
							app.hit('color')
						}
					},
						id:       'color_pick'
						bind:     true
						children: [
							pn(OptionProps{ text: 'Red' }),
							pn(OptionProps{ text: 'Green' }),
						]
					),
					pn(ProgressProps{ value: 30, height: 10 }, id: 'progress'),
					pn(ProgressProps{
						value:  app.level
						max:    50
						height: 10
						tone:   .success
						style:  style_list([style_background(0x112233), style_radius(2)])
					}, id: 'styled_progress'),
					pn(SliderProps{
						value:     app.level
						height:    30
						on_change: fn [mut app] (e ElementEvent) {
							app.level = e.value
						}
					}, id: 'level', bind: true),
					pn(SliderProps{
						value:             5
						min:               -10
						max:               10
						step:              0.5
						orientation:       .vertical
						track_inset:       8
						value_track:       true
						value_track_color: 0xFF0000
						thumb_color:       0x00FF00
						track_width:       6
						thumb_size:        14
						width:             30
						height:            120
					}, id: 'custom_slider'),
					pn(SwitchProps{
						active:    app.dark
						on_active: fn [mut app] (e ElementEvent) {
							app.dark = e.checked
							app.hit('active')
						}
						on_change: props_hit(mut app, 'change')
					}, id: 'dark', bind: true),
					pn(SwitchProps{
						active:               true
						inactive_color:       0x111111
						active_color:         0x222222
						thumb_color:          0x333333
						disabled_track_color: 0x444444
						disabled_thumb_color: 0x555555
						enabled:              false
					}, id: 'custom_switch'),
					pn(ToggleButtonProps{
						text:               'Bold'
						pressed:            app.bold
						group:              'fmt'
						allow_no_selection: false
						down_background:    0x1D4ED8
						down_color:         0xFEFEFE
						down_corner_radius: 3
						height:             30
						on_change:          fn [mut app] (e ElementEvent) {
							app.bold = e.checked
						}
					}, id: 'bold', bind: true),
					pn(ToggleButtonProps{ text: 'Plain', height: 30 }),
					pn(MessageBoxProps{
						title:         'Hello'
						text:          'World'
						dialog_width:  280
						dialog_height: 140
						hidden:        app.msg_hidden
						height:        200
					},
						id:       'msg'
						children: [
							pn(ButtonProps{ text: 'OK', on_click: props_hit(mut app, 'ok') },
								id: 'ok'
							),
							pn(ButtonProps{ text: 'Cancel', on_click: props_hit(mut app, 'cancel') }),
						]
					),
					pn(MessageBoxProps{}, id: 'msg_default'),
				]
			),
		]
	)
}

fn test_props_controls_match_compiled_vml() {
	frame := rect(0, 0, 360, 1600)
	mut compiled_app := PropsApp{}
	mut props_app := PropsApp{}
	compiled := props_controls_compiled(mut compiled_app, frame)
	built := props_document(props_controls_tree(mut props_app), frame)!
	assert_props_equal('controls', compiled, built)
	assert_props_events(compiled, built, mut compiled_app, mut props_app)
}
