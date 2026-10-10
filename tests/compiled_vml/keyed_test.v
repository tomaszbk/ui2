module main

import ui2

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
	rows    []KeyedContractRow
	groups  []KeyedContractGroup
	suffix  string = 'author'
	created int
}

fn test_compiled_nested_repeaters_flatten_and_preserve_independent_keyed_instances() ! {
	mut app := &KeyedContractApp{
		groups: [
			KeyedContractGroup{ id: 'a', rows: [KeyedContractRow{'x', 'A'}] },
			KeyedContractGroup{ id: 'b', rows: [KeyedContractRow{'x', 'B'}] },
		]
	}
	initial := $vml('nested.vml', ui2.rect(0, 0, 400, 300))
	mut root := initial.compiled_node
	root.mount()!
	children := root.element().children[0].children
	assert children.len == 6
	assert children[0].text == 'Before' && children[5].text == 'After'
	assert children[1].kind == .label && children[3].kind == .label
	first := children[2]
	second := children[4]
	assert first.key != second.key
	assert app.created == 2
	first.children[0].on_event(ui2.ElementEvent{ kind: .tap })
	first.children[0].on_event(ui2.ElementEvent{ kind: .tap })
	second.children[0].on_event(ui2.ElementEvent{ kind: .tap })
	creation := root.component.runtime.stats()
	app.groups = [
		KeyedContractGroup{ id: 'b', rows: [KeyedContractRow{'x', 'Updated B'}] },
		KeyedContractGroup{ id: 'a', rows: [KeyedContractRow{'x', 'Updated A'}] },
	]
	root.component.invalidate_app()!
	reordered := root.element().children[0].children
	assert reordered.len == 6
	assert reordered[2].compiled_node == second.compiled_node
	assert reordered[4].compiled_node == first.compiled_node
	assert reordered[2].children[0].text == 'Updated B'
	assert reordered[4].children[1].text == '2'
	assert reordered[2].children[1].text == '1'
	assert reordered[4].children[2].text == 'Updated A/author'
	assert app.created == 2
	assert root.component.runtime.stats() == creation
	app.groups = [KeyedContractGroup{ id: 'b', rows: [KeyedContractRow{'x', 'Remaining'}] }]
	root.component.invalidate_app()!
	assert root.element().children[0].children.len == 4
	assert first.compiled_node.component.is_disposed()
	first.children[0].on_event(ui2.ElementEvent{ kind: .tap })
	assert root.element().children[0].children[2].children[1].text == '1'
	app.groups << KeyedContractGroup{ id: 'a', rows: [KeyedContractRow{'x', 'New'}] }
	root.component.invalidate_app()!
	assert app.created == 3
	assert root.element().children[0].children[4].children[1].text == '0'
	root.dispose_document()!
	assert root.component.runtime.stats() == ui2.SignalStats{}
}

pub fn (mut app KeyedContractApp) new_counter() int {
	app.created++
	return 0
}

fn keyed_contract_tree(mut app KeyedContractApp) ui2.Element {
	return $vml('keyed.vml', ui2.rect(0, 0, 400, 300))
}

fn test_compiled_keyed_components_keep_instance_state_and_lexical_slot_sources() ! {
	mut app := &KeyedContractApp{
		rows: [KeyedContractRow{'a', 'A'}, KeyedContractRow{'b', 'B'}]
	}
	initial := keyed_contract_tree(mut app)
	mut root := initial.compiled_node
	root.mount()!
	rows := root.element().children[0].children
	assert rows.len == 4
	assert rows[0].text == 'Before'
	assert rows[3].text == 'After'
	assert rows[1].key == 'a'
	assert rows[2].key == 'b'
	assert app.created == 2
	created_stats := root.component.runtime.stats()
	first := rows[1]
	second := rows[2]
	first.children[0].on_event(ui2.ElementEvent{ kind: .tap })
	first.children[0].on_event(ui2.ElementEvent{ kind: .tap })
	second.children[0].on_event(ui2.ElementEvent{ kind: .tap })
	app.rows = [KeyedContractRow{'b', 'Updated B'}, KeyedContractRow{'a', 'Updated A'}]
	app.suffix = 'updated author'
	root.component.invalidate_app()!
	reordered := root.element().children[0].children
	assert reordered[1].compiled_node == second.compiled_node
	assert reordered[2].compiled_node == first.compiled_node
	assert reordered[1].children[0].text == 'Updated B'
	assert reordered[2].children[1].text == '2'
	assert reordered[1].children[1].text == '1'
	assert reordered[2].children[2].text == 'Updated A/updated author'
	assert app.created == 2
	assert root.component.runtime.stats() == created_stats
	app.rows = [KeyedContractRow{'a', 'Remaining'}]
	root.component.invalidate_app()!
	assert second.compiled_node.component.is_disposed()
	second.children[0].on_event(ui2.ElementEvent{ kind: .tap })
	assert root.element().children[0].children[1].children[1].text == '2'
	app.rows << KeyedContractRow{'b', 'New B'}
	root.component.invalidate_app()!
	assert app.created == 3
	assert root.element().children[0].children[2].children[1].text == '0'
	root.dispose_document()!
	assert root.component.runtime.stats() == ui2.SignalStats{}
}
