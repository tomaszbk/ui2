module ui2

// The retained motion tree: timelines an element plays on its descendants,
// layout transitions observed from laid-out frames, animated paint, and
// events delivered once a frame has been sampled.

@[heap]
struct TreeTestClock {
mut:
	now f64
}

@[heap]
struct TreeTestLog {
mut:
	events []string
}

fn tree_test_find(el Element, id string) Element {
	if el.id == id {
		return el
	}
	for child in el.children {
		found := tree_test_find(child, id)
		if found.id == id {
			return found
		}
	}
	return Element{}
}

fn tree_test_tile(id string, frame Rect, config MotionConfig) Element {
	return with_motion(view(id, frame, BoxStyle{ bg: 0x000000 }, []Element{}), config)
}

fn test_motion_tree_targets_animate_descendants_by_id() ! {
	mut clock := &TreeTestClock{}
	tick := fn [clock] () f64 {
		return clock.now
	}
	pulse := motion_keyframes(1, MotionKeyframe{
		at:    0.5
		style: MotionStyle{
			opacity: 0.5
		}
	}).looped()
	spin := motion_keyframes(1, MotionKeyframe{
		at:    1
		style: MotionStyle{
			rotation: 90
		}
	}).looped()
	card := fn [tick, pulse, spin] (targets bool, logo_motion bool) Element {
		logo := view('logo', rect(10, 10, 20, 20), BoxStyle{}, []Element{})
		return view('root', rect(0, 0, 200, 100), BoxStyle{}, [
			with_motion(view('card', rect(0, 0, 100, 100), BoxStyle{}, [
				if logo_motion {
					with_motion(logo, compose_motion([motion_timeline(spin), motion_clock(tick)]))
				} else {
					logo
				},
				view('badge', rect(40, 10, 20, 20), BoxStyle{}, []Element{}),
			]), compose_motion([
				if targets { motion_target('logo', pulse) } else { MotionPatch{} },
				motion_clock(tick),
			])),
		])
	}
	mut tree := MotionTree{}
	prepared := tree.prepare(card(true, false))!
	mut logo := tree_test_find(prepared, 'logo').motion_state()
	assert logo != unsafe { nil }
	assert tree_test_find(prepared, 'badge').motion_state() == unsafe { nil }
	// The targeted element runs on the clock of the element that targets it.
	assert logo.timeline_on && logo.timeline == pulse
	clock.now = 0.5
	tree.sample(prepared)!
	assert logo.current.values.opacity == 0.5
	assert motion_tree_needs_frame(prepared)
	// Rebuilding keeps the same state and timeline.
	again := tree.prepare(card(true, false))!
	assert tree_test_find(again, 'logo').motion_state() == logo
	assert logo.timeline_start == 0
	// The element's own timeline takes precedence over a target: the target's
	// channels glide back to the declaration while the own timeline starts.
	own := tree.prepare(card(true, true))!
	assert tree_test_find(own, 'logo').motion_state() == logo
	assert logo.timeline == spin && logo.timeline_start == 0.5
	clock.now = 1.25
	tree.sample(own)!
	assert logo.current.values.opacity == 1
	assert logo.current.values.transform.rotation == 67.5
	// Without a target or motion of its own the element has no state.
	plain := tree.prepare(card(false, false))!
	assert tree_test_find(plain, 'logo').motion_state() == unsafe { nil }
	assert logo.disposed
	tree.dispose()
}

fn test_motion_tree_follows_laid_out_frames() ! {
	mut clock := &TreeTestClock{}
	tick := fn [clock] () f64 {
		return clock.now
	}
	sliding := compose_motion([motion_layout(.position), motion_transition(1), motion_clock(tick)])
	scene := fn [sliding] (x f64) Element {
		return view('root', rect(0, 0, 400, 100), BoxStyle{}, [
			view('row', rect(0, 0, 400, 100), BoxStyle{}, [
				tree_test_tile('tile', rect(x, 10, 40, 40), sliding),
			]),
			view('static', rect(0, 0, 10, 10), BoxStyle{}, []Element{}),
		])
	}
	mut tree := MotionTree{}
	first := tree.prepare(scene(0))!
	assert tree.layout_watchers == 1
	tree.observe_layout(first, true)
	state := tree_test_find(first, 'tile').motion_state()
	assert state.layout_seen && state.layout_frame == rect(0, 10, 40, 40)
	// A frame laid out elsewhere is shown where it was, then slides.
	moved := tree.prepare(scene(100))!
	tree.observe_layout(moved, true)
	assert state.current.layout_offset == Rect{
		x: -100
	}
	tile := tree_test_find(moved, 'tile')
	matrix := tile.presented_matrix(tile.frame)!
	assert matrix.project(tile.frame) == rect(0, 10, 40, 40)
	assert tile.presentation_moves()
	clock.now = 0.5
	assert tree.sample(moved)!
	assert tree.geometry_changed
	assert tile.presented_matrix(tile.frame)!.project(tile.frame) == rect(50, 10, 40, 40)
	// The same layout output again is not visited below the root.
	tree.observe_layout(moved, true)
	assert state.layout_running
	// A resize shows the new frame at once.
	resized := tree.prepare(scene(200))!
	tree.observe_layout(resized, false)
	assert state.current.layout_offset == Rect{} && !state.layout_running
	assert !tree_test_find(resized, 'tile').presentation_moves()
	// Without layout motion nothing is observed.
	still := tree.prepare(view('root', rect(0, 0, 400, 100), BoxStyle{}, []Element{}))!
	assert tree.layout_watchers == 0
	tree.observe_layout(still, true)
	assert tree.observed.children.len == 0
	tree.dispose()
}

fn test_motion_tree_box_and_scale_layout_modes() ! {
	mut clock := &TreeTestClock{}
	tick := fn [clock] () f64 {
		return clock.now
	}
	mut tree := MotionTree{}
	scene := fn [tick] (width f64) Element {
		return view('root', rect(0, 0, 400, 100), BoxStyle{}, [
			tree_test_tile('box', rect(0, 0, width, 20), compose_motion([
				motion_layout(.box),
				motion_transition(1),
				motion_clock(tick),
			])),
			tree_test_tile('scale', rect(0, 40, width, 20), compose_motion([
				motion_layout(.scale),
				motion_transition(1),
				motion_clock(tick),
			])),
		])
	}
	tree.observe_layout(tree.prepare(scene(100))!, true)
	grown := tree.prepare(scene(200))!
	tree.observe_layout(grown, true)
	clock.now = 0.5
	tree.sample(grown)!
	// box resizes the element's own fill and keeps its content's layout.
	box := tree_test_find(grown, 'box')
	width, height := box.presented_box_size(box.frame.width, box.frame.height)
	assert width == 150 && height == 20
	assert box.presented_matrix(box.frame)!.project(box.frame) == box.frame
	// scale maps the whole element from its old frame.
	scaled := tree_test_find(grown, 'scale')
	assert scaled.presented_matrix(scaled.frame)!.project(scaled.frame) == rect(0, 40, 150, 20)
	scaled_width, _ := scaled.presented_box_size(scaled.frame.width, scaled.frame.height)
	assert scaled_width == 200
	tree.dispose()
}

fn test_motion_tree_presents_animated_paint() ! {
	mut clock := &TreeTestClock{}
	config := compose_motion([motion_transition(1), motion_clock(fn [clock] () f64 {
		return clock.now
	})])
	scene := fn [config] (bg u32) Element {
		return view('root', rect(0, 0, 100, 100), BoxStyle{}, [
			with_motion(view('tile', rect(0, 0, 40, 40), BoxStyle{
				bg:     bg
				radius: if bg == 0 { 0.0 } else { 10.0 }
			}, []Element{}), config),
		])
	}
	mut tree := MotionTree{}
	first := tree.prepare(scene(0x000000))!
	tile := tree_test_find(first, 'tile')
	assert tile.with_motion_paint() == tile
	lit := tree.prepare(scene(0xffffff))!
	clock.now = 0.5
	tree.sample(lit)!
	shown := tree_test_find(lit, 'tile').with_motion_paint()
	assert shown.box.bg in [u32(0x7f7f7f), 0x808080]
	assert shown.box.radius == 5
	clock.now = 1
	tree.sample(lit)!
	settled := tree_test_find(lit, 'tile')
	assert settled.with_motion_paint() == settled
	assert !motion_tree_needs_frame(lit)
	tree.dispose()
}

fn test_motion_tree_delivers_events_after_sampling_every_element() ! {
	mut clock := &TreeTestClock{}
	tick := fn [clock] () f64 {
		return clock.now
	}
	log := &TreeTestLog{}
	listen := fn [log] (event MotionEvent) {
		mut entries := unsafe { log }
		entries.events << '${event.id}:${event.source}:${event.kind}'
	}
	config := compose_motion([motion_fade(1), motion_on(listen), motion_clock(tick)])
	root := view('root', rect(0, 0, 100, 100), BoxStyle{}, [
		tree_test_tile('a', rect(0, 0, 10, 10), config),
		tree_test_tile('b', rect(20, 0, 10, 10), config),
		tree_test_tile('quiet', rect(40, 0, 10, 10), compose_motion([motion_fade(1),
			motion_clock(tick)])),
	])
	mut tree := MotionTree{}
	prepared := tree.prepare(root)!
	tree.sample(prepared)!
	assert tree.dispatched
	assert log.events == ['a:enter:start', 'a:enter:progress', 'b:enter:start', 'b:enter:progress']
	clock.now = 1
	tree.sample(prepared)!
	assert log.events[4..] == ['a:enter:complete', 'b:enter:complete']
	// A frame without events delivers nothing.
	tree.sample(prepared)!
	assert !tree.dispatched
	assert log.events.len == 6
	tree.dispose()
	assert !tree.dispatched
}
