module ui2

import math

pub struct ModernLayoutItem {
pub:
	id    int
	title string
	basis f64
	grow  f64
}

pub struct ModernLayoutProject {
pub:
	id          int
	title       string
	description string
}

pub struct ModernLayoutApp {
pub mut:
	caption  string = 'Save'
	query    string = 'initial'
	calls    int
	selected int
	created  int
	items    []ModernLayoutItem
	projects []ModernLayoutProject
}

pub fn (mut app ModernLayoutApp) select(id int) {
	app.selected = id
	app.calls++
}

pub fn (mut app ModernLayoutApp) expand_caption() {
	app.caption = 'Save every pending change'
	app.calls++
}

pub fn (mut app ModernLayoutApp) create_project() {
	app.created++
}

fn modern_layout_find(element Element, id string) ?Element {
	if element.id == id { return element }
	for child in element.children {
		if found := modern_layout_find(child, id) { return found }
	}
	return none
}

fn modern_layout_near(actual f64, expected f64) {
	assert math.abs(actual - expected) < 0.00001, '${actual} != ${expected}'
}

fn modern_layout_assert_siblings_fit(element Element) {
	for index, child in element.children {
		assert child.frame.width >= 0 && child.frame.height >= 0, child.id
		assert child.frame.x >= -0.00001 && child.frame.y >= -0.00001, child.id
		assert child.frame.x + child.frame.width <= element.frame.width + 0.00001, '${child.id}: ${child.frame} outside ${element.id}: ${element.frame}'
		assert child.frame.y + child.frame.height <= element.frame.height + 0.00001, '${child.id}: ${child.frame} outside ${element.id}: ${element.frame}'
		for other in element.children[index + 1..] {
			if child.frame.width == 0 || child.frame.height == 0 || other.frame.width == 0
				|| other.frame.height == 0 {
				continue
			}
			assert child.frame.x + child.frame.width <= other.frame.x + 0.00001
				|| other.frame.x + other.frame.width <= child.frame.x + 0.00001
				|| child.frame.y + child.frame.height <= other.frame.y + 0.00001
				|| other.frame.y + other.frame.height <= child.frame.y + 0.00001, 'overlap: ${child.id} ${child.frame} and ${other.id} ${other.frame}'
		}
	}
}

fn test_vml_flex_parent_owns_final_frame_with_explicit_preferred_dimensions() {
	mut fixture_app := ModernLayoutApp{}

	for width in [150.0, 410.0] {
		direct := modern_flex_parent_owns_final_frame_with_explicit_preferred_dimensions_tree(mut fixture_app, rect(20, 30, width, 50))
		assert direct.children[0].frame == if width == 150 {
			rect(0, 0, 80, 50)
		} else {
			rect(0, 0, 150, 50)
		}
		assert direct.children[1].frame == if width == 150 {
			rect(90, 0, 60, 50)
		} else {
			rect(160, 0, 250, 50)
		}
		modern_layout_assert_siblings_fit(direct)
	}
}

fn test_vml_nested_flex_expressions_see_assigned_parent_size() {
	mut fixture_app := ModernLayoutApp{}

	for width in [300.0, 500.0] {
		root := modern_nested_flex_expressions_see_assigned_parent_size_tree(mut fixture_app, rect(0, 0, width, 100))
		content := modern_layout_find(root, 'content') or { panic('missing content') }
		probe := modern_layout_find(root, 'probe') or { panic('missing probe') }
		assert content.frame.width == width - 100
		assert probe.frame.width == content.frame.width
		assert probe.text.starts_with('width=')
		assert probe.text.all_after('=').f64() == content.frame.width
		modern_layout_assert_siblings_fit(root)
		modern_layout_assert_siblings_fit(content)
	}
}

fn test_vml_nested_wrapping_flex_measures_height_at_assigned_width() {
	mut fixture_app := ModernLayoutApp{}

	for width in [300.0, 500.0] {
		root := modern_nested_wrapping_flex_measures_height_at_assigned_width_tree(mut fixture_app, rect(0, 0, width, 200))
		wrapped := root.children[0]
		assert wrapped.frame.width == (width - 10) / 2
		assert wrapped.frame.height == if width == 300 { 70 } else { 30 }
		modern_layout_assert_siblings_fit(wrapped)
	}
}

fn test_vml_flex_remeasures_multiline_and_width_dependent_text() {
	mut fixture_app := ModernLayoutApp{}

	root := modern_flex_remeasures_multiline_and_width_dependent_text_tree(mut fixture_app, rect(0, 0, 300, 300))
	caption := root.children[0]
	assert caption.frame.width == 145
	assert caption.text.starts_with('A longer')
	measured := measure_layout_text(caption.text, caption.text_style, caption.frame.width) or { panic(err) }
	assert measured.height > measure_layout_text('Short', caption.text_style, 145)!.height
	modern_layout_near(caption.frame.height, measured.height)
}

fn test_vml_vertical_flex_measures_height_after_cross_axis_maximum() {
	mut fixture_app := ModernLayoutApp{}

	{
		root := modern_vertical_flex_measures_height_after_cross_axis_maximum_tree(mut fixture_app, rect(0, 0, 500, 300))
		assert root.children[0].frame == rect(0, 0, 150, 70)
		modern_layout_assert_siblings_fit(root.children[0])
	}
}

fn test_vml_intrinsic_grid_measures_rows_at_assigned_cell_width() {
	mut fixture_app := ModernLayoutApp{}

	{
		root := modern_intrinsic_grid_measures_rows_at_assigned_cell_width_tree(mut fixture_app, rect(0, 0, 300, 300))
		grid := root.children[0]
		mut expected_height := 0.0
		for child in grid.children {
			assert child.frame.width == 145
			measured := measure_layout_text(child.text, child.text_style, child.frame.width)!
			expected_height = math.max(expected_height, measured.height)
		}
		modern_layout_near(grid.frame.height, expected_height)
		modern_layout_assert_siblings_fit(grid)
	}
}

fn test_vml_responsive_screen_reflows_modern_children_after_resizing() {
	mut fixture_app := ModernLayoutApp{}
	for tag in ['Flex', 'Grid'] {
		for width in [390.0, 1000.0] {
			direct := modern_responsive_screen_reflows_modern_children_after_resizing_tree(mut fixture_app, rect(0, 0, width, 780), tag)
			body := direct.children[0].children[0]
			assert body.frame.width == width - 48
			modern_layout_assert_siblings_fit(body)
		}
	}
}

fn test_vml_column_repeaters_preserve_hidden_state_keys_and_actions() {
	mut app := ModernLayoutApp{
		items: [ModernLayoutItem{ id: 7, title: 'First' }, ModernLayoutItem{ id: 9, title: 'Second' }]
	}
	root := modern_column_repeaters_preserve_hidden_state_keys_and_actions_tree(mut app, rect(0, 0, 390, 780))
	column := root.children[0]
	assert column.children.len == 2
	assert !column.children[0].hidden
	assert column.children[1].hidden
	assert column.children[0].key == '7'
	assert column.children[1].key == '9'
	assert column.children[0].children[0].frame.width == 195
	assert column.children[0].children[1].text.f64() == 390
	column.children[0].children[0].on_event(ElementEvent{ kind: .tap })
	assert app.selected == 7
	assert app.calls == 1
}

fn test_vml_flex_wrap_uses_intrinsic_text_sizes_without_window() {
	mut fixture_app := ModernLayoutApp{}

	wide := modern_flex_wrap_uses_intrinsic_text_sizes_without_window_tree(mut fixture_app, rect(0, 0, 1000, 200))
	first := wide.children[0]
	assert first.frame.width > 30
	assert first.frame.height > 12
	assert wide.children[1].frame.y == 0
	modern_layout_near(wide.children[1].frame.x, first.frame.width + 9)
	narrow_width := first.frame.width + 1
	narrow := modern_flex_wrap_uses_intrinsic_text_sizes_without_window_tree(mut fixture_app, rect(0, 0, narrow_width, 200))
	modern_layout_near(narrow.children[0].frame.width, first.frame.width)
	assert narrow.children[1].frame.x == 0
	modern_layout_near(narrow.children[1].frame.y, first.frame.height + 9)
	modern_layout_assert_siblings_fit(narrow)
}

fn test_vml_flex_repeater_resolves_weights_and_preserves_keyed_actions() {
	mut model := ModernLayoutApp{
		items: [
			ModernLayoutItem{ id: 7, title: 'First', basis: 40, grow: 1 },
			ModernLayoutItem{ id: 9, title: 'Second', basis: 80, grow: 3 },
		]
	}
	root := modern_flex_repeater_resolves_weights_and_preserves_keyed_actions_tree(mut model, rect(0, 0, 300, 50))
	assert root.children[0].frame == rect(0, 0, 82.5, 50)
	assert root.children[1].frame == rect(92.5, 0, 207.5, 50)
	assert root.children.map(it.key) == ['7', '9']
	assert root.children[0].key != root.children[1].key
	mut fixture_model_0 := ModernLayoutApp{ items: model.items.reverse() }
	reordered := modern_flex_repeater_resolves_weights_and_preserves_keyed_actions_tree(mut fixture_model_0, rect(0, 0, 300, 50))
	assert reordered.children[0].key == '9'
	mut app := model
	for width in [300.0, 500.0, 150.0] {
		built := modern_flex_repeater_resolves_weights_and_preserves_keyed_actions_tree(mut app, rect(0, 0, width, 50))
		assert app.calls == 0
		modern_layout_assert_siblings_fit(built)
	}
	(modern_flex_repeater_resolves_weights_and_preserves_keyed_actions_tree(mut app, rect(0, 0, 300, 50))).children[1].on_event(ElementEvent{ kind: .tap })
	assert app.selected == 9
	assert app.calls == 1
}

fn modern_layout_control_text(_ string) string {
	return 'edited'
}

fn test_vml_flex_measurement_preserves_binding_and_never_invokes_action() {
	mut app := ModernLayoutApp{}
	first := modern_flex_measurement_preserves_binding_and_never_invokes_action_tree(mut app, rect(0, 0, 700, 80))
	assert app.calls == 0
	assert app.query == 'initial'
	assert first.children[0].frame.width > 24
	assert first.children[1].text == 'initial'
	first.children[1].on_event(ElementEvent{ kind: .change, text: 'edited' })
	assert app.query == 'edited'
	first.children[0].on_event(ElementEvent{ kind: .tap })
	second := modern_flex_measurement_preserves_binding_and_never_invokes_action_tree(mut app, rect(0, 0, 700, 80))
	assert app.calls == 1
	assert second.children[0].frame.width > first.children[0].frame.width
	assert second.children[1].frame.width < first.children[1].frame.width
	assert second.children[1].text == 'edited'
	modern_layout_assert_siblings_fit(second)
}

fn test_vml_grid_auto_columns_spans_nested_flex_and_metadata_resize_together() {
	mut fixture_app := ModernLayoutApp{}

	for width in [620.0, 250.0] {
		direct := modern_grid_auto_columns_spans_nested_flex_and_metadata_resize_together_tree(mut fixture_app, rect(0, 0, width, 300))
		assert direct.children.len == 3
		featured := direct.children[0]
		assert featured.children.len == 2
		assert featured.frame.width == if width == 620 { 410 } else { 250 }
		assert direct.children[1].frame.x == if width == 620 { 420 } else { 0 }
		assert direct.children[1].frame.width == if width == 620 { 200 } else { 250 }
		modern_layout_near(featured.children[0].frame.width, (featured.frame.width - 10) / 2)
		modern_layout_assert_siblings_fit(direct)
		modern_layout_assert_siblings_fit(featured)
		modern_layout_assert_siblings_fit(direct.children[0])
	}
}

fn test_responsive_example_fits_wide_and_compact_windows_and_keeps_actions() {
	model := ModernLayoutApp{
		projects: [
			ModernLayoutProject{ id: 1, title: 'Design system', description: 'Shared controls and typography' },
			ModernLayoutProject{ id: 2, title: 'Desktop app', description: 'One layout across window sizes' },
		]
	}
	mut app := model
	mut action := ElementCallback(unsafe { nil })
	for width in [1000.0, 390.0, 1000.0] {
		root := modern_responsive_example_fits_wide_and_compact_windows_and_keeps_actions_tree(mut app, rect(0, 0, width, 780))
		validate_element_tree(root) or { panic(err) }
		page := modern_layout_find(root, 'page') or { panic('missing page') }
		projects := modern_layout_find(root, 'projects') or { panic('missing projects') }
		toolbar := modern_layout_find(root, 'toolbar') or { panic('missing toolbar') }
		searchbar := modern_layout_find(root, 'searchbar') or { panic('missing searchbar') }
		create := modern_layout_find(root, 'create') or { panic('missing action') }
		assert page.frame.width == width
		assert projects.frame.width == width - 48
		assert projects.children.len == 3
		assert projects.children[1].key == '1'
		assert projects.children[2].key == '2'
		if width == 390 {
			assert projects.children.all(it.frame.x == 0)
			assert projects.children.all(it.frame.width == projects.frame.width)
			assert projects.children[1].frame.y > projects.children[0].frame.y
		} else {
			assert projects.children[0].frame.width > projects.children[1].frame.width
		}
		for container in [page, toolbar, searchbar, projects] {
			modern_layout_assert_siblings_fit(container)
		}
		for card in projects.children {
			modern_layout_assert_siblings_fit(card)
		}
		action = create.on_event
		assert app.created == 0
	}
	action(ElementEvent{ kind: .tap })
	assert app.created == 1
}

fn modern_flex_parent_owns_final_frame_with_explicit_preferred_dimensions_tree(mut app ModernLayoutApp, frame Rect) Element {
	return $vml('fixtures/modern_flex_parent_owns_final_frame_with_explicit_preferred_dimensions.vml', frame)
}

fn modern_nested_flex_expressions_see_assigned_parent_size_tree(mut app ModernLayoutApp, frame Rect) Element {
	return $vml('fixtures/modern_nested_flex_expressions_see_assigned_parent_size.vml', frame)
}

fn modern_nested_wrapping_flex_measures_height_at_assigned_width_tree(mut app ModernLayoutApp, frame Rect) Element {
	return $vml('fixtures/modern_nested_wrapping_flex_measures_height_at_assigned_width.vml', frame)
}

fn modern_flex_remeasures_multiline_and_width_dependent_text_tree(mut app ModernLayoutApp, frame Rect) Element {
	return $vml('fixtures/modern_flex_remeasures_multiline_and_width_dependent_text.vml', frame)
}

fn modern_vertical_flex_measures_height_after_cross_axis_maximum_tree(mut app ModernLayoutApp, frame Rect) Element {
	return $vml('fixtures/modern_vertical_flex_measures_height_after_cross_axis_maximum.vml', frame)
}

fn modern_intrinsic_grid_measures_rows_at_assigned_cell_width_tree(mut app ModernLayoutApp, frame Rect) Element {
	return $vml('fixtures/modern_intrinsic_grid_measures_rows_at_assigned_cell_width.vml', frame)
}

fn modern_responsive_screen_reflows_modern_children_after_resizing_tree_flex(mut app ModernLayoutApp, frame Rect) Element {
	return $vml('fixtures/modern_responsive_screen_reflows_modern_children_after_resizing_flex.vml', frame)
}

fn modern_responsive_screen_reflows_modern_children_after_resizing_tree_grid(mut app ModernLayoutApp, frame Rect) Element {
	return $vml('fixtures/modern_responsive_screen_reflows_modern_children_after_resizing_grid.vml', frame)
}

fn modern_responsive_screen_reflows_modern_children_after_resizing_tree(mut app ModernLayoutApp, frame Rect, tag string) Element {
	return if tag == 'Flex' {
		modern_responsive_screen_reflows_modern_children_after_resizing_tree_flex(mut app, frame)
	} else {
		modern_responsive_screen_reflows_modern_children_after_resizing_tree_grid(mut app, frame)
	}
}

fn modern_column_repeaters_preserve_hidden_state_keys_and_actions_tree(mut app ModernLayoutApp, frame Rect) Element {
	return $vml('fixtures/modern_column_repeaters_preserve_hidden_state_keys_and_actions.vml', frame)
}

fn modern_flex_wrap_uses_intrinsic_text_sizes_without_window_tree(mut app ModernLayoutApp, frame Rect) Element {
	return $vml('fixtures/modern_flex_wrap_uses_intrinsic_text_sizes_without_window.vml', frame)
}

fn modern_flex_repeater_resolves_weights_and_preserves_keyed_actions_tree(mut app ModernLayoutApp, frame Rect) Element {
	return $vml('fixtures/modern_flex_repeater_resolves_weights_and_preserves_keyed_actions.vml', frame)
}

fn modern_flex_measurement_preserves_binding_and_never_invokes_action_tree(mut app ModernLayoutApp, frame Rect) Element {
	return $vml('fixtures/modern_flex_measurement_preserves_binding_and_never_invokes_action.vml', frame)
}

fn modern_grid_auto_columns_spans_nested_flex_and_metadata_resize_together_tree(mut app ModernLayoutApp, frame Rect) Element {
	return $vml('fixtures/modern_grid_auto_columns_spans_nested_flex_and_metadata_resize_together.vml', frame)
}

fn modern_responsive_example_fits_wide_and_compact_windows_and_keeps_actions_tree(mut app ModernLayoutApp, frame Rect) Element {
	return $vml('../examples/responsive_layout/responsive_layout.vml', frame)
}
