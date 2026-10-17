// vtest vflags: -d vml_interpreter
module ui2

// The VML interpreter: documents built from source against a live model,
// with V semantics for the expression subset and load-time errors for
// everything else.

pub struct InterpItem {
pub:
	id    string
	title string
}

@[heap]
pub struct InterpApp {
pub mut:
	count int    = 2
	ratio f64    = 0.5
	name  string = 'Ada'
	flag  bool
	items []InterpItem = [InterpItem{'a', 'One'}, InterpItem{'b', 'Two'}]
	log   []string
	point ?OverlayPoint
pub:
	fixed int = 9
mut:
	private int
}

pub fn (mut a InterpApp) increment() {
	a.count++
}

pub fn (mut a InterpApp) add(n int) {
	a.count += n
}

pub fn (a &InterpApp) greeting(prefix string) string {
	return '${prefix} ${a.name}'
}

pub fn (mut a InterpApp) record(event ElementEvent) {
	a.log << '${event.kind} ${event.text}'
}

pub fn (mut a InterpApp) note(text string, value f64) {
	a.log << '${text}=${value}'
}

@[heap]
struct InterpHits {
mut:
	names []string
}

fn interp_find(el Element, id string) ?Element {
	if el.id == id { return el }
	for child in el.children {
		if found := interp_find(child, id) { return found }
	}
	return none
}

fn interp_build(source string, mut app InterpApp) !&CompiledVmlNode {
	element := vml_interpret(source, app, frame: rect(0, 0, 300, 200))!
	mut root := element.compiled_node
	root.mount()!
	return root
}

fn interp_text(root &CompiledVmlNode, id string) string {
	found := interp_find(root.element(), id) or { return '<missing ${id}>' }
	return found.text
}

fn interp_error(source string) string {
	mut app := &InterpApp{}
	vml_interpret(source, app, frame: rect(0, 0, 300, 200)) or { return err.msg() }
	return ''
}

fn test_interprets_a_document_and_follows_the_model() ! {
	mut app := &InterpApp{}
	mut root := interp_build('Column {
	Label(id: "label", text: "Count \${app.count}")
	Button(id: "add", text: "Add", on_click: app.increment)
}',
		mut app)!
	assert root.element().children.len == 2
	assert interp_text(root, 'label') == 'Count 2'
	button := interp_find(root.element(), 'add')?
	button.on_event(ElementEvent{ kind: .click })
	assert app.count == 3
	assert interp_text(root, 'label') == 'Count 3'
	app.count = 10
	root.component.invalidate_app()!
	assert interp_text(root, 'label') == 'Count 10'
	root.dispose_document()!
}

fn test_expressions_follow_v_semantics() ! {
	mut app := &InterpApp{}
	mut root := interp_build('Column {
	Label(id: "div", text: "\${app.count / 3} \${7 / 2} \${7.0 / 2} \${7 % 3} \${-app.count}")
	Label(id: "mix", text: "\${app.count * app.ratio} \${app.ratio + 1} \${app.count + 1}")
	Label(id: "logic", text: "\${!app.flag && app.count == 2} \${app.flag || app.name.len == 3}")
	Label(id: "pick", text: app.count > 1 ? "big" : "small")
	Label(id: "text", text: "\${app.name.len} \${app.count.str()} \${app.items.len}")
	Label(id: "greet", text: app.greeting("Hi"))
	Label(id: "number", text: app.count)
	Label(id: "float", text: app.ratio)
}',
		mut app)!
	assert interp_text(root, 'div') == '0 3 3.5 1 -2'
	// V rejects int * f64; the interpreter promotes to f64 (it may be less
	// strict than V, never stricter).
	assert interp_text(root, 'mix') == '1.0 1.5 3'
	assert interp_text(root, 'logic') == 'true true'
	assert interp_text(root, 'pick') == 'big'
	assert interp_text(root, 'text') == '3 2 2'
	assert interp_text(root, 'greet') == 'Hi Ada'
	// A number property takes a display text, as compiled VML formats it.
	assert interp_text(root, 'number') == '2'
	assert interp_text(root, 'float') == '0.5'
	root.dispose_document()!
}

fn test_handlers_write_the_model_and_call_methods() ! {
	mut app := &InterpApp{}
	mut root := interp_build('Column {
	Button(id: "a", on_click: app.add(5))
	Button(id: "b", on_click: { app.count++; app.name = "B\${app.count}" })
	Button(id: "c", on_click: app.flag = !app.flag)
	TextInput(id: "d", on_change: app.record)
	TextInput(id: "e", bind.text: app.name)
	Button(id: "f", on_click: app.note(event.text, event.x + 0.5))
}',
		mut app)!
	el := root.element()
	interp_find(el, 'a')?.on_event(ElementEvent{ kind: .click })
	assert app.count == 7
	interp_find(el, 'b')?.on_event(ElementEvent{ kind: .click })
	assert app.count == 8
	assert app.name == 'B8'
	interp_find(el, 'c')?.on_event(ElementEvent{ kind: .click })
	assert app.flag
	interp_find(el, 'd')?.on_event(ElementEvent{ kind: .change, text: 'typed' })
	assert app.log == ['change typed']
	interp_find(el, 'e')?.on_event(ElementEvent{ kind: .change, text: 'Grace' })
	assert app.name == 'Grace'
	interp_find(el, 'f')?.on_event(ElementEvent{ kind: .click, text: 'x', x: 2 })
	assert app.log.last() == 'x=2.5'
	root.dispose_document()!
}

fn test_components_state_slots_and_keyed_repeaters() ! {
	mut app := &InterpApp{}
	mut root := interp_build('component Row(title string, content slot) {
	state count := 0
	computed doubled := count * 2
	Column {
		Button(id: "inc", text: title, on_click: count++)
		Label(id: "count_label", text: "\${count}/\${doubled}")
		Slot(name: "content")
	}
}
Column(id: "rows") {
	Label(id: "before", text: "Before")
	Repeater(model: app.items, key: item.id) {
		Row(title: item.title) {
			Label(text: "\${item.title}:\${index}:\${app.name}")
		}
	}
}',
		mut app)!
	rows := root.element().children
	assert rows.len == 3
	assert rows[1].children[0].text == 'One'
	assert rows[1].children[2].text == 'One:0:Ada'
	assert rows[2].children[2].text == 'Two:1:Ada'
	rows[2].children[0].on_event(ElementEvent{ kind: .click })
	rows[2].children[0].on_event(ElementEvent{ kind: .click })
	assert root.element().children[2].children[1].text == '2/4'
	// Reordering keeps each keyed instance and its state.
	app.items = [InterpItem{'b', 'Second'}, InterpItem{'a', 'First'}, InterpItem{'c', 'Third'}]
	app.name = 'Eve'
	root.component.invalidate_app()!
	updated := root.element().children
	assert updated.len == 4
	assert updated[1].children[0].text == 'Second'
	assert updated[1].children[1].text == '2/4'
	assert updated[1].children[2].text == 'Second:0:Eve'
	assert updated[2].children[1].text == '0/0'
	assert updated[3].children[2].text == 'Third:2:Eve'
	assert updated[1].compiled_node == rows[2].compiled_node
	root.dispose_document()!
}

fn test_component_events_bound_inputs_refs_and_lifecycle() ! {
	mut app := &InterpApp{}
	mut root := interp_build('component Editor(bind name string, changed event(value string)) {
	state edits := 0
	ref field TextInput
	mount { app.note("mount", field.is_available() ? 1 : 0) }
	cleanup { app.note("cleanup", edits) }
	Column {
		TextInput(id: "input", ref: field, bind.text: name)
		Button(id: "notify", text: edits, on_click: { edits++; changed(name) })
	}
}
Column {
	Editor(bind.name: app.name, on_changed: app.note(value, 1))
}',
		mut app)!
	assert app.log == ['mount=1.0']
	editor := root.element().children[0]
	editor.children[0].on_event(ElementEvent{ kind: .change, text: 'Grace' })
	assert app.name == 'Grace'
	editor.children[1].on_event(ElementEvent{ kind: .click })
	assert app.log.last() == 'Grace=1.0'
	assert root.element().children[0].children[1].text == '1'
	app.name = 'Hopper'
	root.component.invalidate_app()!
	assert root.element().children[0].children[0].text == 'Hopper'
	root.dispose_document()!
	assert app.log.last() == 'cleanup=1.0'
}

fn test_references_run_as_handlers() ! {
	mut app := &InterpApp{}
	mut root := interp_build('component Inner(bumped event()) {
	Button(id: "bump", on_click: bumped)
}
component Stepper(stepped event(value int), relayed event()) {
	state count := 0
	fn step() {
		count++
		stepped(count)
	}
	fn relay() {
		count = count + 10
	}
	Column {
		Button(id: "stepper", text: count, on_click: step)
		Inner(on_bumped: relay)
		Inner(on_bumped: relayed)
	}
}
Column {
	Stepper(on_stepped: app.add, on_relayed: app.increment)
}',
		mut app)!
	stepper := root.element().children[0]
	stepper.children[0].on_event(ElementEvent{ kind: .click })
	assert app.count == 3
	assert root.element().children[0].children[0].text == '1'
	stepper.children[1].on_event(ElementEvent{ kind: .click })
	assert root.element().children[0].children[0].text == '11'
	stepper.children[2].on_event(ElementEvent{ kind: .click })
	assert app.count == 4
	root.dispose_document()!
}

fn test_styles_and_theme_tokens() ! {
	mut app := &InterpApp{}
	mut root := interp_build('style card = [background(#102030), padding(spacing.medium)]
Column {
	View(id: "plain", style: card)
	View(id: "mixed", style: [card, radius(radius.medium), app.flag ? background(#FFFFFF) : background(color.surface)])
	Label(id: "text", text: "x", style: [foreground(#FF0000), font_size(typography.body)])
}',
		mut app)!
	assert interp_find(root.element(), 'plain')?.box.bg == 0x102030
	assert interp_find(root.element(), 'mixed')?.box.radius > 0
	assert interp_find(root.element(), 'text')?.text_style.color == 0xff0000
	root.dispose_document()!
}

fn test_load_errors_name_the_construct() {
	assert interp_error('Label(text: app.missing)').contains('missing')
	assert interp_error('Label(text: "\${app.private}")').contains('private')
	assert interp_error('Button(on_click: app.fixed = 1)').contains('app.fixed')
	assert interp_error('Button(on_click: app.add())').contains('argument')
	assert interp_error('Label(text: sqrt(2))').contains('sqrt')
	assert interp_error('Label(id: "spacing", text: "x")').contains('spacing')
	assert interp_error('Unknown(text: "x")').contains('Unknown')
	assert interp_error('Label(colour: "x")').contains('colour')
	assert interp_error('Button(on_click: callback_missing)').contains('callback_missing')
	assert interp_error('Column { Repeater(model: app.count) { Label(text: "x") } }').len > 0
	assert interp_error('Label(text: ').len > 0
}

fn test_external_callbacks_and_sample_models() ! {
	mut hits := &InterpHits{}
	model := vml_sample_model({
		'title': VmlValue('Sample')
		'count': VmlValue(i64(3))
	}, fn [mut hits] (name string, args []VmlValue) {
		hits.names << name
	})
	mut closed := &InterpHits{}
	element := vml_interpret_model('Column {
	Label(id: "t", text: "\${app.title} \${app.count + 1}")
	Button(id: "b", on_click: app.save(app.count))
	Button(id: "c", on_click: callback_close)
	Button(id: "d", on_click: app.count++)
	Button(id: "e", on_click: callback_other)
}', model,
		frame:     rect(0, 0, 200, 100)
		callbacks: {
			'callback_close': fn [mut closed] (event ElementEvent) {
				closed.names << 'close'
			}
		}
		fallback:  fn (name string) ElementCallback {
			return fn [name] (event ElementEvent) {}
		}
	)!
	mut root := element.compiled_node
	root.mount()!
	assert interp_text(root, 't') == 'Sample 4'
	interp_find(root.element(), 'b')?.on_event(ElementEvent{ kind: .click })
	assert hits.names == ['save']
	interp_find(root.element(), 'c')?.on_event(ElementEvent{ kind: .click })
	assert closed.names == ['close']
	interp_find(root.element(), 'e')?.on_event(ElementEvent{ kind: .click })
	interp_find(root.element(), 'd')?.on_event(ElementEvent{ kind: .click })
	assert interp_text(root, 't') == 'Sample 5'
	root.dispose_document()!
}

fn test_reload_keeps_state_for_unchanged_paths_and_keys() ! {
	mut app := &InterpApp{}
	first := 'component Counter(title string) {
	state count := 0
	Button(id: "button", text: "\${title} \${count}", on_click: count++)
}
Column {
	Counter(title: "A")
	Repeater(model: app.items, key: item.id) {
		Counter(title: item.title)
	}
}'
	mut interpreter := vml_interpreter(first, vml_model(app), frame: rect(0, 0, 300, 200))!
	element := interpreter.build()!
	mut root := element.compiled_node
	root.mount()!
	element.children[0].on_event(ElementEvent{ kind: .click })
	element.children[2].on_event(ElementEvent{ kind: .click })
	element.children[2].on_event(ElementEvent{ kind: .click })
	assert root.element().children.map(it.text) == ['A 1', 'One 0', 'Two 2']
	ids := root.element().children.map(it.id)
	// An invalid source leaves the running document alone.
	if _ := interpreter.reload('Column { Label(text: app.missing) }') {
		assert false
	}
	assert !root.component.is_disposed()
	// A changed text and a new last element keep every state.
	second := first.replace('"\${title} \${count}"', '"\${title}: \${count}"').replace('Counter(title: item.title)\n\t}',
		'Counter(title: item.title)\n\t}\n\tLabel(text: "New")')
	reloaded := interpreter.reload(second)!
	assert root.component.is_disposed()
	mut next := reloaded.compiled_node
	next.mount()!
	assert next.element().children.map(it.text) == ['A: 1', 'One: 0', 'Two: 2', 'New']
	assert next.element().children.map(it.id)#[..3] == ids
	// A new first element moves every declaration after it: their state
	// starts over, as it does for compiled VML.
	third := second.replace('Column {', 'Column {\n\tLabel(text: "First")')
	moved := interpreter.reload(third)!
	mut last := moved.compiled_node
	last.mount()!
	assert last.element().children.map(it.text) == ['First', 'A: 0', 'One: 0', 'Two: 0', 'New']
	interpreter.dispose()
	assert last.component.is_disposed()
}
