// vtest vflags: -d vml_props -d vml_fixtures
module ui2

// vml: ../tests/compiled_vml/contract.vml
// vml: ../tests/compiled_vml/named_slots.vml

// Components with state, computed values, refs, bindable inputs, typed
// events, lifecycle hooks and slots (tests/compiled_vml/contract.vml and
// named_slots.vml), written by hand in the shape of the generic lowering.
// Both documents run the same events; trees and model state stay equal.

@[heap]
pub struct WContractApp {
pub mut:
	name     string = 'José'
	other    string = 'Ana'
	suffix   string = 'Author'
	observed []string
	refs     []bool
	cleanups []int
	doubles  []int
}

pub fn (mut app WContractApp) observe(value string) {
	app.observed << value
}

pub fn (mut app WContractApp) record_ref(available bool) {
	app.refs << available
}

pub fn (mut app WContractApp) record_cleanup(value int, doubled int) {
	app.cleanups << value
	app.doubles << doubled
}

fn (app &WContractApp) state() string {
	return '${app.name} ${app.other} ${app.suffix} ${app.observed} ${app.refs} ${app.cleanups} ${app.doubles}'
}

fn w_contract_compiled(mut app WContractApp) Element {
	return contract_vml_framed(mut app, rect(0, 0, 400, 300))
}

fn w_named_slots_compiled(mut app WContractApp) Element {
	return named_slots_vml_framed(mut app, rect(0, 0, 400, 300))
}

// The Editor component, lowered at one call site: its bindable `name` input
// reads and writes the caller's target through `read` and `write`.
fn w_editor(mut app WContractApp, mut owner CompiledVmlComponent, mut parent VmlWidgetNode[ColumnProps], path string, read fn () !string, write fn (string), changed fn (string), content fn (mut CompiledVmlComponent, mut VmlWidgetNode[ColumnProps]) !) ! {
	mut c := owner.child(path)!
	mut name_input := c.computed[string]('@input:name', read)!
	mut name := c.state_factory('name', fn [mut name_input] () !string {
		return name_input.get()!
	})!
	c.scope.effect('@input:name', fn [mut name_input, mut name] () ! {
		name.set(name_input.get()!)!
	})!
	set_name := fn [write, mut name] (value string) ! {
		write(value)
		name.set(value)!
	}
	mut field := c.ref[TextInputProps]('field')!
	mut edits := c.state_factory('edits', fn () !int {
		return 0
	})!
	mut doubled := c.computed[int]('doubled', fn [mut edits] () !int {
		return edits.get()! * 2
	})!
	c.on_mount('mount', fn [mut app, field] () ! {
		app.record_ref(field.is_available())
	})!
	c.on_cleanup('cleanup', fn [mut app, mut edits, mut doubled] () {
		app.record_cleanup(edits.get() or { -1 }, doubled.get() or { -1 })
	})!
	mut root := vml_child(mut parent, mut c, ColumnProps{}, path: path + '.root')!
	mut input := vml_child(mut root, mut c, TextInputProps{}, id: 'input', path: path + '.root.0')!
	input.prop('text', fn [mut name] (mut p TextInputProps) ! {
		p.text = name.get()!
	})!
	input.bind('text', fn [set_name, mut name] (p TextInputProps) ! {
		set_name(vml_assign(name.peek()!, p.text))!
	})!
	field.bind_widget(mut input)!
	mut notify := vml_child(mut root, mut c, ButtonProps{
		on_click: c.callback(fn [mut edits, changed, mut name] (event ElementEvent) ! {
			edits.set(edits.get()! + 1)!
			changed(name.get()!)
		})
	}, id: 'notify', path: path + '.root.1')!
	notify.prop('text', fn [mut edits] (mut p ButtonProps) ! {
		p.text = edits.get()!
	})!
	mut slot := owner.slot_child(mut c, path + '.root.2')!
	content(mut slot, mut root)!
}

fn w_contract_generic(mut app WContractApp) !Element {
	mut d := vml_document(rect(0, 0, 400, 300), follow_viewport: true)!
	mut owner := d.owner
	mut n_0 := vml_root(mut owner, ScreenProps{}, id: 'root', path: '0')!
	mut n_0_0 := vml_child(mut n_0, mut owner, ColumnProps{}, path: '0.0')!
	w_editor(mut app, mut owner, mut n_0_0, '0.0.0', fn [mut app, mut owner] () !string {
		owner.watch_app()!
		return app.name
	}, fn [mut app] (value string) {
		app.name = value
	}, fn [mut app] (value string) {
		app.observe(value)
	}, fn [mut app] (mut slot CompiledVmlComponent, mut parent VmlWidgetNode[ColumnProps]) ! {
		mut label := vml_child(mut parent, mut slot, LabelProps{}, id: 'slot', path: '0.0.0.root.2')!
		label.prop('text', fn [mut app, mut slot] (mut p LabelProps) ! {
			slot.watch_app()!
			p.text = app.suffix
		})!
	})!
	w_editor(mut app, mut owner, mut n_0_0, '0.0.1', fn [mut app, mut owner] () !string {
		owner.watch_app()!
		return app.other
	}, fn [mut app] (value string) {
		app.other = value
	}, fn (value string) {}, fn (mut slot CompiledVmlComponent, mut parent VmlWidgetNode[ColumnProps]) ! {
		vml_child(mut parent, mut slot, LabelProps{ text: 'Other' }, path: '0.0.1.root.2')!
	})!
	return d.finish()!
}

fn w_editor_at(el Element, index int) Element {
	return el.compiled_node.element().children[0].children[index]
}

fn test_generic_components_bindings_refs_and_slots_match_compiled_vml() {
	mut compiled_app := &WContractApp{}
	mut generic_app := &WContractApp{}
	compiled := w_contract_compiled(mut compiled_app)
	generic := w_contract_generic(mut generic_app)!
	assert_props_equal('contract', compiled, generic)
	mut compiled_root := compiled.compiled_node
	mut generic_root := generic.compiled_node
	compiled_root.mount()!
	generic_root.mount()!
	assert generic_app.refs == [true, true]
	assert generic_app.state() == compiled_app.state()
	// A bound change writes back before handlers; the click reads the
	// written value through the component input.
	for el in [compiled, generic] {
		first := w_editor_at(el, 0)
		second := w_editor_at(el, 1)
		first.children[0].on_event(ElementEvent{ kind: .change, text: 'María' })
		first.children[0].on_event(ElementEvent{ kind: .click })
		first.children[1].on_event(ElementEvent{ kind: .click })
		second.children[1].on_event(ElementEvent{ kind: .click })
		second.children[0].on_event(ElementEvent{ kind: .change, text: 'Eva' })
	}
	assert generic_app.name == 'María'
	assert generic_app.other == 'Eva'
	assert generic_app.observed == ['María']
	assert generic_app.state() == compiled_app.state()
	assert_props_equal('contract events', compiled_root.element(), generic_root.element())
	compiled_app.suffix = 'Updated author'
	generic_app.suffix = 'Updated author'
	compiled_app.name = 'Zoe'
	generic_app.name = 'Zoe'
	compiled_root.component.invalidate_app()!
	generic_root.component.invalidate_app()!
	assert w_editor_at(generic, 0).children[2].text == 'Updated author'
	assert w_editor_at(generic, 0).children[0].text == 'Zoe'
	assert_props_equal('contract update', compiled_root.element(), generic_root.element())
	mut owner := generic_root.component
	compiled_root.dispose_document()!
	generic_root.dispose_document()!
	assert generic_app.cleanups == [1, 1]
	assert generic_app.doubles == [2, 2]
	assert generic_app.state() == compiled_app.state()
	assert owner.runtime.stats() == SignalStats{}
}

// Card(title: "Receiver") with named header and body slots, at the root.
fn w_named_slots_generic(mut app WContractApp) !Element {
	mut d := vml_document(rect(0, 0, 400, 300), follow_viewport: true)!
	mut owner := d.owner
	mut c := owner.child('0')!
	mut title_input := c.computed[string]('@input:title', fn () !string {
		return 'Receiver'
	})!
	mut title := c.state_factory('title', fn [mut title_input] () !string {
		return title_input.get()!
	})!
	c.scope.effect('@input:title', fn [mut title_input, mut title] () ! {
		title.set(title_input.get()!)!
	})!
	mut root := vml_root(mut c, ColumnProps{}, path: '0.root')!
	mut heading := vml_child(mut root, mut c, LabelProps{}, path: '0.root.0')!
	heading.prop('text', fn [mut title] (mut p LabelProps) ! {
		p.text = title.get()!
	})!
	mut header := owner.slot_child(mut c, '0.root.1')!
	mut name := vml_child(mut root, mut header, LabelProps{}, path: '0.root.1')!
	name.prop('text', fn [mut app, mut header] (mut p LabelProps) ! {
		header.watch_app()!
		p.text = app.name
	})!
	mut body := owner.slot_child(mut c, '0.root.2')!
	mut suffix := vml_child(mut root, mut body, LabelProps{}, path: '0.root.2')!
	suffix.prop('text', fn [mut app, mut body] (mut p LabelProps) ! {
		body.watch_app()!
		p.text = app.suffix
	})!
	return d.finish()!
}

fn test_generic_named_slots_match_compiled_vml() {
	mut compiled_app := &WContractApp{}
	mut generic_app := &WContractApp{}
	compiled := w_named_slots_compiled(mut compiled_app)
	generic := w_named_slots_generic(mut generic_app)!
	assert_props_equal('named slots', compiled, generic)
	mut compiled_root := compiled.compiled_node
	mut generic_root := generic.compiled_node
	compiled_root.mount()!
	generic_root.mount()!
	compiled_app.name = 'María'
	compiled_app.suffix = 'Body'
	generic_app.name = 'María'
	generic_app.suffix = 'Body'

	compiled_root.component.invalidate_app()!
	generic_root.component.invalidate_app()!
	assert generic_root.element().children.map(it.text) == ['Receiver', 'María', 'Body']
	assert_props_equal('named slots update', compiled_root.element(), generic_root.element())
	generic_root.dispose_document()!
	compiled_root.dispose_document()!
	assert generic_root.component.runtime.stats() == SignalStats{}
}
