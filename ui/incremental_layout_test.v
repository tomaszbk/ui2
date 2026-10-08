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
	assert grown.children[1].frame.y == 60
	assert grown.children[0].frame.height == 60
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

fn incremental_other_measurer(_text string, _style TextStyle, _width f64) !LayoutSize {
	return LayoutSize{ width: 7.25, height: 13.5 }
}

fn test_incremental_measurer_placeholder_insets_rich_runs_and_explicit_inputs() {
	mut tree := LayoutTree{}
	field := text_input(TextInputConfig{ id: 'field', multiline: false, placeholder: 'WW' })!
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
	mut controller := &CompiledVmlController[IncrementalCompiledModel]{ build: incremental_compiled_build }
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
