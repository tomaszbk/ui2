module ui2

// Overlay references inside a component: a local id is namespaced once, and a
// value that already holds the public control id (from state, a ref or an
// event) is kept.

fn test_control_ids_are_recognized() {
	owner := new_vml_component('Panel') or { panic(err) }
	assert vml_is_control_id(owner.control_id('trigger'))
	assert vml_is_control_id('vml:5:Panel/3:Row:74726967676572')
	assert !vml_is_control_id('trigger')
	assert !vml_is_control_id('vml:')
	assert !vml_is_control_id('vml:5:Panel:')
	assert !vml_is_control_id('vml:5:Panel:abc')
	assert !vml_is_control_id('vml:5:Panel:zz')
	assert !vml_is_control_id('vml::7472')
}

fn test_overlay_references_are_namespaced_once_inside_a_component() ! {
	mut d := vml_document(rect(0, 0, 300, 200))!
	mut owner := d.owner
	mut c := owner.child('0')!
	public_id := c.control_id('trigger')
	assert public_id != 'trigger'
	mut root := vml_root(mut c, ViewProps{ width: 300, height: 200 }, path: '0.root')!
	vml_child(mut root, mut c, ButtonProps{ text: 'Open', width: 80, height: 30 },
		id:   'trigger'
		path: '0.root.0'
	)!
	mut local := vml_child(mut root, mut c, PopoverProps{
		anchor: 'trigger'
		width:  100
		height: 60
	}, id: 'local', path: '0.root.1')!
	mut resolved := vml_child(mut root, mut c, PopoverProps{
		width:  100
		height: 60
	}, id: 'resolved', path: '0.root.2')!
	// A dynamic value holding the public id, like `anchor: app.anchor`.
	resolved.prop('anchor', fn [public_id] (mut p PopoverProps) ! {
		p.anchor = public_id
	})!
	element := d.finish()!
	trigger := element.children[0]
	assert trigger.id == public_id
	local_overlay := element.children[1].overlay or { panic('missing overlay') }
	resolved_overlay := element.children[2].overlay or { panic('missing overlay') }
	assert local_overlay.anchor == public_id
	assert resolved_overlay.anchor == public_id
	_ = local
	// Overlays without an authored id still get a public id.
	mut d2 := vml_document(rect(0, 0, 100, 100))!
	mut owner2 := d2.owner
	mut root2 := vml_root(mut owner2, ViewProps{}, path: '0')!
	vml_child(mut root2, mut owner2, DialogProps{}, path: '0.0')!
	element2 := d2.finish()!
	assert element2.children[0].id == '__vml_control_0_0'
	element.compiled_node.dispose_document()!
	element2.compiled_node.dispose_document()!
}
