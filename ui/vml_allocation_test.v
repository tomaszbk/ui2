// vtest vflags: -gc boehm -d no_gc_thread_local_alloc
module ui2

struct AllocationListItem {
	id   string
	text string
}

@[heap]
struct AllocationKeyFixture {
mut:
	builds int
	keys   int
}

fn test_noop_keyed_list_keeps_captured_key_dependencies_and_rejects_errors_atomically() ! {
	mut owner := new_vml_document('no-op key dependencies')!
	owner.set_publisher(fn (_ string, _ Element) {})!
	mut parent := owner.element(Element{ kind: .view, id: 'rows' })!
	mut fixture := &AllocationKeyFixture{}
	mut suffix := owner.state('suffix', '/one')!
	mut pulse := owner.state('pulse', 0)!
	items := [AllocationListItem{'a', 'A'}]
	mut list := new_vml_keyed_list(mut parent, 'rows', fn [mut suffix, mut fixture] (item AllocationListItem) string {
		fixture.keys++
		return item.id + (suffix.get() or { panic(err) })
	}, fn [mut fixture] (mut instance CompiledVmlComponent, source &Signal[AllocationListItem]) ![]&CompiledVmlNode {
		fixture.builds++
		return [instance.element(Element{ kind: .label, id: 'row', text: source.peek()!.text })!]
	})!
	list.bind(fn [mut pulse, items] () ![]AllocationListItem {
		pulse.get()!
		return items
	})!
	first := list.nodes()[0]
	baseline := parent.element()
	assert fixture.keys == 1 && fixture.builds == 1
	pulse.set(1)!
	assert fixture.keys == 2 && fixture.builds == 1
	assert parent.element().compiled_source() == baseline.compiled_source()
	assert list.effect.node.dependencies.len == 2
	assert list.effect.node.dependencies.any(it.node == suffix.node)
	suffix.set('/two')!
	second := list.nodes()[0]
	assert second != first && first.component.is_disposed()
	assert second.element().key == 'a/two'
	assert fixture.keys == 3 && fixture.builds == 2
	unchanged := parent.element()
	if _ := list.update([AllocationListItem{'a', 'changed'}, AllocationListItem{'a', 'duplicate'}]) {
		assert false, 'duplicate keys accepted'
	} else {
		assert err.msg().contains('duplicate')
	}
	assert list.nodes() == [second]
	assert parent.element().compiled_source() == unchanged.compiled_source()
	assert second.element().text == 'A' && fixture.builds == 2
	owner.dispose()!
}

fn test_noop_segment_rejects_a_disposed_retained_child() ! {
	mut owner := new_vml_document('disposed child segment')!
	mut parent := owner.element(Element{ kind: .view, id: 'root' })!
	mut child_owner := owner.child('child')!
	child := child_owner.element(Element{ kind: .label, id: 'label' })!
	parent.set_segment('children', [child])!
	child_owner.dispose()!
	if _ := parent.set_segment('children', [child]) {
		assert false, 'disposed child accepted'
	} else {
		assert err.msg().contains('disposed')
	}
	owner.dispose()!
}

fn test_unchanged_keyed_list_and_constructor_reads_allocate_nothing() ! {
	mut owner := new_vml_document('retained list allocation')!
	owner.set_publisher(fn (_ string, _ Element) {})!
	mut parent := owner.element(Element{ kind: .view, id: 'list' })!
	mut list := new_vml_keyed_list(mut parent, 'rows', fn (item AllocationListItem) string {
		return item.id
	}, fn (mut instance CompiledVmlComponent, source &Signal[AllocationListItem]) ![]&CompiledVmlNode {
		mut item := source
		mut node := instance.element(Element{ kind: .text_field, id: 'edit' })!
		node.effect('text', fn [mut item] (element Element) !Element {
			return Element{ ...element, text: item.get()!.text }
		})!
		return [node]
	})!
	items := [AllocationListItem{'a', 'A'}, AllocationListItem{'b', 'ñ'}]
	list.update(items)!
	nodes := list.nodes()
	mut first_ref := nodes[0].component.ref[VmlTextInput]('first')!
	first_ref.bind(nodes[0])!
	parent.mount()!
	baseline := parent.element()
	assert first_ref.element()!.text == 'A'
	$if gcboehm ? {
		before := gc_allocation_snapshot()!
		for _ in 0 .. 128 {
			list.update(items)!
			parent.set_segment(list.segment, nodes)!
			assert parent.element().compiled_source() == baseline.compiled_source()
			assert first_ref.element()!.text == 'A'
		}
		delta := gc_allocation_snapshot()!.delta_since(before)
		assert delta.allocated_bytes == 0
		assert delta.collections == 0
	}
	// Data changes under the same keys still patch the retained input, while
	// constructor snapshots already returned to a caller stay immutable.
	list.update([AllocationListItem{'a', 'changed'}, AllocationListItem{'b', 'ñ'}])!
	assert list.nodes() == nodes
	assert first_ref.element()!.text == 'changed'
	assert parent.element().children[0].text == 'changed'
	assert baseline.children[0].text == 'A'
	assert baseline.compiled_source().value.children[0].text == 'A'
	list.update([AllocationListItem{'b', 'ñ'}, AllocationListItem{'a', 'changed'}])!
	assert list.nodes() == [nodes[1], nodes[0]]
	assert first_ref.is_available()
	assert parent.element().children[1].compiled_node == nodes[0]
	owner.dispose()!
	assert !first_ref.is_available()
}

fn test_child_identity_checks_reject_cycles_without_changing_the_tree() ! {
	mut owner := new_vml_document('retained child identity')!
	mut root := owner.element(Element{ kind: .view, id: 'root' })!
	mut branch := owner.element(Element{ kind: .view, id: 'branch' })!
	mut leaf := owner.element(Element{ kind: .view, id: 'leaf' })!
	branch.set_children([leaf])!
	root.set_children([branch])!
	baseline := root.element()
	if _ := leaf.set_children([root]) {
		assert false, 'ancestor cycle accepted'
	} else {
		assert err.msg().contains('ancestor')
	}
	if _ := leaf.set_children([leaf]) {
		assert false, 'self cycle accepted'
	} else {
		assert err.msg().contains('itself')
	}
	assert leaf.children.len == 0
	assert voidptr(root.element().compiled_source()) == voidptr(baseline.compiled_source())
	assert root.children == [branch] && branch.children == [leaf]
	owner.dispose()!
}

fn test_unchanged_segment_restores_children_after_direct_structure_update() ! {
	mut owner := new_vml_document('mixed child APIs')!
	mut parent := owner.element(Element{ kind: .view, id: 'root' })!
	first := owner.element(Element{ kind: .label, id: 'first' })!
	second := owner.element(Element{ kind: .label, id: 'second' })!
	parent.set_segment('group', [first])!
	parent.set_children([second])!
	changed := parent.element()
	assert changed.children[0].id == 'second'
	parent.set_segment('group', [first])!
	assert parent.children == [first]
	assert parent.element().children[0].id == 'first'
	assert changed.children[0].id == 'second'
	assert voidptr(first.parent) == voidptr(parent)
	assert second.parent == unsafe { nil }
	owner.dispose()!
}

fn test_unchanged_constructor_geometry_preserves_source_snapshots() ! {
	mut owner := new_vml_document('unchanged allocated constructor')!
	mut parent := owner.element(Element{ kind: .view, id: 'parent' })!
	declaration := Element{ kind: .label, id: 'child', frame: rect(2, 3, 40, 20) }
	child := owner.element(declaration)!
	parent.set_children([child])!
	child_snapshot := child.element()
	parent_snapshot := parent.element()
	$if gcboehm ? {
		before := gc_allocation_snapshot()!
		for _ in 0 .. 128 {
			again := owner.element(declaration)!
			assert voidptr(again) == voidptr(child)
			assert voidptr(again.element().compiled_source()) == voidptr(child_snapshot.compiled_source())
			assert voidptr(parent.element().compiled_source()) == voidptr(parent_snapshot.compiled_source())
		}
		delta := gc_allocation_snapshot()!.delta_since(before)
		assert delta.allocated_bytes == 0
		assert delta.collections == 0
	}
	_ := owner.element(Element{ ...declaration, frame: rect(2, 3, 80, 20) })!
	assert parent.element().children[0].frame.width == 80
	assert parent_snapshot.children[0].frame.width == 40
	assert child_snapshot.frame.width == 40
	owner.dispose()!
}
