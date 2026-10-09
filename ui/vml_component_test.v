module ui2

@[heap]
struct VmlComponentFixture {
mut:
	builds    int
	patches   []string
	values    []string
	lifecycle []string
}

fn component_counter(mut component CompiledVmlComponent, mut fixture VmlComponentFixture) !&CompiledVmlNode {
	fixture.builds++
	mut count := component.state('count', 0)!
	mut doubled := component.computed('doubled', fn [mut count] () !int { return count.get()! * 2 })!
	mut node := component.element(Element{ kind: .button, id: 'counter', text: '0' })!
	node.effect('text', fn [mut doubled, mut fixture] (element Element) !Element {
		value := doubled.get()!.str()
		fixture.values << value
		return Element{ ...element, text: value }
	})!
	node.patch(fn [component, mut count] (element Element) Element {
		return Element{
			...element
			on_event: component.callback(fn [mut count] (_ ElementEvent) ! {
				count.set(count.get()! + 1)!
				count.set(count.get()! + 1)!
			})
		}
	})!
	return node
}

fn test_component_instances_lazy_computed_batch_and_property_patches() ! {
	mut root := new_vml_component('test')!
	mut fixture := &VmlComponentFixture{}
	root.publish = fn [mut fixture] (id string, _ Element) { fixture.patches << id }
	mut left := root.child('left')!
	mut right := root.child('right')!
	mut a := component_counter(mut left, mut fixture)!
	mut b := component_counter(mut right, mut fixture)!
	mut parent := root.element(Element{ kind: .view, id: 'root' })!
	parent.set_children([a, b])!
	parent.mount()!
	a.element().on_event(ElementEvent{})
	assert a.element().text == '4'
	assert b.element().text == '0'
	assert fixture.values == ['0', '0', '4']
	assert fixture.patches == [a.element().id]
	assert parent.element().children[0].text == '4'
	assert fixture.builds == 2
	assert a.element().id != b.element().id
	assert root.child('left')! == left
	assert left.state('count', 999)! == left.state('count', 0)!
	mut initializations := &VmlComponentFixture{}
	left.state_factory('once', fn [mut initializations] () !int {
		initializations.builds++
		return 42
	})!
	left.state_factory('once', fn [mut initializations] () !int {
		initializations.builds++
		return 0
	})!
	assert initializations.builds == 1
	assert left.element(Element{ kind: .button, id: 'counter', text: 'reset' })! == a
	callback := a.element().on_event
	root.dispose()!
	callback(ElementEvent{})
	assert root.runtime.stats() == SignalStats{}
	assert fixture.values.len == 3
}

fn test_component_lifecycle_cleanup_and_late_callback_are_owned_once() ! {
	mut root := new_vml_component('lifecycle')!
	mut fixture := &VmlComponentFixture{}
	mut child := root.child('child')!
	child.on_mount('mount', fn [mut fixture] () ! { fixture.lifecycle << 'mount' })!
	child.on_mount('mount', fn [mut fixture] () ! { fixture.lifecycle << 'duplicate' })!
	child.on_unmount('unmount', fn [mut fixture] () { fixture.lifecycle << 'unmount' })!
	child.on_cleanup('resource', fn [mut fixture] () { fixture.lifecycle << 'cleanup' })!
	callback := child.callback(fn [mut fixture] (_ ElementEvent) ! { fixture.lifecycle << 'event' })
	mut child_node := child.element(Element{ kind: .label, id: 'child' })!
	mut root_node := root.element(Element{ kind: .view, id: 'root' })!
	root_node.set_children([child_node])!
	root_node.mount()!
	root_node.mount()!
	callback(ElementEvent{})
	child.dispose()!
	child.dispose()!
	callback(ElementEvent{})
	assert fixture.lifecycle == ['mount', 'event', 'cleanup', 'unmount']
	mut replacement := root.child('child')!
	assert replacement != child
	root.dispose()!
	assert root.runtime.stats() == SignalStats{}
}

struct VmlListItem {
	id   string
	text string
}

fn test_keyed_list_reorders_instances_updates_items_and_disposes_removed_keys() ! {
	mut component := new_vml_component('list')!
	mut fixture := &VmlComponentFixture{}
	component.publish = fn [mut fixture] (id string, _ Element) { fixture.patches << id }
	mut parent := component.element(Element{ kind: .view, id: 'items' })!
	mut list := new_vml_keyed_list(mut parent, 'items', fn (item VmlListItem) string {
		return item.id
	},
		fn [mut fixture] (mut instance CompiledVmlComponent, source &Signal[VmlListItem]) !&CompiledVmlNode {
			fixture.builds++
			mut item := source
			mut node := instance.element(Element{ kind: .text_field, id: 'edit' })!
			node.effect('text', fn [mut item] (element Element) !Element {
				return Element{ ...element, text: item.get()!.text }
			})!
			instance.on_cleanup('release', fn [mut fixture] () { fixture.lifecycle << 'release' })!
			return node
		})!
	list.update([VmlListItem{'a', 'A'}, VmlListItem{'b', 'B'}])!
	first := list.nodes()[0]
	second := list.nodes()[1]
	mut layout := &LayoutTree{}
	layout.replace(parent.element())!
	identity := layout.identity(first.element().id) or { panic('missing first item') }
	parent.mount()!
	list.update([VmlListItem{'b', 'B!'}, VmlListItem{'a', 'A'}])!
	assert list.nodes()[0] == second && list.nodes()[1] == first
	assert second.element().text == 'B!'
	assert fixture.builds == 2
	assert fixture.lifecycle.len == 0
	layout.patch(parent.element().id, parent.element())!
	assert layout.identity(first.element().id) or { panic('missing retained item') } == identity
	before := parent.element()
	list.update([VmlListItem{'a', 'A'}, VmlListItem{'a', 'duplicate'}]) or {
		assert err.msg().contains('duplicate')
		assert parent.element() == before
	}
	list.update([VmlListItem{'a', 'A'}])!
	assert second.component.is_disposed()
	assert fixture.lifecycle == ['release']
	list.update([VmlListItem{'a', 'A'}, VmlListItem{'b', 'new'}])!
	assert list.nodes()[1] != second
	assert fixture.builds == 3
	list.dispose()!
	component.dispose()!
	assert component.runtime.stats() == SignalStats{}
}

fn test_ref_type_mount_availability_and_slot_author_scope() ! {
	mut author := new_vml_component('author')!
	author.publish = fn (_ string, _ Element) {}
	mut button_ref := author.ref[VmlButton]('submit')!
	mut text_ref := author.ref[VmlTextInput]('edit')!
	assert !button_ref.is_available()
	mut host := author.child('host')!
	mut slot := author.slot_child(mut host, 'content')!
	mut root := host.element(Element{ kind: .view, id: 'host' })!
	mut button := slot.element(Element{ kind: .button, id: 'submit', text: 'slot content' })!
	mut edit := slot.element(Element{ kind: .text_area, id: 'edit' })!
	button_ref.bind(button)!
	text_ref.bind(edit)!
	button_ref.bind(edit) or { assert err.msg().contains('expects') }
	root.set_children([button, edit])!
	root.mount()!
	assert button_ref.is_available()
	assert text_ref.is_available()
	assert button_ref.element()!.text == 'slot content'
	assert button.component == slot
	assert button_ref.id()! == root.element().children[0].id
	root.set_children([edit])!
	assert !button_ref.is_available()
	button_ref.id() or { assert err.msg().contains('unavailable') }
	root.set_children([button, edit])!
	assert button_ref.is_available()
	host.dispose()!
	assert slot.is_disposed()
	assert !author.is_disposed()
	assert !button_ref.is_available() && !text_ref.is_available()
	author.dispose()!
	assert !button_ref.is_available() && !text_ref.is_available()
}

fn test_slot_lexical_author_values_and_receiving_component_cleanup() ! {
	mut author := new_vml_component('slot lifecycle')!
	author.publish = fn (_ string, _ Element) {}
	mut value := author.state('value', 'author')!
	mut host := author.child('receiver')!
	mut slot := author.slot_child(mut host, 'content')!
	mut fixture := &VmlComponentFixture{}
	mut content := slot.element(Element{ kind: .label, id: 'content' })!
	content.effect('text', fn [mut value, mut fixture] (element Element) !Element {
		text := value.get()!
		fixture.values << text
		return Element{ ...element, text: text }
	})!
	slot.on_mount('mount', fn [mut fixture] () ! { fixture.lifecycle << 'mount' })!
	slot.on_unmount('unmount', fn [mut fixture] () { fixture.lifecycle << 'unmount' })!
	slot.on_cleanup('resource', fn [mut fixture] () { fixture.lifecycle << 'cleanup' })!
	mut receiver := host.element(Element{ kind: .view, id: 'receiver' })!
	receiver.set_children([content])!
	receiver.mount()!
	value.set('updated by author')!
	assert content.element().text == 'updated by author'
	host.dispose()!
	assert fixture.lifecycle == ['mount', 'cleanup', 'unmount']
	value.set('author remains alive')!
	assert fixture.values == ['author', 'updated by author']
	assert value.get()! == 'author remains alive'
	author.dispose()!
	assert author.runtime.stats() == SignalStats{}
}

fn test_task_cancellation_discards_queued_worker_delivery_on_unmount() ! {
	mut component := new_vml_component('task')!
	mut fixture := &VmlComponentFixture{}
	mut coordinator := new_frame_coordinator()
	dispatcher := UiDispatcher{ coordinator: coordinator }
	mut task := component.task('load')!
	assert task == component.task('load')!
	assert task.post(dispatcher, fn [mut fixture] () ! { fixture.lifecycle << 'first' })
	for callback in coordinator.take_tasks() { callback() }
	assert fixture.lifecycle == ['first']
	assert task.post(dispatcher, fn [mut fixture] () ! { fixture.lifecycle << 'stale' })
	component.dispose()!
	for callback in coordinator.take_tasks() { callback() }
	assert task.is_cancelled()
	assert !task.post(dispatcher, fn () ! {})
	assert fixture.lifecycle == ['first']
	assert component.runtime.stats() == SignalStats{}
}

struct VmlRunnerFixture {
mut:
	builds  int
	updates int
	text    string
	owner   &CompiledVmlComponent = unsafe { nil }
}

fn component_runner_build(mut model VmlRunnerFixture) Element {
	model.builds++
	mut owner := new_vml_component('runner') or { panic(err) }
	owner.publish = fn (_ string, _ Element) {}
	model.owner = owner
	mut node := owner.element(Element{ kind: .label, id: 'caption' }) or { panic(err) }
	node.effect('text', fn [owner, mut model] (element Element) !Element {
		owner.watch_app()!
		return Element{ ...element, text: model.text }
	}) or { panic(err) }
	return node.element()
}

fn ordinary_runner_build(mut model VmlRunnerFixture) Element {
	model.builds++
	return Element{ kind: .label, id: 'ordinary', text: model.text }
}

fn test_runner_retains_component_builder_and_invalidates_external_app_reads() ! {
	mut runtime := compiled_vml_runtime()
	previous := runtime.controller
	previous_root := runtime.root
	defer {
		runtime.controller = previous
		runtime.root = previous_root
	}
	mut model := &VmlRunnerFixture{ text: 'before' }
	mut controller := &CompiledVmlController[VmlRunnerFixture]{
		build: component_runner_build
		model: model
	}
	runtime.controller = voidptr(controller)
	assert compiled_vml_controller_build[VmlRunnerFixture]().text == 'before'
	model.text = 'after'
	assert compiled_vml_controller_build[VmlRunnerFixture]().text == 'after'
	assert controller.model.builds == 1
	dispose_compiled_vml()
	assert controller.model.owner.runtime.stats() == SignalStats{}
	mut ordinary := &CompiledVmlController[VmlRunnerFixture]{
		build: ordinary_runner_build
		model: &VmlRunnerFixture{ text: 'old' }
	}
	runtime.controller = voidptr(ordinary)
	assert compiled_vml_controller_build[VmlRunnerFixture]().text == 'old'
	ordinary.model.text = 'new'
	assert compiled_vml_controller_build[VmlRunnerFixture]().text == 'new'
	assert ordinary.model.builds == 2
}

fn test_compiled_callbacks_accept_void_signatures_and_absent_listener() {
	mut fixture := &VmlComponentFixture{}
	zero := vml_callback(fn [mut fixture] () { fixture.lifecycle << 'zero' }, refresh: false)
	zero(ElementEvent{})
	value := vml_callback(fn [mut fixture] (event ElementEvent) { fixture.lifecycle << event.text },
		refresh: false
	)
	value(ElementEvent{ text: 'payload' })
	absent := vml_callback(ElementCallback(unsafe { nil }), refresh: false)
	absent(ElementEvent{})
	assert fixture.lifecycle == ['zero', 'payload']
}

fn test_document_ids_hydrate_control_children_and_defer_inactive_mount() ! {
	mut owner := new_vml_document('document')!
	owner.publish = fn (_ string, _ Element) {}
	mut fixture := &VmlComponentFixture{}
	mut dormant := owner.child('inactive')!
	dormant.on_mount('mount', fn [mut fixture] () ! { fixture.lifecycle << 'mount' })!
	mut content := dormant.element(Element{ kind: .label, id: 'content' })!
	mut node := owner.element(view('public', rect(0, 0, 200, 100), BoxStyle{}, [button('helper', 'Header', Rect{}, BoxStyle{}, TextStyle{})]))!
	node.mount()!
	assert node.element().id == 'public'
	assert node.element().children[0].id == 'helper'
	assert node.element().children[0].compiled_node != unsafe { nil }
	assert content.element().id != 'content'
	assert fixture.lifecycle.len == 0
	node.set_children([content])!
	assert fixture.lifecycle == ['mount']
	owner.dispose()!
}

fn test_numeric_control_binding_preserves_destination_type() {
	assert vml_binding_number(0, 3.8) == 3
	assert vml_binding_number(f64(0), 3.8) == f64(3.8)
	assert vml_binding_number(f32(0), 3.8) == f32(3.8)
}

fn test_runner_rejects_missing_model_before_building() {
	run_compiled_vml(CompiledVmlRunConfig[VmlRunnerFixture]{ build: ordinary_runner_build }) or {
		assert err.msg() == 'compiled VML requires a live model'
		return
	}
	assert false
}

fn test_runner_service_update_borrows_live_model_without_rebuilding() ! {
	mut runtime := compiled_vml_runtime()
	previous := runtime.controller
	previous_root := runtime.root
	defer {
		runtime.controller = previous
		runtime.root = previous_root
	}
	mut model := &VmlRunnerFixture{}
	mut controller := &CompiledVmlController[VmlRunnerFixture]{
		model:  model
		build:  component_runner_build
		update: fn (mut state VmlRunnerFixture) {
			state.updates++
			state.text = state.updates.str()
		}
	}
	runtime.controller = voidptr(controller)
	assert compiled_vml_controller_build[VmlRunnerFixture]().text == '1'
	assert compiled_vml_controller_build[VmlRunnerFixture]().text == '2'
	assert model.updates == 2 && model.builds == 1
	dispose_compiled_vml()
}
