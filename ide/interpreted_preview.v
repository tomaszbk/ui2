module main

import ui2

$if !vml_interpreter ? {
	$compile_error('UI2 Studio previews documents with the VML interpreter; build it with -d vml_interpreter')
}

// The live preview interprets the document with ui2's VML interpreter, which
// declares the same retained nodes as compiled VML through the widget
// registry. It needs no compiler or shared library, so it runs on every OS,
// and running it again reloads the document in place: unchanged
// declarations keep their state. Named callbacks become preview_callback,
// and `app` is a sample model without fields whose method calls are logged.
// The compiled preview (compiled_preview.v) remains as the explicit "Verify
// with compiler" action.

fn preview_model_call(name string, args []ui2.VmlValue) {
	mut state := unsafe { ide_state }
	state.status = 'Preview called app.${name}() with ${args.len} argument(s).'
	state.log(state.status)
	ui2.request_refresh()
}

fn preview_fallback(_name string) ui2.ElementCallback {
	return preview_callback
}

// run_preview loads the source into the live preview. A source that does
// not load leaves the running preview unchanged.
fn (mut app IdeApp) run_preview() ! {
	document_path := resolve_vml_path(app.path_input, app.project_root)!
	if app.preview_interpreter != unsafe { nil } && app.preview_document == document_path {
		mut interpreter := app.preview_interpreter
		if _ := interpreter.root() {
			interpreter.reload(app.source_text)!
			// The reload disposed the previous root; preview_element attaches
			// the new one.
			app.preview_node = unsafe { nil }
			return
		}
	}
	interpreter := ui2.vml_interpreter(app.source_text, ui2.vml_sample_model(map[string]ui2.VmlValue{},
		preview_model_call),
		path:     document_path
		frame:    ui2.rect(0, 0, app.canvas_width(), app.canvas_height())
		fallback: preview_fallback
	)!
	app.dispose_preview_node()
	app.preview_build = unsafe { nil }
	app.preview_interpreter = interpreter
	app.preview_document = document_path
}

// verify_preview builds the document with the V compiler and shows the
// compiled document in the preview. Compiled VML is the source of truth: a
// document the interpreter runs may still be one V rejects.
fn (mut app IdeApp) verify_preview() {
	app.compile_preview() or {
		app.status = 'Compiler verification failed: ${err}'
		app.log(app.status)
		app.output_open = true
		return
	}
	app.status = 'Verified with the V compiler. The preview runs the compiled document.'
	app.log(app.status)
	app.select_tab('preview')
}

// has_preview reports whether a preview document is loaded.
fn (app &IdeApp) has_preview() bool {
	return app.preview_interpreter != unsafe { nil } || app.preview_build != unsafe { nil }
}

// preview_compiled reports whether the preview shows the compiled document.
fn (app &IdeApp) preview_compiled() bool {
	return app.preview_build != unsafe { nil }
}
