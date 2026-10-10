module ui2

struct SegmentItem {
	id   string
	span int = 1
}

@[heap]
struct SegmentCounts {
mut:
	builds int
}

fn test_keyed_segments_keep_static_neighbours_constraints_and_reactive_indices() ! {
	mut owner := new_vml_component('segments')!
	owner.publish = fn (_ string, _ Element) {}
	mut parent := owner.element(flex(FlexConfig{ id: 'row', frame: rect(0, 0, 300, 40) })!)!
	mut prefix := owner.element(Element{ kind: .label, id: 'prefix', frame: rect(0, 0, 10, 20) })!
	prefix.set_child_layout(VmlChildLayout{ flex: FlexChild{ basis: 30, shrink: 0 } })!
	parent.set_segment('before', [prefix])!
	mut counts := &SegmentCounts{}
	mut items := owner.state('rows', [SegmentItem{ id: 'a' }, SegmentItem{ id: 'b' }])!
	mut list := new_vml_keyed_list(mut parent, 'rows', fn (item SegmentItem) string {
		return item.id
	},
		fn [mut counts] (mut instance CompiledVmlComponent, source &Signal[SegmentItem]) ![]&CompiledVmlNode {
			counts.builds++
			mut item := source
			mut index := instance.state('@index', 0)!
			mut node := instance.element(Element{ kind: .label, id: 'row', frame: rect(0, 0, 10, 20) })!
			node.set_child_layout(VmlChildLayout{ flex: FlexChild{ basis: 20, grow: 1 } })!
			node.effect('text', fn [mut item, mut index] (element Element) !Element {
				return Element{ ...element, text: '${index.get()!}:${item.get()!.id}' }
			})!
			return [node]
		})!
	mut suffix := owner.element(Element{ kind: .label, id: 'suffix', frame: rect(0, 0, 10, 20) })!
	suffix.set_child_layout(VmlChildLayout{ flex: FlexChild{ basis: 50, shrink: 0 } })!
	parent.set_segment('after', [suffix])!
	list.bind(fn [mut items] () ![]SegmentItem { return items.get()! })!
	parent.mount()!
	first := list.nodes()[0]
	second := list.nodes()[1]
	items.set([SegmentItem{ id: 'b' }, SegmentItem{ id: 'c' }, SegmentItem{ id: 'a' }])!
	assert counts.builds == 3
	assert list.nodes()[0] == second && list.nodes()[2] == first
	assert second.element().text == '0:b' && first.element().text == '2:a'
	assert parent.children[0] == prefix && parent.children.last() == suffix
	assert parent.element().layout.flex.children.map(it.basis) == [30.0, 20.0, 20.0, 20.0, 50.0]
	mut layout := &LayoutTree{}
	layout.replace(parent.element())!
	resolved := layout.resolve(LayoutConstraints{}, measure_layout_text, LayoutEnvironment{})!
	assert resolved.children[0].frame.width == 30
	assert resolved.children.last().frame.width == 50
	for child in resolved.children[1..4] {
		assert child.frame.width > 73 && child.frame.width < 74
	}
	first.set_child_layout(VmlChildLayout{ flex: FlexChild{ basis: 25, grow: 2 } })!
	assert parent.element().layout.flex.children[3].grow == 2
	before := parent.element()
	first.set_child_layout(VmlChildLayout{ flex: FlexChild{ grow: -1 } }) or {
		assert err.msg().contains('negative') || err.msg().contains('non-negative')
		assert parent.element() == before
	}
	list.dispose()!
	assert parent.children == [prefix, suffix]
	assert parent.element().layout.flex.children.map(it.basis) == [30.0, 50.0]
	owner.dispose()!
	assert owner.runtime.stats() == SignalStats{}
}

fn test_grid_segment_span_follows_key_and_preserves_suffix() ! {
	mut owner := new_vml_component('grid segments')!
	owner.publish = fn (_ string, _ Element) {}
	mut parent := owner.element(grid(GridConfig{ id: 'grid', frame: rect(0, 0, 400, 100), columns: 4 })!)!
	mut list := new_vml_keyed_list(mut parent, 'rows', fn (item SegmentItem) string {
		return item.id
	},
		fn (mut instance CompiledVmlComponent, source &Signal[SegmentItem]) ![]&CompiledVmlNode {
			mut item := source
			mut node := instance.element(Element{ kind: .label, id: 'item' })!
			node.set_child_layout(VmlChildLayout{ grid: GridSpan{ column_span: item.get()!.span } })!
			return [node]
		})!
	mut suffix := owner.element(Element{ kind: .label, id: 'end' })!
	suffix.set_child_layout(VmlChildLayout{ grid: GridSpan{ column_span: 2 } })!
	parent.set_segment('end', [suffix])!
	list.update([SegmentItem{ id: 'a', span: 1 }, SegmentItem{ id: 'b', span: 3 }])!
	list.update([SegmentItem{ id: 'b', span: 3 }, SegmentItem{ id: 'a', span: 1 }])!
	assert parent.element().layout.grid.child_spans.map(it.column_span) == [3, 1, 2]
	list.update([SegmentItem{ id: 'a' }])!
	assert parent.element().layout.grid.child_spans.map(it.column_span) == [1, 2]
	owner.dispose()!
}

fn test_keyed_fragment_keeps_multiple_roots_and_shared_instance_state() ! {
	mut owner := new_vml_component('fragments')!
	owner.publish = fn (_ string, _ Element) {}
	mut parent := owner.element(Element{ kind: .view, id: 'parent' })!
	mut list := new_vml_keyed_list(mut parent, 'rows', fn (item SegmentItem) string {
		return item.id
	},
		fn (mut instance CompiledVmlComponent, source &Signal[SegmentItem]) ![]&CompiledVmlNode {
			mut item := source
			mut state := instance.state('count', 0)!
			mut label := instance.element(Element{ kind: .label }, identity: 'label')!
			label.effect('text', fn [mut item, mut state] (element Element) !Element {
				return Element{ ...element, text: '${item.get()!.id}:${state.get()!}' }
			})!
			mut button := instance.element(Element{ kind: .button }, identity: 'add')!
			button.patch(fn [instance, mut state] (element Element) Element {
				return Element{
					...element
					on_event: instance.callback(fn [mut state] (_ ElementEvent) ! {
						state.set(state.get()! + 1)!
					})
				}
			})!
			return [label, button]
		})!
	list.update([SegmentItem{ id: 'a' }, SegmentItem{ id: 'b' }])!
	parent.mount()!
	nodes := list.nodes()
	assert parent.children.len == 4
	assert nodes.map(it.element().id) == ['', '', '', '']
	assert nodes[0].element().key != nodes[1].element().key
	nodes[1].element().on_event(ElementEvent{})
	assert nodes[0].element().text == 'a:1'
	assert nodes[2].element().text == 'b:0'
	list.update([SegmentItem{ id: 'b' }, SegmentItem{ id: 'a' }])!
	assert parent.children == [nodes[2], nodes[3], nodes[0], nodes[1]]
	assert nodes[0].element().text == 'a:1'
	list.update([SegmentItem{ id: 'a' }])!
	assert parent.children == [nodes[0], nodes[1]]
	assert nodes[2].component.is_disposed()
	owner.dispose()!
	assert owner.runtime.stats() == SignalStats{}
}
