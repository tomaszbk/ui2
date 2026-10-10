module ui2

fn axes_measure(_ string, _ TextStyle, _ f64) !LayoutSize {
	return LayoutSize{ width: 24, height: 18 }
}

fn test_absolute_offers_auto_grid_width_once_before_height_reflow() ! {
	mut tree := LayoutTree{}
	mut children := []Element{}
	for i in 0 .. 5 {
		children << view('cell${i}', rect(0, 0, 20, 20), BoxStyle{}, [])
	}
	cells := grid_declaration(GridConfig{ id: 'cells', auto_columns_min_width: 100, children: children })!
	tree.replace(absolute(AbsoluteConfig{ id: 'root', frame: rect(0, 0, 300, 300), children: [cells] })!)!
	resolved := tree.resolve(LayoutConstraints{}, axes_measure, LayoutEnvironment{})!
	assert resolved.children[0].frame == rect(0, 0, 60, 100)
	assert resolved.children[0].children.map(it.frame) == [rect(0, 0, 60, 20), rect(0, 20, 60, 20),
		rect(0, 40, 60, 20), rect(0, 60, 60, 20), rect(0, 80, 60, 20)]
	// An authored child may extend outside an Absolute; an offered width
	// only constrains automatic dimensions.
	tree.replace(absolute(AbsoluteConfig{ id: 'root', frame: rect(0, 0, 50, 30), children: [view('wide', rect(0, 0, 80, 40), BoxStyle{}, [])] })!)!
	assert tree.resolve(LayoutConstraints{}, axes_measure, LayoutEnvironment{})!.children[0].frame == rect(0, 0, 80, 40)
}

fn test_compiled_explicit_zero_axes_survive_measurement_and_live_updates() ! {
	mut owner := new_vml_document('authored axes')!
	owner.publish = fn (_ string, _ Element) {}
	mut width := owner.state('width', f64(0))!
	mut zero := owner.element(label('zero', 'Copy', Rect{}, TextStyle{}),
		authored_width:  true
		authored_height: true
	)!
	zero.effect('width', fn [mut width] (element Element) !Element {
		return element.with_layout_frame(Rect{ ...(element.layout_input or { element.frame }), width: width.get()! })
	})!
	mut automatic := owner.element(label('auto', 'Copy', Rect{}, TextStyle{}))!
	mut root := owner.element(absolute(AbsoluteConfig{ id: 'root', frame: rect(0, 0, 100, 100), children: [
		zero.element(),
		automatic.element(),
	] })!)!
	mut tree := LayoutTree{}
	tree.replace(root.element())!
	first := tree.resolve(LayoutConstraints{}, axes_measure, LayoutEnvironment{})!
	assert first.children[0].frame == Rect{}
	assert first.children[1].frame == rect(0, 0, 24, 18)
	generation := tree.identity('zero')?.generation
	for value in [12.5, 0.0, 32.25, 0.0] {
		width.set(value)!
		tree.patch('root', root.element())!
		updated := tree.resolve(LayoutConstraints{}, axes_measure, LayoutEnvironment{})!
		assert updated.children[0].frame == rect(0, 0, value, 0)
		assert updated.children[1].frame == first.children[1].frame
		assert updated.children[0].compiled_node == zero
		assert tree.identity('zero')?.generation == generation
	}
	owner.dispose()!
}

fn test_compiled_zero_wrapping_axis_keeps_the_other_axis_intrinsic() ! {
	mut owner := new_vml_document('zero wrap')!
	owner.publish = fn (_ string, _ Element) {}
	children := [view('a', rect(0, 0, 30, 20), BoxStyle{}, []),
		view('b', rect(0, 0, 30, 20), BoxStyle{}, [])]
	mut row := owner.element(flex(FlexConfig{ id: 'row', wrap: true, gap: 5, align: .start, children: children.map(FlexChild{ element: it }) })!,
		authored_width: true
	)!
	mut column := owner.element(flex(FlexConfig{ id: 'column', orientation: .vertical, wrap: true, gap: 5, align: .start, children: children.map(FlexChild{ element: Element{ ...it, id: 'c' + it.id } }) })!,
		authored_height: true
	)!
	mut root := owner.element(absolute(AbsoluteConfig{ id: 'root', frame: rect(0, 0, 300, 300), children: [
		row.element(),
		column.element(),
	] })!)!
	mut tree := LayoutTree{}
	tree.replace(root.element())!
	resolved := tree.resolve(LayoutConstraints{}, axes_measure, LayoutEnvironment{})!
	assert resolved.children[0].frame == rect(0, 0, 0, 45)
	assert resolved.children[1].frame == rect(0, 0, 65, 0)
	owner.dispose()!
}

fn test_compiled_nested_views_inherit_the_grid_allocation_without_recreation() ! {
	mut owner := new_vml_document('allocated content')!
	owner.publish = fn (_ string, _ Element) {}
	mut children := []Element{}
	mut leaves := []&CompiledVmlNode{}
	for i in 0 .. 5 {
		mut leaf := owner.element(view('leaf${i}', rect(0, 0, 20, 20), BoxStyle{}, []),
			authored_width:  true
			authored_height: true
		)!
		mut inner := owner.element(view('inner${i}', Rect{}, BoxStyle{}, [leaf.element()]),
			inherit_width:  true
			inherit_height: true
		)!
		mut outer := owner.element(view('outer${i}', Rect{}, BoxStyle{}, [inner.element()]))!
		leaves << leaf
		children << outer.element()
	}
	mut cells := owner.element(grid_declaration(GridConfig{ id: 'cells', auto_columns_min_width: 100, children: children })!)!
	mut root := owner.element(absolute(AbsoluteConfig{ id: 'root', frame: rect(0, 0, 300, 300), children: [cells.element()] })!)!
	mut tree := LayoutTree{}
	tree.replace(root.element())!
	for width in [20.0, 25.0] {
		for mut leaf in leaves { leaf.set_frame(rect(0, 0, width, 20))! }
		tree.patch('root', root.element())!
		resolved := tree.resolve(LayoutConstraints{}, axes_measure, LayoutEnvironment{})!
		assert resolved.children[0].frame == rect(0, 0, width * 3, 100)
		for child in resolved.children[0].children {
			assert child.children[0].frame == rect(0, 0, width * 3, 20)
			assert child.children[0].children[0].frame == rect(0, 0, width, 20)
		}
		assert resolved.children[0].children[0].children[0].children[0].compiled_node == leaves[0]
		assert tree.stats().builds == 1
	}
	owner.dispose()!
}
