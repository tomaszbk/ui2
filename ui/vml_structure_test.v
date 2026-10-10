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

fn test_disposed_composite_owner_releases_surviving_author_source_edges() ! {
	mut author := new_vml_document('author')!
	author.publish = fn (_ string, _ Element) {}
	mut source := author.element(Element{ kind: .label, id: 'author' })!
	mut receiver := author.child('receiver')!
	mut composite := receiver.element(Element{ kind: .view, id: 'composite' })!
	composite.set_sources([source.element()])!
	composite.set_sources([source.element()])!
	assert source.source_owners == [composite]
	receiver.dispose()!
	assert source.source_owners.len == 0
	source.patch(fn (element Element) Element { return Element{ ...element, text: 'still alive' } })!
	author.dispose()!
}

fn test_widget_structural_geometry_preserves_authored_flex_basis_across_resizes() ! {
	mut owner := new_vml_document('widget shrink')!
	owner.publish = fn (_ string, _ Element) {}
	mut progress := owner.element(progress_bar(id: 'progress', frame: rect(0, 0, 0, 14), value: 50))!
	progress.structure('fill', fn [mut progress] () !Element {
		return progress_bar(id: 'progress', frame: progress.frame()!, value: 50)
	})!
	fill := progress.element().children[0].compiled_node
	mut root := owner.element(flex(FlexConfig{
		id: 'root'
		frame: rect(0, 0, 100, 40)
		orientation: .vertical
		children: [
			FlexChild{element: view('fixed', rect(0, 0, 100, 40), BoxStyle{}, [])},
			FlexChild{element: progress.element()},
		]
	})!)!
	root.mount()!
	mut tree := &LayoutTree{}
	tree.replace(root.element())!
	initial := tree.resolve(LayoutConstraints{}, measure_layout_text, LayoutEnvironment{})!
	assert initial.children[1].frame.height < 14 && initial.children[1].frame.height > 0
	assert (progress.element().layout_input or { panic('missing authored geometry') }) == rect(0, 0, 0, 14)
	assert initial.children[1].children[0].frame.width == 50
	assert initial.children[1].children[0].compiled_node == fill
	mut cold := &LayoutTree{}
	cold.replace(root.element())!
	assert cold.resolve(LayoutConstraints{}, measure_layout_text, LayoutEnvironment{})!.children[1].frame == initial.children[1].frame
	root.set_frame(rect(0, 0, 100, 80))!
	tree.patch('root', root.element())!
	grown := tree.resolve(LayoutConstraints{}, measure_layout_text, LayoutEnvironment{})!
	assert grown.children[1].frame.height == 14
	root.set_frame(rect(0, 0, 100, 40))!
	tree.patch('root', root.element())!
	assert tree.resolve(LayoutConstraints{}, measure_layout_text, LayoutEnvironment{})!.children[1].frame == initial.children[1].frame
	progress.set_frame(rect(0, 0, 0, 20))!
	assert (progress.element().layout_input or { panic('missing explicit geometry') }) == rect(0, 0, 0, 20)
	root.set_frame(rect(0, 0, 100, 80))!
	tree.patch('root', root.element())!
	changed := tree.resolve(LayoutConstraints{}, measure_layout_text, LayoutEnvironment{})!
	assert changed.children[1].frame.height == 20
	assert changed.children[1].compiled_node == progress
	assert changed.children[1].children[0].compiled_node == fill
	assert changed.children[1].children[0].frame.width == 50
	assert tree.stats().builds == 1
	root.dispose_document()!
	assert owner.runtime.stats() == SignalStats{}
}
