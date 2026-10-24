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
	theme      Theme
}

@[heap]
struct CompiledVmlController[T] {
	build  fn (mut T) Element = unsafe { nil }
	update fn (mut T)         = unsafe { nil }
mut:
	model &T               = unsafe { nil }
	node  &CompiledVmlNode = unsafe { nil }
	// The first frame shows the document that run_compiled_vml has just
	// built from the updated model, so it neither updates nor rereads it.
	fresh bool
}

// CompiledVmlRuntime is the startup context of a compiled document that is
// being built. The lowering builds documents with context-free calls
// (vml_document, vml_bounds), so while run_compiled_vml or the interpreter
// builds one before its window exists, the configured theme and viewport
// reach it through this process-wide scope. Nothing about a running window
// is kept here: each window's controller is captured by its build function.
@[heap]
struct CompiledVmlRuntime {
mut:
	initial_bounds ?Rect
	initial_theme  ?Theme
}

const compiled_vml_runtime_singleton = &CompiledVmlRuntime{}

fn compiled_vml_runtime() &CompiledVmlRuntime { return unsafe { compiled_vml_runtime_singleton } }

// Only the active builder sees this startup context. Each document takes an
// owned copy before its token consumers are created; later changes use its owner.
fn vml_initial_theme() Theme { return compiled_vml_runtime().initial_theme or { Theme{} } }

// vml_bounds is the frame of a document built without an explicit one: the
// configured viewport while run_compiled_vml builds it, otherwise a window of
// the default size. A document that follows the viewport takes its window's
// bounds when the window mounts it.
pub fn vml_bounds() Rect {
	if frame := compiled_vml_runtime().initial_bounds { return frame }
	return rect(0, 0, default_window_width, default_window_height)
}

// build_frame is the window's build function: it mounts the retained
// document in w, at w's bounds, and returns its declaration.
fn (mut controller CompiledVmlController[T]) build_frame(mut w Window) Element {
	w.begin_compiled_snapshot()
	defer { w.end_compiled_snapshot() }
	$if ui2_dev ? {
		$if vml_interpreter ? {
			// `ui2 dev`: a reloaded document replaces the window's root, which
			// the generated builder returns (vml_dev_d_vml_interpreter.v).
			if vml_dev_frame(mut w, controller.node) {
				controller.node = unsafe { nil }
			}
		}
	}
	mut built := controller.fresh
	controller.fresh = false
	if !built && controller.update != unsafe { nil } { controller.update(mut controller.model) }
	if controller.node == unsafe { nil } {
		declaration := controller.build(mut controller.model)
		if declaration.compiled_node == unsafe { nil } { return declaration }
		controller.node = declaration.compiled_node
		built = true
	}
	mut component := controller.node.component
	component.window = w
	controller.node.update_viewport(w.bounds()) or { eprintln('ui2 compiled VML viewport failed: ${err}') }
	controller.node.mount() or { eprintln('ui2 compiled VML mount failed: ${err}') }
	// A later build is requested after code outside compiled callbacks ran
	// (input handlers, tasks, refresh), which may have changed the model. A
	// document built by this call, or by run_compiled_vml for the first
	// frame, has just read the current model, unless a mount hook has run since.
	if !built || controller.node.component.has_mount_hooks() {
		controller.node.component.invalidate_app() or { eprintln('ui2 compiled VML app update failed: ${err}') }
	}
	return controller.node.element()
}

// dispose drops the document's subscriptions and component-owned captures.
// The window calls it as it closes, before native termination; calling it
// again after the run loop returns is safe.
fn (mut controller CompiledVmlController[T]) dispose() {
	if controller.node == unsafe { nil } { return }
	mut root := controller.node
	controller.node = unsafe { nil }
	root.dispose_document() or { eprintln('ui2 compiled VML cleanup failed: ${err}') }
}

// run_compiled_vml opens one window that shows the compiled document and runs
// it until it closes. The compiled builder attaches its callbacks while
// borrowing this live model.
pub fn run_compiled_vml[T](config CompiledVmlRunConfig[T]) ! {
	mut app := new_app()
	open_compiled_vml[T](mut app, config)!
	app.run()
}

// open_compiled_vml opens a window of app that shows the compiled document,
// and returns it before app runs, so that the model can keep the window it
// asks for its text, focus or bounds. The document is disposed of as the
// window closes.
pub fn open_compiled_vml[T](mut app App, config CompiledVmlRunConfig[T]) !&Window {
	mut controller := start_compiled_vml[T](config)!
	mut w := app.new_window(
		title:      config.title
		width:      config.width
		height:     config.height
		min_width:  config.min_width
		min_height: config.min_height
		build:      fn [mut controller] [T](mut w Window) Element {
			return controller.build_frame(mut w)
		}
	) or {
		controller.dispose()
		return err
	}
	w.on_close(fn [mut controller] [T]() { controller.dispose() })
	return w
}

// start_compiled_vml updates the model, builds and validates the document and
// returns its controller, whose first frame then shows that document.
fn start_compiled_vml[T](config CompiledVmlRunConfig[T]) !&CompiledVmlController[T] {
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
	controller.fresh = true
	return controller
}
