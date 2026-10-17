module ui2

// The interpreter registry fragment of the kit's actions: buttons, icons,
// choice controls and inputs, with the legacy tags they replace. A tag is one
// line here; the registry test checks the bindable fields and part-only tags
// listed below against the props types.

fn kit_actions_widgets() map[string]VmlWidgetType {
	return {
		'Button':       vml_widget[ButtonProps]()
		'Icon':         vml_widget[IconProps]()
		'TextInput':    vml_widget[TextInputProps]()
		'TextArea':     vml_widget[TextAreaProps]()
		'Checkbox':     vml_widget[CheckboxProps]()
		'Slider':       vml_widget[SliderProps]()
		'Switch':       vml_widget[SwitchProps]()
		'ToggleButton': vml_widget[ToggleButtonProps]()
	}
}

// kit_actions_expected_bindables are the fragment's bindable properties,
// `Tag.field`, which the registry test checks.
fn kit_actions_expected_bindables() []string {
	return ['Checkbox.checked', 'Slider.value', 'Switch.active', 'TextArea.text', 'TextInput.text',
		'ToggleButton.pressed']
}

// kit_actions_expected_parts are the fragment's part-only tags, which take no
// common properties.
fn kit_actions_expected_parts() []string {
	return []
}
