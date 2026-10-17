// vtest vflags: -d vml_interpreter -d vml_props
module ui2

// Interpreted nodes are the typed nodes: a document declared by tag and
// property names builds, updates and writes back like the same document
// declared with props types. Conversion errors name the element, the
// property and the valid values.

struct WDynModel {
	name  string = 'Ada'
	level f64    = 2
}

struct WDynApp {
mut:
	level  f64
	clicks int
}

fn w_dyn_typed(mut app WDynApp) !(&Signal[WDynModel], Element) {
	mut d := vml_document(rect(0, 0, 300, 200))!
	mut owner := d.owner
	mut model := owner.state('model', WDynModel{})!
	mut column := vml_root(mut owner, ColumnProps{ width: 300, height: 200, spacing: 4 }, path: '0')!
	mut label := vml_child(mut column, mut owner, LabelProps{
		height: 20
		style:  compose_styles([style_weight(700)])
	}, path: '0.0')!
	label.prop('text', fn [mut model] (mut p LabelProps) ! {
		p.text = model.get()!.name
	})!
	mut slider := vml_child(mut column, mut owner, SliderProps{
		height:      24
		max:         10
		orientation: .horizontal
	}, id: 'level', path: '0.1')!
	slider.prop('value', fn [mut model] (mut p SliderProps) ! {
		p.value = model.get()!.level
	})!
	slider.bind('value', fn [mut app] (p SliderProps) ! {
		app.level = vml_assign(app.level, p.value)
	})!
	vml_child(mut column, mut owner, ButtonProps{
		text:     'Go'
		height:   30
		on_click: owner.callback(fn [mut app] (event ElementEvent) ! {
			app.clicks++
		})
	}, path: '0.2')!
	element := d.finish()!
	return model, element
}

fn w_dyn_interpreted(mut app WDynApp) !(&Signal[WDynModel], Element) {
	mut d := vml_document(rect(0, 0, 300, 200))!
	mut owner := d.owner
	mut model := owner.state('model', WDynModel{})!
	mut column := vml_dyn_node('Column', mut owner, VmlNodeOptions{ path: '0' }, none)!
	column.set_prop('width', i64(300))!
	column.set_prop('height', f64(200))!
	column.set_prop('spacing', i64(4))!
	mut label := vml_dyn_node('Label', mut owner, VmlNodeOptions{ path: '0.0' }, column.vml_parent())!
	label.set_prop('height', i64(20))!
	label.set_prop('style', [VmlValue(compose_styles([style_weight(700)]))])!
	label.prop_value('text', fn [mut model] () !VmlValue {
		return model.get()!.name
	})!
	mut slider := vml_dyn_node('Slider', mut owner, VmlNodeOptions{ id: 'level', path: '0.1' },
		column.vml_parent())!
	slider.set_prop('height', i64(24))!
	slider.set_prop('max', i64(10))!
	slider.set_prop('orientation', VmlEnum{ name: 'horizontal' })!
	slider.prop_value('value', fn [mut model] () !VmlValue {
		return model.get()!.level
	})!
	slider.bind_value('value', fn [mut app] (value VmlValue) ! {
		if value is f64 { app.level = value }
	})!
	mut button := vml_dyn_node('Button', mut owner, VmlNodeOptions{ path: '0.2' }, column.vml_parent())!
	button.set_prop('text', 'Go')!
	button.set_prop('height', i64(30))!
	button.set_prop('on_click', VmlCallable{
		name: 'go'
		run:  fn [mut app] (event ElementEvent) ! {
			app.clicks++
		}
	})!
	element := d.finish()!
	return model, element
}

fn test_interpreted_nodes_build_and_update_like_typed_nodes() {
	mut typed_app := WDynApp{}
	mut dyn_app := WDynApp{}
	mut typed_model, typed := w_dyn_typed(mut typed_app)!
	mut dyn_model, interpreted := w_dyn_interpreted(mut dyn_app)!
	assert_props_equal('interpreted', typed, interpreted)
	mut typed_root := typed.compiled_node
	mut dyn_root := interpreted.compiled_node
	typed_root.mount()!
	dyn_root.mount()!
	// Events: the props update, the write-back runs, then the handlers.
	for root in [typed_root, dyn_root] {
		root.element().children[1].on_event(ElementEvent{ kind: .change, value: 7 })
		root.element().children[2].on_event(ElementEvent{ kind: .click })
	}
	assert typed_app.level == 7 && dyn_app.level == 7
	assert typed_app.clicks == 1 && dyn_app.clicks == 1
	assert dyn_root.element().children[1].value == 7
	assert_props_equal('interpreted events', typed_root.element(), dyn_root.element())
	// Reactive properties commit like prop effects.
	typed_model.set(WDynModel{ name: 'Grace', level: 3 })!
	dyn_model.set(WDynModel{ name: 'Grace', level: 3 })!
	assert dyn_root.element().children[0].text == 'Grace'
	assert_props_equal('interpreted model', typed_root.element(), dyn_root.element())
	typed_root.dispose_document()!
	dyn_root.dispose_document()!
	assert dyn_root.component.runtime.stats() == SignalStats{}
}

fn test_set_prop_on_a_built_node_commits_it() {
	mut d := vml_document(rect(0, 0, 200, 100))!
	mut owner := d.owner
	mut row := vml_dyn_node('Row', mut owner, VmlNodeOptions{ path: '0' }, none)!
	mut label := vml_dyn_node('Label', mut owner, VmlNodeOptions{ path: '0.0' }, row.vml_parent())!
	label.set_prop('text', 'before')!
	element := d.finish()!
	mut root := element.compiled_node
	label.set_prop('text', 'after')!
	label.set_prop('flex_grow', i64(2))!
	label.set_prop('opacity', f64(0.5))!
	assert root.element().children[0].text == 'after'
	assert root.element().children[0].opacity == 0.5
	assert root.element().layout.flex.children[0].grow == 2
	assert label.get_prop('flex_grow')! is f64
	root.dispose_document()!
}

fn w_error(node VmlDynNode, name string, value VmlValue) string {
	mut target := node
	target.set_prop(name, value) or { return err.msg() }
	return ''
}

fn test_conversion_errors_name_the_property_and_valid_values() {
	mut d := vml_document(rect(0, 0, 200, 100))!
	mut owner := d.owner
	mut root := vml_root(mut owner, ViewProps{}, path: '0')!
	mut slider := vml_dyn_node('Slider', mut owner, VmlNodeOptions{
		path: '0.0'
		src:  VmlSourceLocation{
			source: 'doc.vml'
			line:   3
			column: 5
		}
	}, root.vml_parent())!
	assert w_error(slider, 'maxx', i64(1)) == 'doc.vml:3:5: `Slider` has no property `maxx`'
	assert w_error(slider, 'max', 'ten') == 'doc.vml:3:5: property `max` of `Slider` expects a number, not the string "ten"'
	assert w_error(slider, 'orientation', VmlEnum{ name: 'diagonal' }) == 'doc.vml:3:5: property `orientation` of `Slider` has no value `diagonal`; valid values: horizontal, vertical'
	assert w_error(slider, 'orientation', true) == 'doc.vml:3:5: property `orientation` of `Slider` expects one of horizontal, vertical, not the bool true'
	assert w_error(slider, 'column_span', f64(1.5)) == 'doc.vml:3:5: property `column_span` of `Slider` expects an integral number, not 1.5'
	assert w_error(slider, 'column_span', i64(1) << 40) == 'doc.vml:3:5: property `column_span` of `Slider` expects an integer that fits in int, not 1099511627776'
	assert w_error(slider, 'thumb_color', '#12345') == 'doc.vml:3:5: property `thumb_color` of `Slider` expects a color (#RRGGBB or an integer from 0 to 0xFFFFFFFF), not the string "#12345"'
	assert w_error(slider, 'thumb_color', i64(-1)).contains('expects a color')
	assert w_error(slider, 'on_change', 'go') == 'doc.vml:3:5: property `on_change` of `Slider` expects a callable, not the string "go"'
	assert w_error(slider, 'style', [VmlValue(i64(1))]) == 'doc.vml:3:5: property `style` of `Slider` expects a style or an array of styles, not the integer 1'
	assert w_error(slider, 'motion', vml_reflect_value(OverlayPoint{})) == 'doc.vml:3:5: property `motion` of `Slider` expects a MotionConfig value, not an object'
	// Accepted conversions: integral numbers, colors, bare and quoted names.
	assert w_error(slider, 'column_span', f64(3)) == ''
	assert w_error(slider, 'thumb_color', '#0A0b0C') == ''
	assert w_error(slider, 'orientation', 'vertical') == ''
	span := slider.get_prop('column_span')!
	color := slider.get_prop('thumb_color')!
	orientation := slider.get_prop('orientation')!
	assert span is i64 && span == 3
	assert color is i64 && color == 0x0a0b0c
	assert orientation is VmlEnum && orientation.name == 'vertical'
	// Reads, events and bindings.
	slider.get_prop('opacity') or {
		assert err.msg() == 'property `opacity` of `Slider` is not set'
	}
	slider.on('hover', fn (event ElementEvent) {}) or {
		assert err.msg() == 'doc.vml:3:5: `Slider` has no event `hover`'
	}
	slider.bind_value('min', fn (value VmlValue) ! {}) or {
		assert err.msg() == 'doc.vml:3:5: property `min` of `Slider` is not bindable'
	}
	slider.prop_value('maxx', fn () !VmlValue {
		return i64(1)
	}) or { assert err.msg() == 'doc.vml:3:5: `Slider` has no property `maxx`' }
	vml_dyn_node('Gauge', mut owner, VmlNodeOptions{ path: '0.1' }, root.vml_parent()) or {
		assert err.msg() == 'unknown VML element `Gauge`'
	}
	slider.on('click', fn (event ElementEvent) {})!
	click := slider.get_prop('on_click')!
	assert click is VmlCallable
}

// WGaugeProps is a third-party widget.
pub struct WGaugeProps {
	CommonProps
pub mut:
	level f64
	tint  u32 = 0x00ff00
}

pub fn (p WGaugeProps) build(ctx VmlBuildContext) !Element {
	return vml_handled(label(ctx.id, '${p.level}', ctx.frame, TextStyle{ color: p.tint }),
		ctx, p.element_callback())
}

fn test_third_party_widgets_register_by_tag() {
	gauge := vml_widget[WGaugeProps]()
	assert gauge.name == 'WGauge'
	vml_register('', gauge) or { assert err.msg() == 'VML widget tag is empty' }
	vml_register('Label', gauge) or { assert err.msg() == '`Label` is a builtin VML element' }
	vml_register('test.Gauge', gauge)!
	assert 'test.Gauge' in vml_widget_tags()
	t := vml_widget_type('test.Gauge') or { panic('missing test.Gauge') }
	level := t.prop('level') or { panic('missing level') }
	assert level.kind == .number
	mut d := vml_document(rect(0, 0, 200, 100))!
	mut owner := d.owner
	mut node := vml_dyn_node('test.Gauge', mut owner, VmlNodeOptions{ path: '0' }, none)!
	node.set_prop('level', f64(0.75))!
	node.set_prop('tint', '#FF0000')!
	node.set_prop('width', i64(80))!
	element := d.finish()!
	assert element.text == '0.75'
	assert element.text_style.color == 0xff0000
	assert element.frame.width == 80
	element.compiled_node.dispose_document()!
}
