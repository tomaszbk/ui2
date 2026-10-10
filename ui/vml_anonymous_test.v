module ui2

fn test_anonymous_compiled_identity_and_targeted_patch_preserve_public_ids_and_keys() ! {
	mut owner := new_vml_document('anonymous')!
	owner.publish = fn (_ string, _ Element) {}
	mut value := owner.state('value', 'First')!
	mut node := owner.element(Element{ kind: .label, frame: rect(0, 0, 100, 24) },
		identity: 'caption'
	)!
	node.effect('text', fn [mut value] (element Element) !Element {
		return Element{ ...element, text: value.get()! }
	})!
	assert node.element().id == ''
	assert node.element().key == ''
	mut sibling_owner := new_vml_document('anonymous')!
	sibling_owner.publish = fn (_ string, _ Element) {}
	mut sibling := sibling_owner.element(Element{ kind: .label, text: 'Second' }, identity: 'caption')!
	assert node.identity() != sibling.identity()
	assert reconciliation_child_key('root', 0, node.element()) == reconciliation_child_key('root', 4, node.element())
	keyed := Element{ ...node.element(), key: 'authored' }
	assert reconciliation_child_key('root', 0, keyed) != reconciliation_child_key('root', 0, node.element())
	named := Element{ kind: .label, id: node.identity(), text: 'Named' }
	mut tree := &LayoutTree{}
	tree.replace(Element{ kind: .view, id: 'root', children: [node.element(), sibling.element(),
		named] })!
	initial := tree.nodes[tree.nodes[tree.root].children[0]].generation
	node.mount()!
	value.set('Changed')!
	tree.patch_compiled(node, node.element())!
	assert tree.stats().builds == 1
	assert tree.declaration().children.map(it.text) == ['Changed', 'Second', 'Named']
	assert tree.declaration().children.map(it.id) == ['', '', named.id]
	assert tree.nodes[tree.nodes[tree.root].children[0]].generation == initial
	tree.patch_compiled(node, Element{ ...node.element(), key: 'other' }) or { assert err.msg().contains('preserve') }
	assert tree.declaration().children[0].key == ''
	owner.dispose()!
	sibling_owner.dispose()!
}
