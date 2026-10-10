module ui2

struct KeyedDependencyItem {
	id   string
	text string
}

@[heap]
struct KeyedDependencyFixture {
mut:
	reads    int
	builds   int
	counters map[string]&Signal[int]
}

fn test_keyed_list_tracks_the_reader_while_item_memos_and_effects_track_their_own_sources() ! {
	mut owner := new_vml_component('list dependencies')!
	owner.publish = fn (_ string, _ Element) {}
	mut parent := owner.element(Element{ kind: .view, id: 'list' })!
	mut fixture := &KeyedDependencyFixture{}
	mut items := owner.state('rows', [KeyedDependencyItem{'a', 'A'}, KeyedDependencyItem{'b', 'B'}])!
	mut list := new_vml_keyed_list(mut parent, 'rows', fn (item KeyedDependencyItem) string {
		return item.id
	}, fn [mut fixture] (mut instance CompiledVmlComponent, source &Signal[KeyedDependencyItem]) ![]&CompiledVmlNode {
		fixture.builds++
		mut item := source
		initial := item.get()!
		mut count := instance.state('count', 0)!
		fixture.counters[initial.id] = count
		mut doubled := instance.computed('doubled', fn [mut count] () !int {
			return count.get()! * 2
		})!
		mut node := instance.element(Element{ kind: .label, id: 'value', text: '${initial.text}/${doubled.get()!}' })!
		node.effect('text', fn [mut item, mut doubled] (element Element) !Element {
			return Element{ ...element, text: '${item.get()!.text}/${doubled.get()!}' }
		})!
		return [node]
	})!
	list.bind(fn [mut items, mut fixture] () ![]KeyedDependencyItem {
		fixture.reads++
		return items.get()!
	})!
	first := list.nodes()[0]
	second := list.nodes()[1]
	created := owner.runtime.stats()
	assert fixture.reads == 1
	mut counter := fixture.counters['a'] or { panic('missing retained counter') }
	counter.set(3)!
	assert first.element().text == 'A/6'
	assert second.element().text == 'B/0'
	assert fixture.reads == 1
	assert fixture.builds == 2
	assert owner.runtime.stats() == created
	assert list.effect.node.dependencies.len == 1
	assert list.effect.node.dependencies[0].node == items.node
	items.set([KeyedDependencyItem{'b', 'B!'}, KeyedDependencyItem{'a', 'A!'}])!
	assert list.nodes() == [second, first]
	assert second.element().text == 'B!/0' && first.element().text == 'A!/6'
	assert fixture.reads == 2 && fixture.builds == 2
	assert owner.runtime.stats() == created
	owner.dispose()!
	assert owner.runtime.stats() == SignalStats{}
}

fn test_keyed_list_tracks_captured_key_signals_and_disposes_replaced_instances() ! {
	mut owner := new_vml_component('captured keys')!
	owner.publish = fn (_ string, _ Element) {}
	mut parent := owner.element(Element{ kind: .view, id: 'list' })!
	mut fixture := &KeyedDependencyFixture{}
	mut items := owner.state('rows', [KeyedDependencyItem{'a', 'A'}])!
	mut suffix := owner.state('suffix', '/one')!
	mut list := new_vml_keyed_list(mut parent, 'rows', fn [mut suffix] (item KeyedDependencyItem) string {
		return item.id + suffix.get() or { panic(err) }
	}, fn [mut fixture] (mut instance CompiledVmlComponent, source &Signal[KeyedDependencyItem]) ![]&CompiledVmlNode {
		fixture.builds++
		mut item := source
		return [instance.element(Element{ kind: .label, id: 'value', text: item.get()!.text })!]
	})!
	list.bind(fn [mut items, mut fixture] () ![]KeyedDependencyItem {
		fixture.reads++
		return items.get()!
	})!
	before := list.nodes()[0]
	assert before.element().key == 'a/one'
	assert fixture.reads == 1 && fixture.builds == 1
	assert list.effect.node.dependencies.len == 2
	assert list.effect.node.dependencies[0].node == items.node
	assert list.effect.node.dependencies[1].node == suffix.node
	created := owner.runtime.stats()
	suffix.set('/two')!
	after := list.nodes()[0]
	assert after != before && before.component.is_disposed()
	assert after.element().key == 'a/two' && after.element().text == 'A'
	assert fixture.reads == 2 && fixture.builds == 2
	assert owner.runtime.stats() == created
	owner.dispose()!
	assert owner.runtime.stats() == SignalStats{}
}
