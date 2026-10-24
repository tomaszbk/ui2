module ui2

import os
import strconv
import sync
import time

// Development mode, for `ui2 dev`: a program built with `-d vml_interpreter
// -d ui2_dev` builds every generated document with the interpreter, from the
// document's file, so saving a .vml file reloads it in the running program
// (stage 1). `ui2 dev` restarts the program when its V code changes, and the
// program hands its state to the next one (stage 2). Both keep the state of
// every component that still exists: a state survives when its owner path
// and name are unchanged and its initial value has the same kind.
//
// The program learns the files of a restart from its environment:
// * UI2_DEV_STATE: the state the previous program saved, read once at
//   start, and where this program saves its state when asked to;
// * UI2_DEV_REQUEST: a file whose appearance asks the program to save its
//   state and close;
// * UI2_DEV_COMPILED: where the program lists the documents the interpreter
//   cannot run, which it builds compiled and only a restart updates.

@[heap]
struct VmlDev {
mut:
	// Guards `documents`, which the watcher thread reads.
	mu        &sync.Mutex = sync.new_mutex()
	documents map[string]&VmlInterpreter
	compiled  []string
	window    &Window = unsafe { nil }
	watching  bool
	carry     map[string]VmlValue
	started   bool
	quit      bool
}

const vml_dev_session = &VmlDev{}

fn vml_dev() &VmlDev {
	return unsafe { vml_dev_session }
}

// vml_dev_path is the file of a generated document: its path relative to the
// directory of the generated builder, or absolute.
pub fn vml_dev_path(dir string, path string) string {
	return if os.is_abs_path(path) { path } else { os.join_path(dir, path) }
}

// vml_dev_build builds the document at `path` with the interpreter, or its
// reloaded version when one of its files changed. It returns none when the
// interpreter cannot run the document; the generated builder then builds it
// compiled.
pub fn vml_dev_build[T](mut model T, path string, frame Rect, follow bool, callbacks map[string]ElementCallback) ?Element {
	return vml_dev_document(path, '${path}\n${ptr_str(voidptr(&model))}', vml_model(&model),
		frame, follow, callbacks)
}

// vml_dev_build_static is vml_dev_build for a document that reads no model.
pub fn vml_dev_build_static(path string, frame Rect, follow bool, callbacks map[string]ElementCallback) ?Element {
	return vml_dev_document(path, path, vml_model(vml_dev_static_model), frame, follow,
		callbacks)
}

struct VmlDevNoModel {}

const vml_dev_static_model = &VmlDevNoModel{}

fn vml_dev_document(path string, key string, model &VmlModel, frame Rect, follow bool, callbacks map[string]ElementCallback) ?Element {
	mut dev := vml_dev()
	dev.start()
	dev.mu.lock()
	mut existing := dev.documents[key] or { unsafe { nil } }
	dev.mu.unlock()
	if existing != unsafe { nil } {
		mut interpreter := existing
		if interpreter.stale {
			return interpreter.reload_file() or {
				eprintln('ui2 dev: ${err}')
				interpreter.watch_files(interpreter.files.keys())
				interpreter.root_element()
			}
		}
		return interpreter.root_element()
	}
	if path in dev.compiled {
		return none
	}
	mut interpreter := vml_interpreter_file(path, model, VmlInterpretConfig{
		frame:     if follow { ?Rect(none) } else { ?Rect(frame) }
		callbacks: callbacks
	}) or {
		dev.compile(path, err)
		return none
	}
	interpreter.seed(dev.carry)
	element := interpreter.build() or {
		dev.compile(path, err)
		return none
	}
	dev.mu.lock()
	dev.documents[key] = interpreter
	dev.mu.unlock()
	if !dev.watching {
		dev.watching = true
		spawn vml_dev_watch(dev)
	}
	return element
}

// seed gives the document, before its first build, the state a previous
// program held.
fn (mut i VmlInterpreter) seed(carry map[string]VmlValue) {
	session := i.new_run(i.program, carry)
	i.run = session
}

fn (i &VmlInterpreter) root_element() Element {
	return i.root.element()
}

// compile records a document the interpreter cannot run.
fn (mut dev VmlDev) compile(path string, err IError) {
	dev.compiled << path
	eprintln('ui2 dev: ${os.file_name(path)} is built compiled, so only a restart updates it: ${err}')
	if file := os.getenv_opt('UI2_DEV_COMPILED') {
		os.write_file(file, dev.compiled.join('\n') + '\n') or {}
	}
}

// start reads the state the previous program saved, once.
fn (mut dev VmlDev) start() {
	if dev.started {
		return
	}
	dev.started = true
	file := os.getenv_opt('UI2_DEV_STATE') or { return }
	text := os.read_file(file) or { return }
	dev.carry = vml_dev_decode(text)
	os.rm(file) or {}
}

// vml_dev_frame is the development step of a window frame (CompiledVmlController):
// it saves the state and closes the window when `ui2 dev` asks for a restart,
// and reports whether the window's root document is stale, which the frame
// then builds again: the generated builder reloads it.
fn vml_dev_frame(mut w Window, root &CompiledVmlNode) bool {
	mut dev := vml_dev()
	dev.window = w
	if !dev.watching {
		// The restart request is watched even when every document is compiled.
		dev.watching = true
		spawn vml_dev_watch(dev)
	}
	if dev.quit {
		dev.quit = false
		dev.save()
		w.quit()
		return false
	}
	if root == unsafe { nil } {
		return false
	}
	dev.mu.lock()
	defer { dev.mu.unlock() }
	for _, interpreter in dev.documents {
		if interpreter.stale && interpreter.root == root {
			return true
		}
	}
	return false
}

// save writes the state of every interpreted document for the next program.
fn (dev &VmlDev) save() {
	file := os.getenv_opt('UI2_DEV_STATE') or { return }
	mut states := map[string]VmlValue{}
	for _, interpreter in dev.documents {
		for record in interpreter.run.states {
			mut signal := record.signal
			if value := signal.peek() {
				states[record.key] = value
			}
		}
	}
	os.write_file(file, vml_dev_encode(states)) or { eprintln('ui2 dev: ${err}') }
}

// vml_dev_watch polls the documents' files and the restart request, and asks
// the window for a frame when either changes; the frame reloads on the UI
// thread.
fn vml_dev_watch(session &VmlDev) {
	mut dev := unsafe { session }
	request := os.getenv('UI2_DEV_REQUEST')
	for {
		time.sleep(300 * time.millisecond)
		mut changed := false
		dev.mu.lock()
		documents := dev.documents.values()
		dev.mu.unlock()
		for document in documents {
			mut interpreter := unsafe { document }
			if !interpreter.stale && interpreter.changed() {
				interpreter.stale = true
				changed = true
			}
		}
		if request.len > 0 && os.exists(request) {
			os.rm(request) or {}
			dev.quit = true
			changed = true
		}
		if changed && dev.window != unsafe { nil } {
			mut w := dev.window
			w.backend_invalidate(.build)
		}
	}
}

// vml_value_same_kind reports whether two values have the same kind, which a
// carried state needs to replace its initial value.
fn vml_value_same_kind(a VmlValue, b VmlValue) bool {
	return match a {
		string { b is string }
		i64 { b is i64 }
		f64 { b is f64 }
		bool { b is bool }
		VmlEnum { b is VmlEnum }
		[]VmlValue { b is []VmlValue }
		VmlObject { b is VmlObject }
		VmlCallable { b is VmlCallable }
		StylePatch { b is StylePatch }
		VmlNone { b is VmlNone }
	}
}

// ----------------------------------------------------------- saved state

// The saved state is text: a header, then one value per line, `kind TAB key
// TAB value`, with backslash, tab and newline escaped. Strings, numbers,
// bools, enum values and lists of them are saved; other values start again.

const vml_dev_header = 'ui2 dev state 1'

fn vml_dev_encode(states map[string]VmlValue) string {
	mut lines := [vml_dev_header]
	for key, value in states {
		if encoded := vml_dev_value(value) {
			lines << '${vml_dev_escape(key)}\t${encoded}'
		}
	}
	return lines.join('\n') + '\n'
}

fn vml_dev_value(value VmlValue) ?string {
	return match value {
		string {
			's' + vml_dev_escape(value)
		}
		i64 {
			'i${value}'
		}
		f64 {
			'f${value}'
		}
		bool {
			if value { 'b1' } else { 'b0' }
		}
		VmlEnum {
			'e' + vml_dev_escape(value.name)
		}
		[]VmlValue {
			mut items := []string{cap: value.len}
			for item in value {
				items << vml_dev_escape(vml_dev_value(item)?)
			}
			'a' + items.join('\t')
		}
		else {
			none
		}
	}
}

fn vml_dev_decode(text string) map[string]VmlValue {
	mut states := map[string]VmlValue{}
	lines := text.split_into_lines()
	if lines.len == 0 || lines[0] != vml_dev_header {
		return states
	}
	for line in lines[1..] {
		fields := line.split('\t')
		if fields.len < 2 {
			continue
		}
		value := vml_dev_parse(fields[1..].join('\t')) or { continue }
		states[vml_dev_unescape(fields[0])] = value
	}
	return states
}

fn vml_dev_parse(text string) ?VmlValue {
	if text.len == 0 {
		return none
	}
	body := text[1..]
	return match text[0] {
		`s` {
			VmlValue(vml_dev_unescape(body))
		}
		`i` {
			VmlValue(strconv.parse_int(body, 10, 64) or { return none })
		}
		`f` {
			VmlValue(strconv.atof64(body) or { return none })
		}
		`b` {
			VmlValue(body == '1')
		}
		`e` {
			VmlValue(VmlEnum{
				name: vml_dev_unescape(body)
			})
		}
		`a` {
			mut items := []VmlValue{}
			if body.len > 0 {
				for item in body.split('\t') {
					items << vml_dev_parse(vml_dev_unescape(item))?
				}
			}
			VmlValue(items)
		}
		else {
			none
		}
	}
}

fn vml_dev_escape(text string) string {
	return text.replace('\\', '\\\\').replace('\t', '\\t').replace('\n', '\\n')
}

fn vml_dev_unescape(text string) string {
	mut out := []u8{cap: text.len}
	mut i := 0
	for i < text.len {
		if text[i] == `\\` && i + 1 < text.len {
			out << match text[i + 1] {
				`t` { `\t` }
				`n` { `\n` }
				else { text[i + 1] }
			}
			i += 2
			continue
		}
		out << text[i]
		i++
	}
	return out.bytestr()
}
