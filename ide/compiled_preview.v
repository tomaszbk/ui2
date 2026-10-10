module main

import dl
import os
import rand
import ui2

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
	ui2.request_refresh()
}

fn preview_publish(_id string, _element ui2.Element) {
	ui2.request_refresh()
}

fn preview_command(command ui2.VmlHostCommand) ! {
	match command.kind {
		.focus { ui2.focus(command.id) }
		.set_text { ui2.set_text(command.id, command.text) }
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
	// Keep the managed graph in the library's own roots while its callbacks can
	// remain in the host. Loaded libraries stay alive until the window closes.
	return '@[has_globals]\nmodule main\n\nimport ui2\n\n__global preview_root = &ui2.CompiledVmlNode(unsafe { nil })\n\n@[export: \'ui2_designer_build\']\npub fn designer_build(frame ui2.Rect, on_event ui2.ElementCallback) ui2.Element {\n${locals}\tresult := \$vml("${path_literal}", frame)\n\tpreview_root = result.compiled_node\n\treturn result\n}\n'
}

fn (mut app IdeApp) compile_preview() ! {
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
	$if ui2_custom_rendering ? {
		command << ['-d', 'ui2_custom_rendering']
	}
	$if ui2_headless ? {
		command << ['-d', 'ui2_headless']
	}
	command << ['-shared', '-o', library, source]
	result := os.exec(command)
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

fn (mut app IdeApp) dispose_preview_node() {
	if app.preview_node == unsafe { nil } { return }
	app.preview_node.dispose_document() or { app.log('Preview cleanup failed: ${err}') }
	app.preview_node = unsafe { nil }
}

fn (mut app IdeApp) preview_element(frame ui2.Rect) !ui2.Element {
	if app.preview_build == unsafe { nil } { return error('preview has not been compiled') }
	if app.preview_node == unsafe { nil } {
		declaration := app.preview_build(frame, preview_callback)
		ui2.validate_element_tree(declaration) or {
			if declaration.compiled_node != unsafe { nil } {
				declaration.compiled_node.dispose_document()!
			}
			return err
		}
		if declaration.compiled_node == unsafe { nil } {
			return error('compiled preview has no retained owner')
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
