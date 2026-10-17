// vtest vflags: -d ui2_custom_rendering
@[has_globals]
module ui2

import math

@[heap]
struct VmlPresenceClock {
mut:
	now f64
}

@[heap]
struct VmlPresenceFixture {
mut:
	builds   int
	mounts   []string
	unmounts []string
	cleanups []string
}

struct VmlPresenceItem {
	id string
}

@[heap]
struct NestedPresenceFixture {
mut:
	inner    &VmlKeyedList[string] = unsafe { nil }
	builds   int
	cleanups []string
}

fn presence_config(clock &VmlPresenceClock, duration f64, reduced bool) MotionConfig {
	return MotionConfig{
		clock:            fn [clock] () f64 { return clock.now }
		enter_transition: MotionTransition{ duration: 0.2 }
		exit_transition:  MotionTransition{ duration: duration }
		reduced_motion:   reduced
	}
}

fn presence_list(mut parent CompiledVmlNode, mut fixture VmlPresenceFixture,
	clock &VmlPresenceClock, fragment bool, reduced bool) !&VmlKeyedList[VmlPresenceItem] {
	return new_vml_keyed_list(mut parent, 'rows', fn (item VmlPresenceItem) string {
		return item.id
	},
		fn [mut fixture, clock, fragment, reduced] (mut row CompiledVmlComponent,
			source &Signal[VmlPresenceItem]) ![]&CompiledVmlNode {
			fixture.builds++
			id := source.peek()!.id
			row.on_mount('mounted', fn [mut fixture, id] () ! { fixture.mounts << id })!
			row.on_unmount('unmounted', fn [mut fixture, id] () { fixture.unmounts << id })!
			row.on_cleanup('resource', fn [mut fixture, id] () { fixture.cleanups << id })!
			mut count := row.state('count', 0)!
			mut lead := row.element(Element{
				kind:     .button
				id:       'lead'
				frame:    rect(0, 0, 40, 20)
				motion:   presence_config(clock, if fragment { 0.1 } else { 0.4 }, reduced)
				on_event: row.callback(fn [mut count] (_ ElementEvent) ! {
					count.set(count.get()! + 1)!
				})
			})!
			lead.effect('text', fn [mut count] (element Element) !Element {
				return Element{ ...element, text: count.get()!.str() }
			})!
			if !fragment { return [lead] }
			mut group := row.fragment('body')!
			mut tail := row.element(Element{
				kind:   .text_field
				id:     'tail'
				key:    'tail'
				text:   'ñ edit'
				frame:  rect(0, 0, 40, 20)
				motion: presence_config(clock, 0.3, reduced)
			})!
			group.set_children([lead, tail])!
			return [group]
		})!
}

// A completion may mutate the parent's children; the host likewise takes its
// states before invoking completion, rather than iterating a mutable tree.
fn sample_presence_nodes(mut node CompiledVmlNode) ! {
	if node.motion_state != unsafe { nil } {
		node.motion_state.sample()!
	}
	for mut child in node.children.clone() { sample_presence_nodes(mut child)! }
}

fn test_presence_list_retains_exit_and_reentry_preserves_state_and_callbacks() ! {
	mut owner := new_vml_document('presence keys')!
	owner.set_publisher(fn (_ string, _ Element) {})!
	mut fixture := &VmlPresenceFixture{}
	mut clock := &VmlPresenceClock{}
	mut parent := owner.element(flex(FlexConfig{ id: 'root', frame: rect(0, 0, 200, 40) })!)!
	mut list := presence_list(mut parent, mut fixture, clock, false, false)!
	list.update([VmlPresenceItem{ id: 'a' }, VmlPresenceItem{ id: 'b' }])!
	parent.mount()!
	mut original := list.nodes()[0]
	callback := original.element().on_event
	callback(ElementEvent{})
	assert original.element().text == '1'
	assert fixture.mounts == ['a', 'b']
	clock.now = 0.2
	sample_presence_nodes(mut parent)!
	list.update([VmlPresenceItem{ id: 'b' }])!
	assert list.order == ['b']
	assert list.leaving == ['a']
	assert list.nodes().len == 1
	assert parent.element().children.len == 2
	assert parent.element().children[1].presence_exiting()
	assert !parent.element().children[1].enabled
	assert !original.component.is_disposed()
	assert fixture.cleanups.len == 0
	callback(ElementEvent{})
	assert original.element().text == '1'
	clock.now = 0.3
	sample_presence_nodes(mut parent)!
	before := original.motion_state.current.style.opacity
	assert math.abs(before - 0.75) < 0.00001
	list.update([VmlPresenceItem{ id: 'b' }, VmlPresenceItem{ id: 'a' }])!
	assert list.nodes()[1] == original
	assert list.leaving.len == 0
	assert fixture.builds == 2 && fixture.mounts == ['a', 'b']
	assert original.motion_state.current.style.opacity == before
	assert !parent.element().children[1].presence_exiting()
	callback(ElementEvent{})
	assert original.element().text == '2'
	clock.now = 0.5
	sample_presence_nodes(mut parent)!
	list.update([VmlPresenceItem{ id: 'b' }])!
	clock.now = 0.9
	sample_presence_nodes(mut parent)!
	assert original.component.is_disposed()
	assert list.leaving.len == 0 && parent.children.len == 1
	assert fixture.unmounts == ['a'] && fixture.cleanups == ['a']
	callback(ElementEvent{})
	owner.dispose()!
	assert fixture.unmounts == ['a', 'b'] && fixture.cleanups == ['a', 'b']
	assert owner.runtime.stats() == SignalStats{}
}

fn test_fragment_presence_waits_for_every_visible_root_and_cancels_on_reentry() ! {
	mut owner := new_vml_document('presence fragments')!
	owner.set_publisher(fn (_ string, _ Element) {})!
	mut fixture := &VmlPresenceFixture{}
	mut clock := &VmlPresenceClock{}
	mut parent := owner.element(Element{ kind: .view, id: 'root' })!
	mut list := presence_list(mut parent, mut fixture, clock, true, false)!
	list.update([VmlPresenceItem{ id: 'a' }])!
	parent.mount()!
	mut group := list.nodes()[0]
	lead := group.children[0]
	tail := group.children[1]
	clock.now = 0.2
	sample_presence_nodes(mut parent)!
	list.update([])!
	assert list.nodes().len == 0 && parent.children == [group]
	assert parent.element().children.len == 2
	assert parent.element().children.all(it.presence_exiting() && !it.enabled)
	clock.now = 0.31
	sample_presence_nodes(mut parent)!
	assert lead.motion_state.current.phase == .absent
	assert !group.component.is_disposed() && fixture.cleanups.len == 0
	list.update([VmlPresenceItem{ id: 'a' }])!
	assert list.nodes()[0] == group && group.children[1] == tail
	assert lead.motion_state.current.phase == .entering
	clock.now = 0.6
	sample_presence_nodes(mut parent)!
	list.update([])!
	clock.now = 0.91
	sample_presence_nodes(mut parent)!
	assert group.component.is_disposed() && parent.element().children.len == 0
	assert fixture.cleanups == ['a'] && fixture.unmounts == ['a']
	owner.dispose()!
	assert fixture.cleanups == ['a']
}

fn test_reduced_motion_removal_is_immediate_and_owner_disposal_cancels_exits_once() ! {
	for reduced in [false, true] {
		mut owner := new_vml_document('presence dispose')!
		owner.set_publisher(fn (_ string, _ Element) {})!
		mut fixture := &VmlPresenceFixture{}
		mut clock := &VmlPresenceClock{}
		mut parent := owner.element(Element{ kind: .view, id: 'root' })!
		mut list := presence_list(mut parent, mut fixture, clock, false, reduced)!
		list.update([VmlPresenceItem{ id: 'a' }])!
		parent.mount()!
		mut original := list.nodes()[0]
		clock.now = 0.2
		sample_presence_nodes(mut parent)!
		list.update([])!
		assert original.component.is_disposed() == reduced
		assert parent.children.len == if reduced { 0 } else { 1 }
		owner.dispose()!
		owner.dispose()!
		assert fixture.cleanups == ['a'] && fixture.unmounts == ['a']
		clock.now = 1
		sample_presence_nodes(mut original)!
		assert fixture.cleanups == ['a']
		assert list.entries.len == 0 && list.leaving.len == 0
		assert owner.runtime.stats() == SignalStats{}
	}
}

fn test_hidden_motion_retains_owner_until_visible_again_without_unmounting() ! {
	mut owner := new_vml_document('presence hidden')!
	owner.set_publisher(fn (_ string, _ Element) {})!
	mut fixture := &VmlPresenceFixture{}
	mut clock := &VmlPresenceClock{}
	owner.on_unmount('unmount', fn [mut fixture] () { fixture.unmounts << 'root' })!
	mut node := owner.element(Element{ kind: .button, id: 'root', motion: presence_config(clock, 0.4, false) })!
	node.mount()!
	clock.now = 0.2
	sample_presence_nodes(mut node)!
	node.patch(fn (element Element) Element { return Element{ ...element, hidden: true } })!
	assert node.declaration.hidden
	assert !node.motion_state.presented_hidden(true)
	assert !node.motion_state.input_enabled()
	clock.now = 0.61
	sample_presence_nodes(mut node)!
	assert node.motion_state.presented_hidden(true)
	assert fixture.unmounts.len == 0 && !owner.is_disposed()
	node.patch(fn (element Element) Element { return Element{ ...element, hidden: false } })!
	assert node.motion_state.current.phase == .entering
	assert !node.motion_state.presented_hidden(false)
	owner.dispose()!
	assert fixture.unmounts == ['root']
}

fn test_removing_motion_configuration_detaches_timeline_and_finishes_pending_exit() ! {
	mut owner := new_vml_document('presence config removal')!
	owner.set_publisher(fn (_ string, _ Element) {})!
	mut fixture := &VmlPresenceFixture{}
	mut clock := &VmlPresenceClock{}
	mut parent := owner.element(Element{ kind: .view, id: 'root' })!
	mut list := presence_list(mut parent, mut fixture, clock, false, false)!
	list.update([VmlPresenceItem{ id: 'a' }])!
	parent.mount()!
	mut node := list.nodes()[0]
	old := node.motion_state
	node.patch(fn (element Element) Element { return Element{ ...element, motion: none } })!
	assert node.motion_state == unsafe { nil } && old.disposed
	node.patch(fn [clock] (element Element) Element {
		return Element{ ...element, motion: presence_config(clock, 0.4, false) }
	})!
	assert node.motion_state != unsafe { nil } && node.motion_state != old
	clock.now = 0.2
	sample_presence_nodes(mut parent)!
	list.update([])!
	assert list.leaving == ['a'] && !node.component.is_disposed()
	node.patch(fn (element Element) Element { return Element{ ...element, motion: none } })!
	assert node.component.is_disposed() && list.leaving.len == 0 && parent.children.len == 0
	assert fixture.cleanups == ['a'] && fixture.unmounts == ['a']
	owner.dispose()!
	assert fixture.cleanups == ['a']
}

fn test_outer_reentry_preserves_an_independent_inner_exit_and_its_cleanup() ! {
	mut owner := new_vml_document('nested presence owners')!
	owner.set_publisher(fn (_ string, _ Element) {})!
	mut clock := &VmlPresenceClock{}
	mut fixture := &NestedPresenceFixture{}
	mut parent := owner.element(Element{ kind: .view, id: 'root' })!
	mut outer := new_vml_keyed_list(mut parent, 'outer', fn (key string) string { return key },
		fn [mut fixture, clock] (mut row CompiledVmlComponent, _ &Signal[string]) ![]&CompiledVmlNode {
			fixture.builds++
			row.on_cleanup('released', fn [mut fixture] () { fixture.cleanups << 'outer' })!
			mut group := row.element(Element{
				kind:   .view
				id:     'group'
				frame:  rect(0, 0, 100, 100)
				motion: presence_config(clock, 0.1, false)
			})!
			mut inner := new_vml_keyed_list(mut group, 'inner', fn (key string) string {
				return key
			},
				fn [mut fixture, clock] (mut item CompiledVmlComponent, _ &Signal[string]) ![]&CompiledVmlNode {
					item.on_cleanup('released', fn [mut fixture] () { fixture.cleanups << 'inner' })!
					return [item.element(Element{
						kind:   .button
						id:     'item'
						frame:  rect(0, 0, 40, 20)
						motion: presence_config(clock, 0.4, false)
					})!]
				})!
			fixture.inner = inner
			inner.update(['x'])!
			return [group]
		})!
	outer.update(['a'])!
	parent.mount()!
	mut inner := fixture.inner
	mut group := outer.nodes()[0]
	child := inner.nodes()[0]
	clock.now = 0.2
	sample_presence_nodes(mut parent)!
	inner.update([])!
	outer.update([])!
	clock.now = 0.31
	sample_presence_nodes(mut parent)!
	assert group.motion_state.current.phase == .absent
	assert !child.component.is_disposed() && fixture.cleanups.len == 0
	outer.update(['a'])!
	assert outer.nodes()[0] == group && fixture.builds == 1
	assert child.motion_state.current.phase == .exiting
	assert inner.leaving == ['x']
	clock.now = 0.61
	sample_presence_nodes(mut parent)!
	assert child.component.is_disposed() && group.children.len == 0
	assert !group.component.is_disposed() && fixture.cleanups == ['inner']
	outer.update([])!
	clock.now = 0.72
	sample_presence_nodes(mut parent)!
	assert group.component.is_disposed() && parent.children.len == 0
	assert fixture.cleanups == ['inner', 'outer']
	owner.dispose()!
	assert fixture.cleanups == ['inner', 'outer']
}

fn test_public_mount_reports_invalid_clock_without_mounting_component() ! {
	mut owner := new_vml_document('presence mount clock')!
	owner.set_publisher(fn (_ string, _ Element) {})!
	mut clock := &VmlPresenceClock{ now: 1 }
	mut fixture := &VmlPresenceFixture{}
	owner.on_mount('mounted', fn [mut fixture] () ! { fixture.mounts << 'root' })!
	mut node := owner.element(Element{ kind: .view, id: 'root', motion: presence_config(clock, 0.4, false) })!
	clock.now = 0
	mut rejected := false
	node.mount() or {
		rejected = true
		assert err.msg().contains('monotonic')
	}
	assert rejected && !node.mounted && !node.motion_state.mounted
	assert fixture.mounts.len == 0
	clock.now = 1
	node.mount()!
	assert node.mounted && fixture.mounts == ['root']
	owner.dispose()!
}
