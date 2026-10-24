// vtest vflags: -d vml_props -d vml_fixtures
module ui2

// vml: fixtures/props_common.vml

// Golden equivalence of the common props on every kind of tag: direct
// elements, self-styled widgets, composites, layout containers and editors.

fn props_common_compiled(mut app PropsApp, frame Rect) Element {
	return props_common_vml_framed(mut app, frame)
}

fn props_common_tree(mut app PropsApp) PNode {
	return pn(ScreenProps{},
		id:       'root'
		children: [
			pn(AbsoluteProps{},
				id:       'abs'
				children: [
					pn(ViewProps{
						x:                   4
						y:                   6
						width:               100
						height:              50
						button_behavior:     true
						secure:              true
						clickable:           true
						draggable:           true
						long_press:          true
						swipe_left:          true
						rotation:            15
						opacity:             0.5
						motion:              app.motion
						translate_x:         2
						translate_y:         3
						scale_x:             1.5
						scale_y:             0.5
						origin_x:            10
						origin_y:            20
						cursor:              'pointer'
						tooltip:             'tip'
						hidden:              false
						enabled:             false
						accessibility_role:  'button'
						accessibility_label: 'All'
						accessibility_value: 'v'
						native:              true
						autocorrect:         false
						on_click:            props_hit(mut app, 'click')
						on_change:           props_hit(mut app, 'change')
						on_scroll:           props_hit(mut app, 'scroll')
						on_pointer_down:     props_hit(mut app, 'down')
						on_pointer_drag:     props_hit(mut app, 'drag')
						on_pointer_up:       props_hit(mut app, 'up')
						on_long_press:       props_hit(mut app, 'long')
						on_swipe_left:       props_hit(mut app, 'swipe')
						on_link:             props_hit(mut app, 'link')
						on_open:             props_hit(mut app, 'open')
						on_dismiss:          props_hit(mut app, 'dismiss')
						style:               style_list([style_background(0xFF0000), style_radius(4)])
					}, id: 'all', key: 'all-key'),
					pn(LabelProps{
						x:                   0
						y:                   60
						width:               80
						height:              20
						text:                'L'
						opacity:             0.8
						tooltip:             'label tip'
						hidden:              true
						accessibility_label: 'Lbl'
					}, id: 'common_label', key: app.name),
					pn(SliderProps{
						x:                   0
						y:                   90
						width:               120
						height:              30
						value:               3
						enabled:             false
						clickable:           true
						accessibility_value: '3'
						cursor:              'grab'
						rotation:            5
					}, id: 'common_slider'),
					pn(SwitchProps{
						x:                  130
						y:                  90
						width:              60
						height:             30
						button_behavior:    true
						secure:             true
						accessibility_role: 'toggle'
					}, id: 'common_switch'),
					pn(ToggleButtonProps{
						x:                  0
						y:                  130
						width:              80
						height:             30
						text:               'T'
						button_behavior:    false
						native:             true
						enabled:            false
						accessibility_role: 'switch'
						opacity:            0.9
						on_click:           props_hit(mut app, 'toggle click')
					}, id: 'common_toggle', key: 'toggle-key'),
					pn(TextInputProps{ x: 0, y: 170, width: 120, height: 30, password: true },
						id: 'pw'
					),
					pn(TextInputProps{
						x:                   130
						y:                   170
						width:               120
						height:              30
						secure:              true
						autocorrect:         false
						accessibility_label: 'Secret'
					}, id: 'sec'),
					pn(AccordionProps{
						x:                   0
						y:                   210
						width:               200
						height:              100
						hidden:              false
						opacity:             0.7
						tooltip:             'acc'
						accessibility_label: 'Acc'
						clickable:           true
						on_click:            props_hit(mut app, 'acc click')
					},
						id:       'common_acc'
						children: [
							pn(AccordionItemProps{ title: 'x' }, children: [pn(ViewProps{})]),
						]
					),
					pn(ProgressProps{
						x:                   210
						y:                   210
						width:               100
						height:              10
						value:               10
						tooltip:             'p'
						enabled:             false
						accessibility_label: 'Progress'
					}, id: 'common_progress'),
					pn(SpinnerProps{
						x:        210
						y:        230
						width:    100
						height:   30
						opacity:  0.6
						on_click: props_hit(mut app, 'spin click')
					}, id: 'common_spinner'),
					pn(MessageBoxProps{
						x:                  210
						y:                  270
						width:              200
						height:             100
						accessibility_role: 'alertdialog'
						tooltip:            'm'
					},
						id:       'common_msg'
						children: [
							pn(ButtonProps{ text: 'OK', on_click: props_hit(mut app, 'common ok') }),
						]
					),
					pn(ImageProps{
						x:                   320
						y:                   0
						width:               20
						height:              20
						source:              'a.png'
						accessibility_label: 'Img'
						draggable:           true
					}, id: 'common_image'),
					pn(CheckboxProps{
						x:                   320
						y:                   30
						width:               80
						height:              20
						text:                'C'
						accessibility_role:  'switch'
						accessibility_value: 'on'
						checked:             app.agree
						on_change:           fn [mut app] (e ElementEvent) {
							app.agree = e.checked
						}
					}, id: 'common_check', bind: true),
					pn(ButtonProps{
						x:      320
						y:      60
						width:  80
						height: 20
						text:   app.name
					}),
					pn(ScrollProps{
						x:         320
						y:         90
						width:     80
						height:    40
						on_scroll: props_hit(mut app, 'scrolled')
						opacity:   0.5
					},
						id:       'common_scroll'
						children: [
							pn(ViewProps{ width: 10, height: 100 }),
						]
					),
					pn(TreeProps{ x: 320, y: 140, width: 100, height: 60, enabled: false, tooltip: 'tree' },
						id:       'common_tree'
						children: [
							pn(TreeItemProps{ text: 'n' }),
						]
					),
					pn(TabsProps{
						x:                  0
						y:                  320
						width:              200
						height:             100
						accessibility_role: 'tablist'
						rotation:           1
					},
						id:       'common_tabs'
						children: [
							pn(TabProps{ text: 'a', tooltip: 'tab tip', opacity: 0.5 },
								children: [
									pn(ViewProps{}),
								]
							),
						]
					),
					pn(CarouselProps{
						x:          210
						y:          380
						width:      100
						height:     40
						cursor:     'move'
						swipe_left: false
					},
						id:       'common_carousel'
						children: [
							pn(CarouselSlideProps{ opacity: 0.4 }, children: [pn(ViewProps{})]),
						]
					),
					pn(StackProps{
						x:        320
						y:        210
						width:    80
						height:   40
						opacity:  0.3
						on_click: props_hit(mut app, 'stack')
					},
						id:       'common_stack'
						children: [
							pn(ViewProps{ width: 10, height: 10 }),
						]
					),
					pn(GridProps{
						x:        320
						y:        260
						width:    80
						height:   40
						columns:  2
						tooltip:  'grid'
						on_click: props_hit(mut app, 'grid')
					},
						id:       'common_grid'
						children: [
							pn(ViewProps{}),
						]
					),
					pn(RowProps{
						x:        320
						y:        310
						width:    80
						height:   30
						hidden:   true
						on_click: props_hit(mut app, 'row')
					},
						id:       'common_row'
						children: [
							pn(ViewProps{}),
						]
					),
				]
			),
		]
	)
}

fn test_props_common_match_compiled_vml() {
	frame := rect(0, 0, 500, 500)
	mut compiled_app := PropsApp{}
	mut props_app := PropsApp{}
	compiled := props_common_compiled(mut compiled_app, frame)
	built := props_document(props_common_tree(mut props_app), frame)!
	assert_props_equal('common', compiled, built)
	assert_props_events(compiled, built, mut compiled_app, mut props_app)
}
