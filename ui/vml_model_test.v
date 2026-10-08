module ui2

pub struct VmlTestUser {
pub:
	id     int
	name   string
	weight f64
}

pub struct VmlTestNestedItem {
pub:
	id string
}

pub struct VmlTestGroup {
pub:
	id    string
	items []VmlTestNestedItem
}

pub struct VmlTestApp {
pub:
	max_users int = 3
pub mut:
	name        string
	enabled     bool
	secondary   bool
	level       f64
	users       []VmlTestUser
	groups      []VmlTestGroup
	removed     int
	saved       string
	page        int
	tree_open   bool
	selected    string
	screen_name string
	modal_open  bool
}

fn vml_test_control_value(_id string) f64 {
	return 72.5
}

fn vml_test_spinner_text(_id string) string {
	return 'Work'
}

pub fn (mut app VmlTestApp) clear() {
	app.name = ''
}

pub fn (mut app VmlTestApp) remove_user(id int) {
	app.removed = id
}

pub fn (mut app VmlTestApp) save_name(name string) {
	app.saved = name
}

pub fn (mut app VmlTestApp) select_second_tab() {
	app.page = 1
}

pub fn (mut app VmlTestApp) toggle_tree() {
	app.tree_open = !app.tree_open
}

pub fn (mut app VmlTestApp) select_tree_leaf() {
	app.selected = 'guide'
}

pub fn (mut app VmlTestApp) show_details_screen() {
	app.screen_name = 'details'
}

pub fn (mut app VmlTestApp) open_modal() {
	app.modal_open = true
}

pub fn (mut app VmlTestApp) close_modal() {
	app.modal_open = false
}

fn vml_test_find(element Element, text string) ?Element {
	if element.text == text {
		return element
	}
	for child in element.children {
		if found := vml_test_find(child, text) {
			return found
		}
	}
	return none
}

fn test_vml_model_expressions_bindings_and_repeaters() {
	source := r'Screen {
		id: root
		property bool compact: root.width < 700
    Absolute {
        transparent: true
        TextInput { multiline: false
                bind.text: app.name
                width: root.compact ? root.width-32 : 210
            }
            Checkbox {
                bind.checked: app.enabled
            }
            Label {
                text: "${app.users.len}/${app.max_users}"
            }
            Button {
                text: "Clear"
                on_tap: app.clear()
            }
            Column {
                Repeater {
                    model: app.users
                    key: item.id
                    Row {
                        height: 30
                        background: index % 2 == 0 ? #FFFFFF : #F1F5F9
                        Label { text: item.name }
                        Button { text: "Remove" on_tap: app.remove_user(item.id) }
                    }
                }
            }
    }
	}'
	app := VmlTestApp{
		name:    'Ada'
		enabled: true
		users:   [
			VmlTestUser{
				id:   7
				name: 'Ada'
			},
			VmlTestUser{
				id:   9
				name: 'Lin'
			},
		]
	}
	root := element_from_vml_model(source, app, rect(0, 0, 640, 400)) or { panic(err) }
	validate_element_tree(root) or { panic(err) }
	assert (vml_test_find(root, '2/3') or { panic('missing count') }).text == '2/3'
	assert (vml_test_find(root, 'Ada') or { panic('missing model-bound field') }).frame.width == 608
	column := root.children[0].children[4]
	assert column.children.len == 2
	assert column.children[0].key == '7'
	assert column.children[1].key == '9'
	assert column.children[0].box.bg == u32(0xFFFFFF)
	assert column.children[1].box.bg == u32(0xF1F5F9)
}

fn test_vml_model_supports_numeric_slider_bindings() {
	source := 'Slider { id: volume bind.value: app.level min: 0 max: 100 step: 0.5 }'
	root := element_from_vml_model(source, VmlTestApp{ level: 12.5 }, rect(0, 0, 240, 32)) or {
		panic(err)
	}
	assert root.kind == .slider
	assert root.value == 12.5

	mut app := new_vml_app(source, VmlTestApp{ level: 12.5 }) or { panic(err) }
	built := app.build(rect(0, 0, 240, 32)) or { panic(err) }
	built.on_event(ElementEvent{ kind: .change, value: 72.5 })
	assert app.state().level == 72.5
}

fn test_vml_model_supports_active_switch_bindings() {
	source := 'Switch { id: notifications bind.active: app.enabled }'
	root := element_from_vml_model(source, VmlTestApp{ enabled: true }, rect(0, 0, 83, 32)) or {
		panic(err)
	}
	assert root.kind == .switch_control
	assert root.checked

	mut app := new_vml_app(source, VmlTestApp{ enabled: false }) or { panic(err) }
	built := app.build(rect(0, 0, 83, 32)) or { panic(err) }
	built.on_event(ElementEvent{ kind: .change, checked: true })
	assert app.state().enabled
}

fn test_vml_model_rejects_non_boolean_switch_bindings() {
	if _ := element_from_vml_model('Switch { bind.active: app.name }', VmlTestApp{}, rect(0, 0, 83,
		32))
	{
		assert false, 'switch active state must bind to a bool field'
	} else {
		assert err.msg().contains('bind.active requires a bool field')
	}
}

fn test_vml_model_supports_spinner_text_bindings() {
	source := 'Spinner {
		id: location
		bind.text: app.name
		Option { text: "Home" }
		Option { text: "Work" }
	}'
	mut app := new_vml_app(source, VmlTestApp{ name: 'Home' }) or { panic(err) }
	built := app.build(rect(0, 0, 160, 42)) or { panic(err) }
	assert built.kind == .dropdown
	assert built.menu.len == 2
	built.on_event(ElementEvent{ kind: .change, text: 'Work' })
	assert app.state().name == 'Work'
}

fn test_vml_model_supports_text_input_bindings_and_validation_events() {
	source := 'TextInput {
		id: entry
		multiline: false
		bind.text: app.name
		on_submit: app.clear()
	}'
	mut app := new_vml_app(source, VmlTestApp{ name: 'Before' }) or { panic(err) }
	built := app.build(rect(0, 0, 240, 36)) or { panic(err) }
	assert built.kind == .text_field
	assert built.text == 'Before'
	built.on_event(ElementEvent{ kind: .change, text: 'Work' })
	assert app.state().name == 'Work'
	built.on_event(ElementEvent{ kind: .submit })
	assert app.state().name == ''
}

fn test_vml_model_supports_toggle_button_pressed_bindings() {
	source := 'ToggleButton { id: bold text: "Bold" bind.pressed: app.enabled }'
	root := element_from_vml_model(source, VmlTestApp{ enabled: true }, rect(0, 0, 100, 40)) or {
		panic(err)
	}
	assert root.kind == .toggle_button
	assert root.checked

	mut app := new_vml_app(source, VmlTestApp{ enabled: false }) or { panic(err) }
	built := app.build(rect(0, 0, 100, 40)) or { panic(err) }
	built.on_event(ElementEvent{ kind: .change, checked: true })
	assert app.state().enabled
}

fn test_vml_model_toggle_button_groups_update_all_bound_fields() {
	source := 'Screen {
		ToggleButton {
			id: primary
			text: "Primary"
			group: choice
			allow_no_selection: false
			bind.pressed: app.enabled
		}
		ToggleButton {
			id: secondary
			text: "Secondary"
			group: choice
			allow_no_selection: false
			bind.pressed: app.secondary
		}
	}'
	normalized := element_from_vml_model(source, VmlTestApp{
		enabled:   true
		secondary: true
	}, rect(0, 0, 240, 80)) or { panic(err) }
	assert (vml_test_find(normalized, 'Primary') or { panic('missing primary toggle') }).checked
	assert !(vml_test_find(normalized, 'Secondary') or { panic('missing secondary toggle') }).checked

	mut app := new_vml_app(source, VmlTestApp{ enabled: true }) or { panic(err) }
	built := app.build(rect(0, 0, 240, 80)) or { panic(err) }
	secondary := vml_test_find(built, 'Secondary') or { panic('missing secondary toggle') }
	secondary.on_event(ElementEvent{ kind: .change, checked: true })
	assert !app.state().enabled
	assert app.state().secondary

	rebuilt := app.build(rect(0, 0, 240, 80)) or { panic(err) }
	primary := vml_test_find(rebuilt, 'Primary') or { panic('missing primary toggle') }
	primary.on_event(ElementEvent{ kind: .change, checked: true })
	assert app.state().enabled
	assert !app.state().secondary
	primary.on_event(ElementEvent{ kind: .change, checked: true })
	assert app.state().enabled
}

fn test_vml_model_grid_layout_counts_repeater_children() {
	source := 'Grid {
		columns: 2
		padding: 10
		spacing: 10
		Repeater {
			model: app.users
			key: item.id
			Button { text: item.name }
		}
	}'
	grid := element_from_vml_model(source, VmlTestApp{
		users: [
			VmlTestUser{
				id:   1
				name: 'One'
			},
			VmlTestUser{
				id:   2
				name: 'Two'
			},
			VmlTestUser{
				id:   3
				name: 'Three'
			},
		]
	}, rect(0, 0, 210, 110)) or { panic(err) }
	assert grid.children.len == 3
	assert grid.children[0].frame == rect(10, 10, 90, 40)
	assert grid.children[1].frame == rect(110, 10, 90, 40)
	assert grid.children[2].frame == rect(10, 60, 90, 40)
}

fn test_vml_model_box_layout_uses_repeater_size_hints() {
	source := 'Flex {
		padding: 10
		gap: 10
		Button { text: "Fixed" width: 80 flex_shrink: 0 }
		Repeater {
			model: app.users
			key: item.id
			Button { text: item.name flex_basis: 0 flex_grow: item.weight }
		}
	}'
	box := element_from_vml_model(source, VmlTestApp{
		users: [
			VmlTestUser{
				id:     1
				name:   'Wide'
				weight: 2
			},
			VmlTestUser{
				id:     2
				name:   'Narrow'
				weight: 1
			},
		]
	}, rect(0, 0, 330, 80)) or { panic(err) }
	assert box.children.len == 3
	assert box.children[0].frame == rect(10, 10, 80, 60)
	assert box.children[1].frame == rect(100, 10, 140, 60)
	assert box.children[2].frame == rect(250, 10, 70, 60)
}

fn test_vml_model_tabbed_panel_switches_content_through_tab_action() {
	source := 'TabbedPanel {
		id: panel
		current: app.page
		tab_width: 100
		Tab { id: first text: "First" Label { text: "First content" } }
		Tab {
			id: second
			text: "Second"
			on_select: app.select_second_tab()
			Label { text: "Second content" }
		}
	}'
	mut app := new_vml_app(source, VmlTestApp{}) or { panic(err) }
	initial := app.build(rect(0, 0, 300, 180)) or { panic(err) }
	assert initial.children[0].children[0].text == 'First content'
	initial.children[2].on_event(ElementEvent{ kind: .tap })
	assert app.state().page == 1
	rebuilt := app.build(rect(0, 0, 300, 180)) or { panic(err) }
	assert rebuilt.children[0].children[0].text == 'Second content'
	assert rebuilt.children[2].accessibility_value == 'selected'
}

fn test_vml_model_accordion_switches_content_through_item_action() {
	source := 'Accordion {
		id: sections
		current: app.page
		orientation: vertical
		min_space: 40
		AccordionItem { id: first title: "First" Label { text: "First content" } }
		AccordionItem {
			id: second
			title: "Second"
			on_select: app.select_second_tab()
			Label { text: "Second content" }
		}
	}'
	mut app := new_vml_app(source, VmlTestApp{}) or { panic(err) }
	initial := app.build(rect(0, 0, 300, 180)) or { panic(err) }
	assert initial.children[0].children[0].text == 'First content'
	initial.children[2].on_event(ElementEvent{ kind: .tap })
	assert app.state().page == 1
	rebuilt := app.build(rect(0, 0, 300, 180)) or { panic(err) }
	assert rebuilt.children[0].children[0].text == 'Second content'
	assert rebuilt.children[2].accessibility_value == 'expanded'
}

fn test_vml_model_tree_view_expands_and_selects_through_actions() {
	source := 'TreeView {
		id: navigation
		TreeNode {
			id: docs
			text: "Documentation"
			expanded: app.tree_open
			on_toggle: app.toggle_tree()
			TreeNode {
				id: guide
				text: "Guide"
				selected: app.selected == "guide"
				on_select: app.select_tree_leaf()
			}
		}
		TreeNode { id: license text: "License" }
	}'
	mut app := new_vml_app(source, VmlTestApp{}) or { panic(err) }
	initial := app.build(rect(0, 0, 300, 200)) or { panic(err) }
	assert initial.children.len == 2
	initial.children[0].children[0].on_event(ElementEvent{ kind: .tap })
	assert app.state().tree_open

	expanded := app.build(rect(0, 0, 300, 200)) or { panic(err) }
	assert expanded.children.len == 3
	expanded.children[1].children[1].on_event(ElementEvent{ kind: .tap })
	assert app.state().selected == 'guide'

	selected := app.build(rect(0, 0, 300, 200)) or { panic(err) }
	assert selected.children[1].children[1].accessibility_value == 'selected'
}

fn test_vml_model_screen_manager_switches_active_screen_through_action() {
	source := 'ScreenManager {
		id: manager
		current: app.screen_name
		Screen {
			id: home
			Button { text: "Details" on_tap: app.show_details_screen() }
		}
		Screen { id: details Label { text: "Details content" } }
	}'
	mut app := new_vml_app(source, VmlTestApp{}) or { panic(err) }
	initial := app.build(rect(0, 0, 320, 200)) or { panic(err) }
	assert initial.children.len == 1
	assert initial.children[0].id == 'home'
	initial.children[0].children[0].on_event(ElementEvent{ kind: .tap })
	assert app.state().screen_name == 'details'

	rebuilt := app.build(rect(0, 0, 320, 200)) or { panic(err) }
	assert rebuilt.children.len == 1
	assert rebuilt.children[0].id == 'details'
	assert rebuilt.children[0].children[0].text == 'Details content'
}

fn test_vml_model_carousel_switches_active_slide_through_action() {
	source := 'Carousel {
		id: gallery
		index: app.page
		loop: true
		CarouselSlide {
			id: first
			Button { text: "Next" on_tap: app.select_second_tab() }
		}
		CarouselSlide { id: second Label { text: "Second slide" } }
	}'
	mut app := new_vml_app(source, VmlTestApp{}) or { panic(err) }
	initial := app.build(rect(0, 0, 320, 200)) or { panic(err) }
	assert !initial.children[0].hidden
	assert initial.children[1].hidden
	initial.children[0].children[0].on_event(ElementEvent{ kind: .tap })
	assert app.state().page == 1

	rebuilt := app.build(rect(0, 0, 320, 200)) or { panic(err) }
	assert rebuilt.children[0].hidden
	assert !rebuilt.children[1].hidden
	assert rebuilt.children[1].children[0].text == 'Second slide'
}

fn test_vml_model_modal_view_opens_and_dismisses_through_actions() {
	source := 'Screen {
		Button { text: "Open" on_tap: app.open_modal() }
		ModalView {
			id: confirm
			width: 400
			height: 300
			open: app.modal_open
			on_dismiss: app.close_modal()
			content_width: 240
			content_height: 140
			Label { text: "Confirmation" }
		}
	}'
	mut app := new_vml_app(source, VmlTestApp{}) or { panic(err) }
	initial := app.build(rect(0, 0, 400, 300)) or { panic(err) }
	assert initial.children[1].hidden
	initial.children[0].on_event(ElementEvent{ kind: .tap })
	assert app.state().modal_open

	opened := app.build(rect(0, 0, 400, 300)) or { panic(err) }
	assert !opened.children[1].hidden
	assert opened.children[1].children[2].children[0].text == 'Confirmation'
	opened.children[1].children[0].on_event(ElementEvent{ kind: .tap })
	assert !app.state().modal_open
}

fn test_vml_model_popup_opens_and_dismisses_through_actions() {
	source := 'Screen {
		Button { text: "Edit" on_tap: app.open_modal() }
		Popup {
			id: editor
			width: 400
			height: 300
			open: app.modal_open
			title: "Edit profile"
			on_dismiss: app.close_modal()
			content_width: 260
			content_height: 180
			Label { text: "Profile fields" }
		}
	}'
	mut app := new_vml_app(source, VmlTestApp{}) or { panic(err) }
	initial := app.build(rect(0, 0, 400, 300)) or { panic(err) }
	assert initial.children[1].hidden
	initial.children[0].on_event(ElementEvent{ kind: .tap })
	opened := app.build(rect(0, 0, 400, 300)) or { panic(err) }
	assert !opened.children[1].hidden
	assert opened.children[1].children[2].children[0].text == 'Edit profile'
	assert opened.children[1].children[2].children[2].children[0].text == 'Profile fields'
	opened.children[1].children[0].on_event(ElementEvent{ kind: .tap })
	assert !app.state().modal_open
}

fn test_vml_model_stack_layout_wraps_repeater_children_by_resolved_size() {
	source := 'Flex { wrap: true align_items: start
		padding: 10
		gap: 6
		line_gap: 4
		Repeater {
			model: app.users
			key: item.id
			Button { text: item.name width: item.weight height: 24 }
		}
	}'
	stack := element_from_vml_model(source, VmlTestApp{
		users: [
			VmlTestUser{
				id:     1
				name:   'One'
				weight: 70
			},
			VmlTestUser{
				id:     2
				name:   'Two'
				weight: 80
			},
			VmlTestUser{
				id:     3
				name:   'Three'
				weight: 90
			},
		]
	}, rect(0, 0, 180, 100)) or { panic(err) }
	assert stack.children.len == 3
	assert stack.children[0].frame == rect(10, 10, 70, 24)
	assert stack.children[1].frame == rect(86, 10, 80, 24)
	assert stack.children[2].frame == rect(10, 38, 90, 24)
}

fn test_vml_model_rejects_non_numeric_slider_bindings() {
	if _ := element_from_vml_model('Slider { bind.value: app.name }', VmlTestApp{}, rect(0, 0, 100,
		30))
	{
		assert false, 'slider values must bind to numeric fields'
	} else {
		assert err.msg().contains('bind.value requires a numeric field')
	}
}

fn test_vml_model_reports_unknown_paths_with_a_source_line() {
	if _ := element_from_vml_model('Label { text: app.frist_name }', VmlTestApp{}, rect(0, 0, 100,
		30))
	{
		assert false, 'unknown fields must not silently become empty strings'
	} else {
		assert err.msg().contains('app.frist_name')
		assert err.msg().contains('line 1')
	}
}

fn test_vml_model_rejects_readonly_bindings_and_unknown_actions() {
	if _ := element_from_vml_model('TextInput { multiline: false  bind.text: app.max_users }', VmlTestApp{}, rect(0,
		0, 100, 30))
	{
		assert false, 'readonly fields must not be binding targets'
	} else {
		assert err.msg().contains('not mutable')
	}
	if _ := element_from_vml_model('Button { on_tap: app.typo() }', VmlTestApp{}, rect(0, 0, 100,
		30))
	{
		assert false, 'unknown actions must fail document loading'
	} else {
		assert err.msg().contains('unknown app action `typo`')
		assert err.msg().contains('line 1')
	}
}

fn test_vml_model_dispatches_a_composite_button_action() {
	source := 'View {
		id: clear_card
		button_behavior: true
		on_tap: app.clear()
		width: 180
		height: 56
    Absolute {
        transparent: true
        Label { text: "Clear name" x: 16 y: 16 width: 148 height: 24 }
    }
	}'
	mut app := new_vml_app(source, VmlTestApp{
		name: 'Ada'
	}) or { panic(err) }
	built := app.build(rect(0, 0, 320, 200)) or { panic(err) }

	assert built.kind == .view
	assert built.button_behavior
	assert !built.clickable
	assert voidptr(built.on_event) != unsafe { nil }
	assert built.children.len == 1
	assert built.children[0].children[0].text == 'Clear name'
	built.on_event(ElementEvent{ kind: .tap })
	assert app.state().name == ''
}

fn test_vml_model_validates_an_initially_empty_repeater() {
	source := 'Screen { Repeater { model: app.users key: item.id Label { text: item.typo } } }'
	if _ := element_from_vml_model(source, VmlTestApp{}, rect(0, 0, 100, 30)) {
		assert false, 'empty repeaters must still validate their item paths'
	} else {
		assert err.msg().contains('item.typo')
	}
}

fn test_vml_model_does_not_evaluate_an_empty_repeater_schema() {
	source := 'Screen { Repeater { model: app.users key: item.id Label { width: 100 / item.weight } } }'
	root := element_from_vml_model(source, VmlTestApp{}, rect(0, 0, 100, 30)) or { panic(err) }
	assert root.children.len == 0
}

fn test_vml_model_validates_inactive_expression_branches() {
	source := 'Label { text: app.enabled ? app.typo : "OK" }'
	if _ := element_from_vml_model(source, VmlTestApp{ enabled: false }, rect(0, 0, 100, 30)) {
		assert false, 'inactive branches must still be validated'
	} else {
		assert err.msg().contains('app.typo')
	}
}

fn test_vml_model_resolves_named_node_geometry_before_children() {
	source := 'Screen { View { id: panel width: 200
    Absolute {
        transparent: true
        Label { text: "Hello" width: panel.width }
    } } }'
	root := element_from_vml_model(source, VmlTestApp{}, rect(0, 0, 780, 300)) or { panic(err) }
	text_label := vml_test_find(root, 'Hello') or { panic('missing label') }
	assert text_label.frame.width == 200
}

fn test_vml_model_evaluates_action_arguments_after_binding_writes() {
	source := 'TextInput { multiline: false  bind.text: app.name on_change: app.save_name(app.name) }'
	template := parse_vml(source) or { panic(err) }
	mut app := VmlTestApp{
		name: 'Ada'
	}
	v_validate_template[VmlTestApp](template, app) or { panic(err) }
	resolved, events := v_evaluate_template(template, app, rect(0, 0, 200, 30)) or { panic(err) }
	field := element_from_vnode(resolved, rect(0, 0, 200, 30)) or { panic(err) }
	event := events[resolved.prop('on_change')] or { panic('missing field event') }
	invocation := event.invocation or { panic('missing field action') }

	// This is the order used by VmlController.handle(): binding first, action second.
	vml_set_field[VmlTestApp](mut app, 'name', v_string('Adam')) or { panic(err) }
	vml_dispatch[VmlTestApp](mut app, invocation) or { panic(err) }
	assert app.name == 'Adam'
	assert app.saved == 'Adam'
}

fn test_vml_model_event_assignment_updates_a_mutable_field() {
	source := 'Button { id: home on_tap: app.screen_name = app.enabled ? "details" : "home" }'
	mut app := new_vml_app(source, VmlTestApp{ enabled: false }) or { panic(err) }
	built := app.build(rect(0, 0, 100, 30)) or { panic(err) }
	built.on_event(ElementEvent{ kind: .tap })
	assert app.state().screen_name == 'home'

	mut details_app := new_vml_app(source, VmlTestApp{ enabled: true }) or { panic(err) }
	details := details_app.build(rect(0, 0, 100, 30)) or { panic(err) }
	details.on_event(ElementEvent{ kind: .tap })
	assert details_app.state().screen_name == 'details'
}

fn test_vml_model_event_assignment_runs_after_a_binding_write() {
	source := 'TextInput { multiline: false  bind.text: app.name on_change: app.saved = app.name }'
	mut app := new_vml_app(source, VmlTestApp{ name: 'Ada' }) or { panic(err) }
	built := app.build(rect(0, 0, 200, 30)) or { panic(err) }
	built.on_event(ElementEvent{ kind: .change, text: 'Adam' })
	assert app.state().name == 'Adam'
	assert app.state().saved == 'Adam'
}

fn test_vml_model_rejects_invalid_event_assignment_targets_and_values() {
	if _ := element_from_vml_model('Button { on_tap: app.max_users = 4 }', VmlTestApp{}, rect(0, 0,
		100, 30))
	{
		assert false, 'event assignments must require a mutable app field'
	} else {
		assert err.msg().contains('not mutable')
	}
	if _ := element_from_vml_model('Button { on_tap: app.screen_name = 4 }', VmlTestApp{}, rect(0,
		0, 100, 30))
	{
		assert false, 'event assignment values must match their target type'
	} else {
		assert err.msg().contains('expects `string`')
	}
	if _ := element_from_vml_model('Button { on_tap: app.screen_name.value = "home" }', VmlTestApp{}, rect(0,
		0, 100, 30))
	{
		assert false, 'event assignments must be limited to top-level app fields'
	} else {
		assert err.msg().contains('top-level app field')
	}
}

fn test_vml_model_nested_repeater_event_identities_do_not_collide() {
	source := 'Screen {
		Repeater {
			model: app.groups
			key: item.id
			View {
				Repeater {
					model: item.items
					key: item.id
					Button { text: item.id on_tap: app.save_name(item.id) }
				}
			}
		}
	}'
	mut app := VmlTestApp{
		groups: [
			VmlTestGroup{
				id:    'a/b'
				items: [VmlTestNestedItem{ id: 'c' }]
			},
			VmlTestGroup{
				id:    'a'
				items: [VmlTestNestedItem{ id: 'b/c' }]
			},
		]
	}
	template := parse_vml(source) or { panic(err) }
	v_validate_template[VmlTestApp](template, app) or { panic(err) }
	resolved, events := v_evaluate_template(template, app, rect(0, 0, 200, 100)) or { panic(err) }
	root := element_from_vnode(resolved, rect(0, 0, 200, 100)) or { panic(err) }
	first := vml_test_find(root, 'c') or { panic('missing first nested item') }
	second := vml_test_find(root, 'b/c') or { panic('missing second nested item') }
	assert resolved.children[0].children[0].prop('on_tap') != resolved.children[1].children[0].prop('on_tap')
	assert events.len == 2

	first_invocation := (events[resolved.children[0].children[0].prop('on_tap')] or { panic('missing first event') }).invocation or {
		panic('missing first invocation')
	}

	second_invocation := (events[resolved.children[1].children[0].prop('on_tap')] or { panic('missing second event') }).invocation or {
		panic('missing second invocation')
	}

	vml_dispatch[VmlTestApp](mut app, first_invocation) or { panic(err) }
	assert app.saved == 'c'
	vml_dispatch[VmlTestApp](mut app, second_invocation) or { panic(err) }
	assert app.saved == 'b/c'
}

fn test_vml_model_adapter_writes_fields_and_dispatches_typed_actions() {
	mut app := VmlTestApp{
		name: 'before'
	}
	vml_set_field[VmlTestApp](mut app, 'name', v_string('after')) or { panic(err) }
	assert app.name == 'after'
	vml_dispatch[VmlTestApp](mut app, VmlInvocation{ name: 'clear' }) or { panic(err) }
	assert app.name == ''
	argument := &VExpression{
		kind:  .literal
		value: '42'
		line:  1
	}
	vml_dispatch[VmlTestApp](mut app, VmlInvocation{
		name: 'remove_user'
		args: [argument]
	}) or { panic(err) }
	assert app.removed == 42
}
