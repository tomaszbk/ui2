module main

import dl
import os
import rand
import ui2

// A preview library allocates from the designer's Boehm collector. V links libgc
// statically into every executable and shared library, so a library built the
// default way runs a second, private collector in this process. Neither
// collector scans the other's heap, yet the preview's document graph holds
// pointers in both directions, so each one frees objects that only the other's
// heap still references. On Linux the private collector also replaces the
// designer's stop-the-world signal handlers, and its marker threads remain,
// waiting in unmapped code, once the library is closed.
//
// The library is therefore built with `-d dynamic_boehm` against a pkg-config
// entry (see `write_host_collector_package`) that supplies V's collector headers
// but nothing to link, which leaves every `GC_*` symbol undefined. The designer
// exports its collector, and the dynamic loader binds those symbols to it. A
// library that cannot bind them fails to load instead of running a collector of
// its own.
$if linux {
	$if tinyc {
		// TCC has no option to export only some symbols.
		#flag -rdynamic
	} $else {
		#flag -Wl,--export-dynamic-symbol=GC_*
	}
}

type DesignerPreviewBuild = fn (ui2.Rect, ui2.ElementCallback) ui2.Element

// Loaded code stays alive until the window closes, because retained controls
// may still hold callbacks from an earlier preview after a successful reload.
struct DesignerPreviewLibrary {
	handle    voidptr
	directory string
}

fn preview_callback(event ui2.ElementEvent) {
	mut state := unsafe { ide_state }
	state.status = 'Preview event: ${event.kind} on ${event.id}'
	state.log(state.status)
	event.window.request_refresh()
}

fn preview_publish(_id string, _element ui2.Element) {
	state := unsafe { ide_state }
	state.refresh()
}

fn preview_command(command ui2.VmlHostCommand) ! {
	state := unsafe { ide_state }
	if state.window == unsafe { nil } {
		return
	}
	match command.kind {
		.focus { state.window.focus(command.id) }
		.set_text { state.window.set_text(command.id, command.text) }
	}
}

fn preview_library_source(app &IdeApp, source_path string) string {
	mut actions := []string{}
	for component in app.components {
		if component.event_handler.len > 0 && component.event_handler !in actions {
			actions << component.event_handler
		}
	}
	mut locals := ''
	for action in actions {
		locals += '\t${action} := on_event\n'
	}
	path_literal := vml_escape(source_path).replace('$', '\\$')
	// The document graph lives in the designer's collector, which also traces
	// the designer's references to it, so the library keeps no roots of its own.
	return 'module main\n\nimport ui2\n\n@[export: \'ui2_designer_build\']\npub fn designer_build(frame ui2.Rect, on_event ui2.ElementCallback) ui2.Element {\n${locals}\treturn \$vml("${path_literal}", frame)\n}\n'
}

// host_collector_libs returns the linker flags that let a preview library leave
// the collector's symbols for the dynamic loader to bind to the designer's. ELF
// shared libraries may keep undefined symbols, and Mach-O ones may when they look
// them up dynamically. A Windows DLL has to import them from a named module, and
// V cannot link one against the executable's collector, so there is no
// collector a preview could share.
fn host_collector_libs() ?string {
	$if linux {
		return ''
	} $else $if macos {
		return '-Wl,-undefined,dynamic_lookup'
	}
	return none
}

// write_host_collector_package writes the pkg-config entry through which a
// `-d dynamic_boehm` build finds its collector: V's bundled headers, which the
// designer was compiled with, and no library. It returns the entry's directory.
fn write_host_collector_package(directory string, libs string) !string {
	package_dir := os.join_path(directory, 'pkgconfig')
	os.mkdir_all(package_dir)!
	include := os.join_path(@VEXEROOT, 'thirdparty', 'libgc', 'include').replace(' ', '\\ ')
	os.write_file(os.join_path(package_dir, 'bdw-gc-threaded.pc'), 'Name: bdw-gc-threaded\nDescription: Boehm GC of the process that loads the library\nVersion: 8.3.0\nCflags: -I${include}\nLibs: ${libs}\n')!
	return package_dir
}

// run_preview_compiler runs `command` with the host collector's pkg-config
// entry ahead of any installed one.
fn run_preview_compiler(command []string, package_dir string) os.Result {
	mut environment := os.environ()
	search_path := environment['PKG_CONFIG_PATH'] or { '' }
	environment['PKG_CONFIG_PATH'] = if search_path == '' {
		package_dir
	} else {
		package_dir + os.path_delimiter + search_path
	}
	mut process := os.new_process(command[0])
	process.set_args(command[1..])
	process.set_environment(environment)
	process.set_redirect_stdio_merged()
	process.run()
	output := process.stdout_slurp()
	process.wait()
	exit_code := process.code
	process.close()
	return os.Result{ exit_code: exit_code, output: output }
}

fn (mut app IdeApp) compile_preview() ! {
	collector_libs := host_collector_libs() or {
		return error('compiled previews need a collector shared with the designer, which V cannot link on ${os.user_os()}')
	}
	directory := os.join_path(os.temp_dir(), 'ui2-designer-${os.getpid()}', app.preview_libraries.len.str())
	os.mkdir_all(directory)!
	mut keep := false
	defer { if !keep { os.rmdir_all(directory) or {} } }
	// Compile unsaved source beside its document, so the compiler's normal
	// relative import resolution also applies to the preview. Remove the
	// temporary source after compiling; the loaded library owns its code.
	document_path := resolve_vml_path(app.path_input, app.project_root)!
	preview_source := os.join_path(os.dir(document_path), '.ui2-preview-${rand.uuid_v4()}.vml')
	os.write_file(preview_source, app.source_text)!
	defer { os.rm(preview_source) or {} }
	source := os.join_path(directory, 'preview.v')
	os.write_file(source, preview_library_source(app, preview_source))!
	library := os.join_path(directory, dl.get_libname('preview'))
	module_path := [os.dir(@VMODROOT), '@vlib', '@vmodules'].join(os.path_delimiter)
	// The exported structs and callbacks use the C backend's native ABI, as do
	// the designer host and ui2's platform builds.
	mut command := [@VEXE, '-b', 'c', '-path', module_path]
	command << ['-d', 'ui2_document_library']
	$if ui2_headless ? {
		command << ['-d', 'ui2_headless']
	}
	// Bind to the designer's collector (see the top of this file). The library's
	// runtime start-up would otherwise also install its GC warning callback in
	// that collector, where it would outlive the library's code.
	command << ['-d', 'dynamic_boehm', '-d', 'gc_warn_on_stderr']
	command << ['-shared', '-o', library, source]
	result := run_preview_compiler(command, write_host_collector_package(directory, collector_libs)!)
	if result.exit_code != 0 { return error(result.output.trim_space()) }
	handle := dl.open_opt(library, dl.rtld_now | dl.rtld_local)!
	symbol := dl.sym_opt(handle, 'ui2_designer_build') or {
		dl.close(handle)
		return err
	}
	app.preview_libraries << DesignerPreviewLibrary{ handle: handle, directory: directory }
	app.dispose_preview_node()
	app.preview_build = DesignerPreviewBuild(symbol)
	keep = true
}

// dispose_preview_node disposes the previewed document: the interpreted one
// with its interpreter, or the compiled library's.
fn (mut app IdeApp) dispose_preview_node() {
	if app.preview_interpreter != unsafe { nil } {
		mut interpreter := app.preview_interpreter
		interpreter.dispose()
		app.preview_interpreter = unsafe { nil }
		app.preview_node = unsafe { nil }
		return
	}
	if app.preview_node == unsafe { nil } { return }
	app.preview_node.dispose_document() or { app.log('Preview cleanup failed: ${err}') }
	app.preview_node = unsafe { nil }
}

fn (mut app IdeApp) preview_declaration(frame ui2.Rect) !ui2.Element {
	if app.preview_interpreter != unsafe { nil } {
		mut interpreter := app.preview_interpreter
		return interpreter.build()!
	}
	if app.preview_build == unsafe { nil } { return error('preview has not been run') }
	return app.preview_build(frame, preview_callback)
}

fn (mut app IdeApp) preview_element(frame ui2.Rect) !ui2.Element {
	if app.preview_node == unsafe { nil } {
		declaration := app.preview_declaration(frame)!
		ui2.validate_element_tree(declaration) or {
			if app.preview_interpreter != unsafe { nil } {
				app.dispose_preview_node()
			} else if declaration.compiled_node != unsafe { nil } {
				declaration.compiled_node.dispose_document()!
			}
			return err
		}
		if declaration.compiled_node == unsafe { nil } {
			return error('the preview has no retained owner')
		}
		app.preview_node = declaration.compiled_node
		app.preview_node.component.set_publisher(preview_publish)!
		app.preview_node.component.set_command_handler(preview_command)!
	}
	app.preview_node.set_frame(frame)!
	app.preview_node.mount()!
	return app.preview_node.element()
}

fn (mut app IdeApp) dispose_preview() {
	app.dispose_preview_node()
	app.preview_build = unsafe { nil }
	for library in app.preview_libraries {
		dl.close(library.handle)
		os.rmdir_all(library.directory) or {}
	}
	app.preview_libraries.clear()
}
