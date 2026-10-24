// vtest vflags: -d vml_interpreter
module ui2

import os

// The interpreter registry: one builtin tag per props type, and every
// property of every tag set and read back by name.

fn test_builtin_tags_cover_every_props_type() {
	// Every props type of the module with a `build` or `part` method is a tag:
	// `ui2 gen` writes them to vml_widgets_d_vml_interpreter.v, which must be
	// current.
	mut declared := []string{}
	mut built := map[string]bool{}
	for file in os.ls(@DIR)! {
		if !file.ends_with('.v') || file.ends_with('_test.v') || file.contains('_d_')
			|| file.ends_with('_vml.v') {
			continue
		}
		for line in os.read_lines(os.join_path(@DIR, file))! {
			if line.starts_with('pub struct ') {
				name := line.all_after('pub struct ').all_before('{').trim_space()
				if name.len > 5 && name.ends_with('Props') { declared << name[..name.len - 5] }
			} else if line.starts_with('pub fn (') {
				method := line.all_after(') ').all_before('(')
				if method in ['build', 'part'] {
					receiver := line.all_after('pub fn (').all_before(')').all_after_last(' ')
					built[receiver.trim_left('&').all_before_last('Props')] = true
				}
			}
		}
	}
	mut expected := declared.filter(it in built)
	expected.sort()
	mut builtins := vml_builtin_widgets.keys()
	builtins.sort()
	assert builtins == expected
	mut common := []VmlPropInfo{}
	vml_collect_props(CommonProps{}, [], mut common)
	assert common.len == 57
	mut parts := []string{}
	for tag, t in vml_builtin_widgets {
		assert t.name == tag
		assert t.type_name == 'ui2.${tag}Props'
		assert t.new_node != unsafe { nil }
		mut names := map[string]bool{}
		for info in t.props {
			assert info.name !in names, '${tag}.${info.name} is listed twice'
			names[info.name] = true
			assert info.kind != .other, '${tag}.${info.name} (${info.type_name}) cannot be set'
		}
		// Every element tag takes the common properties, embedded structs included.
		if common.all(it.name in names) {
			assert t.props.len >= common.len
		} else {
			parts << tag
		}
	}
	parts.sort()
	assert parts == ['BreadcrumbItem', 'Keyframe', 'Menu', 'MenuBar', 'MenuItem', 'MenuSeparator',
		'Option', 'Run', 'Timeline']
	assert vml_widget_tags() == builtins
}

fn w_sample(info VmlPropInfo) VmlValue {
	return match info.kind {
		.number {
			VmlValue(f64(0.5))
		}
		.integer {
			VmlValue(i64(2))
		}
		.color {
			VmlValue('#123456')
		}
		.boolean {
			VmlValue(true)
		}
		.string, .display_text {
			VmlValue('sample')
		}
		.enumeration {
			VmlValue(VmlEnum{
				name: info.enum_values.last()
			})
		}
		.style {
			VmlValue(compose_styles([style_radius(3)]))
		}
		.callback {
			VmlValue(VmlCallable{
				name: info.name
				run:  fn (event ElementEvent) ! {}
			})
		}
		.string_list {
			VmlValue([VmlValue('left'), VmlValue('cmd+s')])
		}
		.object {
			match info.type_name.trim_left('?').all_after_last('.') {
				'BoxStyle' { vml_reflect_value(BoxStyle{ bg: 0x123456 }) }
				'MotionConfig' { vml_reflect_value(MotionConfig{ reduced_motion: true }) }
				'OverlayConfig' { vml_reflect_value(OverlayConfig{ anchor: 'sample' }) }
				'OverlayPoint' { vml_reflect_value(OverlayPoint{ x: 1, y: 2 }) }
				else { panic('no sample value for ${info.type_name}') }
			}
		}
		.other {
			VmlValue(false)
		}
	}
}

// w_read_back checks the value a property reads back after w_sample.
fn w_read_back(info VmlPropInfo, value VmlValue) bool {
	return match info.kind {
		.number {
			value is f64 && value == 0.5
		}
		.integer {
			value is i64 && value == 2
		}
		.color {
			value is i64 && value == 0x123456
		}
		.boolean {
			value is bool && value
		}
		.string, .display_text {
			value is string && value == 'sample'
		}
		.enumeration {
			value is VmlEnum && value.name == info.enum_values.last()
		}
		.style {
			value is StylePatch && value == compose_styles([style_radius(3)])
		}
		.callback {
			value is VmlCallable
		}
		.string_list {
			'${value}' == '${VmlValue([VmlValue('left'), VmlValue('cmd+s')])}'
		}
		.object {
			if value is VmlObject {
				field, expected := match info.type_name.trim_left('?').all_after_last('.') {
					'BoxStyle' { 'bg', VmlValue(i64(0x123456)) }
					'MotionConfig' { 'reduced_motion', VmlValue(true) }
					'OverlayConfig' { 'anchor', VmlValue('sample') }
					else { 'y', VmlValue(f64(2)) }
				}
				got := value.get(field) or { return false }
				'${got}' == '${expected}'
			} else {
				false
			}
		}
		.other {
			false
		}
	}
}

fn test_every_property_of_every_tag_is_set_by_name() {
	mut count := 0
	for tag in vml_widget_tags() {
		t := vml_widget_type(tag) or { panic('missing ${tag}') }
		mut d := vml_document(rect(0, 0, 200, 100))!
		mut owner := d.owner
		mut root := vml_root(mut owner, ViewProps{}, path: '0')!
		mut node := t.new_node(mut owner, VmlNodeOptions{ path: '0.0' }, root.vml_parent())!
		for info in t.props {
			node.set_prop(info.name, w_sample(info)) or {
				assert false, '${tag}.${info.name}: ${err}'
				continue
			}
			value := node.get_prop(info.name) or {
				assert false, '${tag}.${info.name}: ${err}'
				continue
			}
			assert w_read_back(info, value), '${tag}.${info.name} read back ${value}'
			count++
		}
	}
	assert count > 1500
}

fn test_bindable_properties_come_from_apply_event() {
	mut bindable := []string{}
	for tag in vml_widget_tags() {
		t := vml_widget_type(tag) or { panic('missing ${tag}') }
		for info in t.props {
			if info.bindable { bindable << '${tag}.${info.name}' }
		}
	}
	bindable.sort()
	assert bindable == ['Accordion.value', 'Accordion.values', 'Carousel.index', 'Checkbox.checked',
		'Clipboard.copied', 'Collapsible.open', 'Dropdown.text', 'Pagination.page', 'Slider.value',
		'Switch.active', 'Tabs.value', 'TextArea.text', 'TextInput.text', 'ToggleButton.pressed',
		'Tree.value', 'TreeItem.expanded']
	slider := vml_widget_type('Slider') or { panic('missing Slider') }
	orientation := slider.prop('orientation') or { panic('missing orientation') }
	assert orientation.kind == .enumeration
	assert orientation.enum_values == ['horizontal', 'vertical']
	assert orientation.type_name == 'Orientation'
	click := slider.prop('on_click') or { panic('missing on_click') }
	assert click.is_event && click.kind == .callback
	opacity := slider.prop('opacity') or { panic('missing opacity') }
	assert opacity.optional && opacity.kind == .number
	grow := slider.prop('flex_grow') or { panic('missing flex_grow') }
	assert !grow.optional && grow.kind == .number
}
