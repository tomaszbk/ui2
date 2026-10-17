// vtest vflags: -d vml_props
module ui2

// Reactive structural widgets and parts (tabs, options, runs, message box
// actions, menu items, tree nodes), an anchored overlay and bound controls
// (fixtures/widget_parts.vml), written by hand in the shape of the generic
// lowering. Events and model changes keep both documents equal.

fn w_parts_compiled(mut app PropsApp) Element {
	return $vml('fixtures/widget_parts.vml', rect(0, 0, 420, 900))
}

fn w_action(mut app PropsApp, mut owner CompiledVmlComponent, name string) ElementCallback {
	return owner.callback(fn [mut app, name] (event ElementEvent) ! {
		app.hit(name)
	})
}

fn w_parts_generic(mut app PropsApp) !Element {
	mut d := vml_document(rect(0, 0, 420, 900))!
	mut owner := d.owner
	mut root := vml_root(mut owner, ColumnProps{ width: 420, height: 900 }, id: 'parts', path: '0')!
	mut tabs := vml_child(mut root, mut owner, TabbedPanelProps{ width: 300, height: 120 },
		id:   'tabs'
		path: '0.0'
	)!
	tabs.prop('current', fn [mut app, mut owner] (mut p TabbedPanelProps) ! {
		owner.watch_app()!
		p.current = app.tab
	})!
	mut first := vml_child(mut tabs, mut owner, TabProps{
		on_select: w_action(mut app, mut owner, 't1')
	}, id: 't1', path: '0.0.0')!
	first.prop('text', fn [mut app, mut owner] (mut p TabProps) ! {
		owner.watch_app()!
		p.text = app.name
	})!
	mut notes := vml_child(mut first, mut owner, LabelProps{ width: 100, height: 20 },
		path: '0.0.0.0'
	)!
	notes.prop('text', fn [mut app, mut owner] (mut p LabelProps) ! {
		owner.watch_app()!
		p.text = app.notes
	})!
	mut second := vml_child(mut tabs, mut owner, TabProps{ text: 'Second' },
		id:   't2'
		path: '0.0.1'
	)!
	second.prop('enabled', fn [mut app, mut owner] (mut p TabProps) ! {
		owner.watch_app()!
		p.enabled = app.agree
	})!
	vml_child(mut second, mut owner, ViewProps{}, path: '0.0.1.0')!
	mut choice := vml_child(mut root, mut owner, DropdownProps{ width: 200, height: 30 },
		id:   'choice'
		path: '0.1'
	)!
	choice.prop('text', fn [mut app, mut owner] (mut p DropdownProps) ! {
		owner.watch_app()!
		p.text = app.color
	})!
	choice.bind('text', fn [mut app] (p DropdownProps) ! {
		app.color = vml_assign(app.color, p.text)
	})!
	mut option := vml_child(mut choice, mut owner, OptionProps{}, path: '0.1.0')!
	option.prop('text', fn [mut app, mut owner] (mut p OptionProps) ! {
		owner.watch_app()!
		p.text = app.name
	})!
	vml_child(mut choice, mut owner, OptionProps{ text: 'Green' }, path: '0.1.1')!
	mut rich := vml_child(mut root, mut owner, LabelProps{ width: 200, height: 20 },
		id:   'rich'
		path: '0.2'
	)!
	mut run := vml_child(mut rich, mut owner, RunProps{}, path: '0.2.0')!
	run.prop('text', fn [mut app, mut owner] (mut p RunProps) ! {
		owner.watch_app()!
		p.text = app.name
	})!
	vml_child(mut rich, mut owner,
		RunProps{ text: '!', style: compose_styles([style_weight(700)]) },
		path: '0.2.1'
	)!
	mut message := vml_child(mut root, mut owner, MessageBoxProps{ width: 300, height: 150 },
		id:   'box'
		path: '0.3'
	)!
	message.prop('title', fn [mut app, mut owner] (mut p MessageBoxProps) ! {
		owner.watch_app()!
		p.title = app.name
	})!
	message.prop('text', fn [mut app, mut owner] (mut p MessageBoxProps) ! {
		owner.watch_app()!
		p.text = app.notes
	})!
	message.prop('hidden', fn [mut app, mut owner] (mut p MessageBoxProps) ! {
		owner.watch_app()!
		p.hidden = app.msg_hidden
	})!
	mut ok := vml_child(mut message, mut owner, ButtonProps{
		on_click: w_action(mut app, mut owner, 'ok')
	}, id: 'ok', path: '0.3.0')!
	ok.prop('text', fn [mut app, mut owner] (mut p ButtonProps) ! {
		owner.watch_app()!
		p.text = app.place
	})!
	vml_child(mut root, mut owner, ButtonProps{ text: 'Open', width: 80, height: 30 },
		id:   'trigger'
		path: '0.4'
	)!
	mut dialog := vml_child(mut root, mut owner, DialogProps{
		width:  200
		height: 100
		anchor: 'trigger'
	}, id: 'dialog', path: '0.5')!
	dialog.prop('open', fn [mut app, mut owner] (mut p DialogProps) ! {
		owner.watch_app()!
		p.open = app.open
	})!
	mut inside := vml_child(mut dialog, mut owner, LabelProps{ width: 100, height: 20 },
		path: '0.5.0'
	)!
	inside.prop('text', fn [mut app, mut owner] (mut p LabelProps) ! {
		owner.watch_app()!
		p.text = app.name
	})!
	mut menu_view := vml_child(mut root, mut owner, ViewProps{ width: 40, height: 40 },
		id:   'menu_view'
		path: '0.6'
	)!
	mut copy := vml_child(mut menu_view, mut owner, MenuItemProps{
		on_click: w_action(mut app, mut owner, 'copy')
	}, id: 'copy', path: '0.6.0')!
	copy.prop('text', fn [mut app, mut owner] (mut p MenuItemProps) ! {
		owner.watch_app()!
		p.text = app.name
	})!
	mut agree := vml_child(mut root, mut owner, CheckboxProps{
		text:   'Agree'
		width:  120
		height: 24
	}, id: 'agree', path: '0.7')!
	agree.prop('checked', fn [mut app, mut owner] (mut p CheckboxProps) ! {
		owner.watch_app()!
		p.checked = app.agree
	})!
	agree.bind('checked', fn [mut app] (p CheckboxProps) ! {
		app.agree = vml_assign(app.agree, p.checked)
	})!
	mut level := vml_child(mut root, mut owner, SliderProps{ width: 120, height: 24 }, path: '0.8')!
	level.prop('value', fn [mut app, mut owner] (mut p SliderProps) ! {
		owner.watch_app()!
		p.value = app.level
	})!
	level.bind('value', fn [mut app] (p SliderProps) ! {
		app.level = vml_assign(app.level, p.value)
	})!
	mut tree := vml_child(mut root, mut owner, TreeViewProps{ width: 200, height: 80 },
		id:   'tree'
		path: '0.9'
	)!
	mut node := vml_child(mut tree, mut owner, TreeNodeProps{}, id: 'n1', path: '0.9.0')!
	node.prop('text', fn [mut app, mut owner] (mut p TreeNodeProps) ! {
		owner.watch_app()!
		p.text = DisplayText(app.name)
	})!
	node.prop('expanded', fn [mut app, mut owner] (mut p TreeNodeProps) ! {
		owner.watch_app()!
		p.expanded = app.dark
	})!
	return d.finish()!
}

// The compiled lowering patches some reactive fields onto the element its
// constructor built: `checked` and `value` of a bound control without the
// accessibility value the constructor derives from them, and the `text` of a
// MessageBox root (its text is drawn by a generated child). The generic commit
// runs the constructor again, so only those derived fields may differ.
fn w_assert_equal_except(name string, compiled Element, generic Element) {
	mut out := []string{}
	props_diff(compiled, generic, name, mut out)
	unexpected := out.filter(!it.contains('.accessibility_value:') && !it.contains('/3:box.text:'))
	for line in unexpected {
		eprintln(line)
	}
	assert unexpected.len == 0
}

fn w_parts_update(mut app PropsApp) {
	app.name = 'Grace'
	app.notes = 'updated'
	app.tab = 1
	app.open = false
	app.msg_hidden = true
	app.dark = true
	app.place = 'Home'
	app.agree = false
}

fn test_generic_parts_overlays_and_bindings_match_compiled_vml() {
	mut compiled_app := PropsApp{}
	mut generic_app := PropsApp{}
	compiled := w_parts_compiled(mut compiled_app)
	generic := w_parts_generic(mut generic_app)!
	assert_props_equal('parts', compiled, generic)
	mut compiled_root := compiled.compiled_node
	mut generic_root := generic.compiled_node
	compiled_root.mount()!
	generic_root.mount()!
	// Every event kind on every callback: bound controls write back first.
	assert_props_events(compiled, generic, mut compiled_app, mut generic_app)
	assert generic_app.agree && generic_app.color == 'T1' && generic_app.level == 1.5
	w_assert_equal_except('parts events', compiled_root.element(), generic_root.element())
	assert generic_root.element().children[7].accessibility_value == 'checked'
	assert generic_root.element().children[8].accessibility_value == '1.5'
	w_parts_update(mut compiled_app)
	w_parts_update(mut generic_app)
	compiled_root.component.invalidate_app()!
	generic_root.component.invalidate_app()!
	w_assert_equal_except('parts updated', compiled_root.element(), generic_root.element())
	assert generic_root.element().children[3].hidden
	compiled_root.dispose_document()!
	generic_root.dispose_document()!
	assert generic_root.component.runtime.stats() == SignalStats{}
}
