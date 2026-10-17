module ui2

import os
import time
import vml

// The VML interpreter (design §3), compiled only with `-d vml_interpreter`.
// It runs a VML document without compiling it: the shared parser (vlib/vml)
// reads it, the loader (vml_interpret_check_d_vml_interpreter.v) resolves it
// against the model's type and the widget registry, and the runtime
// (vml_interpret_run_d_vml_interpreter.v) declares the same generic nodes as
// compiled VML. Compiled VML (`$vml(...)`) stays the default and the source
// of truth; the interpreter serves development and dynamic documents: the
// IDE preview, hot reload (`run_vml` with `watch: true`) and documents
// pushed to a debug build.
//
// Entry points:
// * `vml_interpret(source, &model, config)` builds a document once and
//   returns its root element, like `$vml(...)`;
// * `vml_interpreter(source, model, config)` returns a handle that builds
//   the document and reloads it from new source, keeping state;
// * `run_vml[T](source_path: ..., model: &app, watch: true)` runs a window,
//   reloading the document when its files change.

// VmlInterpretConfig configures an interpreted document.
@[params]
pub struct VmlInterpretConfig {
pub:
	// The document's file. Imports resolve next to it and errors name it; the
	// source passed to the interpreter replaces the file's contents.
	path string
	// The document frame. Without one, the document follows the viewport
	// (vml_bounds()), like `$vml(path)` without a frame.
	frame ?Rect
	theme ?Theme
	// The external callbacks the document names (`on_click: callback_save`).
	callbacks map[string]ElementCallback
	// Gives a callback for a name missing from `callbacks`. With it, unknown
	// callbacks are not load errors (previews supply placeholder handlers).
	fallback ?fn (name string) ElementCallback
	// Replaces os.read_file for imported documents.
	read_file ?fn (path string) !string
}

// vml_interpret builds the VML document `source` against the live model. The
// result is the document's root element, with its retained node, as `$vml`
// returns it.
pub fn vml_interpret[T](source string, model &T, config VmlInterpretConfig) !Element {
	mut interpreter := vml_interpreter(source, vml_model(model), config)!
	return interpreter.build()!
}

// vml_interpret_model is vml_interpret for a model handle, such as a sample
// model (vml_sample_model).
pub fn vml_interpret_model(source string, model &VmlModel, config VmlInterpretConfig) !Element {
	mut interpreter := vml_interpreter(source, model, config)!
	return interpreter.build()!
}

// VmlInterpreter is an interpreted document that can be rebuilt from new
// source. A reload re-parses and re-checks the source; if it is valid, it
// builds a new document in the identity namespace of the current one, seeds
// every component state that still exists (same owner path and name, which
// are declaration paths and repeater keys) with its current value, and then
// disposes the current document. Element ids, and with them focus and the
// backend's edit buffers, stay the same for unchanged declarations. Lifecycle
// hooks run again: cleanup and unmount for the old document, mount for the
// new one. An invalid source leaves the current document running.
@[heap]
pub struct VmlInterpreter {
pub:
	path string
mut:
	model   &VmlModel = unsafe { nil }
	config  VmlInterpretConfig
	program &VmlProgram      = unsafe { nil }
	run     &VmlSession      = unsafe { nil }
	root    &CompiledVmlNode = unsafe { nil }
	files   map[string]i64
	// A file change seen by the watcher thread, applied on the UI thread.
	stale bool
	stop  bool
	// The current document has not been shown yet.
	fresh bool
}

// vml_interpreter loads `source`: it is parsed and checked, not built.
pub fn vml_interpreter(source string, model &VmlModel, config VmlInterpretConfig) !&VmlInterpreter {
	if model == unsafe { nil } { return error('the VML interpreter requires a model') }
	program, files := vml_load(source, model, config)!
	mut interpreter := &VmlInterpreter{
		path:    config.path
		model:   unsafe { model }
		config:  config
		program: program
	}
	interpreter.run = interpreter.new_run(program, map[string]VmlValue{})
	interpreter.watch_files(files)
	return interpreter
}

// vml_interpreter_file loads the document at `path`.
pub fn vml_interpreter_file(path string, model &VmlModel, config VmlInterpretConfig) !&VmlInterpreter {
	source := os.read_file(path)!
	return vml_interpreter(source, model, VmlInterpretConfig{
		...config
		path: path
	})
}

fn (i &VmlInterpreter) new_run(program &VmlProgram, carry map[string]VmlValue) &VmlSession {
	return &VmlSession{
		program:   program
		model:     i.model
		callbacks: i.config.callbacks
		fallback:  i.config.fallback
		carry:     carry
	}
}

// vml_load parses and checks a document. It returns the program and the
// files it was read from.
fn vml_load(source string, model &VmlModel, config VmlInterpretConfig) !(&VmlProgram, []string) {
	mut files := &[]string{}
	root := if config.path.len == 0 {
		vml.parse_source(source)!
	} else {
		path := os.real_path(config.path)
		reader := config.read_file
		vml.parse_file(path, vml.ParseConfig{
			read_file: fn [path, source, reader, mut files] (file string) !string {
				if file !in files { files << file }
				if file == path { return source }
				if read := reader { return read(file) }
				return os.read_file(file)
			}
		})!
	}
	program := vml_check(root, model, config.callbacks, config.fallback != none)!
	mut program_files := program.files.clone()
	program_files << *files
	return program, program_files
}

// build builds the document, the first time it is called; later calls return
// the current document's element.
pub fn (mut i VmlInterpreter) build() !Element {
	if i.root != unsafe { nil } { return i.root.element() }
	frame, follow := i.document_frame()
	element := vml_build(i.run, frame, VmlDocumentConfig{
		theme:           i.config.theme
		follow_viewport: follow
	})!
	i.root = element.compiled_node
	i.fresh = true
	return element
}

fn (i &VmlInterpreter) document_frame() (Rect, bool) {
	if frame := i.config.frame { return frame, false }
	return vml_bounds(), true
}

// root is the current document's retained root node.
pub fn (i &VmlInterpreter) root() ?&CompiledVmlNode {
	if i.root == unsafe { nil } { return none }
	return i.root
}

// reload replaces the document with one built from `source`, keeping state
// (see VmlInterpreter). It returns the new root element.
pub fn (mut i VmlInterpreter) reload(source string) !Element {
	program, files := vml_load(source, i.model, i.config)!
	if i.root == unsafe { nil } {
		i.program = program
		i.run = i.new_run(program, map[string]VmlValue{})
		i.watch_files(files)
		return i.build()!
	}
	mut carry := map[string]VmlValue{}
	for record in i.run.states {
		mut signal := record.signal
		if value := signal.peek() { carry[record.key] = value }
	}
	mut old := i.root
	mut owner := old.component
	for owner.parent != unsafe { nil } {
		owner = owner.parent
	}
	session := i.new_run(program, carry)
	frame, follow := i.document_frame()
	element := vml_build(session, frame, VmlDocumentConfig{
		theme:           owner.theme
		follow_viewport: follow
		identity:        owner.identity_namespace
	})!
	i.program = program
	i.run = session
	i.root = element.compiled_node
	i.fresh = true
	i.watch_files(files)
	old.dispose_document()!
	return element
}

// reload_file reloads the document from its file.
pub fn (mut i VmlInterpreter) reload_file() !Element {
	if i.path.len == 0 { return error('the VML document has no file') }
	return i.reload(os.read_file(i.path)!)!
}

// files are the document's files: the document and its imports.
pub fn (i &VmlInterpreter) files() []string {
	return i.files.keys()
}

// changed reports whether a file of the document changed since it was loaded.
pub fn (i &VmlInterpreter) changed() bool {
	for file, modified in i.files {
		if vml_modified(file) != modified { return true }
	}
	return false
}

fn (mut i VmlInterpreter) watch_files(files []string) {
	i.files = map[string]i64{}
	for file in files {
		i.files[file] = vml_modified(file)
	}
	i.stale = false
}

fn vml_modified(path string) i64 {
	attributes := os.stat(path) or { return -1 }
	return attributes.mtime
}

// dispose disposes the current document and stops watching.
pub fn (mut i VmlInterpreter) dispose() {
	i.stop = true
	if i.root == unsafe { nil } { return }
	mut root := i.root
	i.root = unsafe { nil }
	root.dispose_document() or { eprintln('ui2 VML cleanup failed: ${err}') }
}

// VmlRunConfig configures run_vml.
@[params]
pub struct VmlRunConfig[T] {
pub:
	source_path string
	model       &T = unsafe { nil }
	// Reload the document when one of its files changes.
	watch      bool
	title      string = 'App'
	width      int    = 400
	height     int    = 800
	min_width  int
	min_height int
	theme      Theme
	callbacks  map[string]ElementCallback
	// Runs before every build, like CompiledVmlRunConfig.update.
	update fn (mut T) = unsafe { nil }
}

// run_vml runs a window showing the interpreted document at `source_path`,
// like run_compiled_vml does for a compiled one. With `watch`, saving the
// document or one of its imports reloads it in place, keeping state, focus
// and edit buffers; a document that does not load is reported on stderr and
// the window keeps the last good one.
pub fn run_vml[T](config VmlRunConfig[T]) ! {
	if config.model == unsafe { nil } { return error('run_vml requires a live model') }
	if config.source_path.len == 0 { return error('run_vml requires source_path') }
	config.theme.validate()!
	mut runtime := compiled_vml_runtime()
	runtime.initial_theme = config.theme
	defer { runtime.initial_theme = none }
	runtime.initial_bounds = rect(0, 0, config.width, config.height)
	mut model := unsafe { config.model }
	if config.update != unsafe { nil } { config.update(mut model) }
	mut interpreter := vml_interpreter_file(config.source_path, vml_model(config.model),
		callbacks: config.callbacks
		theme:     config.theme
	) or {
		runtime.initial_bounds = none
		return err
	}
	declaration := interpreter.build() or {
		runtime.initial_bounds = none
		return err
	}
	runtime.initial_bounds = none
	runtime.initial_theme = none
	validate_element_tree(declaration) or {
		interpreter.dispose()
		return err
	}
	dispose_compiled_vml()
	// The backend disposes the runtime root when the window closes.
	runtime.root = interpreter.root
	defer {
		interpreter.stop = true
		dispose_compiled_vml()
	}
	if config.watch {
		spawn vml_watch(interpreter)
	}
	update := config.update
	build := fn [mut interpreter, mut model, update] [T]() Element {
		compiled_vml_begin_snapshot()
		defer { compiled_vml_end_snapshot() }
		if update != unsafe { nil } { update(mut model) }
		return interpreter.next_frame()
	}
	$if macos || windows || linux {
		run_window_with_min_size(config.title, config.width, config.height, config.min_width,
			config.min_height, build)
	} $else {
		run(build)
	}
}

// next_frame is one window frame of a running document: it applies a reload
// the watcher asked for, follows the viewport, mounts the document and
// returns its root element.
fn (mut i VmlInterpreter) next_frame() Element {
	if i.stale {
		i.reload_file() or {
			eprintln('ui2 VML reload failed: ${err}')
			i.watch_files(i.files.keys())
		}
		mut runtime := compiled_vml_runtime()
		if runtime.root != unsafe { nil } && runtime.root != i.root {
			runtime.root = i.root
		}
	}
	mut root := i.root
	root.update_viewport(vml_bounds()) or { eprintln('ui2 VML viewport failed: ${err}') }
	root.mount() or { eprintln('ui2 VML mount failed: ${err}') }
	// As in run_compiled_vml: a document built for this frame has just read
	// the model, unless a mount hook has run since.
	if !i.fresh || root.component.has_mount_hooks() {
		root.component.invalidate_app() or { eprintln('ui2 VML app update failed: ${err}') }
	}
	i.fresh = false
	return root.element()
}

// vml_watch polls the document's files and asks for a build when one changes;
// the build reloads the document on the UI thread.
fn vml_watch(interpreter &VmlInterpreter) {
	mut watched := unsafe { interpreter }
	for !watched.stop {
		time.sleep(300 * time.millisecond)
		if !watched.stale && watched.changed() {
			watched.stale = true
			request_animation_refresh(false)
		}
	}
}
