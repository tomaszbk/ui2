// vtest vflags: -d vml_props -d vml_fixtures
module ui2

// vml: fixtures/props_composites.vml

// Golden equivalence of the composite props (Accordion, Collapsible, Tabs,
// Carousel, ScreenManager, Tree and their child declarations).


fn props_composites_compiled(mut app PropsApp, frame Rect) Element {
	return props_composites_vml_framed(mut app, frame)
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
			pn(TabsProps{
				x:         310
				y:         0
				width:     300
				height:    200
				value:     app.place
				on_change: props_hit(mut app, 'tabs')
				style:     style_list([style_background(0xFFFFFF)])
			}, id: 'tabs', children: [
				pn(TabProps{ value: 'Work', text: 'First', icon: .info }, id: 't1', children: [
					pn(LabelProps{ text: 'tab one', width: 100, height: 20 }),
				]),
				pn(TabProps{ value: 'Home', text: 'Second' }, id: 't2', children: [
					pn(ViewProps{}),
				]),
			]),
			pn(TabsProps{
				x:       310
				y:       210
				width:   300
				height:  200
				variant: .segmented
				size:    .small
			}, id: 'tabs2', children: [
				pn(TabProps{ text: 'A', gap: 4 }, children: [pn(ViewProps{})]),
				pn(TabProps{ text: 'B', enabled: false }, children: [pn(ViewProps{})]),
			]),
			pn(CarouselProps{ x: 620, y: 0, width: 200, height: 100 }, id: 'car', children: [
				pn(CarouselSlideProps{}, id: 's1', children: [
					pn(LabelProps{ text: 'slide 1', width: 80, height: 20 }),
				]),
				pn(CarouselSlideProps{}, children: [pn(ViewProps{})]),
			]),
			pn(CarouselProps{
				x:         620
				y:         110
				width:     200
				height:    100
				index:     app.current
				loop:      true
				on_change: props_hit(mut app, 'carousel')
			}, id: 'car2', children: [
				pn(CarouselSlideProps{ accessibility_label: 'First', gap: 4 }, children: [
					pn(ViewProps{}),
				]),
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
			pn(TreeProps{
				x:         0
				y:         420
				width:     300
				height:    200
				value:     app.name
				on_change: props_hit(mut app, 'tree')
			}, id: 'tree', children: [
				pn(TreeItemProps{
					text:      'Docs'
					icon:      .folder
					expanded:  true
					on_change: props_hit(mut app, 'toggle')
				}, id: 'n1', children: [
					pn(TreeItemProps{ value: 'Ada', text: 'Intro' }, id: 'n11'),
					pn(TreeItemProps{ text: 'Other', enabled: false }),
				]),
				pn(TreeItemProps{ text: DisplayText(app.count) }, id: 'n2'),
			]),
			pn(TreeProps{
				x:      310
				y:      420
				width:  300
				height: 200
				style:  style_list([style_background(0xFFFFFF)])
			}, id: 'tree2', children: [
				pn(TreeItemProps{ text: 'M1' }, id: 'm1'),
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
