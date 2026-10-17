// vtest vflags: -d vml_props
module ui2

// Golden equivalence of the composite props (Accordion, Collapsible,
// TabbedPanel, Carousel, ScreenManager, TreeView and their child
// declarations).


fn props_composites_compiled(mut app PropsApp, frame Rect) Element {
	return $vml('fixtures/props_composites.vml', frame)
}

fn props_composites_tree(mut app PropsApp) PNode {
	return pn(ScreenProps{}, id: 'root', children: [
		pn(AbsoluteProps{}, id: 'abs', children: [
			pn(AccordionProps{
				x:         0
				y:         0
				width:     300
				height:    200
				value:     app.place
				on_change: props_hit(mut app, 'acc')
				style:     style_list([style_background(0xFFFFFF), style_radius(4)])
			}, id: 'acc', children: [
				pn(AccordionItemProps{ value: 'Work', title: 'One', icon: .info }, id: 'a1', children: [
					pn(LabelProps{ text: 'first', width: 100, height: 20 }),
				]),
				pn(AccordionItemProps{ title: 'Two', enabled: false }, children: [
					pn(ViewProps{}),
				]),
			]),
			pn(AccordionProps{
				x:        0
				y:        210
				width:    300
				height:   200
				multiple: true
				bordered: false
			}, id: 'acc2', children: [
				pn(AccordionItemProps{ title: 'B1', gap: 4 }, id: 'b1', children: [
					pn(AbsoluteProps{}, children: [
						pn(ViewProps{ x: 5, y: 5, width: 20, height: 20 }),
					]),
				]),
				pn(AccordionItemProps{ title: 'B2' }, id: 'b2', children: [
					pn(ViewProps{}),
				]),
			]),
			pn(CollapsibleProps{
				x:      620
				y:      330
				width:  200
				height: 80
				text:   app.name
				icon:   .info
				open:   app.open
			}, id: 'more', children: [
				pn(LabelProps{ text: 'more', width: 80, height: 20 }),
			]),
			pn(TabbedPanelProps{
				x:       310
				y:       0
				width:   300
				height:  200
				current: app.tab
				style:   style_list([style_background(0xFFFFFF)])
			}, id: 'tabs', children: [
				pn(TabProps{ text: 'First', on_select: props_hit(mut app, 't1') }, id: 't1', children: [
					pn(LabelProps{ text: 'tab one', width: 100, height: 20 }),
				]),
				pn(TabProps{ text: 'Second' }, id: 't2', children: [
					pn(ViewProps{}),
				]),
			]),
			pn(TabbedPanelProps{
				x:                     310
				y:                     210
				width:                 300
				height:                200
				current_tab:           app.current
				tab_pos:               .left_top
				tab_height:            30
				tab_width:             80
				tab_background:        0x111111
				active_tab_background: 0x222222
				tab_color:             0x333333
				active_tab_color:      0x444444
				tab_font_size:         12
				tab_corner_radius:     2
			}, id: 'tabs2', children: [
				pn(TabProps{ text: 'A' }, children: [pn(ViewProps{})]),
				pn(TabProps{ text: 'B', enabled: false }, children: [pn(ViewProps{})]),
			]),
			pn(CarouselProps{ x: 620, y: 0, width: 200, height: 100 }, id: 'car', children: [
				pn(CarouselSlideProps{}, id: 's1', children: [
					pn(LabelProps{ text: 'slide 1', width: 80, height: 20 }),
				]),
				pn(CarouselSlideProps{}, children: [pn(ViewProps{})]),
			]),
			pn(CarouselProps{
				x:                           620
				y:                           110
				width:                       200
				height:                      100
				index:                       app.current
				direction:                   .left
				loop:                        true
				min_move:                    0.3
				ignore_perpendicular_swipes: true
			}, id: 'car2', children: [
				pn(CarouselSlideProps{}, children: [pn(ViewProps{})]),
				pn(CarouselSlideProps{}, children: [pn(ViewProps{})]),
			]),
			pn(ScreenManagerProps{
				x:       620
				y:       220
				width:   200
				height:  100
				current: app.screen
				style:   style_list([style_background(0xFFFFFF)])
			}, id: 'screens', children: [
				pn(ScreenProps{}, id: 'home', children: [
					pn(LabelProps{ text: 'home', width: 80, height: 20 }),
				]),
				pn(ScreenProps{ name: 'settings', style: style_list([style_background(0xEFF6FF)]) }, id: 'named', children: [
					pn(ViewProps{}),
				]),
				pn(ManagedScreenProps{ name: 'managed' }, children: [pn(ViewProps{})]),
				pn(ScreenViewProps{}, id: 'sv', children: [pn(ViewProps{})]),
			]),
			pn(TreeViewProps{ x: 0, y: 420, width: 300, height: 200 }, id: 'tree', children: [
				pn(TreeNodeProps{
					text:      DisplayText('Docs')
					expanded:  true
					on_toggle: props_hit(mut app, 'toggle')
				}, id: 'n1', children: [
					pn(TreeNodeProps{
						title:     'Intro'
						selected:  true
						on_select: props_hit(mut app, 'select')
					}, id: 'n11'),
					pn(TreeNodeProps{ text: DisplayText('Other'), enabled: false }),
				]),
				pn(TreeNodeProps{ text: DisplayText(app.count) }, id: 'n2'),
			]),
			pn(TreeViewProps{
				x:                     310
				y:                     420
				width:                 300
				height:                200
				row_height:            30
				spacing:               4
				indent:                20
				disclosure_width:      24
				row_background:        0x111111
				row_corner_radius:     2
				selected_background:   0x222222
				disclosure_background: 0x333333
				selected_color:        0x444444
				disclosure_color:      0x555555
				style:                 style_list([style_foreground(0x666666), style_font_size(13)])
			}, id: 'tree2', children: [
				pn(TreeNodeProps{ text: DisplayText('M1') }, id: 'm1'),
			]),
		]),
	])
}

fn test_props_composites_match_compiled_vml() {
	frame := rect(0, 0, 900, 700)
	mut compiled_app := PropsApp{}
	mut props_app := PropsApp{}
	compiled := props_composites_compiled(mut compiled_app, frame)
	built := props_document(props_composites_tree(mut props_app), frame)!
	assert_props_equal('composites', compiled, built)
}
