// vtest vflags: -d vml_props
module ui2

// The keyed repeater fixture (tests/compiled_vml/keyed.vml): a Repeater of
// RowItem components with state and a slot, written by hand in the shape of
// the generic lowering, against the compiled lowering. Both documents run the
// same actions; their retained trees and model state stay equal.

pub struct WKeyedRow {
pub:
	id    string
	title string
}

pub struct WKeyedGroup {
pub:
	id   string
	rows []WKeyedRow
}

@[heap]
pub struct WKeyedApp {
pub mut:
	rows    []WKeyedRow
	groups  []WKeyedGroup
	suffix  string = 'author'
	created int
}

pub fn (mut app WKeyedApp) new_counter() int {
	app.created++
	return 0
}

fn w_keyed_compiled(mut app WKeyedApp, frame Rect) Element {
	return $vml('../tests/compiled_vml/keyed.vml', frame)
}

// RowItem(title: item.title) { Label(text: "${item.title}/${app.suffix}") },
// lowered inside a repeater item: `name` is the component's child name.
fn w_row_item(mut app WKeyedApp, mut item_owner CompiledVmlComponent, mut segment VmlSegment, mut item Signal[WKeyedRow], name string, path string) ! {
	mut c := item_owner.child(name)!
	mut title_input := c.computed[string]('@input:title', fn [mut item] () !string {
		return item.get()!.title
	})!
	mut title := c.state_factory('title', fn [mut title_input] () !string {
		return title_input.get()!
	})!
	c.scope.effect('@input:title', fn [mut title_input, mut title] () ! {
		title.set(title_input.get()!)!
	})!
	mut count := c.state_factory('count', fn [mut app] () !int {
		return app.new_counter()
	})!
	mut root := vml_child(mut segment, mut c, ColumnProps{}, path: path + '.root')!
	mut button := vml_child(mut root, mut c, ButtonProps{
		on_click: c.callback(fn [mut count] (event ElementEvent) ! {
			count.set(count.get()! + 1)!
		})
	}, id: 'increment', path: path + '.root.0')!
	button.prop('text', fn [mut title] (mut p ButtonProps) ! {
		p.text = title.get()!
	})!
	mut label := vml_child(mut root, mut c, LabelProps{}, id: 'count_label', path: path + '.root.1')!
	label.prop('text', fn [mut count] (mut p LabelProps) ! {
		p.text = count.get()!
	})!
	mut slot := item_owner.slot_child(mut c, name + '.root.2')!
	mut content := vml_child(mut root, mut slot, LabelProps{}, path: path + '.root.2')!
	content.prop('text', fn [mut app, mut slot, mut item] (mut p LabelProps) ! {
		slot.watch_app()!
		p.text = '${item.get()!.title}/${app.suffix}'
	})!
}

fn w_keyed_generic(mut app WKeyedApp, frame Rect) !Element {
	mut d := vml_document(frame)!
	mut owner := d.owner
	mut n_0 := vml_root(mut owner, ScreenProps{}, path: '0')!
	mut n_0_0 := vml_child(mut n_0, mut owner, ColumnProps{ align_items: .stretch },
		id:   'rows'
		path: '0.0'
	)!
	vml_child(mut n_0_0, mut owner, LabelProps{ text: 'Before' }, id: 'before', path: '0.0.0')!
	vml_repeat(mut n_0_0, '0_0_1', fn [mut app, mut owner] () ![]WKeyedRow {
		owner.watch_app()!
		return app.rows
	}, fn (item WKeyedRow) string {
		return item.id
	}, fn [mut app] (mut item_owner CompiledVmlComponent, mut segment VmlSegment, item_input &Signal[WKeyedRow]) ! {
		mut item := unsafe { item_input }
		item_owner.state('@index', 0)!
		w_row_item(mut app, mut item_owner, mut segment, mut item, '0_0.1.0', '0.0.1.0')!
	}, source: 'keyed.vml', line: 5, column: 9)!
	vml_child(mut n_0_0, mut owner, LabelProps{ text: 'After' }, id: 'after', path: '0.0.2')!
	return d.finish()!
}

fn w_rows(el Element) []Element {
	return el.compiled_node.element().children[0].children
}

fn test_generic_keyed_repeater_matches_compiled_vml() {
	frame := rect(0, 0, 400, 300)
	mut compiled_app := &WKeyedApp{
		rows: [WKeyedRow{'a', 'A'}, WKeyedRow{'b', 'B'}]
	}
	mut generic_app := &WKeyedApp{
		rows: [WKeyedRow{'a', 'A'}, WKeyedRow{'b', 'B'}]
	}
	compiled := w_keyed_compiled(mut compiled_app, frame)
	generic := w_keyed_generic(mut generic_app, frame)!
	assert_props_equal('keyed', compiled, generic)
	mut compiled_root := compiled.compiled_node
	mut generic_root := generic.compiled_node
	compiled_root.mount()!
	generic_root.mount()!
	assert generic_app.created == 2
	// Actions run through each document's own callbacks.
	for el in [compiled, generic] {
		rows := w_rows(el)
		rows[1].children[0].on_event(ElementEvent{ kind: .click })
		rows[1].children[0].on_event(ElementEvent{ kind: .click })
		rows[2].children[0].on_event(ElementEvent{ kind: .click })
	}
	assert w_rows(generic)[1].children[1].text == '2'
	assert_props_equal('keyed clicks', compiled_root.element(), generic_root.element())
	first := w_rows(generic)[1].compiled_node
	creation := generic_root.component.runtime.stats()
	for app in [compiled_app, generic_app] {
		mut model := unsafe { app }
		model.rows = [WKeyedRow{'b', 'Updated B'}, WKeyedRow{'a', 'Updated A'}]
		model.suffix = 'reader'
	}
	compiled_root.component.invalidate_app()!
	generic_root.component.invalidate_app()!
	assert w_rows(generic)[2].compiled_node == first
	assert w_rows(generic)[2].children[0].text == 'Updated A'
	assert w_rows(generic)[2].children[2].text == 'Updated A/reader'
	assert generic_root.component.runtime.stats() == creation
	assert_props_equal('keyed reorder', compiled_root.element(), generic_root.element())
	for app in [compiled_app, generic_app] {
		mut model := unsafe { app }
		model.rows = [WKeyedRow{'c', 'C'}, WKeyedRow{'a', 'A'}]
	}
	compiled_root.component.invalidate_app()!
	generic_root.component.invalidate_app()!
	assert_props_equal('keyed replace', compiled_root.element(), generic_root.element())
	assert generic_app.created == compiled_app.created
	assert generic_app.created == 3
	compiled_root.dispose_document()!
	generic_root.dispose_document()!
	assert generic_root.component.runtime.stats() == SignalStats{}
}

fn w_nested_compiled(mut app WKeyedApp, frame Rect) Element {
	return $vml('../tests/compiled_vml/nested.vml', frame)
}

// A repeater inside a repeater item: the item's roots and the inner
// repeater share one fragment, in declaration order.
fn w_nested_generic(mut app WKeyedApp, frame Rect) !Element {
	mut d := vml_document(frame)!
	mut owner := d.owner
	mut n_0 := vml_root(mut owner, ScreenProps{}, path: '0')!
	mut n_0_0 := vml_child(mut n_0, mut owner, ColumnProps{ align_items: .stretch }, path: '0.0')!
	vml_child(mut n_0_0, mut owner, LabelProps{ text: 'Before' }, path: '0.0.0')!
	vml_repeat(mut n_0_0, '0_0_1', fn [mut app, mut owner] () ![]WKeyedGroup {
		owner.watch_app()!
		return app.groups
	}, fn (group WKeyedGroup) string {
		return group.id
	}, fn [mut app] (mut group_owner CompiledVmlComponent, mut segment VmlSegment, group_input &Signal[WKeyedGroup]) ! {
		mut group := unsafe { group_input }
		group_owner.state('@index', 0)!
		mut header := vml_child(mut segment, mut group_owner, LabelProps{},
			key:  'header'
			path: '0.0.1.0'
		)!
		header.prop('text', fn [mut group] (mut p LabelProps) ! {
			p.text = group.get()!.id
		})!
		vml_repeat(mut segment, '0_0_1_1', fn [mut group] () ![]WKeyedRow {
			return group.get()!.rows
		}, fn (row WKeyedRow) string {
			return row.id
		}, fn [mut app] (mut item_owner CompiledVmlComponent, mut inner VmlSegment, item_input &Signal[WKeyedRow]) ! {
			mut item := unsafe { item_input }
			item_owner.state('@index', 0)!
			w_row_item(mut app, mut item_owner, mut inner, mut item, '0_0.1.1.0', '0.0.1.1.0')!
		}, source: 'nested.vml', line: 7, column: 13)!
	}, source: 'nested.vml', line: 5, column: 9)!
	vml_child(mut n_0_0, mut owner, LabelProps{ text: 'After' }, path: '0.0.2')!
	return d.finish()!
}

fn w_set_groups(mut app WKeyedApp, groups []WKeyedGroup) {
	app.groups = groups
}

fn test_generic_nested_repeaters_match_compiled_vml() {
	frame := rect(0, 0, 400, 300)
	groups := [WKeyedGroup{'a', [WKeyedRow{'x', 'A'}]}, WKeyedGroup{'b', [WKeyedRow{'x', 'B'}]}]
	mut compiled_app := &WKeyedApp{
		groups: groups
	}
	mut generic_app := &WKeyedApp{
		groups: groups
	}
	compiled := w_nested_compiled(mut compiled_app, frame)
	generic := w_nested_generic(mut generic_app, frame)!
	assert_props_equal('nested', compiled, generic)
	mut compiled_root := compiled.compiled_node
	mut generic_root := generic.compiled_node
	compiled_root.mount()!
	generic_root.mount()!
	assert w_rows(generic).len == 6
	for el in [compiled, generic] {
		rows := w_rows(el)
		rows[2].children[0].on_event(ElementEvent{ kind: .click })
		rows[4].children[0].on_event(ElementEvent{ kind: .click })
	}
	reordered := [
		WKeyedGroup{'b', [WKeyedRow{'x', 'Updated B'}, WKeyedRow{'y', 'New'}]},
		WKeyedGroup{'a', [WKeyedRow{'x', 'Updated A'}]},
	]
	w_set_groups(mut compiled_app, reordered)
	w_set_groups(mut generic_app, reordered)
	compiled_root.component.invalidate_app()!
	generic_root.component.invalidate_app()!
	assert w_rows(generic).len == 7
	assert_props_equal('nested reorder', compiled_root.element(), generic_root.element())
	w_set_groups(mut compiled_app, [WKeyedGroup{'a', []WKeyedRow{}}])
	w_set_groups(mut generic_app, [WKeyedGroup{'a', []WKeyedRow{}}])
	compiled_root.component.invalidate_app()!
	generic_root.component.invalidate_app()!
	assert_props_equal('nested removal', compiled_root.element(), generic_root.element())
	assert generic_app.created == compiled_app.created
	compiled_root.dispose_document()!
	generic_root.dispose_document()!
	assert generic_root.component.runtime.stats() == SignalStats{}
}
