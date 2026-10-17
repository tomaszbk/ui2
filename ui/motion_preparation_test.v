// vtest vflags: -gc boehm -d no_gc_thread_local_alloc -d ui2_custom_rendering
module ui2

@[heap]
struct PreparationClock {
mut:
	now f64
}

$if (android || linux || ((macos || windows) && ui2_custom_rendering ?)) && !ui2_headless ?&& !ui2_document_library ? {
	fn preparation_static_group() Element {
		mut children := []Element{cap: 300}
		for i in 0 .. 300 {
			children << label('static-${i}', 'España ñ', rect(0, f64(i * 20), 100, 20), TextStyle{})
		}
		return view('static', rect(0, 0, 100, 6000), BoxStyle{}, children)
	}

	fn preparation_motion(clock &PreparationClock, key string) Element {
		return with_motion(Element{ kind: .view, key: key, frame: rect(0, 0, 80, 40) }, MotionConfig{
			clock:            fn [clock] () f64 { return clock.now }
			enter_transition: MotionTransition{ duration: 0 }
			exit_transition:  MotionTransition{ duration: 0.4 }
		})
	}

	fn test_static_motion_preparation_preserves_tree_without_allocating() ! {
		root := preparation_static_group()
		mut tree := MotionTree{}
		assert tree.prepare(root)! == root
		before := gc_allocation_snapshot()!
		for _ in 0 .. 20 {
			assert tree.prepare(root)! == root
		}
		delta := gc_allocation_snapshot()!.delta_since(before)
		assert delta.allocated_bytes == 0
		assert delta.collections == 0
		assert tree.states.len == 0
	}

	fn test_static_group_inside_a_motion_tree_has_bounded_action_allocations() ! {
		mut clock := &PreparationClock{}
		root := view('root', rect(0, 0, 100, 6000), BoxStyle{}, [
			preparation_motion(clock, 'moving'),
			preparation_static_group(),
		])
		mut tree := MotionTree{}
		first := tree.prepare(root)!
		state := first.children[0].motion_state()
		before := gc_allocation_snapshot()!
		for _ in 0 .. 20 {
			prepared := tree.prepare(root)!
			assert prepared.children[0].motion_state() == state
			assert prepared.children[1] == root.children[1]
		}
		delta := gc_allocation_snapshot()!.delta_since(before)
		// Linux measures about 11 KB per preparation: the changed root and its
		// motion child. Copying the static group would cost over 1 MB each time.
		assert delta.allocated_bytes <= u64(20 * 24 * 1024)
	}

	fn test_motion_can_be_added_then_removed_after_static_preparation() ! {
		mut clock := &PreparationClock{}
		plain := view('root', rect(0, 0, 100, 40), BoxStyle{}, [
			Element{ kind: .view, key: 'card', frame: rect(0, 0, 80, 40) },
		])
		mut tree := MotionTree{}
		assert tree.prepare(plain)! == plain
		animated := Element{ ...plain, children: [preparation_motion(clock, 'card')] }
		state := tree.prepare(animated)!.children[0].motion_state()
		assert state != unsafe { nil } && !state.disposed
		assert tree.prepare(plain)! == plain
		assert tree.states.len == 0 && state.disposed
	}

	fn test_reordered_keyed_motion_keeps_states_and_removed_key_exits_once() ! {
		mut clock := &PreparationClock{}
		first := preparation_motion(clock, 'first')
		second := preparation_motion(clock, 'second')
		caption := label('caption', 'España ñ', rect(0, 0, 80, 20), TextStyle{})
		mut tree := MotionTree{}
		root := view('root', rect(0, 0, 100, 100), BoxStyle{}, [first, caption, second])
		initial := tree.prepare(root)!
		first_state := initial.children[0].motion_state()
		second_state := initial.children[2].motion_state()
		reordered := tree.prepare(Element{ ...root, children: [second, caption, first] })!
		assert reordered.children[0].motion_state() == second_state
		assert reordered.children[2].motion_state() == first_state
		clock.now = 0.1
		leaving := tree.prepare(Element{ ...root, children: [second, caption] })!
		assert leaving.children.len == 3
		assert leaving.children[2].presence_exiting()
		assert leaving.children[2].motion_state() == first_state
		assert leaving.children[0].motion_state() == second_state
		clock.now = 0.6
		tree.sample(leaving)!
		pruned := tree.prune(leaving)
		assert pruned.children.len == 2 && first_state.disposed
		assert pruned.children[0].motion_state() == second_state && !second_state.disposed
	}
}
