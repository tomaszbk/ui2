module ui2

// Compiled lowering passes typed declarations directly to callback factories.
// Event identity stays in Element.id and is never encoded into a routing string.
pub type CompiledVmlArgument = int | string

pub struct CompiledVmlCallbackConfig {
pub:
	binding_property string
	binding_target   string
	action_name      string
	arguments        []CompiledVmlArgument
	argument_path    string
	group_targets    []string
}

pub fn compiled_vml_callback[T](mut model T, config CompiledVmlCallbackConfig) ElementCallback {
	return fn [mut model, config] [T](event ElementEvent) {
		vml_apply_compiled_event[T](mut model, config, event) or {
			eprintln('ui2 compiled VML event failed: ${err}')
			return
		}
		request_refresh()
	}
}

fn vml_apply_compiled_event[T](mut model T, config CompiledVmlCallbackConfig, event ElementEvent) ! {
	if config.binding_property.len > 0 {
		value := match config.binding_property {
			'checked', 'active', 'pressed' { v_bool(event.checked) }
			'text' { v_string(event.text) }
			'value' { v_number(event.value, slider_number(event.value)) }
			else { return error('unsupported compiled VML binding `${config.binding_property}`') }
		}
		vml_set_field[T](mut model, config.binding_target.all_after('app.'), value)!
		if config.binding_property == 'pressed' && event.checked {
			for target in config.group_targets {
				if target != config.binding_target {
					vml_set_field[T](mut model, target.all_after('app.'), v_bool(false))!
				}
			}
		}
	}
	mut arguments := config.arguments.clone()
	if config.argument_path.len > 0 {
		argument := v_lookup({
			'app': v_value_from(model)
		}, config.argument_path, 0)!
		arguments = if argument.kind == .number {
			[CompiledVmlArgument(int(argument.numeric(0)!))]
		} else {
			[CompiledVmlArgument(argument.string_value())]
		}
	}
	if config.action_name.len > 0 {
		vml_dispatch_compiled[T](mut model, config.action_name, arguments)!
	}
}

fn vml_dispatch_compiled[T](mut model T, name string, arguments []CompiledVmlArgument) ! {
	$for method in T.methods {
		if method.name == name {
			$if method.is_pub && method.typ is fn ( ) {
				if arguments.len != 0 { return error('app action `${name}` expects no arguments') }
				model.$method()
				return
			} $else $if method.is_pub && method.typ is fn ( int ) {
				if arguments.len != 1 {
					return error('app action `${name}` expects one int argument')
				}
				argument := arguments[0]
				if argument is int {
					model.$method(argument)
					return
				}
				return error('app action `${name}` expects one int argument')
			} $else $if method.is_pub && method.typ is fn ( string ) {
				if arguments.len != 1 {
					return error('app action `${name}` expects one string argument')
				}
				argument := arguments[0]
				if argument is string {
					model.$method(argument)
					return
				}
				return error('app action `${name}` expects one string argument')
			} $else {
				return error('app action `${name}` has an unsupported signature')
			}
		}
	}
	return error('unknown app action `${name}`')
}

pub struct CompiledVmlRunConfig[T] {
pub:
	model      T
	build      fn (mut T) Element = unsafe { nil }
	title      string             = 'App'
	width      int                = 400
	height     int                = 800
	min_width  int
	min_height int
}

@[heap]
struct CompiledVmlController[T] {
	build fn (mut T) Element = unsafe { nil }
mut:
	model T
}

@[heap]
struct CompiledVmlRuntime {
mut:
	controller voidptr
}

const compiled_vml_runtime_singleton = &CompiledVmlRuntime{}

fn compiled_vml_runtime() &CompiledVmlRuntime { return unsafe { compiled_vml_runtime_singleton } }

fn compiled_vml_controller_build[T]() Element {
	runtime := compiled_vml_runtime()
	mut controller := unsafe { &CompiledVmlController[T](runtime.controller) }
	return controller.build(mut controller.model)
}

// The compiled builder attaches its callbacks while borrowing this live model.
pub fn run_compiled_vml[T](config CompiledVmlRunConfig[T]) ! {
	if config.build == unsafe { nil } { return error('compiled VML requires a build function') }
	mut controller := &CompiledVmlController[T]{ build: config.build, model: config.model }
	validate_element_tree(controller.build(mut controller.model))!
	mut runtime := compiled_vml_runtime()
	runtime.controller = voidptr(controller)
	$if macos || windows || linux {
		run_window_with_min_size(config.title, config.width, config.height, config.min_width,
			config.min_height, compiled_vml_controller_build[T])
	} $else {
		run(compiled_vml_controller_build[T])
	}
}
