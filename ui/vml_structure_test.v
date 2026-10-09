module ui2

@[heap]
struct VmlStructureFixture {
mut:
	patches []string
	mounts  []string
	reads   int
}

fn vml_accordion_source(mut component CompiledVmlComponent, title string) !&CompiledVmlNode {
	return component.element(Element{ kind: .view, id: 'content', compiled_metadata: &CompiledVmlMetadata{ accordion: AccordionItem{ id: title, title: title } } })
}

fn test_composite_structure_updates_helpers_and_preserves_authored_instances() ! {
	mut owner := new_vml_document('composites')!
	mut fixture := &VmlStructureFixture{}
	owner.publish = fn [mut fixture] (id string, _ Element) { fixture.patches << id }
	mut first_scope := owner.child('first')!
	mut second_scope := owner.child('second')!
	first_scope.on_mount('mount', fn [mut fixture] () ! { fixture.mounts << 'first' })!
	second_scope.on_mount('mount', fn [mut fixture] () ! { fixture.mounts << 'second' })!
	mut first := vml_accordion_source(mut first_scope, 'first')!
	mut second := vml_accordion_source(mut second_scope, 'second')!
	mut node := owner.element(Element{ kind: .view, id: 'accordion', frame: rect(0, 0, 400, 200) })!
	node.set_sources([first.element(), second.element()])!
	mut current := owner.state('current', 0)!
	mut revision := owner.state('revision', 0)!
	node.structure('config', fn [mut node, mut current, mut revision, mut fixture] () !Element {
		revision.get()!
		fixture.reads++
		items := node.child_elements()!.map(AccordionItem{ ...(it.compiled_metadata.accordion or { panic('metadata') }), content: it })
		return accordion(AccordionConfig{ id: 'accordion', frame: rect(0, 0, 400, 200), current: current.get()!, items: items })!
	})!
	node.mount()!
	assert fixture.mounts == ['first']
	assert node.element().children[0].compiled_node == first
	first_header := node.element().children[1].compiled_node
	second_header := node.element().children[2].compiled_node
	current.set(1)!
	assert fixture.mounts == ['first', 'second']
	assert node.element().children[0].compiled_node == second
	assert node.element().children[1].compiled_node == first_header
	assert node.element().children[2].compiled_node == second_header
	assert node.element().children[1].accessibility_value == 'collapsed'
	assert node.element().children[2].accessibility_value == 'expanded'
	assert fixture.patches == ['accordion']
	revision.set(1)!
	assert fixture.patches == ['accordion']
	first.effect('title', fn (element Element) !Element {
		return Element{ ...element, compiled_metadata: &CompiledVmlMetadata{ accordion: AccordionItem{ id: 'first', title: 'Renamed' } } }
	})!
	assert node.element().children[1].text == 'Renamed'
	assert fixture.patches == ['accordion', 'accordion']
	reads := fixture.reads
	first.patch(fn (element Element) Element {
		return Element{ ...element, compiled_metadata: &CompiledVmlMetadata{ accordion: AccordionItem{ id: 'first', title: 'Renamed' } } }
	})!
	assert fixture.reads == reads
	assert fixture.reads < 8
	owner.dispose()!
}

fn test_nested_composite_sources_keep_actual_parent_and_refresh_snapshots() ! {
	mut owner := new_vml_document('popup')!
	mut fixture := &VmlStructureFixture{}
	owner.publish = fn [mut fixture] (id string, _ Element) { fixture.patches << id }
	mut label := owner.element(Element{ kind: .label, id: 'caption', text: 'before' })!
	mut node := owner.element(Element{ kind: .view, id: 'popup' })!
	node.set_sources([label.element()])!
	mut open := owner.state('open', true)!
	node.structure('config', fn [mut node, mut open] () !Element {
		content := view('popup__body', Rect{}, BoxStyle{}, node.child_elements()!)
		return popup(PopupConfig{ id: 'popup', frame: rect(0, 0, 500, 500), open: open.get()!, content: content })!
	})!
	node.mount()!
	actual_parent := label.parent
	assert actual_parent != node
	label.patch(fn (element Element) Element { return Element{ ...element, text: 'after' } })!
	assert label.parent == actual_parent
	assert node.child_elements()![0].text == 'after'
	assert vml_find_caption(node.element()) == 'after'
	open.set(false)!
	assert node.element().hidden
	open.set(true)!
	assert !node.element().hidden && label.mounted
	assert label.parent == actual_parent
	owner.dispose()!
}

fn vml_find_caption(element Element) string {
	if element.id == 'caption' { return element.text }
	for child in element.children {
		found := vml_find_caption(child)
		if found.len > 0 { return found }
	}
	return ''
}
