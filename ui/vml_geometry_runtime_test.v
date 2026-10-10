module ui2

@[heap]
struct GeometryRunCount {
mut:
	count int
}

@[heap]
struct GeometryFrameTrace {
mut:
	values []Rect
}

fn test_hidden_subtree_retains_logical_frames_for_effects_and_refs_after_resize() ! {
	mut owner := new_vml_document('hidden geometry')!
	owner.publish = fn (_ string, _ Element) {}
	mut visible := owner.state('visible', false)!
	mut frames := &GeometryFrameTrace{}
	mut control := owner.element(button('control', 'Action', rect(0, 0, 80, 24), BoxStyle{}, TextStyle{}))!
	mut reference := owner.ref[VmlButton]('control')!
	reference.bind(control)!
	mut hidden := owner.element(view('hidden', rect(0, 0, 300, 180), BoxStyle{}, [control.element()]))!
	hidden.structure('surface', fn [mut hidden, mut visible, mut frames] () !Element {
		frame := hidden.frame()!
		assert frame.width > 0 && frame.height > 0
		frames.values << frame
		return Element{ ...hidden.source_element(), hidden: !visible.get()!, frame: frame }
	})!
	mut root := owner.element(view('root', rect(0, 0, 400, 240), BoxStyle{}, [hidden.element()]))!
	root.mount()!
	mut tree := &LayoutTree{}
	tree.replace(root.element())!
	_ = tree.resolve(LayoutConstraints{}, measure_layout_text, LayoutEnvironment{})!
	assert hidden.frame()! == rect(0, 0, 300, 180)
	assert control.frame()! == rect(0, 0, 80, 24)
	assert frames.values == [rect(0, 0, 300, 180)]
	hidden.set_frame(rect(0, 0, 360, 200))!
	root.set_frame(rect(0, 0, 600, 300))!
	tree.patch('root', root.element())!
	_ = tree.resolve(LayoutConstraints{}, measure_layout_text, LayoutEnvironment{})!
	assert hidden.frame()! == rect(0, 0, 360, 200)
	assert control.frame()! == rect(0, 0, 80, 24)
	visible.set(true)!
	tree.patch('root', root.element())!
	shown := tree.resolve(LayoutConstraints{}, measure_layout_text, LayoutEnvironment{})!
	assert !shown.children[0].hidden
	assert shown.children[0].frame == rect(0, 0, 360, 200)
	assert shown.children[0].children[0].compiled_node == control
	assert reference.element()!.compiled_node == control
	assert frames.values.all(it.width > 0 && it.height > 0)
	root.dispose_document()!
	assert owner.runtime.stats() == SignalStats{}
}

fn test_compiled_geometry_refs_share_sources_and_observe_resolved_allocation() ! {
	mut owner := new_vml_component('geometry')!
	owner.publish = fn (_ string, _ Element) {}
	mut frame := owner.geometry('root', rect(0, 0, 200, 100))!
	mut child := owner.element(Element{ kind: .view, id: 'child', frame: rect(0, 0, 0, 20) })!
	child.effect('width', fn [mut frame] (element Element) !Element {
		return Element{ ...element, frame: Rect{ ...element.frame, width: frame.get()!.width / 2 } }
	})!
	mut root := owner.element(Element{ kind: .view, id: 'root', frame: rect(0, 0, 200, 100) })!
	assert root.frame_value == frame
	root.set_children([child])!
	root.follow_viewport(true, true)
	root.mount()!
	assert child.element().frame.width == 100
	root.update_viewport(rect(0, 0, 320, 180))!
	assert root.element().frame == rect(0, 0, 320, 180)
	assert child.element().frame.width == 160
	mut tree := &LayoutTree{}
	tree.replace(root.element())!
	resolved := tree.resolve(LayoutConstraints{}, measure_layout_text, LayoutEnvironment{})!
	assert root.frame()! == resolved.frame
	assert child.frame()! == resolved.children[0].frame
	root.follow_viewport(false, true)
	root.update_viewport(rect(0, 0, 800, 240))!
	assert root.frame()!.width == 320
	assert root.frame()!.height == 240
	owner.dispose()!
	assert owner.runtime.stats() == SignalStats{}
}

fn test_compiled_geometry_sources_ignore_unchanged_and_reject_invalid_frames() ! {
	mut owner := new_vml_component('unchanged')!
	mut runs := &GeometryRunCount{}
	owner.publish = fn (_ string, _ Element) {}
	mut node := owner.element(Element{ kind: .view, id: 'box', frame: rect(0, 0, 80, 40) })!
	node.effect('geometry', fn [mut node, mut runs] (element Element) !Element {
		_ = node.frame()!
		runs.count++
		return element
	})!
	assert runs.count == 1
	node.set_frame(rect(0, 0, 80, 40))!
	assert runs.count == 1
	if _ := node.set_frame(rect(0, 0, -1, 40)) {
		assert false
	}
	assert node.frame()! == rect(0, 0, 80, 40)
	node.set_frame(rect(0, 0, 100, 40))!
	assert runs.count == 2
	owner.dispose()!
}

fn test_resolved_parent_allocation_settles_absolute_geometry_effects_before_return() ! {
	mut owner := new_vml_document('allocated geometry')!
	owner.publish = fn (_ string, _ Element) {}
	mut parent_frame := owner.geometry('absolute', rect(0, 0, 300, 40))!
	mut child := owner.element(Element{ kind: .view, id: 'child', frame: rect(0, 0, 150, 20) })!
	child.effect('width', fn [mut parent_frame] (element Element) !Element {
		return element.with_layout_frame(Rect{ ...element.frame, width: parent_frame.get()!.width / 2 })
	})!
	mut absolute_node := owner.element(absolute(AbsoluteConfig{ id: 'absolute', frame: rect(0, 0, 300, 40), children: [child.element()] })!)!
	mut fixed := owner.element(Element{ kind: .view, id: 'fixed', frame: rect(0, 0, 100, 40) })!
	mut root := owner.element(flex(FlexConfig{
		id:       'root'
		frame:    rect(0, 0, 300, 40)
		children: [
			FlexChild{ element: fixed.element(), basis: 100, shrink: 0 },
			FlexChild{ element: absolute_node.element(), basis: 0, grow: 1 },
		]
	})!)!
	mut tree := &LayoutTree{}
	tree.replace(root.element())!
	resolved := tree.resolve(LayoutConstraints{}, measure_layout_text, LayoutEnvironment{})!
	assert resolved.children[1].frame.width == 200
	assert resolved.children[1].children[0].frame.width == 100
	assert child.frame()!.width == 100
	assert tree.stats().builds == 1
	// Re-entering a preferred-size pass before mount must retain the allocated
	// frame observed by descendants, rather than reseeding its initial width.
	assert owner.geometry('absolute', rect(0, 0, 300, 40))! == parent_frame
	assert parent_frame.get()!.width == 200
	assert child.frame()!.width == 100
	root.set_frame(rect(0, 0, 500, 40))!
	tree.patch('root', root.element())!
	resized := tree.resolve(LayoutConstraints{}, measure_layout_text, LayoutEnvironment{})!
	assert resized.children[1].frame.width == 400
	assert resized.children[1].children[0].frame.width == 200
	assert tree.stats().builds == 1
	owner.dispose()!
}
