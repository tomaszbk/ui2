module ui2

fn test_retained_private_scroll_keys_follow_identity_and_changed_paths() ! {
	keyed := Element{kind: .scroll, key: 'items/a', frame: rect(0, 0, 20, 20)}
	indexed := Element{kind: .scroll, frame: rect(30, 0, 20, 20)}
	editor := Element{kind: .text_area, id: '@scroll-path:root/i:1', frame: rect(60, 0, 20, 20)}
	root := Element{kind: .view, frame: rect(0, 0, 100, 100), children: [keyed, indexed, editor]}
	mut tree := LayoutTree{}
	tree.replace(root)!
	before := tree.resolve(LayoutConstraints{}, unsafe { nil }, LayoutEnvironment{})!
	keyed_id := before.children[0].mounted_scroll_id
	indexed_id := before.children[1].mounted_scroll_id
	editor_id := before.children[2].mounted_scroll_id
	assert keyed_id == authored_scroll_state_id(keyed, before.children[0].mounted_path)
	assert indexed_id == authored_scroll_state_id(indexed, before.children[1].mounted_path)
	assert editor_id != indexed_id
	tree.replace(Element{...root, children: [indexed, keyed, editor]})!
	after := tree.resolve(LayoutConstraints{}, unsafe { nil }, LayoutEnvironment{})!
	assert after.children[1].mounted_scroll_id == keyed_id
	assert after.children[0].mounted_scroll_id != indexed_id
	assert after.children[2].mounted_scroll_id == editor_id
	assert before.children[1].mounted_scroll_id == indexed_id
}
