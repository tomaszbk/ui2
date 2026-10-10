module ui2

@[heap]
struct VmlPresentationFixture {
mut:
	patches int
}

fn test_retained_carousel_projection_preserves_authored_visibility_and_live_fields() ! {
	mut owner := new_vml_document('projected carousel')!
	mut fixture := &VmlPresentationFixture{}
	owner.set_publisher(fn [mut fixture] (_ string, _ Element) { fixture.patches++ })!
	mut first := owner.element(Element{ kind: .label, id: 'first', text: 'first', frame: rect(0, 0, 11, 12) })!
	mut second := owner.element(Element{ kind: .label, id: 'second', text: 'second', frame: rect(0, 0, 13, 14) })!
	initial := carousel(CarouselConfig{
		id:     'gallery'
		frame:  rect(0, 0, 300, 100)
		slides: [
			first.element(),
			second.element(),
		]
	})!
	mut node := owner.element(initial)!
	assert node.element().children.map(it.hidden) == [false, true]
	assert second.element().hidden && !second.source_element().hidden
	assert second.element().frame == rect(300, 0, 300, 100)
	assert second.source_element().frame == rect(0, 0, 13, 14)
	node.set_sources([first.source_element(), second.source_element()])!
	mut index := owner.state('index', 0)!
	mut hidden := owner.state('source hidden', false)!
	second.effect('hidden', fn [mut hidden] (element Element) !Element {
		return Element{ ...element, hidden: hidden.get()! }
	})!
	node.structure('config', fn [mut node, mut index] () !Element {
		return carousel(CarouselConfig{ id: 'gallery', frame: rect(0, 0, 300, 100), index: index.get()!, slides: node.child_elements()! })!
	})!
	node.mount()!
	first_handle := node.element().children[0].compiled_node
	second_handle := node.element().children[1].compiled_node
	index.set(1)!
	assert node.element().children.map(it.hidden) == [true, false]
	assert second.element().frame == rect(0, 0, 300, 100)
	index.set(0)!
	assert node.element().children.map(it.hidden) == [false, true]
	assert !first.source_element().hidden && !second.source_element().hidden
	assert node.element().children[0].compiled_node == first_handle
	assert node.element().children[1].compiled_node == second_handle
	second.patch(fn (element Element) Element {
		return Element{ ...element, text: 'ñ live', box: BoxStyle{ bg: 0x112233 } }
	})!
	assert node.element().children[1].hidden
	assert node.element().children[1].text == 'ñ live'
	assert node.element().children[1].box.bg == 0x112233
	assert !second.source_element().hidden
	hidden.set(true)!
	index.set(1)!
	assert node.element().children.map(it.hidden) == [true, true]
	assert second.source_element().hidden
	index.set(0)!
	index.set(1)!
	assert node.element().children[1].hidden
	hidden.set(false)!
	assert node.element().children.map(it.hidden) == [true, false]
	patches := fixture.patches
	index.set(1)!
	assert fixture.patches == patches
	node.set_children([])!
	assert !first.element().hidden && !second.element().hidden
	assert second.element().frame == rect(0, 0, 13, 14)
	owner.dispose()!
	assert owner.runtime.stats() == SignalStats{}
}

fn test_constructor_projection_merges_all_presentation_fields_without_writing_the_source() ! {
	mut owner := new_vml_document('projection fields')!
	owner.set_publisher(fn (_ string, _ Element) {})!
	mut source := owner.element(Element{ kind: .button, id: 'source', text: 'authored', frame: rect(0, 0, 20, 30), box: BoxStyle{ bg: 0x010203 } })!
	decorated := Element{ ...source.element(), hidden: true, accessibility_value: 'decorated', box: BoxStyle{ bg: 0xaabbcc }, text_style: TextStyle{ size: 22 }, enabled: false }
	mut parent := owner.element(Element{ kind: .view, id: 'parent', children: [decorated] })!
	assert source.element().hidden && !source.element().enabled
	assert source.element().box.bg == 0xaabbcc
	assert source.element().text_style.size == 22
	assert source.element().accessibility_value == 'decorated'
	source.patch(fn (element Element) Element {
		return Element{ ...element, text: 'new authored text', box: BoxStyle{ bg: 0x040506 } }
	})!
	assert parent.element().children[0].text == 'new authored text'
	assert parent.element().children[0].box.bg == 0xaabbcc
	assert source.source_element().box.bg == 0x040506
	assert !source.source_element().hidden && source.source_element().enabled
	parent.set_children([])!
	assert !source.element().hidden && source.element().enabled
	assert source.element().box.bg == 0x040506
	owner.dispose()!
}

fn test_presentation_accepts_updated_child_snapshots_and_preserves_owned_structure() ! {
	mut owner := new_vml_document('projection children')!
	owner.set_publisher(fn (_ string, _ Element) {})!
	mut first := owner.element(Element{ kind: .label, id: 'first', text: 'initial' })!
	mut second := owner.element(Element{ kind: .label, id: 'second' })!
	mut child := owner.element(Element{
		kind:     .view
		id:       'child'
		text:     'container initial'
		children: [
			first.element(),
			second.element(),
		]
	})!
	stale := child.element()
	assert stale.compiled_source == child.element().compiled_source
	assert child.source_element().compiled_source == unsafe { nil }
	first.patch(fn (element Element) Element {
		return Element{ ...element, text: 'live', frame: rect(1, 2, 3, 4) }
	})!
	child.patch(fn (element Element) Element {
		return Element{ ...element, text: 'container live' }
	})!
	mut parent := owner.element(Element{ kind: .view, id: 'parent', children: [Element{ ...stale, hidden: true }] })!
	assert child.element().hidden
	assert child.element().text == 'container live'
	assert stale.compiled_source.value.text == 'container initial'
	assert !child.source_element().hidden
	assert child.element().children[0].text == 'live'
	assert child.element().children[0].frame == rect(1, 2, 3, 4)
	assert child.element().children[0].compiled_node == first
	mut rejected := false
	child.set_presentation(Element{ ...stale, children: [second.element(), first.element()] }, parent) or {
		rejected = true
		assert err.msg().contains('owned children')
	}
	assert rejected
	rejected = false
	child.set_presentation(Element{ ...stale, children: [first.element()] }, parent) or {
		rejected = true
		assert err.msg().contains('owned children')
	}
	assert rejected
	rejected = false
	child.set_presentation(Element{
		...stale
		children: [
			Element{ ...first.element(), compiled_node: unsafe { nil } },
			second.element(),
		]
	}, parent) or {
		rejected = true
		assert err.msg().contains('owned children')
	}
	assert rejected
	assert child.children == [first, second]
	assert child.element().children[0].text == 'live'
	owner.dispose()!
	assert child.source_snapshot == unsafe { nil }
	assert child.declaration.compiled_source == unsafe { nil }
	assert child.presentation == unsafe { nil } || !child.presentation.active
	assert owner.runtime.stats() == SignalStats{}
}
