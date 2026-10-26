module main

// vml: syntax.vml

import ui2

pub struct SyntaxCell {
pub:
	id string
pub mut:
	value int
}

pub struct SyntaxRow {
pub:
	id string
pub mut:
	cells []SyntaxCell
}

pub struct SyntaxPlayer {
pub:
	name string
}

@[heap]
pub struct SyntaxApp {
pub mut:
	mode    int
	board   []SyntaxRow
	log     []string
	total   int = 1
	choice  ?string
	scores  map[string]int
	watches []string
	picks   []string
}

pub fn (app &SyntaxApp) player() SyntaxPlayer { return SyntaxPlayer{'ada'} }

pub fn (app &SyntaxApp) format_score(value int) string { return 'score ${value}' }

pub fn (mut app SyntaxApp) picked(value string) { app.picks << value }

pub fn (mut app SyntaxApp) watched(old int, now int) { app.watches << '${old}->${now}' }

fn syntax_app() &SyntaxApp {
	return &SyntaxApp{
		board:  [
			SyntaxRow{ id: 'a', cells: [SyntaxCell{'x', 1}, SyntaxCell{'y', 2}] },
			SyntaxRow{ id: 'b', cells: [SyntaxCell{'z', 3}] },
		]
		scores: {
			'a': 7
		}
	}
}

fn test_if_for_indexing_and_assignments() ! {
	mut app := syntax_app()
	initial := syntax_vml_framed(mut app, ui2.rect(0, 0, 400, 600))
	mut root := initial.compiled_node
	root.mount()!
	column := root.element().children[0]
	assert column.children[0].text == 'zero'
	rows := column.children[1..3]
	assert rows[0].children.map(it.accessibility_label) == ['0.0=1', '0.1=2']
	assert rows[1].children.map(it.accessibility_label) == ['1.0=3']
	assert column.children[3].text == 'ADA'
	app.mode = 1
	root.component.invalidate_app()!
	assert root.element().children[0].children[0].text == 'one'
	app.mode = 5
	root.component.invalidate_app()!
	assert root.element().children[0].children[0].text == 'many'
	root.element().children[0].children[2].children[0].on_event(ui2.ElementEvent{ kind: .click })
	assert app.board[1].cells[0].value == 13
	assert root.element().children[0].children[2].children[0].accessibility_label == '1.0=13'
	root.element().children[0].children[4].on_event(ui2.ElementEvent{ kind: .click })
	assert app.log == ['x'] && app.total == 3
	root.dispose_document()!
}

fn test_component_optional_map_fn_inputs_watch_and_id_refs() ! {
	mut app := syntax_app()
	initial := syntax_vml_framed(mut app, ui2.rect(0, 0, 400, 600))
	mut root := initial.compiled_node
	root.mount()!
	card := root.element().children[0].children[5]
	assert card.children[1].text == 'no choice'
	assert card.children[2].text == 'score 7'
	assert card.children[4].text == '1:0'
	card.children[3].on_event(ui2.ElementEvent{ kind: .click })
	card.children[3].on_event(ui2.ElementEvent{ kind: .click })
	assert app.watches == ['0->2', '2->4']
	updated := root.element().children[0].children[5]
	assert updated.children[3].accessibility_label == '4'
	assert updated.children[4].text == '3:4'
	app.choice = 'red'
	root.component.invalidate_app()!
	assert root.element().children[0].children[5].children[1].text == 'chose red'
	root.element().children[0].children[5].children[6].on_event(ui2.ElementEvent{ kind: .click })
	// The handler ran past `name_field.set_text(label)`, the ref of the id.
	assert app.picks == ['card']
	root.dispose_document()!
}
