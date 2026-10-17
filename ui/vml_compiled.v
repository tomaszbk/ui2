module ui2

pub struct CompiledVmlRunConfig[T] {
pub:
	model      &T                 = unsafe { nil }
	build      fn (mut T) Element = unsafe { nil }
	update     fn (mut T)         = unsafe { nil }
	title      string             = 'App'
	width      int                = 400
	height     int                = 800
	min_width  int
	min_height int
	theme Theme
}

@[heap]
struct CompiledVmlController[T] {
	build  fn (mut T) Element = unsafe { nil }
	update fn (mut T)         = unsafe { nil }
mut:
	model &T               = unsafe { nil }
	node  &CompiledVmlNode = unsafe { nil }
}

@[heap]
struct CompiledVmlRuntime {
mut:
	controller     voidptr
	root           &CompiledVmlNode = unsafe { nil }
	initial_bounds ?Rect
	initial_theme ?Theme
}

const compiled_vml_runtime_singleton = &CompiledVmlRuntime{}

fn compiled_vml_runtime() &CompiledVmlRuntime { return unsafe { compiled_vml_runtime_singleton } }

// Only the active builder sees this startup context. Each document takes an
// owned copy before its token consumers are created; later changes use its owner.
fn vml_initial_theme() Theme { return compiled_vml_runtime().initial_theme or { Theme{} } }

// Before a native window exists, compile validation uses its configured logical
// viewport. Ordinary builders and explicit template frames still use bounds().
$if !ui2_document_library ? {
pub fn vml_bounds() Rect {
	if frame := compiled_vml_runtime().initial_bounds { return frame }
	return bounds()
}
}


$if !ui2_document_library ? {
fn compiled_vml_controller_build[T]() Element {
	runtime := compiled_vml_runtime()
	mut controller := unsafe { &CompiledVmlController[T](runtime.controller) }
	compiled_vml_begin_snapshot()
	defer { compiled_vml_end_snapshot() }
	if controller.update != unsafe { nil } { controller.update(mut controller.model) }
	mut built := false
	if controller.node == unsafe { nil } {
		declaration := controller.build(mut controller.model)
		if declaration.compiled_node == unsafe { nil } { return declaration }
		controller.node = declaration.compiled_node
		mut live := compiled_vml_runtime()
		live.root = controller.node
		built = true
	}
	controller.node.update_viewport(vml_bounds()) or { eprintln('ui2 compiled VML viewport failed: ${err}') }
	controller.node.mount() or { eprintln('ui2 compiled VML mount failed: ${err}') }
	// A later build is requested after code outside compiled callbacks ran
	// (input handlers, tasks, refresh), which may have changed the model. A
	// document built by this call has just read the current model, unless a
	// mount hook has run since.
	if !built || controller.node.component.has_mount_hooks() {
		controller.node.component.invalidate_app() or { eprintln('ui2 compiled VML app update failed: ${err}') }
	}
	return controller.node.element()
}
}


// Backend shutdown drops subscriptions and component-owned captures before
// native termination. Calling this again after the run loop returns is safe.
pub fn dispose_compiled_vml() {
	mut runtime := compiled_vml_runtime()
	runtime.controller = unsafe { nil }
	if runtime.root == unsafe { nil } { return }
	mut root := runtime.root
	runtime.root = unsafe { nil }
	root.dispose_document() or { eprintln('ui2 compiled VML cleanup failed: ${err}') }
}

// The compiled builder attaches its callbacks while borrowing this live model.
$if !ui2_document_library ? {
pub fn run_compiled_vml[T](config CompiledVmlRunConfig[T]) ! {
	if config.model == unsafe { nil } { return error('compiled VML requires a live model') }
	if config.build == unsafe { nil } { return error('compiled VML requires a build function') }
	mut controller := &CompiledVmlController[T]{ build: config.build, update: config.update, model: config.model }
	mut runtime := compiled_vml_runtime()
	config.theme.validate()!
	runtime.initial_theme = config.theme
	defer { runtime.initial_theme = none }
	runtime.initial_bounds = rect(0, 0, config.width, config.height)
	if controller.update != unsafe { nil } { controller.update(mut controller.model) }
	declaration := controller.build(mut controller.model)
	runtime.initial_bounds = none
	runtime.initial_theme = none
	validate_element_tree(declaration) or {
		if declaration.compiled_node != unsafe { nil } {
			declaration.compiled_node.dispose_document()!
		}
		return err
	}
	controller.node = declaration.compiled_node
	dispose_compiled_vml()
	runtime.controller = voidptr(controller)
	runtime.root = controller.node
	defer { dispose_compiled_vml() }
	$if macos || windows || linux {
		run_window_with_min_size(config.title, config.width, config.height, config.min_width,
			config.min_height, compiled_vml_controller_build[T])
	} $else {
		run(compiled_vml_controller_build[T])
	}
}
}
