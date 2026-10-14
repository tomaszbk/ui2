module ui2

fn test_scroll_modes_keep_automatic_content_loose_only_along_scrolling_axes() ! {
	mut owner := new_vml_document('scroll modes')!
	owner.publish = fn (_ string, _ Element) {}
	mut content := owner.element(view('content', Rect{}, BoxStyle{}, [
		view('wide', rect(0, 0, 230.5, 180.25), BoxStyle{}, []),
	]), inherit_width: true, inherit_height: true)!
	mut pane := owner.element(scroll_with_mode('pane', rect(0, 0, 100.25, 80.5), 0xffffff,
		.vertical_only, [content.element()]))!
	mut tree := LayoutTree{}
	tree.replace(pane.element())!
	generation := tree.identity('content')?.generation
	for mode in [ScrollMode.vertical_only, .horizontal_only, .both, .vertical_only] {
		pane.patch(fn [mode] (el Element) Element { return Element{ ...el, scroll_mode: mode } })!
		tree.patch('pane', pane.element())!
		resolved := tree.resolve(LayoutConstraints{}, unsafe { nil }, LayoutEnvironment{})!
		expected := match mode {
			.vertical_only { rect(0, 0, 100.25, 180.25) }
			.horizontal_only { rect(0, 0, 230.5, 80.5) }
			.both { rect(0, 0, 230.5, 180.25) }
		}
		assert resolved.children[0].frame == expected
		assert tree.identity('content')?.generation == generation
		assert resolved.children[0].layout_input? == Rect{}
	}
	owner.dispose()!
}

fn test_horizontal_scroll_wraps_vertical_flex_at_viewport_height_and_reflows_on_resize() ! {
	mut owner := new_vml_document('sideways wrap')!
	owner.publish = fn (_ string, _ Element) {}
	mut content := owner.element(flex(FlexConfig{
		id:          'content'
		orientation: .vertical
		wrap:        true
		align:       .start
		children:    [
			FlexChild{ element: view('a', rect(0, 0, 40, 30), BoxStyle{}, []), shrink: 0 },
			FlexChild{ element: view('b', rect(0, 0, 40, 30), BoxStyle{}, []), shrink: 0 },
			FlexChild{ element: view('c', rect(0, 0, 40, 30), BoxStyle{}, []), shrink: 0 },
		]
	})!, inherit_width: true, inherit_height: true)!
	mut tree := LayoutTree{}
	for height in [50.0, 70.0, 50.0] {
		tree.replace(scroll_with_mode('pane', rect(0, 0, 30, height), 0xffffff,
			.horizontal_only, [content.element()]))!
		resolved := tree.resolve(LayoutConstraints{}, unsafe { nil }, LayoutEnvironment{})!
		assert resolved.children[0].frame == rect(0, 0, if height == 50 { 120 } else { 80 }, height)
		assert resolved.children[0].children[2].frame.x == if height == 50 { 80 } else { 40 }
	}
	owner.dispose()!
}

fn test_two_axis_scroll_preserves_explicit_zero_and_authored_overflow() ! {
	mut owner := new_vml_document('explicit scroll axes')!
	owner.publish = fn (_ string, _ Element) {}
	mut zero := owner.element(view('zero', Rect{}, BoxStyle{}, []),
		authored_width:  true
		authored_height: true
	)!
	mut tree := LayoutTree{}
	for mode in [ScrollMode.vertical_only, .horizontal_only, .both] {
		tree.replace(scroll_with_mode('pane', rect(0, 0, 100, 80), 0xffffff, mode, [
			zero.element(),
			view('overflow', rect(120, 100, 40, 30), BoxStyle{}, []),
		]))!
		resolved := tree.resolve(LayoutConstraints{}, unsafe { nil }, LayoutEnvironment{})!
		assert resolved.children[0].frame == Rect{}
		assert resolved.children[1].frame == rect(120, 100, 40, 30)
	}
	owner.dispose()!
}
