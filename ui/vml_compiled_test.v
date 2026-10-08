module ui2

pub struct CompiledVmlTestModel {
pub mut:
	checked   bool
	secondary bool
	level     f64
	selected  string
	source    string
}

pub fn (mut model CompiledVmlTestModel) select(value string) { model.selected = value }

fn test_compiled_callback_reads_argument_after_binding_write() {
	mut model := CompiledVmlTestModel{ source: 'before' }
	callback := compiled_vml_callback(mut model, CompiledVmlCallbackConfig{
		binding_property: 'text'
		binding_target:   'app.source'
		action_name:      'select'
		argument_path:    'app.source'
	})
	callback(ElementEvent{ kind: .change, text: 'after' })
	assert model.source == 'after'
	assert model.selected == 'after'
}

fn test_compiled_callback_carries_typed_action_data() {
	mut model := CompiledVmlTestModel{}
	callback := compiled_vml_callback(mut model, CompiledVmlCallbackConfig{
		binding_property: 'checked'
		binding_target:   'app.checked'
		action_name:      'select'
		arguments:        [CompiledVmlArgument('Привет')]
	})
	callback(ElementEvent{ kind: .change, checked: true })
	assert model.checked
	assert model.selected == 'Привет'
}

fn test_compiled_callback_uses_numeric_and_boolean_payloads() {
	mut model := CompiledVmlTestModel{ checked: true, level: 12.5 }
	value := compiled_vml_callback(mut model, CompiledVmlCallbackConfig{
		binding_property: 'value'
		binding_target:   'app.level'
	})
	value(ElementEvent{ kind: .change, value: 72.5 })
	assert model.level == 72.5
	active := compiled_vml_callback(mut model, CompiledVmlCallbackConfig{
		binding_property: 'active'
		binding_target:   'app.checked'
	})
	active(ElementEvent{ kind: .change, checked: false })
	assert !model.checked
}

fn test_compiled_callback_captures_explicit_group_targets_without_global_registry() {
	mut model := CompiledVmlTestModel{ checked: true }
	select_right := compiled_vml_callback(mut model, CompiledVmlCallbackConfig{
		binding_property: 'pressed'
		binding_target:   'app.secondary'
		group_targets:    ['app.checked', 'app.secondary']
	})
	select_right(ElementEvent{ kind: .change, checked: true })
	assert !model.checked
	assert model.secondary
}

fn compiled_callback_test_build(mut model CompiledVmlTestModel) Element {
	return with_event(button('accept', 'Accept', rect(0, 0, 100, 32), BoxStyle{}, TextStyle{}),
		compiled_vml_callback(mut model, CompiledVmlCallbackConfig{
			binding_property: 'checked'
			binding_target:   'app.checked'
		}))
}

fn test_compiled_window_builder_callbacks_borrow_the_live_model() {
	mut controller := &CompiledVmlController[CompiledVmlTestModel]{ build: compiled_callback_test_build }
	mut runtime := compiled_vml_runtime()
	previous := runtime.controller
	runtime.controller = voidptr(controller)
	defer { runtime.controller = previous }
	root := compiled_vml_controller_build[CompiledVmlTestModel]()
	root.on_event(ElementEvent{ kind: .change, checked: true })
	assert controller.model.checked
}
