module ui2

fn test_targeted_patch_rejects_sibling_key_collision_before_mutating_snapshots() ! {
	left := Element{kind: .view, id: 'left', key: 'left-key', frame: rect(0, 0, 40, 40)}
	right := Element{kind: .view, id: 'right', key: 'right-key', frame: rect(40, 0, 40, 40)}
	mut tree := LayoutTree{}
	tree.replace(Element{kind: .view, id: 'root', frame: rect(0, 0, 100, 100), children: [left, right]})!
	before := tree.resolve(LayoutConstraints{}, unsafe { nil }, LayoutEnvironment{})!
	authored := tree.declaration()
	identity := tree.identity('left') or { panic('missing left') }
	if _ := tree.patch('left', Element{...left, key: 'right-key', text: 'rejected'}) { assert false }
	after := tree.resolve(LayoutConstraints{}, unsafe { nil }, LayoutEnvironment{})!
	assert after == before
	assert after.children.data == before.children.data
	assert tree.declaration().children.data == authored.children.data
	assert (tree.identity('left') or { panic('missing left') }) == identity
	tree.patch('left', Element{...left, key: 'renamed-key'})!
	assert tree.resolve(LayoutConstraints{}, unsafe { nil }, LayoutEnvironment{})!.children[0].key == 'renamed-key'
}

fn test_targeted_patch_allows_same_key_in_different_parent() ! {
	left := Element{kind: .view, id: 'left', key: 'a', frame: rect(0, 0, 20, 20)}
	mut tree := LayoutTree{}
	tree.replace(Element{kind: .view, id: 'root', frame: rect(0, 0, 100, 100), children: [
		Element{kind: .view, id: 'parent', frame: rect(0, 0, 40, 40), children: [left]},
		Element{kind: .view, id: 'other', key: 'b', frame: rect(40, 0, 40, 40)},
	]})!
	tree.patch('left', Element{...left, key: 'b'})!
	assert tree.resolve(LayoutConstraints{}, unsafe { nil }, LayoutEnvironment{})!.children[0].children[0].key == 'b'
}
