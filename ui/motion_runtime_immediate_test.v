@[has_globals]
module ui2

import math

@[heap]
struct RuntimeMotionClock {
mut:
	now f64
}

$if (android || linux || macos || windows) && !ui2_headless ? {
	__global motion_runtime_pointer_events = []ElementEvent{}

	fn runtime_motion_style(clock &RuntimeMotionClock) MotionConfig {
		return MotionConfig{
			clock:            fn [clock] () f64 { return clock.now }
			enter:            MotionStyle{ opacity: 0, translate_x: -40 }
			enter_transition: MotionTransition{ duration: 0.2 }
			exit_transition:  MotionTransition{ duration: 0.4 }
		}
	}

	fn runtime_motion_pointer(event ElementEvent) { motion_runtime_pointer_events << event }

	fn runtime_motion_frame(mut w Window, now i64) !(Element, FrameWork) {
		work := w.scheduler.begin_frame(now) or { return error('expected a motion frame') }
		root := w.resolve_custom_layout(work, measure_layout_text, w.take_custom_layout_patches())!
		w.reconcile_mounted_focus_controls(root)
		w.update_custom_focus_tree(root)
		w.scheduler.set_motion_active(motion_tree_needs_frame(w.declared_root))
		w.scheduler.finish_frame(work)
		return root, work
	}

	fn test_motion_host_retains_edit_reverses_exit_and_schedules_only_presentation() ! {
		mut clock := &RuntimeMotionClock{}
		field := with_motion(text_input(TextInputConfig{
			id:    'edit'
			text:  'declarado'
			frame: rect(60, 20, 120, 40)
		})!, runtime_motion_style(clock))
		declared := Element{ kind: .screen, id: 'root', frame: rect(0, 0, 300, 200), children: [field] }
		mut w := &Window{ ctx: &DrawContext{ width: 300, height: 200 }, has_root: true, declared_root: declared }
		defer {
			w.motion_tree.dispose()
		}
		runtime_motion_frame(mut w, 0)!
		clock.now = 0.1
		_, entering := runtime_motion_frame(mut w, 100)!
		assert !entering.build && entering.reasons == RenderReason.motion
		mounted := w.navigation.node('edit') or { panic('missing entering input') }
		assert math.abs(mounted.transform.x + 20) < 0.00001
		center := mounted.transform.point(mounted.local_frame.x + 60, mounted.local_frame.y + 20)
		assert w.hit_test(center.x, center.y).id == 'edit'
		assert w.hit_test(175, 40).id == '' // outside the currently presented input
		clock.now = 0.21
		runtime_motion_frame(mut w, 210)!
		assert w.scheduler.begin_frame(211) == none
		identity := w.layout_tree.identity('edit') or { panic('missing editor layout') }
		w.replace_text_value('edit', 'año café ñ')
		w.replace_text_editor('edit', TextEditor{ text: 'año café ñ'.clone(), selection: TextSelection{ anchor: 1, caret: 5 } })
		w.focused_field = 'edit'
		w.composition = TextComposition{ field_id: 'edit', text: 'á' }
		w.declared_root = Element{ ...declared, children: [] }
		w.declaration_pending = true
		w.scheduler.invalidate(.layout)
		leaving, removal := runtime_motion_frame(mut w, 220)!
		assert !removal.build && leaving.children.len == 1
		assert leaving.children[0].presence_exiting() && !leaving.children[0].presented_enabled()
		assert scroll_content_height(Element{ ...leaving, kind: .scroll }) == 0
		assert w.focused_field == '' && w.composition.field_id == ''
		assert !(w.editable_fields['edit'] or { true })
		assert w.hit_test(100, 40).id == ''
		assert w.text('edit') == 'año café ñ'
		clock.now = 0.31
		runtime_motion_frame(mut w, 310)!
		partial := w.declared_root.children[0].presented_opacity()
		w.declared_root = declared
		w.declaration_pending = true
		w.scheduler.invalidate(.layout)
		returned, _ := runtime_motion_frame(mut w, 320)!
		assert returned.children.len == 1 && !returned.children[0].presence_exiting()
		assert returned.children[0].presented_opacity() == partial
		assert w.layout_tree.identity('edit') or { panic('editor retired') } == identity
		assert w.text('edit') == 'año café ñ'
		assert w.text_editors['edit'].selection == TextSelection{ anchor: 1, caret: 5 }
		clock.now = 0.52
		runtime_motion_frame(mut w, 520)!
		assert w.scheduler.begin_frame(521) == none
		w.declared_root = Element{ ...declared, children: [] }
		w.declaration_pending = true
		w.scheduler.invalidate(.layout)
		runtime_motion_frame(mut w, 530)!
		clock.now = 0.93
		terminal, _ := runtime_motion_frame(mut w, 930)!
		assert terminal.children.len == 0
		assert w.scheduler.begin_frame(931) == none
	}

	fn test_motion_exit_finished_by_public_setter_still_retires_its_retained_tree() ! {
		mut clock := &RuntimeMotionClock{}
		card := with_motion(view('card', rect(20, 20, 120, 60), BoxStyle{}, []),
			runtime_motion_style(clock))
		declared := Element{ kind: .screen, id: 'root', frame: rect(0, 0, 300, 200), children: [card] }
		mut w := &Window{ ctx: &DrawContext{ width: 300, height: 200 }, has_root: true, declared_root: declared }
		defer {
			w.motion_tree.dispose()
		}
		runtime_motion_frame(mut w, 0)!
		clock.now = 0.21
		runtime_motion_frame(mut w, 210)!
		w.declared_root = Element{ ...declared, children: [] }
		w.declaration_pending = true
		w.scheduler.invalidate(.layout)
		leaving, _ := runtime_motion_frame(mut w, 220)!
		assert leaving.children.len == 1 && leaving.children[0].presence_exiting()
		state := leaving.children[0].motion_state()
		clock.now = 0.7
		w.set_visual_transform('card', VisualTransform{ translate_x: 30 })!
		assert state.current.phase == .absent && !state.disposed
		assert w.declared_root.children.len == 1
		before_revision := w.presentation_revision
		terminal, _ := runtime_motion_frame(mut w, 700)!
		assert terminal.children.len == 0 && w.motion_tree.states.len == 0
		assert state.disposed && w.presentation_revision > before_revision
		assert w.scheduler.begin_frame(701) == none
	}

	fn test_motion_exit_cancels_captured_pointer_before_another_drag() ! {
		motion_runtime_pointer_events.clear()
		mut clock := &RuntimeMotionClock{}
		card := with_motion(Element{
			kind:      .view
			id:        'drag'
			key:       'drag'
			frame:     rect(30, 20, 100, 50)
			clickable: true
			draggable: true
			on_event:  runtime_motion_pointer
		}, runtime_motion_style(clock))
		declared := Element{ kind: .screen, id: 'root', frame: rect(0, 0, 300, 200), children: [card] }
		mut w := &Window{ ctx: &DrawContext{ width: 300, height: 200 }, has_root: true, declared_root: declared }
		defer {
			w.motion_tree.dispose()
		}
		runtime_motion_frame(mut w, 0)!
		clock.now = 0.21
		runtime_motion_frame(mut w, 210)!
		w.handle_touch_down(60, 40)
		assert w.touch.pointer_captured && w.touch.down
		assert motion_runtime_pointer_events.map(it.kind) == [ElementEventKind.pointer_down]
		w.declared_root = Element{ ...declared, children: [] }
		w.declaration_pending = true
		w.scheduler.invalidate(.layout)
		runtime_motion_frame(mut w, 220)!
		assert !w.touch.pointer_captured && !w.touch.down
		before := motion_runtime_pointer_events.len
		w.handle_touch_move(90, 60)
		w.handle_touch_up(90, 60)
		assert motion_runtime_pointer_events.len == before
		assert motion_runtime_pointer_events.filter(it.kind == .pointer_drag).len == 0
	}

	fn test_motion_tree_samples_nested_exits_until_the_slowest_descendant_completes() ! {
		for parent_motion in [false, true] {
			mut clock := &RuntimeMotionClock{}
			mut tree := MotionTree{}
			child := with_motion(Element{ kind: .view, key: 'child', frame: rect(0, 0, 20, 20) },
				MotionConfig{ clock: fn [clock] () f64 { return clock.now }, exit_transition: MotionTransition{ duration: 0.4 } })
			mut parent := Element{ kind: .view, key: 'parent', frame: rect(0, 0, 100, 100), children: [child] }
			if parent_motion {
				parent = with_motion(parent, MotionConfig{
					clock:           fn [clock] () f64 { return clock.now }
					exit_transition: MotionTransition{ duration: 0.1 }
				})
			}
			declared := Element{ kind: .view, children: [parent] }
			mut root := tree.prepare(declared)!
			original_child := root.children[0].children[0].motion_state()
			clock.now = 0.2
			tree.sample(root)!
			root = tree.prepare(Element{ kind: .view })!
			assert root.children.len == 1 && root.children[0].presence_exiting()
			clock.now = 0.31
			tree.sample(root)!
			if parent_motion {
				assert root.children[0].presented_hidden()
			}
			assert motion_tree_needs_frame(root)
			assert tree.prune(root).children.len == 1
			root = tree.prepare(declared)!
			assert !root.children[0].presence_exiting()
			assert root.children[0].children[0].motion_state() == original_child
			assert original_child.current.phase == .entering
			clock.now = 0.6
			tree.sample(root)!
			root = tree.prepare(Element{ kind: .view })!
			clock.now = 0.71
			tree.sample(root)!
			assert tree.prune(root).children.len == 1
			assert !original_child.disposed
			clock.now = 1.01
			tree.sample(root)!
			pruned := tree.prune(root)
			assert pruned.children.len == 0 && tree.states.len == 0
			assert original_child.disposed && !motion_tree_needs_frame(pruned)
			tree.dispose()
		}
	}
}

fn test_outgoing_nodes_keep_frames_and_do_not_reserve_flex_spacing_or_grid_cells() ! {
	for kind in [LayoutKind.flex, .grid] {
		a := Element{ kind: .button, id: 'a', key: 'a', frame: rect(0, 0, 40, 20) }
		b := Element{ kind: .button, id: 'b', key: 'b', frame: rect(0, 0, 40, 20) }
		c := Element{ kind: .button, id: 'c', key: 'c', frame: rect(0, 0, 40, 20) }
		root := if kind == .flex {
			flex(FlexConfig{
				id:       'root'
				frame:    rect(0, 0, 200, 40)
				justify:  .space_between
				children: [FlexChild{ element: a }, FlexChild{ element: b }, FlexChild{ element: c }]
			})!
		} else {
			grid(GridConfig{
				id:       'root'
				frame:    rect(0, 0, 300, 40)
				columns:  3
				children: [
					a,
					b,
					c,
				]
			})!
		}
		mut tree := &LayoutTree{}
		tree.replace(root)!
		before := tree.resolve(LayoutConstraints{}, measure_layout_text, LayoutEnvironment{})!
		frozen := before.children[1].frame
		changed := Element{
			...root
			frame:        rect(0, 0, if kind == .flex { 300.0 } else { 600.0 }, 40)
			layout_input: none
			children:     [a, c,
				Element{ ...b, runtime: &ElementRuntime{ exiting: true }, enabled: false }]
		}
		tree.replace(changed)!
		after := tree.resolve(LayoutConstraints{}, measure_layout_text, LayoutEnvironment{})!
		assert after.children[0].frame.x == 0
		assert after.children[1].frame.x == if kind == .flex { 260.0 } else { 200.0 }
		assert after.children[2].frame == frozen
	}
}
