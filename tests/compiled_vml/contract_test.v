module main

import ui2

@[heap]
pub struct ContractApp {
pub mut:
	name     string = 'José'
	other    string = 'Ana'
	suffix   string = 'Author'
	observed []string
	refs     []bool
	cleanups []int
	doubles  []int
}

pub fn (mut app ContractApp) observe(value string) { app.observed << value }

pub fn (mut app ContractApp) record_ref(available bool) { app.refs << available }

pub fn (mut app ContractApp) record_cleanup(value int, doubled int) {
	app.cleanups << value
	app.doubles << doubled
}

fn contract_tree(mut app ContractApp) ui2.Element {
	return $vml('contract.vml', ui2.rect(0, 0, 400, 300))
}

fn named_slots_tree(mut app ContractApp) ui2.Element {
	return $vml('named_slots.vml', ui2.rect(0, 0, 400, 300))
}

fn test_compiled_bindable_inputs_typed_events_slots_and_refs_share_lifetime() ! {
	mut app := &ContractApp{}
	initial := contract_tree(mut app)
	mut root := initial.compiled_node
	root.mount()!
	assert app.refs == [true, true]
	first := root.element().children[0].children[0]
	second := root.element().children[0].children[1]
	assert first.children[0].text == 'José'
	assert first.children[2].text == 'Author'
	first.children[0].on_event(ui2.ElementEvent{ kind: .change, text: 'María' })
	assert app.name == 'María'
	assert app.other == 'Ana'
	first.children[1].on_event(ui2.ElementEvent{ kind: .tap })
	second.children[1].on_event(ui2.ElementEvent{ kind: .tap })
	assert app.observed == ['María']
	app.suffix = 'Updated author'
	root.component.invalidate_app()!
	updated := root.element().children[0].children[0]
	assert updated.children[2].text == 'Updated author'
	assert updated.children[1].text == '1'
	assert updated.id == first.id
	mut owner := root.component
	root.dispose_document()!
	assert app.cleanups == [1, 1]
	assert app.doubles == [2, 2]
	first.children[1].on_event(ui2.ElementEvent{ kind: .tap })
	assert app.observed == ['María']
	assert owner.runtime.stats() == ui2.SignalStats{}
}

fn test_named_slots_keep_declared_order_and_author_values() ! {
	mut app := &ContractApp{}
	initial := named_slots_tree(mut app)
	mut root := initial.compiled_node
	root.mount()!
	assert root.element().children.map(it.text) == ['Receiver', 'José', 'Author']
	app.name = 'María'
	app.suffix = 'Body'
	root.component.invalidate_app()!
	assert root.element().children.map(it.text) == ['Receiver', 'María', 'Body']
	root.dispose_document()!
	assert root.component.runtime.stats() == ui2.SignalStats{}
}
