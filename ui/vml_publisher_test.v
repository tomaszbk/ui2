module ui2

@[heap]
struct VmlPublisherFixture {
mut:
	ids   []string
	texts []string
}

fn test_host_publisher_reaches_existing_and_future_descendants() ! {
	mut owner := new_vml_document('embedded')!
	mut previous := &VmlPublisherFixture{}
	owner.set_publisher(fn [mut previous] (id string, element Element) {
		previous.ids << id
		previous.texts << element.text
	})!
	mut existing := owner.child('existing')!
	mut nested := existing.child('nested')!
	mut node := nested.element(Element{ kind: .label, id: 'caption' })!
	mut root := owner.element(Element{ kind: .view, id: 'root' })!
	root.set_children([node])!
	root.mount()!
	mut relay := &VmlPublisherFixture{}
	owner.set_publisher(fn [mut relay] (id string, element Element) {
		relay.ids << id
		relay.texts << element.text
	})!
	mut future := existing.child('future')!
	mut future_node := future.element(Element{ kind: .label, id: 'caption' })!
	root.set_children([node, future_node])!
	relay.ids.clear()
	relay.texts.clear()
	mut value := nested.state('caption', 'first relay')!
	node.effect('text', fn [mut value] (element Element) !Element {
		return Element{ ...element, text: value.get()! }
	})!
	value.set('second relay')!
	future_node.patch(fn (element Element) Element {
		return Element{ ...element, text: 'future relay' }
	})!
	assert previous.ids.len == 0
	assert relay.ids == [node.element().id, node.element().id, future_node.element().id]
	assert relay.texts == ['first relay', 'second relay', 'future relay']
	owner.set_publisher(unsafe { nil }) or { assert err.msg().contains('nil') }
	value.set('still relayed')!
	assert relay.texts.last() == 'still relayed'
	owner.dispose()!
	owner.set_publisher(fn (_ string, _ Element) {}) or { assert err.msg().contains('disposed') }
	assert owner.runtime.stats() == SignalStats{}
}
