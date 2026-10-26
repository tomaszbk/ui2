// vtest vflags: -d vml_interpreter -d ui2_headless
// vtest build: vml_conformance?
module main

// vml: contract.vml
// vml: named_slots.vml

import ui2

// Conformance of the interpreter with compiled VML (ui2.vml_conformance) for
// components with bindable inputs, typed events, refs, lifecycle and slots:
// contract.vml (importing editor.vml) and named_slots.vml (importing
// card.vml).

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

fn contract_tree(mut app ContractApp, frame ui2.Rect) ui2.Element {
	return contract_vml_framed(mut app, frame)
}

fn named_slots_tree(mut app ContractApp, frame ui2.Rect) ui2.Element {
	return named_slots_vml_framed(mut app, frame)
}

fn contract_reset(mut app ContractApp) {
	app = ContractApp{}
}

fn test_contract_interpreted_vml_matches_compiled() {
	mut app := ContractApp{}
	report := ui2.vml_conformance[ContractApp](
		path:     @DIR + '/contract.vml'
		frame:    ui2.rect(0, 0, 400, 300)
		model:    &app
		reset:    contract_reset
		compiled: contract_tree
	) or { panic(err) }
	println(report)
	assert report.equal(), report.str()
}

fn test_named_slots_interpreted_vml_matches_compiled() {
	mut app := ContractApp{}
	report := ui2.vml_conformance[ContractApp](
		path:     @DIR + '/named_slots.vml'
		frame:    ui2.rect(0, 0, 400, 300)
		model:    &app
		reset:    contract_reset
		compiled: named_slots_tree
	) or { panic(err) }
	println(report)
	assert report.equal(), report.str()
}
