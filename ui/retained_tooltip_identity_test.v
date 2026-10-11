module ui2

fn test_retained_tooltip_identity_survives_movement_and_keyed_reorder() ! {
	named := label('named', 'Full text', rect(0, 0, 10, 10), TextStyle{})
	keyed := Element{ ...label('', 'Anonymous', rect(20, 0, 10, 10), TextStyle{}), key: 'row' }
	root := view('root', rect(0, 0, 100, 100), BoxStyle{}, [named, keyed])
	mut tree := LayoutTree{}
	tree.replace(root)!
	before := tree.resolve(LayoutConstraints{}, unsafe { nil }, LayoutEnvironment{})!
	named_key := before.children[0].mounted_tooltip_key
	anonymous_key := before.children[1].mounted_tooltip_key
	assert named_key == 'label#named'
	assert anonymous_key != named_key
	assert anonymous_key.len > 0
	tree.replace(Element{
		...root
		children: [
			Element{ ...keyed, frame: rect(40, 0, 10, 10) },
			Element{ ...named, frame: rect(60, 0, 10, 10) },
		]
	})!
	after := tree.resolve(LayoutConstraints{}, unsafe { nil }, LayoutEnvironment{})!
	assert after.children[0].mounted_tooltip_key == anonymous_key
	assert after.children[1].mounted_tooltip_key == named_key
	assert after.children[1].mounted_tooltip_key.str == named_key.str
	assert before.children[0].frame.x == 0
	assert before.children[1].mounted_tooltip_key == anonymous_key
	tree.replace(Element{
		...root
		children: [
			Element{ ...named, kind: .button },
			keyed,
		]
	})!
	replaced := tree.resolve(LayoutConstraints{}, unsafe { nil }, LayoutEnvironment{})!
	assert replaced.children[0].mounted_tooltip_key == 'button#named'
}
