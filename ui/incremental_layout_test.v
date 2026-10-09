module ui2

import math

fn incremental_width(text string) f64 {
	mut width := 0.0
	for ch in text.runes() {
		width += match ch {
			`W` { 12.0 }
			`i` { 3.0 }
			` ` { 4.0 }
			else { 8.0 }
		}
	}
	return width
}

fn incremental_text(text string, style TextStyle, width f64) !LayoutSize {
	return layout_measure_text_lines(text, style, width, 20, incremental_width)
}

fn incremental_resolve(mut tree LayoutTree) !Element {
	return tree.resolve(LayoutConstraints{}, incremental_text, LayoutEnvironment{})!
}

fn incremental_label(id string, text string) Element {
	return label(id, text, Rect{}, TextStyle{ lines: 20 })
}

fn incremental_column(id string, frame Rect, children []Element) !Element {
	return flex(FlexConfig{
		id:          id
		frame:       frame
		orientation: .vertical
		align:       .stretch
		children:    children.map(FlexChild{ element: it, shrink: 0 })
	})!
}

fn test_incremental_paint_patch_has_no_geometry_or_text_work() {
	mut tree := LayoutTree{}
	leaf := incremental_label('label', 'WW ii')
	tree.replace(incremental_column('column', rect(0, 0, 60, 100), [leaf])!)!
	first := incremental_resolve(mut tree)!
	tree.reset_stats()
	tree.patch('label', Element{ ...leaf, text_style: TextStyle{ ...leaf.text_style, color: 0xff0000 }, box: BoxStyle{ bg: 0x123456 } })!
	paint := incremental_resolve(mut tree)!
	assert paint.children[0].frame == first.children[0].frame
	assert paint.children[0].text_style.color == 0xff0000
	assert tree.stats().text_measurements == 0
	assert tree.stats().measure_visits == 0
	assert tree.stats().layout_visits == 0
	assert tree.stats().builds == 0
}

fn test_incremental_boundary_and_intrinsic_ancestor_sibling_dependencies() {
	mut tree := LayoutTree{}
	leaf := incremental_label('text', 'WW')
	fixed := incremental_column('fixed', rect(0, 0, 30, 100), [leaf, incremental_label('inside', 'i')])!
	unrelated := incremental_column('other', rect(0, 0, 40, 100), [incremental_label('cached', 'WWW')])!
	root := flex(FlexConfig{
		id:       'root'
		frame:    rect(0, 0, 200, 120)
		align:    .start
		children: [
			FlexChild{ element: fixed },
			FlexChild{ element: unrelated },
		]
	})!
	tree.replace(root)!
	first := incremental_resolve(mut tree)!
	before := tree.identity('fixed') or { panic('no identity') }
	tree.reset_stats()
	tree.patch('text', incremental_label('text', 'WW WW WW'))!
	changed := incremental_resolve(mut tree)!
	assert changed.children[0].children[0].frame.height == 60
	assert changed.children[0].children[1].frame.y == 60
	assert changed.children[1].frame == first.children[1].frame
	assert tree.identity('fixed')?.content_version == before.content_version
	assert tree.stats().text_measurements == 2 // intrinsic and assigned width
	assert tree.stats().layout_visits == 2 // fixed and changed leaf; ancestor allocation reused
	// Remove fixed height: intrinsic propagation now moves an outside sibling.
	mut intrinsic := LayoutTree{}
	column := incremental_column('flow', rect(0, 0, 30, 0), [leaf])!
	intrinsic.replace(incremental_column('outer', rect(0, 0, 60, 200), [column,
		incremental_label('after', 'i')])!)!
	initial := incremental_resolve(mut intrinsic)!
	intrinsic.patch('text', incremental_label('text', 'WW WW WW'))!
	grown := incremental_resolve(mut intrinsic)!
	assert initial.children[1].frame.y == 20
	// The outer column stretches flow to 60 units: two text rows at the
	// assigned width, rather than three rows at flow's authored 30-unit width.
	assert grown.children[1].frame.y == 40
	assert grown.children[0].frame.height == 40
}

fn test_incremental_declared_sizes_survive_resize_and_fractional_distribution() {
	mut tree := LayoutTree{}
	leaf := incremental_label('wrap', 'WW WW')
	for width in [60.25, 30.5, 60.25, 30.5, 60.25] {
		root := flex(FlexConfig{
			id:       'root'
			frame:    rect(0, 0, width, 100)
			align:    .start
			children: [FlexChild{ element: leaf, grow: 1, minimum_width: 10 }]
		})!
		assert root.children[0].layout_input? == Rect{}
		tree.replace(root)!
		resolved := incremental_resolve(mut tree)!
		assert resolved.children[0].frame.width == width
		assert resolved.children[0].frame.height == if width > 50 { 20.0 } else { 40.0 }
		assert resolved.children[0].layout_input? == Rect{}
	}
	// Frozen maxima leave 90 units for the second item, not 75.
	bound := flex(FlexConfig{
		id:       'bounded'
		frame:    rect(0, 0, 150.5, 50)
		children: [
			FlexChild{ element: view('a', rect(0, 0, 50, 10), BoxStyle{}, []), grow: 1, maximum_width: 60 },
			FlexChild{ element: view('b', rect(0, 0, 50, 10), BoxStyle{}, []), grow: 1 },
		]
	})!
	tree.replace(bound)!
	resolved := incremental_resolve(mut tree)!
	assert resolved.children[0].frame.width == 60
	assert resolved.children[1].frame.width == 90.5
	assert resolved.children[1].frame.x == 60
}

fn test_incremental_identity_keys_reorder_retire_and_kind_change() {
	mut tree := LayoutTree{}
	a := Element{ ...incremental_label('', 'WW'), key: 'a/b' }
	b := Element{ ...incremental_label('', 'i'), key: 'b' }
	root := incremental_column('root', rect(0, 0, 60, 100), [a, b])!
	tree.replace(root)!
	_ = incremental_resolve(mut tree)!
	a_key := 'root/key:' + 'a/b'.bytes().hex()
	generation := (tree.nodes[a_key] or { panic('missing key') }).generation
	tree.replace(incremental_column('root', rect(0, 0, 60, 100), [b, a])!)!
	tree.reset_stats()
	reordered := incremental_resolve(mut tree)!
	assert reordered.children[0].text == 'i'
	assert reordered.children[1].text == 'WW'
	assert (tree.nodes[a_key] or { panic('missing key') }).generation == generation
	assert tree.stats().text_measurements == 0
	tree.replace(incremental_column('root', rect(0, 0, 60, 100), [b])!)!
	tree.replace(root)!
	assert (tree.nodes[a_key] or { panic('missing key') }).generation != generation
	old := (tree.nodes[a_key] or { panic('missing key') }).generation
	tree.replace(incremental_column('root', rect(0, 0, 60, 100), [
		Element{ ...a, kind: .button },
		b,
	])!)!
	assert (tree.nodes[a_key] or { panic('missing key') }).generation != old
	mut isolated := LayoutTree{}
	isolated.replace(root)!
	_ = incremental_resolve(mut isolated)!
	assert isolated.stats().text_measurements > 0
}

fn test_incremental_environment_complete_typography_keys_and_constraints() {
	mut tree := LayoutTree{}
	leaf := incremental_label('text', 'WW WW')
	tree.replace(leaf)!
	wide := tree.resolve(LayoutConstraints{ max_width: 60 }, incremental_text, LayoutEnvironment{})!
	narrow := tree.resolve(LayoutConstraints{ max_width: 30 }, incremental_text, LayoutEnvironment{})!
	zero := tree.resolve(LayoutConstraints{ max_width: 0 }, incremental_text, LayoutEnvironment{})!
	assert wide.frame.height == 20
	assert narrow.frame.height == 40
	assert zero.frame.width == 0
	tree.reset_stats()
	_ = tree.resolve(LayoutConstraints{ max_width: 60 }, incremental_text, LayoutEnvironment{})!
	assert tree.stats().text_measurements == 0
	for env in [LayoutEnvironment{ version: 1 }, LayoutEnvironment{ version: 1, font_version: 2 },
		LayoutEnvironment{ version: 1, font_version: 2, scale: 1.25 }] {
		tree.reset_stats()
		_ = tree.resolve(LayoutConstraints{ max_width: 60 }, incremental_text, env)!
		assert tree.stats().text_measurements == 1
	}
	for style in [TextStyle{ lines: 20, size: 18 }, TextStyle{ lines: 20, weight: 600 },
		TextStyle{ lines: 20, letter_spacing: 0.25 }, TextStyle{ lines: 20, line_height: 25 },
		TextStyle{ lines: 20, font_family: 'new' }] {
		tree.replace(Element{ ...leaf, text_style: style })!
		tree.reset_stats()
		_ = incremental_resolve(mut tree)!
		assert tree.stats().text_measurements == 1
	}
	before := tree.identity('text')?
	if _ := tree.identity('') { assert false }
	if _ := tree.patch('', Element{}) { assert false }
	if _ := tree.patch('text', Element{ ...leaf, children: [Element{ id: 'text' }] }) {
		assert false
	}
	assert tree.identity('text')? == before
}

fn test_incremental_grid_span_nested_stack_and_repeated_resize() {
	mut tree := LayoutTree{}
	for width in [120.5, 180.25, 120.5] {
		nested := stack(StackConfig{
			id:       'overlay'
			frame:    rect(0, 0, 10, 20)
			align_x:  .center
			children: [StackChild{ element: view('small', rect(0, 0, 10, 5), BoxStyle{}, []) }]
		})!
		root := grid(GridConfig{
			id:          'grid'
			frame:       rect(0, 0, width, 80)
			columns:     3
			spacing:     GridSpacing{ horizontal: 2 }
			child_spans: [GridSpan{ column_span: 2 }, GridSpan{}, GridSpan{}]
			children:    [nested, incremental_label('one', 'W'), incremental_label('two', 'i')]
		})!
		tree.replace(root)!
		resolved := incremental_resolve(mut tree)!
		track := (width - 4) / 3
		assert math.abs(resolved.children[0].frame.width - (2 * track + 2)) < 0.000001
		assert resolved.children[0].frame.height == 40
		assert resolved.children[2].frame.y == 40
		assert math.abs(resolved.children[0].children[0].frame.x - ((2 * track + 2 - 10) / 2)) < 0.000001
	}
}

fn test_incremental_shrink_freezing_and_nonstretch_overflow() {
	mut tree := LayoutTree{}
	root := flex(FlexConfig{
		id:       'row'
		frame:    rect(0, 0, 90.5, 30)
		align:    .start
		children: [
			FlexChild{ element: view('a', rect(0, 0, 80, 10), BoxStyle{}, []), minimum_width: 60 },
			FlexChild{ element: view('b', rect(0, 0, 80, 10), BoxStyle{}, []) },
		]
	})!
	tree.replace(root)!
	resolved := incremental_resolve(mut tree)!
	assert resolved.children[0].frame.width == 60
	assert resolved.children[1].frame.width == 30.5
	assert resolved.children[1].frame.x == 60
	column := flex(FlexConfig{
		id:          'column'
		frame:       rect(0, 0, 30, 80)
		orientation: .vertical
		align:       .start
		children:    [FlexChild{ element: view('wide', rect(0, 0, 60, 20), BoxStyle{}, []) }]
	})!
	tree.replace(column)!
	assert incremental_resolve(mut tree)!.children[0].frame.width == 60
}

fn test_incremental_grid_and_stack_remeasure_assigned_width_before_intrinsic_height() {
	mut tree := LayoutTree{}
	root := grid(GridConfig{
		id:       'grid'
		frame:    rect(0, 0, 60, 0)
		columns:  2
		children: [incremental_label('a', 'WW WW'), incremental_label('b', 'WW'),
			incremental_label('c', 'i')]
	})!
	tree.replace(root)!
	resolved := incremental_resolve(mut tree)!
	assert resolved.frame.height == 80
	assert resolved.children[0].frame == rect(0, 0, 30, 40)
	assert resolved.children[2].frame == rect(0, 40, 30, 40)
	root_stack := stack(StackConfig{
		id:       'stack'
		frame:    rect(0, 0, 30, 0)
		align_x:  .stretch
		children: [StackChild{ element: incremental_label('text', 'WW WW') }]
	})!
	tree.replace(root_stack)!
	stack_result := incremental_resolve(mut tree)!
	assert stack_result.frame.height == 40
	assert stack_result.children[0].frame == rect(0, 0, 30, 40)
	// Padding leaves 30 units for assigned text, not 50.
	padded := flex(FlexConfig{
		id:          'padded'
		frame:       rect(0, 0, 50, 0)
		orientation: .vertical
		padding:     LayoutPadding{ left: 10, right: 10, top: 2.5, bottom: 3.25 }
		children:    [FlexChild{ element: incremental_label('text', 'WW WW'), shrink: 0 }]
	})!
	tree.replace(padded)!
	result := incremental_resolve(mut tree)!
	assert result.frame.height == 45.75
	assert result.children[0].frame == rect(10, 2.5, 30, 40)
}

fn test_nested_intrinsic_containers_measure_height_at_assigned_width() {
	// The outer column owns its children's widths. An authored width remains a
	// preference when the same container is assigned narrower or wider space.
	for authored_width in [30.0, 100.0] {
		text := incremental_label('text', 'WW WW')
		containers := [
			incremental_column('nested', rect(0, 0, authored_width, 0), [text])!,
			grid(GridConfig{ id: 'nested', frame: rect(0, 0, authored_width, 0), columns: 1,
				children: [text] })!,
			stack(StackConfig{ id: 'nested', frame: rect(0, 0, authored_width, 0), align_x: .stretch,
				children: [StackChild{ element: text }] })!,
		]
		for nested in containers {
			mut tree := LayoutTree{}
			for assigned_width in [50.0, 100.0, 30.0, 50.0] {
				root := incremental_column('parent', rect(0, 0, assigned_width, 160), [
					nested,
					view('after', rect(0, 0, 10, 20), BoxStyle{}, []),
				])!
				tree.replace(root)!
				resolved := incremental_resolve(mut tree)!
				expected_height := if assigned_width == 100 { 20.0 } else { 40.0 }
				assert resolved.children[0].frame == rect(0, 0, assigned_width, expected_height)
				assert resolved.children[0].children[0].frame == rect(0, 0, assigned_width, expected_height)
				assert resolved.children[1].frame.y == expected_height
				assert resolved.children[0].layout_input?.width == authored_width
				tree.reset_stats()
				cached := incremental_resolve(mut tree)!
				assert cached.children[0].frame == resolved.children[0].frame
				assert cached.children[1].frame == resolved.children[1].frame
				assert tree.stats().measure_visits == 0
				assert tree.stats().text_measurements == 0
			}
			// A subtree patch must move the following sibling using the assigned
			// width, without rebuilding declarations or changing authored sizing.
			tree.patch('text', incremental_label('text', 'WW'))!
			shorter := incremental_resolve(mut tree)!
			assert shorter.children[0].frame.height == 20
			assert shorter.children[1].frame.y == 20
		}
	}
}

fn test_wrapped_vertical_flex_intrinsic_width_contains_columns_and_moves_sibling() {
	children := [
		view('a', rect(0, 0, 20, 40), BoxStyle{}, []),
		view('b', rect(0, 0, 20, 40), BoxStyle{}, []),
		view('c', rect(0, 0, 20, 40), BoxStyle{}, []),
	]
	mut tree := LayoutTree{}
	for height in [80.0, 120.0, 80.0] {
		column := flex(FlexConfig{ id: 'columns', frame: rect(0, 0, 0, height), orientation: .vertical,
			wrap: true, children: children.map(FlexChild{ element: it, shrink: 0 }) })!
		root := flex(FlexConfig{ id: 'parent', frame: rect(0, 0, 200, 160), align: .start,
			children: [FlexChild{ element: column, shrink: 0 },
				FlexChild{ element: view('after', rect(0, 0, 10, 20), BoxStyle{}, []), shrink: 0 }] })!
		tree.replace(root)!
		resolved := incremental_resolve(mut tree)!
		expected_width := if height == 80 { 40.0 } else { 20.0 }
		assert resolved.children[0].frame == rect(0, 0, expected_width, height)
		assert resolved.children[0].children[0].frame == rect(0, 0, 20, 40)
		assert resolved.children[0].children[1].frame == rect(0, 40, 20, 40)
		assert resolved.children[0].children[2].frame == if height == 80 {
			rect(20, 0, 20, 40)
		} else {
			rect(0, 80, 20, 40)
		}
		assert resolved.children[1].frame.x == expected_width
		tree.reset_stats()
		cached := incremental_resolve(mut tree)!
		assert cached.children[0].frame == resolved.children[0].frame
		assert cached.children[1].frame == resolved.children[1].frame
		assert tree.stats().measure_visits == 0
	}
}

fn test_wrapped_vertical_flex_intrinsic_width_includes_padding_and_line_gap() {
	mut tree := LayoutTree{}
	column := flex(FlexConfig{ id: 'columns', frame: rect(0, 0, 0, 94), orientation: .vertical,
		wrap: true, gap: 4, line_gap: 5.5,
		padding: LayoutPadding{ left: 2.5, right: 3.25, top: 4, bottom: 6 },
		children: [
			FlexChild{ element: view('a', rect(0, 0, 20, 40), BoxStyle{}, []), shrink: 0 },
			FlexChild{ element: view('b', rect(0, 0, 20, 40), BoxStyle{}, []), shrink: 0 },
			FlexChild{ element: view('c', rect(0, 0, 20, 40), BoxStyle{}, []), shrink: 0 },
		] })!
	tree.replace(column)!
	loose := incremental_resolve(mut tree)!
	assert loose.frame == rect(0, 0, 51.25, 94)
	assert loose.children[0].frame == rect(2.5, 4, 20, 40)
	assert loose.children[1].frame == rect(2.5, 48, 20, 40)
	assert loose.children[2].frame == rect(28, 4, 20, 40)
	// Constraining authored height reduces the main axis before wrapping; each
	// child then needs its own column. The fractional cross extent stays exact.
	tight := tree.resolve(LayoutConstraints{ max_height: 90 }, incremental_text, LayoutEnvironment{})!
	assert tight.frame == rect(0, 0, 76.75, 90)
	assert tight.children[1].frame == rect(28, 4, 20, 40)
	assert tight.children[2].frame == rect(53.5, 4, 20, 40)
}

fn incremental_intrinsic_wrapped_columns() !Element {
	return flex(FlexConfig{ id: 'columns', orientation: .vertical, wrap: true,
		children: [
			FlexChild{ element: view('a', rect(0, 0, 20, 40), BoxStyle{}, []), shrink: 0 },
			FlexChild{ element: view('b', rect(0, 0, 20, 40), BoxStyle{}, []), shrink: 0 },
			FlexChild{ element: view('c', rect(0, 0, 20, 40), BoxStyle{}, []), shrink: 0 },
		] })!
}

fn test_intrinsic_wrapped_columns_use_bounded_height_including_tight_zero() {
	mut tree := LayoutTree{}
	tree.replace(incremental_intrinsic_wrapped_columns()!)!
	constraints := [
		LayoutConstraints{ max_height: 80 },
		LayoutConstraints{ min_height: 80, max_height: 80 },
		LayoutConstraints{ max_height: 0 },
		LayoutConstraints{ max_height: 160 },
	]
	expected_sizes := [rect(0, 0, 40, 80), rect(0, 0, 40, 80), rect(0, 0, 60, 0), rect(0, 0, 20, 120)]
	expected_third := [rect(20, 0, 20, 40), rect(20, 0, 20, 40), rect(40, 0, 20, 40), rect(0, 80, 20, 40)]
	for i, limits in constraints {
		resolved := tree.resolve(limits, incremental_text, LayoutEnvironment{})!
		assert resolved.frame == expected_sizes[i]
		assert resolved.children[2].frame == expected_third[i]
		// A bounded maximum larger than natural content does not force a stretch;
		// a tight zero is still a real bound and hard child sizes can overflow it.
		for child in resolved.children {
			assert child.frame.height == 40
		}
		tree.reset_stats()
		cached := tree.resolve(limits, incremental_text, LayoutEnvironment{})!
		assert cached.frame == resolved.frame
		assert cached.children[2].frame == resolved.children[2].frame
		assert tree.stats().measure_visits == 0
	}
}

fn test_horizontal_parent_assigns_height_before_wrapped_columns_width_and_sibling() {
	mut tree := LayoutTree{}
	for height in [80.0, 120.0, 80.0, 0.0] {
		parent := flex(FlexConfig{ id: 'parent', frame: rect(0, 0, 200, height), align: .stretch,
			children: [
				FlexChild{ element: incremental_intrinsic_wrapped_columns()!, shrink: 0 },
				FlexChild{ element: view('after', rect(0, 0, 10, 20), BoxStyle{}, []), shrink: 0 },
			] })!
		tree.replace(parent)!
		resolved := tree.resolve(LayoutConstraints{ min_height: height, max_height: height },
			incremental_text, LayoutEnvironment{})!
		expected_width := if height == 80 { 40.0 } else if height == 0 { 60.0 } else { 20.0 }
		assert resolved.children[0].frame == rect(0, 0, expected_width, height)
		assert resolved.children[1].frame.x == expected_width
		assert resolved.children[0].children[2].frame == if height == 80 {
			rect(20, 0, 20, 40)
		} else if height == 0 {
			rect(40, 0, 20, 40)
		} else {
			rect(0, 80, 20, 40)
		}
		tree.reset_stats()
		cached := tree.resolve(LayoutConstraints{ min_height: height, max_height: height },
			incremental_text, LayoutEnvironment{})!
		assert cached.children[0].frame == resolved.children[0].frame
		assert cached.children[1].frame == resolved.children[1].frame
		assert tree.stats().measure_visits == 0
	}
}

fn test_vertical_parent_assigns_height_before_wrapped_child_intrinsic_width() {
	mut tree := LayoutTree{}
	parent := flex(FlexConfig{ id: 'parent', frame: rect(0, 0, 0, 80), orientation: .vertical,
		children: [FlexChild{ element: incremental_intrinsic_wrapped_columns()! }] })!
	tree.replace(parent)!
	resolved := incremental_resolve(mut tree)!
	assert resolved.frame == rect(0, 0, 40, 80)
	assert resolved.children[0].frame == rect(0, 0, 40, 80)
	assert resolved.children[0].children[2].frame == rect(20, 0, 20, 40)
}

fn test_wrapped_columns_keep_preferred_height_basis_during_parent_shrink() {
	mut tree := LayoutTree{}
	parent := flex(FlexConfig{ id: 'parent', frame: rect(0, 0, 0, 120), orientation: .vertical,
		children: [
			FlexChild{ element: incremental_intrinsic_wrapped_columns()! },
			FlexChild{ element: view('after', rect(0, 0, 20, 60), BoxStyle{}, []) },
		] })!
	tree.replace(parent)!
	resolved := incremental_resolve(mut tree)!
	// Preferred heights120 and60 shrink proportionally into120:80 and40.
	// Assigned height80 determines two columns; it must not become a new basis
	// and cause a second shrink when the shared solver redistributes the parent.
	assert resolved.frame == rect(0, 0, 40, 120)
	assert resolved.children[0].frame == rect(0, 0, 40, 80)
	assert resolved.children[0].children[2].frame == rect(20, 0, 20, 40)
	assert resolved.children[1].frame == rect(0, 80, 40, 40)
}

fn test_grid_and_stack_assign_height_before_wrapped_intrinsic_width() {
	for authored_height in [0.0, 80.0] {
		containers := [
			grid(GridConfig{ id: 'outer', frame: rect(0, 0, 0, authored_height), columns: 1,
				children: [incremental_intrinsic_wrapped_columns()!] })!,
			stack(StackConfig{ id: 'outer', frame: rect(0, 0, 0, authored_height), align_x: .stretch,
				align_y: .stretch, children: [StackChild{ element: incremental_intrinsic_wrapped_columns()! }] })!,
		]
		for container in containers {
			mut tree := LayoutTree{}
			tree.replace(container)!
			standalone := tree.resolve(LayoutConstraints{ min_height: 80, max_height: 80 },
				incremental_text, LayoutEnvironment{})!
			assert standalone.frame == rect(0, 0, 40, 80)
			assert standalone.children[0].frame == rect(0, 0, 40, 80)
			assert standalone.children[0].children[2].frame == rect(20, 0, 20, 40)
			// The dependency reaches an enclosing Flex through either container.
			// Its following sibling must start after both wrapped columns.
			parent := flex(FlexConfig{ id: 'parent', frame: rect(0, 0, 200, 80), align: .stretch,
				children: [FlexChild{ element: container, shrink: 0 },
					FlexChild{ element: view('after', rect(0, 0, 10, 20), BoxStyle{}, []), shrink: 0 }] })!
			tree.replace(parent)!
			resolved := incremental_resolve(mut tree)!
			assert resolved.children[0].frame == rect(0, 0, 40, 80)
			assert resolved.children[0].children[0].frame == rect(0, 0, 40, 80)
			assert resolved.children[1].frame.x == 40
			assert resolved.children[0].children[0].children[2].frame == rect(20, 0, 20, 40)
			tree.reset_stats()
			cached := incremental_resolve(mut tree)!
			assert cached.children[0].frame == resolved.children[0].frame
			assert cached.children[1].frame == resolved.children[1].frame
			assert tree.stats().measure_visits == 0
		}
	}
}

fn incremental_long_text_measure(text string, _style TextStyle, width f64) !LayoutSize {
	natural := if text == 'long' { 600.0 } else { 20.0 }
	return LayoutSize{
		width:  if width < 0 { natural } else { math.min(natural, width) }
		height: if width < 0 { 20.0 } else { 20.0 * math.ceil(natural / math.max(1.0, width)) }
	}
}

fn test_mixed_wrapped_container_grows_at_assigned_width_before_following_sibling() {
	wrapper := stack(StackConfig{ id: 'wrapper', align_x: .stretch,
		children: [
			StackChild{ element: incremental_intrinsic_wrapped_columns()! },
			StackChild{ element: label('long', 'long', Rect{}, TextStyle{ lines: 100 }) },
		] })!
	parents := [
		flex(FlexConfig{ id: 'parent', frame: rect(0, 0, 50, 0),
			children: [FlexChild{ element: wrapper }] })!,
		flex(FlexConfig{ id: 'parent', frame: rect(0, 0, 50, 0), orientation: .vertical,
			children: [FlexChild{ element: wrapper }] })!,
		grid(GridConfig{ id: 'parent', frame: rect(0, 0, 50, 0), columns: 1,
			children: [wrapper] })!,
		stack(StackConfig{ id: 'parent', frame: rect(0, 0, 50, 0), align_x: .stretch,
			align_y: .stretch, children: [StackChild{ element: wrapper }] })!,
	]
	// Synthetic text is600 units wide and20 high per row. At50 units it needs
	// twelve rows; native macOS's four-unit label inset leaves46, or14 rows.
	insets := layout_measure_control_insets(incremental_label('', ''))
	expected_height := if insets.left + insets.right == 4 { 280.0 } else { 240.0 }
	for parent in parents {
		mut tree := LayoutTree{}
		root := incremental_column('root', rect(0, 0, 50, 0), [parent,
			view('after', rect(0, 0, 20, 20), BoxStyle{}, [])])!
		tree.replace(root)!
		for limits in [LayoutConstraints{}, LayoutConstraints{ max_height: 300 }] {
			resolved := tree.resolve(limits, incremental_long_text_measure, LayoutEnvironment{})!
			assert resolved.children[0].frame == rect(0, 0, 50, expected_height)
			assert resolved.children[0].children[0].frame == rect(0, 0, 50, expected_height)
			assert resolved.children[0].children[0].children[1].frame == rect(0, 0, 50, expected_height)
			assert resolved.children[1].frame.y == expected_height
			assert resolved.frame.height == expected_height + 20
			tree.reset_stats()
			cached := tree.resolve(limits, incremental_long_text_measure, LayoutEnvironment{})!
			assert cached.children[0].frame == resolved.children[0].frame
			assert cached.children[1].frame == resolved.children[1].frame
			assert tree.stats().measure_visits == 0
		}
		tree.patch('long', label('long', 'short', Rect{}, TextStyle{ lines: 100 }))!
		shortened := tree.resolve(LayoutConstraints{}, incremental_long_text_measure, LayoutEnvironment{})!
		assert shortened.children[0].frame.height == 120
		assert shortened.children[1].frame.y == 120
		assert tree.stats().builds == 0
		// Actual bounds remain real bounds. Only provisional measurement height
		// is loose; the resolved parent and stretched child accept80 or zero.
		mut bounded := LayoutTree{}
		bounded.replace(parent)!
		for limits in [LayoutConstraints{ max_height: 80 },
			LayoutConstraints{ min_height: 80, max_height: 80 }, LayoutConstraints{ max_height: 0 }] {
			resolved := bounded.resolve(limits, incremental_long_text_measure, LayoutEnvironment{})!
			assert resolved.frame == rect(0, 0, 50, limits.max_height)
			assert resolved.children[0].frame == rect(0, 0, 50, limits.max_height)
		}
	}
}

fn incremental_other_measurer(_text string, _style TextStyle, _width f64) !LayoutSize {
	return LayoutSize{ width: 7.25, height: 13.5 }
}

fn test_incremental_measurer_placeholder_insets_rich_runs_and_explicit_inputs() {
	mut tree := LayoutTree{}
	field := text_input(TextInputConfig{ id: 'field', placeholder: 'WW' })!
	tree.replace(field)!
	initial := incremental_resolve(mut tree)!
	assert initial.frame == rect(0, 0, 44, 32)
	tree.patch('field', Element{ ...field, padding_left: 20 })!
	assert incremental_resolve(mut tree)!.frame.width == 52
	tree.patch('field', Element{ ...field, placeholder: 'i' })!
	assert incremental_resolve(mut tree)!.frame.width == 23
	tree.reset_stats()
	changed := tree.resolve(LayoutConstraints{}, incremental_other_measurer, LayoutEnvironment{})!
	assert changed.frame.height == 25.5
	assert tree.stats().text_measurements == 1
	// Run metric changes retire measurements; run color alone keeps them.
	base := rich_label('rich', [TextRun{ text: 'WW', style: TextStyle{ weight: 600 } }], Rect{}, TextStyle{})
	tree.replace(base)!
	_ = incremental_resolve(mut tree)!
	tree.reset_stats()
	tree.patch('rich', Element{ ...base, text_runs: [TextRun{ text: 'WW', style: TextStyle{ weight: 600, color: 0xff0000 } }] })!
	_ = incremental_resolve(mut tree)!
	assert tree.stats().text_measurements == 0
	tree.patch('rich', Element{ ...base, text_runs: [TextRun{ text: 'WW', style: TextStyle{ weight: 800 } }] })!
	_ = incremental_resolve(mut tree)!
	assert tree.stats().text_measurements == 1
	resolved := incremental_resolve(mut tree)!
	tree.patch('rich', resolved.with_layout_frame(rect(0, 0, 100.25, 20.5)))!
	assert incremental_resolve(mut tree)!.frame == rect(0, 0, 100.25, 20.5)
}

pub struct IncrementalCompiledModel {
pub mut:
	text string = 'WW'
}

fn incremental_compiled_build(mut model IncrementalCompiledModel) Element {
	return incremental_column('compiled', rect(0, 0, 30, 100), [
		incremental_label('text', model.text),
		incremental_label('after', 'i'),
	]) or { panic(err) }
}

fn test_compiled_builder_uses_retained_layout_without_interpreter_nodes() {
	mut model := IncrementalCompiledModel{}
	mut controller := &CompiledVmlController[IncrementalCompiledModel]{ build: incremental_compiled_build, model: &model }
	mut runtime := compiled_vml_runtime()
	previous := runtime.controller
	defer { runtime.controller = previous }
	runtime.controller = voidptr(controller)
	mut tree := LayoutTree{}
	tree.replace(compiled_vml_controller_build[IncrementalCompiledModel]())!
	initial := incremental_resolve(mut tree)!
	controller.model.text = 'WW WW WW'
	tree.replace(compiled_vml_controller_build[IncrementalCompiledModel]())!
	changed := incremental_resolve(mut tree)!
	assert initial.children[1].frame.y == 20
	assert changed.children[1].frame.y == 60
	assert changed.children[0].layout_input? == Rect{}
}

fn test_position_only_move_reuses_typography_and_hidden_subtrees_do_not_measure() {
	mut tree := LayoutTree{}
	leaf := incremental_label('text', 'WW')
	root := absolute(AbsoluteConfig{ id: 'root', frame: rect(0, 0, 100, 100), children: [leaf] })!
	tree.replace(root)!
	_ = incremental_resolve(mut tree)!
	tree.reset_stats()
	tree.patch('text', leaf.with_layout_frame(rect(10.25, 3.5, 0, 0)))!
	resolved := incremental_resolve(mut tree)!
	assert resolved.children[0].frame.x == 10.25
	assert tree.stats().text_measurements == 0
	assert tree.stats().text_hits > 0
	hidden := Element{ ...incremental_column('hidden', rect(0, 0, 30, 100), [incremental_label('unseen', 'WW WW')])!, hidden: true }
	tree.replace(hidden)!
	tree.reset_stats()
	_ = incremental_resolve(mut tree)!
	assert tree.stats().text_measurements == 0
}

fn test_geometry_animations_update_layout_input_while_paint_animations_reuse_measurement() {
	mut tree := LayoutTree{}
	root := incremental_column('root', rect(0, 0, 60, 100), [incremental_label('text', 'WW WW')])!
	tree.replace(root)!
	_ = incremental_resolve(mut tree)!
	tree.reset_stats()
	paint := merge_animation_properties(root, Element{ ...root, box: BoxStyle{ bg: 0x234567 } }, ['background'])
	tree.replace(paint)!
	_ = incremental_resolve(mut tree)!
	assert tree.stats().text_measurements == 0
	geometry := merge_animation_properties(root, Element{ ...root, frame: rect(0, 0, 30, 100) }, ['width'])
	assert geometry.layout_input?.width == 30
	tree.replace(geometry)!
	resized := incremental_resolve(mut tree)!
	assert resized.children[0].frame.width == 30
	assert resized.children[0].frame.height == 40
}

fn test_intrinsic_stack_padding_and_fixed_leaf_content_dependencies() {
	mut tree := LayoutTree{}
	root := stack(StackConfig{ id: 'stack', padding: LayoutPadding{ left: 10, right: 10 }, align_x: .stretch,
		children: [StackChild{ element: incremental_label('text', 'WW WW') }] })!
	tree.replace(root)!
	resolved := incremental_resolve(mut tree)!
	// Custom label metrics are 52; native labels include their 4-unit cell inset.
	inset := layout_measure_control_insets(incremental_label('text', 'WW WW'))
	assert resolved.frame.width == 72 + inset.left + inset.right
	assert resolved.frame.height == 20
	fixed := label('fixed', 'WW', rect(0, 0, 100, 30), TextStyle{})
	tree.replace(incremental_column('parent', rect(0, 0, 200, 100), [fixed])!)!
	_ = incremental_resolve(mut tree)!
	tree.reset_stats()
	tree.patch('fixed', Element{ ...fixed, text: 'texto nuevo', text_style: TextStyle{ size: 30 } })!
	_ = incremental_resolve(mut tree)!
	assert tree.stats().layout_visits == 0
	assert tree.stats().measure_visits == 0
	assert tree.stats().text_measurements == 0
}

fn test_measurer_identity_change_rearranges_inside_fixed_boundary() {
	mut tree := LayoutTree{}
	tree.replace(incremental_column('parent', rect(0, 0, 60, 100), [incremental_label('text', 'WW'), incremental_label('after', 'i')])!)!
	initial := incremental_resolve(mut tree)!
	changed := tree.resolve(LayoutConstraints{}, incremental_other_measurer, LayoutEnvironment{})!
	assert initial.children[1].frame.y == 20
	assert changed.children[1].frame.y == 13.5
}

fn test_default_desktop_measurer_stabilizes_font_environment_before_paint() {
	$if (linux || ((macos || windows) && ui2_custom_rendering ?)) && !ui2_headless ? {
		mut tree := LayoutTree{}
		leaf := label('text', 'Hola ñ', Rect{}, TextStyle{ lines: 20 })
		tree.replace(incremental_column('parent', rect(0, 0, 80, 100), [leaf])!)!
		_ = tree.resolve(LayoutConstraints{}, measure_layout_text, LayoutEnvironment{})!
		assert tree.environment.backend_font_version > 0
		tree.reset_stats()
		tree.patch('text', Element{ ...leaf, text_style: TextStyle{ ...leaf.text_style, color: 0xff0000 } })!
		_ = tree.resolve(LayoutConstraints{}, measure_layout_text, LayoutEnvironment{})!
		assert tree.stats().measure_visits == 0
		assert tree.stats().layout_visits == 0
		assert tree.stats().text_measurements == 0
	}
}
