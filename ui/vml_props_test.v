// vtest vflags: -d vml_props
module ui2

// Golden equivalence of the VML props table with the current compiled
// lowering (harness: vml_props_harness_d_vml_props.v): layout containers,
// menus, and the props rules (apply_event, validate, defaults).

// ---------------------------------------------------------------- layout

fn props_layout_tree() PNode {
	return pn(ScreenProps{
		style: style_list([style_background(0xF1F5F9)])
	}, id: 'root', children: [
		pn(ColumnProps{
			gap:         6
			line_gap:    2
			justify:     .center
			align_items: .start
			style:       style_list([style_padding(4), style_transparent(true)])
		}, id: 'main', children: [
			pn(RowProps{
				spacing:   3
				height:    40
				wrap:      true
				flex_grow: 1
				justify:   .space_between
			}, id: 'row', children: [
				pn(ViewProps{
					width:       30
					height:      20
					flex_basis:  25
					flex_shrink: 0
					align_self:  .center
				}, id: 'a'),
				pn(ViewProps{
					height:     20
					flex_grow:  2
					min_width:  10
					max_width:  80
					min_height: 5
					max_height: 30
				}, id: 'b'),
				pn(ViewProps{
					height: 12
					width:  12
					style:  style_list([style_background(0xFF0000), style_radius(3)])
				}, key: 'plain'),
			]),
			pn(FlexProps{
				orientation: .vertical
				gap:         2
				spacing:     9
				height:      60
				align_items: .center
			}, id: 'flex', children: [
				pn(LabelProps{ text: 'one', height: 18 }),
				pn(LabelProps{ text: 42, height: 18 }),
			]),
			pn(FlexProps{ spacing: 5, height: 30, line_gap: 4 }, id: 'flex_spacing', children: [
				pn(ViewProps{ width: 20, height: 10 }),
				pn(ViewProps{ width: 20, height: 10 }),
			]),
			pn(GridProps{
				columns:            3
				spacing:            4
				spacing_y:          6
				height:             80
				col_default_width:  30
				row_default_height: 20
				col_force_default:  true
				row_force_default:  true
				style:              style_padding(2)
			}, id: 'grid', children: [
				pn(ViewProps{ column_span: 2 }, id: 'g1'),
				pn(ViewProps{ row_span: 2 }, id: 'g2'),
				pn(ViewProps{}, id: 'g3'),
				pn(ViewProps{}, id: 'g4'),
			]),
			pn(GridProps{
				rows:        2
				orientation: .top_to_bottom_left_to_right
				spacing_x:   3
				height:      40
			}, id: 'rows', children: [
				pn(ViewProps{}, id: 'r1'),
				pn(ViewProps{}, id: 'r2'),
				pn(ViewProps{}, id: 'r3'),
			]),
			pn(GridProps{ auto_columns_min_width: 40, max_columns: 3, height: 50 }, id: 'auto', children: [
				pn(ViewProps{ height: 10 }, id: 'h1'),
				pn(ViewProps{ height: 10 }, id: 'h2'),
			]),
			pn(GridProps{ cols: 2, height: 30 }, id: 'cols', children: [
				pn(ViewProps{ height: 10 }),
				pn(ViewProps{ height: 10 }),
			]),
			pn(StackProps{
				align_x: .center
				align_y: .end
				height:  50
				style:   style_padding(3)
			}, id: 'stack', children: [
				pn(ViewProps{ width: 20, height: 10 }, id: 's1'),
				pn(ViewProps{
					width:        10
					height:       10
					align_self_x: .end
					align_self_y: .stretch
				}, id: 's2'),
			]),
			pn(ScrollProps{ persistent: true, scroll_mode: .both, height: 60 }, id: 'scroll', children: [
				pn(ViewProps{ width: 500, height: 300 }, id: 'sc'),
			]),
			pn(ScrollProps{ height: 20 }, children: [
				pn(LabelProps{ text: 'default scroll' }),
			]),
			pn(ScaledContentProps{ content_width: 200, content_height: 100, width: 300, height: 50 }, id: 'scaled', children: [
				pn(AbsoluteProps{}, id: 'abs', children: [
					pn(ViewProps{ x: 10, y: 5, width: 50, height: 20 }, id: 'p1'),
					pn(ViewProps{ y: 40 }, id: 'p2'),
				]),
			]),
			pn(ViewProps{ height: 30 }, id: 'plain_view', children: [
				pn(ViewProps{ width: 10 }, id: 'inner'),
			]),
		]),
	])
}

fn props_bump_leaf(el Element) Element {
	if el.children.len == 0 {
		return Element{
			...el
			frame: rect(el.frame.x + 1, el.frame.y, el.frame.width, el.frame.height)
		}
	}
	mut children := el.children.clone()
	children[0] = props_bump_leaf(children[0])
	return Element{
		...el
		children: children
	}
}

fn props_differences(compiled Element, built Element) int {
	mut out := []string{}
	props_diff(compiled, built, 'check', mut out)
	return out.len
}

fn test_props_layout_matches_compiled_vml() {
	frame := rect(0, 0, 360, 900)
	compiled := $vml('fixtures/props_layout.vml', frame)
	built := props_document(props_layout_tree(), frame)!
	assert_props_equal('layout', compiled, built)
	// The comparison itself sees a field, a deep frame, a callback and metadata.
	assert props_differences(compiled, built) == 0
	assert props_differences(compiled, Element{ ...built, opacity: 0.5 }) == 1
	assert props_differences(compiled, props_bump_leaf(built)) == 1
	assert props_differences(compiled, Element{
		...built
		on_event: fn (event ElementEvent) {}
	}) == 1
	assert props_differences(compiled, Element{
		...built
		compiled_metadata: unsafe { nil }
	}) == 1
}

// ---------------------------------------------------------------- menus

fn props_menu_items(items []MenuItem) string {
	return items.map('${it.id}|${it.title}|${it.shortcut}|${it.separator}|${it.checked}|${it.enabled}|${props_set(it.on_select)}[${props_menu_items(it.items)}]').join(',')
}

fn props_menus_string(document []Menu) string {
	return document.map('${it.title}{${props_menu_items(it.items)}}').join(' ')
}

fn props_fire_menu_items(items []MenuItem, mut app PropsApp) {
	for item in items {
		if item.on_select != unsafe { nil } {
			item.on_select(ElementEvent{ kind: .click, id: item.id })
		}
		props_fire_menu_items(item.items, mut app)
	}
}

fn props_menu_document(root PNode) ![]Menu {
	return menus(props_document(root, rect(0, 0, 0, 0))!)!
}

fn props_example_menus(mut app PropsApp) []Menu {
	callback_file_new := props_hit(mut app, 'file_new')
	callback_file_open := props_hit(mut app, 'file_open')
	callback_file_revert := props_hit(mut app, 'file_revert')
	callback_export_pdf := props_hit(mut app, 'export_pdf')
	callback_export_png := props_hit(mut app, 'export_png')
	callback_word_wrap := props_hit(mut app, 'word_wrap')
	return $vml('../examples/vml_menu/menus.vml')
}

fn test_props_menus_match_compiled_vml() {
	mut compiled_app := PropsApp{}
	mut props_app := PropsApp{}
	compiled := props_example_menus(mut compiled_app)
	built := props_menu_document(pn(MenuBarProps{}, children: [
		pn(MenuProps{ title: 'File' }, children: [
			pn(MenuItemProps{
				on_click: props_hit(mut props_app, 'file_new')
				text:     'New'
				shortcut: 'cmd+n'
			}, id: 'file_new'),
			pn(MenuItemProps{
				text:     'Open'
				on_click: props_hit(mut props_app, 'file_open')
				shortcut: 'cmd+o'
			}, id: 'file_open'),
			pn(MenuSeparatorProps{}),
			pn(MenuItemProps{
				on_click: props_hit(mut props_app, 'file_revert')
				text:     'Revert'
				enabled:  false
			}, id: 'file_revert'),
			pn(MenuProps{ title: 'Export' }, children: [
				pn(MenuItemProps{ on_click: props_hit(mut props_app, 'export_pdf'), text: 'PDF' }, id: 'export_pdf'),
				pn(MenuItemProps{ on_click: props_hit(mut props_app, 'export_png'), text: 'PNG' }, id: 'export_png'),
			]),
		]),
		pn(MenuProps{ title: 'View' }, children: [
			pn(MenuItemProps{
				on_click: props_hit(mut props_app, 'word_wrap')
				text:     'Word Wrap'
				checked:  true
			}, id: 'word_wrap'),
		]),
	]))!
	assert props_menus_string(built) == props_menus_string(compiled)
	for menu in compiled {
		props_fire_menu_items(menu.items, mut compiled_app)
	}
	for menu in built {
		props_fire_menu_items(menu.items, mut props_app)
	}
	assert props_app.log == compiled_app.log
	assert props_app.log.len == 6
}

fn props_solo_menu(mut app PropsApp) []Menu {
	return $vml('fixtures/props_menu.vml')
}

fn test_props_single_menu_document_matches_compiled_vml() {
	mut app := PropsApp{}
	built := props_menu_document(pn(MenuProps{ text: 'Solo' }, children: [
		pn(MenuItemProps{ text: 'One', title: 'Uno', shortcut: 'cmd+1' }, id: 'one'),
		pn(MenuItemProps{ text: app.name, checked: true, separator: false }, id: 'named'),
		pn(MenuSeparatorProps{}),
		pn(MenuProps{ text: 'More' }, children: [
			pn(MenuItemProps{ text: 'Deep', enabled: false }, id: 'deep'),
		]),
	]))!
	assert props_menus_string(built) == props_menus_string(props_solo_menu(mut app))
}

fn test_props_menus_reject_ordinary_elements() {
	if _ := menus(view('plain', rect(0, 0, 1, 1), BoxStyle{}, [])) {
		assert false
	}
}

// ---------------------------------------------------------------- unit rules

fn test_props_apply_event_updates_widget_values() {
	mut slider := SliderProps{
		value: 1
	}
	slider.apply_event(ElementEvent{ kind: .change, value: 42 })
	slider.apply_event(ElementEvent{ kind: .click, value: 7 })
	assert slider.value == 42
	mut switch_props := SwitchProps{}
	switch_props.apply_event(ElementEvent{ kind: .change, checked: true })
	assert switch_props.active
	mut check := CheckboxProps{
		checked: true
	}
	check.apply_event(ElementEvent{ kind: .change, checked: false })
	assert !check.checked
	mut input := TextInputProps{
		text: 'a'
	}
	input.apply_event(ElementEvent{ kind: .submit, text: 'ignored' })
	input.apply_event(ElementEvent{ kind: .change, text: 'b' })
	assert input.text.str() == 'b'
	mut area := TextAreaProps{}
	area.apply_event(ElementEvent{ kind: .change, text: 'multi\nline' })
	assert area.text.str() == 'multi\nline'
	mut dropdown := DropdownProps{}
	dropdown.apply_event(ElementEvent{ kind: .change, text: 'Green' })
	assert dropdown.text.str() == 'Green'
	mut spinner := SpinnerProps{}
	spinner.apply_event(ElementEvent{ kind: .change, text: 'Work' })
	assert spinner.text.str() == 'Work'
	mut toggle := ToggleButtonProps{}
	toggle.apply_event(ElementEvent{ kind: .change, checked: true })
	assert toggle.pressed
	mut view_props := ViewProps{}
	view_props.apply_event(ElementEvent{ kind: .change, checked: true })
	assert view_props.hidden == none
}

fn props_build_error[P](props P) string {
	vml_build_element(props, VmlBuildContext{ id: 'x', frame: rect(0, 0, 10, 10) }) or {
		return err.msg()
	}
	return ''
}

fn test_props_validate_rejects_invalid_values() {
	assert props_build_error(ViewProps{ opacity: 1.5 }).contains('opacity')
	assert props_build_error(ViewProps{ opacity: -0.1 }).contains('opacity')
	assert props_build_error(ViewProps{ scale_x: 0 }).contains('scale_x')
	assert props_build_error(LabelProps{ scale_y: 0 }).contains('scale_y')
	assert props_build_error(ViewProps{ column_span: 0 }).contains('column_span')
	assert props_build_error(ViewProps{ row_span: -1 }).contains('row_span')
	assert props_build_error(ScaledContentProps{ content_width: 0, content_height: 10 }) != ''
	assert props_build_error(ViewProps{ opacity: 1, scale_x: -1 }) == ''
}

fn test_props_defaults_equal_compiled_defaults() {
	// Hidden defaults of the compiled lowering are field defaults of the props.
	slider := SliderProps{}
	assert slider.max == 100 && slider.track_inset == 16 && slider.value_track_color == 0x93c5fd
	assert slider.thumb_color == 0x2563eb && slider.track_width == 4 && slider.thumb_size == 20
	switch_props := SwitchProps{}
	assert switch_props.inactive_color == 0xcbd5e1 && switch_props.active_color == 0x22c55e
	assert switch_props.disabled_track_color == 0xe2e8f0 && switch_props.disabled_thumb_color == 0xf8fafc
	assert ProgressBarProps{}.max == 100
	assert MessageBoxProps{}.dialog_width == 300 && MessageBoxProps{}.dialog_height == 150
	toggle := ToggleButtonProps{}
	assert toggle.allow_no_selection && toggle.down_background == 0x2563eb && toggle.down_corner_radius == 6
	accordion := AccordionProps{}
	assert accordion.min_space == 44 && accordion.active_title_background == 0x2563eb
	tabs := TabbedPanelProps{}
	assert tabs.tab_height == 40 && tabs.tab_width == 100 && tabs.active_tab_color == 0x0f172a
	assert CarouselProps{}.min_move == 0.2
	tree := TreeViewProps{}
	assert tree.row_height == 36 && tree.indent == 24 && tree.disclosure_width == 28
	overlay := DialogProps{}
	assert overlay.placement == .bottom_start && overlay.gap == 6 && overlay.margin == 8
	assert overlay.backdrop.bg == 0x202938 && overlay.backdrop_opacity == 0.3
	assert overlay.dismiss_on_escape && overlay.dismiss_on_outside && overlay.tooltip_delay == 0.5
	flex := FlexProps{}
	assert flex.align_items == .stretch && flex.line_gap == -1
	item := VmlLayoutItem{}
	assert item.flex_basis == -1 && item.flex_shrink == 1 && item.max_width == -1
	assert item.column_span == 1 && item.align_self == .auto
	assert MenuItemProps{}.enabled
}
