module ui2

fn test_mounted_menu_options_reuse_geometry_updates_and_replace_changed_titles() {
	chooser := dropdown('chooser', 'España', ['España', 'café ñ'], rect(10, 10, 120, 30), BoxStyle{}, TextStyle{})
	root := Element{ kind: .view, frame: rect(0, 0, 200, 100), children: [chooser] }
	mut manager := FocusManager{}
	manager.update_mounted(root, map[string]f64{}, root.frame, ContentTransform{})
	before := manager.node('chooser') or { panic('chooser must be mounted') }
	assert before.menu_options_snapshot() == ['España', 'café ñ']
	manager.update_mounted(root, map[string]f64{}, root.frame, ContentTransform{ x: 3 })
	moved := manager.node('chooser') or { panic('chooser must stay mounted') }
	assert moved.menu_options.data == before.menu_options.data
	assert moved.menu_options_snapshot() == before.menu_options_snapshot()
	changed := Element{ ...chooser, menu: [MenuEntry{ id: 'one', title: 'Perú' },
		MenuEntry{ id: 'two', title: 'año' }] }
	manager.update_mounted(Element{ ...root, children: [changed] }, map[string]f64{}, root.frame, ContentTransform{ x: 3 })
	after := manager.node('chooser') or { panic('changed chooser must be mounted') }
	assert after.menu_options_snapshot() == ['Perú', 'año']
	assert after.menu_options.data != before.menu_options.data
	assert before.menu_options_snapshot() == ['España', 'café ñ']
	assert (FocusNode{ el: changed }).menu_options_snapshot() == ['Perú', 'año']
	manager.update_mounted(Element{ ...root, children: [Element{ ...changed, menu: []MenuEntry{} }] }, map[string]f64{}, root.frame, ContentTransform{})
	empty := manager.node('chooser') or { panic('empty chooser must be mounted') }
	assert empty.menu_options_snapshot().len == 0
	assert after.menu_options_snapshot() == ['Perú', 'año']
}
