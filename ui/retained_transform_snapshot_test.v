module ui2

fn test_retained_transform_updates_publish_new_geometry_without_mutating_old_snapshots() ! {
	leaf := Element{kind: .button, id: 'action', frame: rect(5, 8, 20, 20)}
	group := Element{kind: .view, id: 'group', frame: rect(10, 20, 50, 50), children: [leaf]}
	other := Element{kind: .view, id: 'other', frame: rect(80, 0, 20, 20), children: [
		Element{kind: .view, id: 'other-leaf', frame: rect(0, 0, 10, 10)},
	]}
	mut tree := LayoutTree{}
	tree.replace(Element{kind: .view, id: 'root', frame: rect(0, 0, 100, 100), children: [group, other]})!
	before := tree.resolve(LayoutConstraints{}, unsafe { nil }, LayoutEnvironment{})!
	authored_before := tree.declaration()
	transform := VisualTransform{rotation: 90, translate_x: 7}
	tree.set_transform('group', transform)!
	after := tree.resolve(LayoutConstraints{}, unsafe { nil }, LayoutEnvironment{})!
	authored_after := tree.declaration()
	assert before.children[0].visual_transform() == VisualTransform{}
	assert authored_before.children[0].visual_transform() == VisualTransform{}
	assert after.children[0].visual_transform() == transform
	assert authored_after.children[0].visual_transform() == transform
	assert after.children[1].children.data == before.children[1].children.data
	assert after.children[0].children[0] == before.children[0].children[0]
	mut focus := FocusManager{}
	focus.update(before, map[string]f64{})
	before_frame := (focus.node('action') or { panic('missing action') }).frame
	focus.update(after, map[string]f64{})
	after_node := focus.node('action') or { panic('missing action') }
	assert after_node.frame != before_frame
	assert after_node.frame == transform.matrix(group.frame)!.project(rect(15, 28, 20, 20))
}
