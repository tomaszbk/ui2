// vtest vflags: -gc boehm -d no_gc_thread_local_alloc
module ui2

// A frame of running motion allocates nothing: sampling every element,
// delivering progress events, observing layout and reading the presented
// transform, box and paint all reuse retained storage. Only a build, which
// changes the declaration, may allocate.

@[heap]
struct MotionAllocationClock {
mut:
	now    f64
	events int
}

const motion_allocation_frames = 240

// motion_allocation_frame is one motion-only frame as the custom renderer runs
// it: sample, observe the laid-out frames, then read what each element shows.
fn motion_allocation_frame(mut tree MotionTree, root Element, mut clock MotionAllocationClock) !f64 {
	clock.now += 1.0 / 60.0
	tree.sample(root)!
	tree.observe_layout(root, true)
	mut checksum := 0.0
	for child in root.children {
		matrix := child.presented_matrix(child.frame)!
		painted := child.with_motion_paint()
		width, height := child.presented_box_size(child.frame.width, child.frame.height)
		checksum += matrix.x + matrix.xx + width + height + f64(painted.box.bg & 0xff) +
			child.presented_opacity()
	}
	if !motion_tree_needs_frame(root) {
		return error('motion stopped before the measurement ended')
	}
	return checksum
}

fn motion_allocation_measure(name string, mut tree MotionTree, root Element, mut clock MotionAllocationClock) ! {
	// Warm up so retained buffers reach their steady capacity.
	for _ in 0 .. 8 {
		motion_allocation_frame(mut tree, root, mut clock)!
	}
	before := gc_allocation_snapshot()!
	mut checksum := 0.0
	for _ in 0 .. motion_allocation_frames {
		checksum += motion_allocation_frame(mut tree, root, mut clock)!
	}
	delta := gc_allocation_snapshot()!.delta_since(before)
	println('${name}: ${delta.allocated_bytes} bytes and ${delta.collections} collections over ${motion_allocation_frames} frames (checksum ${checksum:.1f})')
	assert delta.allocated_bytes == 0, name
	assert delta.collections == 0, name
}

fn motion_allocation_config(clock &MotionAllocationClock, patches []MotionPatch) MotionConfig {
	mut all := patches.clone()
	all << motion_clock(fn [clock] () f64 {
		return clock.now
	})
	all << motion_on(fn [clock] (event MotionEvent) {
		mut counter := unsafe { clock }
		counter.events++
	})
	return compose_motion(all)
}

fn test_running_color_transitions_allocate_nothing() ! {
	mut clock := &MotionAllocationClock{}
	config := motion_allocation_config(clock, [motion_transition(1000)])
	scene := fn [config] (bg u32, text u32) Element {
		mut children := []Element{}
		for i in 0 .. 12 {
			children << with_motion(view('tile-${i}', rect(f64(i * 30), 0, 24, 24), BoxStyle{
				bg:           bg
				border_color: bg
				radius:       if bg == 0 { 0.0 } else { 8.0 }
				shadow:       BoxShadow{
					blur:    if bg == 0 { 0.0 } else { 6.0 }
					opacity: 0.5
				}
			}, []Element{}), config)
			children << with_motion(label('text-${i}', 'España', rect(f64(i * 30), 30, 24, 20),
				TextStyle{
					color: text
				}), config)
		}
		return view('root', rect(0, 0, 400, 60), BoxStyle{}, children)
	}
	mut tree := MotionTree{}
	tree.prepare(scene(0x000000, 0x000000))!
	running := tree.prepare(scene(0xffffff, 0xff0000))!
	motion_allocation_measure('color transitions', mut tree, running, mut clock)!
	assert clock.events > motion_allocation_frames
	tree.dispose()
}

fn test_running_layout_transitions_allocate_nothing() ! {
	mut clock := &MotionAllocationClock{}
	box := motion_allocation_config(clock, [motion_layout(.box), motion_transition(1000)])
	sliding := motion_allocation_config(clock, [motion_layout(.position), motion_transition(1000)])
	scaling := motion_allocation_config(clock, [motion_layout(.scale), motion_transition(1000)])
	scene := fn [box, sliding, scaling] (x f64, width f64) Element {
		return view('root', rect(0, 0, 400, 100), BoxStyle{}, [
			with_motion(view('box', rect(x, 0, width, 20), BoxStyle{ bg: 0x336699 }, []Element{}),
				box),
			with_motion(view('slide', rect(x, 30, width, 20), BoxStyle{ bg: 0x336699 }, []Element{}),
				sliding),
			with_motion(view('scale', rect(x, 60, width, 20), BoxStyle{ bg: 0x336699 }, []Element{}),
				scaling),
		])
	}
	mut tree := MotionTree{}
	tree.observe_layout(tree.prepare(scene(0, 100))!, true)
	moved := tree.prepare(scene(120, 200))!
	tree.observe_layout(moved, true)
	motion_allocation_measure('layout transitions', mut tree, moved, mut clock)!
	tree.dispose()
}

fn test_running_loops_allocate_nothing() ! {
	mut clock := &MotionAllocationClock{}
	pulse := motion_keyframes(0.8, MotionKeyframe{
		at:    0
		style: MotionStyle{
			opacity:     1
			background:  0x000000
			translate_x: 0
			box_scale_x: 1
		}
	}, MotionKeyframe{
		at:     0.5
		style:  MotionStyle{
			opacity:     0.4
			background:  0x3366cc
			translate_x: 12
			box_scale_x: 0.5
		}
		easing: .in_out_sine
	}, MotionKeyframe{
		at:    1
		style: MotionStyle{
			opacity:     1
			background:  0x000000
			translate_x: 0
			box_scale_x: 1
		}
	})
	spin := motion_sequence(motion_tween(MotionStyle{ rotation: 180 }, MotionTransition{
		duration: 0.5
	}), motion_tween(MotionStyle{ rotation: 360 }, MotionTransition{ duration: 0.5 }))
	looping := motion_allocation_config(clock, [
		motion_timeline(motion_parallel(pulse, spin).looped()),
	])
	stepped := motion_allocation_config(clock, [
		motion_timeline(MotionTimeline{
			...pulse.looped()
			alternate: true
			step:      0.1
		}),
	])
	mut children := []Element{}
	for i in 0 .. 8 {
		children << with_motion(view('loop-${i}', rect(f64(i * 40), 0, 30, 30), BoxStyle{
			bg: 0x000000
		}, []Element{}), if i % 2 == 0 { looping } else { stepped })
	}
	// A parent that orchestrates its children's loops by id.
	children << with_motion(view('group', rect(0, 40, 200, 30), BoxStyle{}, [
		view('dot', rect(0, 0, 10, 10), BoxStyle{ bg: 0x000000 }, []Element{}),
	]), motion_allocation_config(clock, [motion_target('dot', pulse.looped())]))
	root := view('root', rect(0, 0, 400, 80), BoxStyle{}, children)
	mut tree := MotionTree{}
	prepared := tree.prepare(root)!
	motion_allocation_measure('loops', mut tree, prepared, mut clock)!
	tree.dispose()
}
