module ui2

import math

fn correction_rect(actual Rect, expected Rect) {
	assert math.abs(actual.x - expected.x) < 0.000001, '${actual} != ${expected}'
	assert math.abs(actual.y - expected.y) < 0.000001, '${actual} != ${expected}'
	assert math.abs(actual.width - expected.width) < 0.000001, '${actual} != ${expected}'
	assert math.abs(actual.height - expected.height) < 0.000001, '${actual} != ${expected}'
}

fn correction_measure(text string, style TextStyle, width f64) !LayoutSize {
	if style.size <= 0 { return error('intrinsic text size must be positive') }
	if text == 'fail-narrow' && width >= 0 && width < 80 { return error('narrow fixture failure') }
	return LayoutSize{ width: 100, height: if width >= 0 && width < 80 { 24.0 } else { 12.0 } }
}

fn correction_other_measure(_text string, _style TextStyle, _width f64) !LayoutSize {
	return error('fixture measurer unavailable')
}

fn correction_grid() !Element {
	return grid(GridConfig{
		id:                     'auto'
		auto_columns_min_width: 100
		children:               [view('a', rect(0, 0, 20, 20), BoxStyle{}, []),
			view('b', rect(0, 0, 20, 20), BoxStyle{}, []),
			view('c', rect(0, 0, 20, 20), BoxStyle{}, [])]
	})!
}

fn test_intrinsic_grid_accepts_width_before_dependent_height() {
	mut tree := LayoutTree{}
	tree.replace(correction_grid()!)!
	id := tree.identity('auto') or { panic('missing grid') }
	// Maximum500 selects three preferred tracks of20, hence accepted width60.
	// At60 automatic placement has one column, so intrinsic height is60.
	for limits in [LayoutConstraints{ max_width: 500 },
		LayoutConstraints{ min_width: 199.5, max_width: 500 },
		LayoutConstraints{ min_width: 200, max_width: 500 },
		LayoutConstraints{ min_width: 299.5, max_width: 500 },
		LayoutConstraints{ min_width: 300, max_width: 500 },
		LayoutConstraints{ min_width: 200, max_width: 500 }, LayoutConstraints{ max_width: 500 },
		LayoutConstraints{ max_width: 50 }] {
		width := if limits.min_width > 0 {
			limits.min_width
		} else if limits.max_width == 50 {
			20.0
		} else {
			60.0
		}
		columns := if width >= 300 {
			3
		} else if width >= 200 {
			2
		} else {
			1
		}
		height := if columns == 3 {
			20.0
		} else if columns == 2 {
			40.0
		} else {
			60.0
		}
		out := tree.resolve(limits, correction_measure, LayoutEnvironment{})!
		correction_rect(out.frame, rect(0, 0, width, height))
		for i, child in out.children {
			correction_rect(child.frame, rect(f64(i % columns) * width / columns, f64(i / columns) * 20, width / columns, 20))
			correction_rect(tree.declaration().children[i].frame, rect(0, 0, 20, 20))
		}
		assert (tree.identity('auto') or { panic('missing grid') }) == id
		tree.reset_stats()
		_ = tree.resolve(limits, correction_measure, LayoutEnvironment{})!
		assert tree.stats().measure_visits == 0 && tree.stats().layout_visits == 0
	}
	// A retained return to a previously measured bound must reuse measurements.
	tree.reset_stats()
	_ = tree.resolve(LayoutConstraints{ max_width: 500 }, correction_measure, LayoutEnvironment{})!
	assert tree.stats().measure_visits == 0
}

fn test_intrinsic_grid_fractional_padding_spans_threshold_and_height_cap() {
	mut tree := LayoutTree{}
	grid := grid(GridConfig{
		id:                     'fractional'
		auto_columns_min_width: 100
		padding:                GridPadding{ left: 3.5, right: 4.25, top: 1.5, bottom: 2.75 }
		spacing:                GridSpacing{ horizontal: 2.5, vertical: 1.25 }
		child_spans:            [GridSpan{ column_span: 2 }]
		children:               [view('a', rect(0, 0, 20.25, 10.5), BoxStyle{}, []),
			view('b', rect(0, 0, 20.25, 10.5), BoxStyle{}, []),
			view('c', rect(0, 0, 20.25, 10.5), BoxStyle{}, [])]
	})!
	tree.replace(grid)!
	for minimum in [0.0, 210.0, 210.25, 0.0] {
		out := tree.resolve(LayoutConstraints{ min_width: minimum, max_width: 500 }, correction_measure, LayoutEnvironment{})!
		width := if minimum == 0 { 73.5 } else { minimum }
		if minimum == 210.25 {
			correction_rect(out.frame, rect(0, 0, 210.25, 26.5))
			correction_rect(out.children[0].frame, rect(3.5, 1.5, 202.5, 10.5))
			correction_rect(out.children[1].frame, rect(3.5, 13.25, 100, 10.5))
			correction_rect(out.children[2].frame, rect(106, 13.25, 100, 10.5))
		} else {
			correction_rect(out.frame, rect(0, 0, width, 38.25))
			for i, child in out.children {
				correction_rect(child.frame, rect(3.5, 1.5 + 11.75 * i, width - 7.75, 10.5))
			}
		}
	}
	out := tree.resolve(LayoutConstraints{ max_width: 500, max_height: 30 }, correction_measure, LayoutEnvironment{})!
	correction_rect(out.frame, rect(0, 0, 73.5, 30))
	for i, child in out.children {
		correction_rect(child.frame, rect(3.5, 1.5 + 9.0 * i, 65.75, 7.75))
	}
}

fn test_nested_intrinsic_grid_reflows_at_wrapper_and_parent_assigned_width() {
	grid := correction_grid()!
	for wrapper in [
		stack(StackConfig{ id: 'wrapper', align_x: .stretch, children: [StackChild{ element: grid }] })!,
		flex(FlexConfig{ id: 'wrapper', orientation: .vertical, align: .stretch, children: [FlexChild{ element: grid, shrink: 0 }] })!,
	] {
		mut tree := LayoutTree{}
		tree.replace(wrapper)!
		out := tree.resolve(LayoutConstraints{ max_width: 500 }, correction_measure, LayoutEnvironment{})!
		correction_rect(out.frame, rect(0, 0, 20, 60))
		correction_rect(out.children[0].frame, rect(0, 0, 20, 60))
	}
	// Parent stretch crosses a column threshold and moves a following sibling.
	mut tree := LayoutTree{}
	for width in [199.5, 200.0, 199.5] {
		root := flex(FlexConfig{
			id:          'root'
			frame:       rect(0, 0, width, 0)
			orientation: .vertical
			align:       .stretch
			children:    [FlexChild{ element: grid, shrink: 0 },
				FlexChild{ element: view('after', rect(0, 0, 10, 10), BoxStyle{}, []), shrink: 0 }]
		})!
		tree.replace(root)!
		out := tree.resolve(LayoutConstraints{}, correction_measure, LayoutEnvironment{})!
		height := if width == 200 { 40.0 } else { 60.0 }
		correction_rect(out.frame, rect(0, 0, width, height + 10))
		correction_rect(out.children[0].frame, rect(0, 0, width, height))
		correction_rect(out.children[1].frame, rect(0, height, width, 10))
	}
	// Shrink an authored300-wide grid into50; width preference stays authored.
	root := flex(FlexConfig{
		id:       'root'
		frame:    rect(0, 0, 100, 0)
		align:    .start
		children: [FlexChild{ element: grid.with_layout_frame(rect(0, 0, 300, 0)) },
			FlexChild{ element: view('after', rect(0, 0, 50, 10), BoxStyle{}, []), shrink: 0 }]
	})!
	tree.replace(root)!
	out := tree.resolve(LayoutConstraints{}, correction_measure, LayoutEnvironment{})!
	correction_rect(out.frame, rect(0, 0, 100, 60))
	correction_rect(out.children[0].frame, rect(0, 0, 50, 60))
	correction_rect(tree.declaration().children[0].frame, rect(0, 0, 300, 0))
	correction_rect(out.children[1].frame, rect(50, 0, 50, 10))
}

fn correction_expect_error(mut tree LayoutTree, limits LayoutConstraints, measure LayoutTextMeasureFn, env LayoutEnvironment, message string) {
	if _ := tree.resolve(limits, measure, env) {
		assert false, 'failed traversal became accepted output'
	} else {
		assert err.msg() == message
	}
}

fn test_failed_placement_repeats_then_patch_hide_reorder_and_removal_recover() {
	mut tree := LayoutTree{}
	bad := label('bad', 'bad', rect(0, 0, 24, 0), TextStyle{ size: 0 })
	good := label('good', 'good', rect(0, 0, 24, 0), TextStyle{})
	boundary := view('boundary', rect(0, 0, 50, 50), BoxStyle{}, [bad])
	independent := view('independent', rect(50, 0, 50, 50), BoxStyle{}, [good])
	root := view('root', rect(0, 0, 100, 100), BoxStyle{}, [independent, boundary])
	tree.replace(root)!
	id := tree.identity('bad') or { panic('missing label') }
	for _ in 0 .. 2 {
		correction_expect_error(mut tree, LayoutConstraints{}, correction_measure, LayoutEnvironment{}, 'intrinsic text size must be positive')
	}
	// The successful independent sibling retains measurement and arrangement.
	tree.reset_stats()
	correction_expect_error(mut tree, LayoutConstraints{}, correction_measure, LayoutEnvironment{}, 'intrinsic text size must be positive')
	assert tree.stats().text_measurements == 1 && tree.stats().layout_visits == 1
	tree.patch('bad', Element{ ...bad, hidden: true })!
	_ = tree.resolve(LayoutConstraints{}, correction_measure, LayoutEnvironment{})!
	tree.patch('bad', bad)!
	for _ in 0 .. 2 {
		correction_expect_error(mut tree, LayoutConstraints{}, correction_measure, LayoutEnvironment{}, 'intrinsic text size must be positive')
	}
	tree.replace(Element{ ...root, children: [boundary, independent] })!
	for _ in 0 .. 2 {
		correction_expect_error(mut tree, LayoutConstraints{}, correction_measure, LayoutEnvironment{}, 'intrinsic text size must be positive')
	}
	tree.replace(Element{ ...root, children: [independent] })!
	_ = tree.resolve(LayoutConstraints{}, correction_measure, LayoutEnvironment{})!
	tree.replace(root)!
	assert (tree.identity('bad') or { panic('missing label') }).generation != id.generation
	for _ in 0 .. 2 {
		correction_expect_error(mut tree, LayoutConstraints{}, correction_measure, LayoutEnvironment{}, 'intrinsic text size must be positive')
	}
	recovered_id := tree.identity('bad') or { panic('missing label') }
	tree.patch('bad', Element{ ...bad, text_style: TextStyle{} })!
	out := tree.resolve(LayoutConstraints{}, correction_measure, LayoutEnvironment{})!
	correction_rect(out.children[1].children[0].frame, rect(0, 0, 24, 24))
	assert (tree.identity('bad') or { panic('missing label') }).generation == recovered_id.generation
	tree.reset_stats()
	_ = tree.resolve(LayoutConstraints{}, correction_measure, LayoutEnvironment{})!
	assert tree.stats().measure_visits == 0 && tree.stats().layout_visits == 0
	// Paint changes remain geometry-free after recovery.
	tree.patch('bad', Element{ ...bad, text_style: TextStyle{ color: 0xff0000 } })!
	_ = tree.resolve(LayoutConstraints{}, correction_measure, LayoutEnvironment{})!
	assert tree.stats().measure_visits == 0 && tree.stats().layout_visits == 0
}

fn test_prior_valid_placement_is_not_reused_after_failed_width_attempt() {
	mut tree := LayoutTree{}
	mut children := []FlexChild{}
	for id in ['first', 'second'] {
		boundary := flex(FlexConfig{
			id:          id
			frame:       rect(0, 0, 100, 50)
			orientation: .vertical
			align:       .stretch
			children:    [FlexChild{ element: label(id + '-text', if id == 'first' {
				'ok'
			} else {
				'fail-narrow'
			}, Rect{}, TextStyle{}), shrink: 0 }]
		})!
		children << FlexChild{ element: boundary }
	}
	tree.replace(flex(FlexConfig{ id: 'root', frame: rect(0, 0, 200, 100), align: .start, children: children })!)!
	wide := LayoutConstraints{ min_width: 200, max_width: 200 }
	narrow := LayoutConstraints{ min_width: 100, max_width: 100 }
	out := tree.resolve(wide, correction_measure, LayoutEnvironment{})!
	correction_rect(out.children[0].children[0].frame, rect(0, 0, 100, 12))
	for _ in 0 .. 2 {
		correction_expect_error(mut tree, narrow, correction_measure, LayoutEnvironment{}, 'narrow fixture failure')
	}
	recovered := tree.resolve(wide, correction_measure, LayoutEnvironment{})!
	correction_rect(recovered.children[0].children[0].frame, rect(0, 0, 100, 12))
	correction_rect(recovered.children[1].children[0].frame, rect(0, 0, 100, 12))
	tree.reset_stats()
	_ = tree.resolve(wide, correction_measure, LayoutEnvironment{})!
	assert tree.stats().measure_visits == 0 && tree.stats().layout_visits == 0
	// Environment and measurer failures never publish partially traversed output.
	for _ in 0 .. 2 {
		correction_expect_error(mut tree, wide, correction_other_measure, LayoutEnvironment{ version: 1 }, 'fixture measurer unavailable')
	}
	_ = tree.resolve(wide, correction_measure, LayoutEnvironment{})!
	tree.patch('second-text', label('second-text', 'ok', Rect{}, TextStyle{}))!
	narrow_out := tree.resolve(narrow, correction_measure, LayoutEnvironment{})!
	correction_rect(narrow_out.children[0].children[0].frame, rect(0, 0, 50, 24))
	correction_rect(narrow_out.children[1].children[0].frame, rect(0, 0, 50, 24))
}

fn test_default_measurer_invalid_style_never_publishes_placement_success() {
	mut tree := LayoutTree{}
	bad := label('bad', 'invalid', Rect{}, TextStyle{ size: 0 })
	tree.replace(view('root', rect(0, 0, 100, 100), BoxStyle{}, [
		view('boundary', rect(0, 0, 50, 50), BoxStyle{}, [bad]),
	]))!
	identity := tree.identity('bad') or { panic('missing label') }
	for _ in 0 .. 3 {
		correction_expect_error(mut tree, LayoutConstraints{}, measure_layout_text,
			LayoutEnvironment{}, 'intrinsic text size must be finite and positive')
	}
	tree.patch('bad', label('bad', 'valid', rect(0, 0, 24, 12), TextStyle{}))!
	out := tree.resolve(LayoutConstraints{}, measure_layout_text, LayoutEnvironment{})!
	correction_rect(out.children[0].children[0].frame, rect(0, 0, 24, 12))
	assert (tree.identity('bad') or { panic('missing label') }).generation == identity.generation
	tree.reset_stats()
	_ = tree.resolve(LayoutConstraints{}, measure_layout_text, LayoutEnvironment{})!
	assert tree.stats().measure_visits == 0 && tree.stats().layout_visits == 0
}

fn test_arrangement_errors_and_rejected_resolve_inputs_preserve_recovery() {
	mut tree := LayoutTree{}
	// Public LayoutSpec can be invalid even when fixed-size measurement succeeds.
	// The error occurs in recursive arrangement, below an already arranged root.
	broken := Element{
		...view('broken', rect(0, 0, 50, 50), BoxStyle{}, [
			view('leaf', rect(0, 0, 20, 20), BoxStyle{}, []),
		])
		layout: LayoutSpec{ kind: .grid, grid: GridConfig{ columns: -1 } }
	}
	tree.replace(view('root', rect(0, 0, 100, 100), BoxStyle{}, [broken]))!
	for _ in 0 .. 3 {
		correction_expect_error(mut tree, LayoutConstraints{}, correction_measure,
			LayoutEnvironment{}, 'grid rows, columns and max_columns cannot be negative')
	}
	identity := tree.identity('broken') or { panic('missing boundary') }
	tree.patch('broken', grid(GridConfig{
		id:       'broken'
		frame:    rect(0, 0, 50, 50)
		columns:  1
		children: broken.children
	})!)!
	out := tree.resolve(LayoutConstraints{}, correction_measure, LayoutEnvironment{})!
	correction_rect(out.children[0].children[0].frame, rect(0, 0, 50, 50))
	assert (tree.identity('broken') or { panic('missing boundary') }).generation == identity.generation
	for _ in 0 .. 2 {
		correction_expect_error(mut tree, LayoutConstraints{ min_width: 20, max_width: 10 },
			correction_measure, LayoutEnvironment{}, 'layout minimum cannot exceed its maximum')
		correction_expect_error(mut tree, LayoutConstraints{}, correction_measure,
			LayoutEnvironment{ scale: 0 }, 'layout environment scale must be positive and finite')
	}
	tree.reset_stats()
	_ = tree.resolve(LayoutConstraints{}, correction_measure, LayoutEnvironment{})!
	assert tree.stats().measure_visits == 0 && tree.stats().layout_visits == 0
}
