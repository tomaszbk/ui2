module ui2

fn test_drag_preview_uses_source_projection_and_window_anchor_once() {
	// Outer ScaledContent: scale 2, translate(10,20). Nested scale .5 and
	// translate(30,40) gives identity scale plus translate(70,100).
	outer := ContentTransform{xx: 2, yy: 2, x: 10, y: 20 }
	inner := ContentTransform{xx: 0.5, yy: 0.5, x: 30, y: 40 }
	transform := drag_preview_transform(outer.compose(inner), 200, 80)
	assert transform.project(rect(12, 6, 40, 20)) == rect(212, 86, 40, 20)
	assert outer.project(rect(30, 40, 0, 0)) == rect(70, 100, 0, 0)
}

fn test_drag_configuration_rejects_ambiguous_gestures_and_invalid_geometry() {
	callback := fn (_ ElementEvent) {}
	base := with_event(view('source', rect(0, 0, 100, 40), BoxStyle{}, []), callback)
	for source in [DragSource{ allowed: [] }, DragSource{ allowed: [.none] },
		DragSource{ threshold: -1 }, DragSource{ preview: DragPreview{ width: 0 } }] {
		if _ := validate_element_tree(with_drag_source(base, source)) {
			assert false
		}
	}
	if _ := validate_element_tree(with_drop_target(base, DropTarget{})) {
		assert false
	}
	if _ := validate_element_tree(with_drag_source(Element{ ...base, draggable: true }, DragSource{})) {
		assert false
	}
	if _ := validate_element_tree(with_drag_source(Element{ ...base, kind: .text_field }, DragSource{})) {
		assert false
	}
	if _ := validate_element_tree(with_drag_source(view('source', rect(0, 0, 40, 40), BoxStyle{}, []), DragSource{})) {
		assert false
	}
	$if !( android || linux || ( ( macos || windows ) && ui2_custom_rendering ?) ) && !ui2_headless ? {
		validate_element_tree(with_drag_source(base, DragSource{})) or {
			assert err.msg() == 'drag-drop requires the custom renderer'
			return
		}
		assert false, 'native profile must diagnose unsupported drag presentation'
	} $else {
		validate_element_tree(with_drag_source(base, DragSource{})) or { panic(err) }
	}
}
