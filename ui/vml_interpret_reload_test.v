// vtest vflags: -d vml_interpreter -d ui2_headless
module ui2

import os

// Hot reload in a running window: a changed document file is re-read and
// rebuilt against the same owner tree, and unchanged declarations keep their
// state, focus and edit buffers.

@[heap]
pub struct ReloadApp {
pub mut:
	title  string = 'Notes'
	clicks int
}

pub fn (mut a ReloadApp) click() {
	a.clicks++
}

const reload_first = 'import Counter
Column(id: "root") {
	Label(id: "title", text: app.title)
	TextInput(id: "name", text: "Ada")
	Counter(label: "Count")
	Button(id: "click", text: "Click \${app.clicks}", on_click: app.click)
}'

const reload_counter = 'component Counter(label string) {
	state count := 0
	Button(id: "counter", text: "\${label} \${count}", on_click: count++)
}'

fn reload_find(el Element, id string) ?Element {
	if el.id == id { return el }
	for child in el.children {
		if found := reload_find(child, id) { return found }
	}
	return none
}

fn reload_texts(el Element) []string {
	return el.children.map(it.text)
}

fn test_hot_reload_keeps_state_focus_and_edit_buffers() ! {
	directory := os.join_path(os.temp_dir(), 'ui2-vml-reload-${os.getpid()}')
	os.mkdir_all(directory)!
	defer { os.rmdir_all(directory) or {} }
	document := os.join_path(directory, 'app.vml')
	component := os.join_path(directory, 'counter.vml')
	os.write_file(document, reload_first)!
	os.write_file(component, reload_counter)!
	mut app := &ReloadApp{}
	mut interpreter := vml_interpreter_file(document, vml_model(app))!
	assert interpreter.files().len == 2
	interpreter.build()!
	mut ui_app := new_app()
	mut w := ui_app.new_window(
		title:  'Reload'
		width:  320
		height: 240
		build:  fn [mut interpreter] (mut w Window) Element {
			return interpreter.next_frame(mut w)
		}
	)!
	assert w.layout_error == ''
	mut root := interpreter.root()?
	first := root.element()
	assert reload_texts(first) == ['Notes', 'Ada', 'Count 0', 'Click 0']
	// Live state: a component state, an edit buffer, focus and the model.
	// The counter's id lives in its component's namespace; it is the third
	// child.
	first.children[2].on_event(ElementEvent{ kind: .click })
	first.children[2].on_event(ElementEvent{ kind: .click })
	reload_find(first, 'click')?.on_event(ElementEvent{ kind: .click })
	w.set_text('name', 'Grace')
	w.focus('name')
	w.request_refresh()
	w.headless_frame()
	assert w.focused_id() == 'name'
	// The edit lives in the backend's control; the declaration still says Ada.
	assert w.text('name') == 'Grace'
	assert reload_texts(root.element()) == ['Notes', 'Ada', 'Count 2', 'Click 1']
	// Edit both files: the document gains an element and a style, the
	// imported component a new text.
	os.write_file(document, reload_first.replace('Label(id: "title", text: app.title)',
		'Label(id: "title", text: app.title, style: [foreground(#FF0000)])').replace('on_click: app.click)',
		'on_click: app.click)\n\tLabel(id: "added", text: "Added")'))!
	os.write_file(component, reload_counter.replace('"\${label} \${count}"', '"\${label}: \${count}"'))!
	os_touch_later(document)
	os_touch_later(component)
	assert interpreter.changed()
	interpreter.stale = true
	w.request_refresh()
	w.headless_frame()
	assert root.component.is_disposed()
	mut next := interpreter.root()?
	assert next != root
	reloaded := next.element()
	assert reload_find(reloaded, 'title')?.text_style.color == 0xff0000
	assert reloaded.children[2].text == 'Count: 2'
	assert reloaded.children[2].id == first.children[2].id
	assert reload_find(reloaded, 'click')?.text == 'Click 1'
	assert reload_find(reloaded, 'added')?.text == 'Added'
	assert w.text('name') == 'Grace'
	assert w.focused_id() == 'name'
	assert w.layout_error == ''
	// A document that no longer loads keeps the running one.
	os.write_file(document, 'Column { Label(text: app.missing) }')!
	os_touch_later(document)
	interpreter.stale = true
	w.request_refresh()
	w.headless_frame()
	assert interpreter.root()? == next
	assert !next.component.is_disposed()
	assert !interpreter.stale
	interpreter.dispose()
	assert next.component.is_disposed()
}

fn test_open_vml_runs_a_document_file() ! {
	directory := os.join_path(os.temp_dir(), 'ui2-vml-run-${os.getpid()}')
	os.mkdir_all(directory)!
	defer { os.rmdir_all(directory) or {} }
	document := os.join_path(directory, 'app.vml')
	os.write_file(document, 'Column(id: "root") { Label(id: "title", text: app.title) }')!
	mut app := &ReloadApp{}
	mut ui_app := new_app()
	mut w := open_vml[ReloadApp](mut ui_app,
		source_path: document
		model:       app
		title:       'Notes'
		width:       320
		height:      240
	)!
	ui_app.run()
	assert w.title == 'Notes'
	assert w.layout_error == ''
	assert reload_find(w.root, 'title')?.text == 'Notes'
	w.quit()
	run_vml[ReloadApp](source_path: os.join_path(directory, 'missing.vml'), model: app) or {
		assert err.msg().contains('missing.vml')
		return
	}
	assert false
}

// The watcher compares modification times; make each write visibly newer.
fn os_touch_later(path string) {
	attributes := os.stat(path) or { return }
	os.utime(path, int(attributes.mtime + 2), int(attributes.mtime + 2)) or {}
}
