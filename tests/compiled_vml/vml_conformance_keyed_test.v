// vtest vflags: -d vml_interpreter -d ui2_headless
// vtest build: vml_conformance?
module main

import ui2

// Conformance of the interpreter with compiled VML (ui2.vml_conformance) for
// keyed and nested repeaters of components with slot content: keyed.vml and
// nested.vml (both importing row_item.vml).

pub struct KeyedContractRow {
pub:
	id    string
	title string
}

pub struct KeyedContractGroup {
pub:
	id   string
	rows []KeyedContractRow
}

@[heap]
pub struct KeyedContractApp {
pub mut:
	rows    []KeyedContractRow   = [KeyedContractRow{'a', 'Alpha'}, KeyedContractRow{'b', 'Beta'}]
	groups  []KeyedContractGroup = [
		KeyedContractGroup{
			id:   'a'
			rows: [KeyedContractRow{'x', 'A'}, KeyedContractRow{'y', 'AY'}]
		},
		KeyedContractGroup{
			id:   'b'
			rows: [KeyedContractRow{'x', 'B'}]
		},
	]
	suffix  string = 'author'
	created int
}

pub fn (mut app KeyedContractApp) new_counter() int {
	app.created++
	return 0
}

fn keyed_tree(mut app KeyedContractApp, frame ui2.Rect) ui2.Element {
	return $vml('keyed.vml', frame)
}

fn nested_tree(mut app KeyedContractApp, frame ui2.Rect) ui2.Element {
	return $vml('nested.vml', frame)
}

fn keyed_reset(mut app KeyedContractApp) {
	app = KeyedContractApp{}
}

fn test_keyed_interpreted_vml_matches_compiled() {
	mut app := KeyedContractApp{}
	report := ui2.vml_conformance[KeyedContractApp](
		path:     @DIR + '/keyed.vml'
		frame:    ui2.rect(0, 0, 400, 300)
		model:    &app
		reset:    keyed_reset
		compiled: keyed_tree
	) or { panic(err) }
	println(report)
	assert report.equal(), report.str()
}

fn test_nested_interpreted_vml_matches_compiled() {
	mut app := KeyedContractApp{}
	report := ui2.vml_conformance[KeyedContractApp](
		path:     @DIR + '/nested.vml'
		frame:    ui2.rect(0, 0, 400, 300)
		model:    &app
		reset:    keyed_reset
		compiled: nested_tree
	) or { panic(err) }
	println(report)
	assert report.equal(), report.str()
}
