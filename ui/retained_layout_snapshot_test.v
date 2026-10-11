module ui2

fn snapshot_resolve(mut tree LayoutTree) !Element {
	return tree.resolve(LayoutConstraints{}, unsafe { nil }, LayoutEnvironment{})!
}

fn snapshot_branch(id string, child string) Element {
	return Element{
		kind:     .view
		id:       id
		frame:    rect(0, 0, 80, 80)
		children: [
			Element{ kind: .view, id: child, frame: rect(0, 0, 20, 20) },
		]
	}
}

fn test_retained_layout_shares_unchanged_projections_and_keeps_old_snapshots() ! {
	mut tree := LayoutTree{}
	root := Element{
		kind:     .view
		id:       'root'
		frame:    rect(0, 0, 200, 100)
		children: [
			snapshot_branch('left', 'a'),
			snapshot_branch('right', 'b'),
		]
	}
	tree.replace(root)!
	first := snapshot_resolve(mut tree)!
	authored := tree.declaration()
	tree.reset_stats()
	for _ in 0 .. 10 {
		same := snapshot_resolve(mut tree)!
		assert same.children.data == first.children.data
		assert tree.declaration().children.data == authored.children.data
	}
	assert tree.stats().output_visits == 0
	assert tree.stats().authored_visits == 0
	tree.patch('a', Element{ kind: .view, id: 'a', frame: rect(0, 0, 20, 20), text: 'changed' })!
	changed := snapshot_resolve(mut tree)!
	new_authored := tree.declaration()
	assert tree.stats().output_visits == 3
	assert tree.stats().authored_visits == 3
	assert changed.children[0].children[0].text == 'changed'
	assert first.children[0].children[0].text == ''
	assert authored.children[0].children[0].text == ''
	assert changed.children[1].children.data == first.children[1].children.data
	assert new_authored.children[1].children.data == authored.children[1].children.data
}

fn test_retained_layout_effective_enabled_and_paths_follow_ancestor_changes() ! {
	mut tree := LayoutTree{}
	root := Element{
		kind:     .view
		id:       'root'
		frame:    rect(0, 0, 200, 100)
		children: [
			snapshot_branch('left', 'a'),
			snapshot_branch('right', 'b'),
		]
	}
	tree.replace(root)!
	first := snapshot_resolve(mut tree)!
	tree.patch('left', Element{ ...root.children[0], enabled: false })!
	disabled := snapshot_resolve(mut tree)!
	assert !disabled.children[0].enabled
	assert !disabled.children[0].children[0].enabled
	assert tree.declaration().children[0].children[0].enabled
	assert first.children[0].children[0].enabled
	tree.replace(Element{ ...root, children: [root.children[1], root.children[0]] })!
	reordered := snapshot_resolve(mut tree)!
	assert reordered.children[0].id == 'right'
	assert reconciliation_child_key('root', 0, reordered.children[0]) == 'root/i:0'
	assert reconciliation_child_key('root/i:0', 0, reordered.children[0].children[0]) == 'root/i:0/i:0'
	assert reordered.children[1].children[0].enabled
}

fn test_targeted_layout_validation_rejects_outside_id_collisions_atomically() ! {
	mut tree := LayoutTree{}
	root := Element{
		kind:     .view
		id:       'root'
		frame:    rect(0, 0, 200, 100)
		children: [
			snapshot_branch('left', 'a'),
			snapshot_branch('right', 'b'),
		]
	}
	tree.replace(root)!
	first := snapshot_resolve(mut tree)!
	if _ := tree.patch('left', snapshot_branch('left', 'b')) {
		assert false
	}
	assert snapshot_resolve(mut tree)! == first
	// Removing an id within this replacement allows it to move locally.
	tree.patch('left', Element{ ...root.children[0], children: [snapshot_branch('new', 'a')] })!
	assert snapshot_resolve(mut tree)!.children[0].children[0].children[0].id == 'a'
}
