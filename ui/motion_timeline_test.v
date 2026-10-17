module ui2

import math

// Timelines, springs, composed configurations and the retained element state:
// paint and layout transitions, events, handles and reduced motion. These run
// without a window; the tree that drives them is tested in motion_tree_test.v.

@[heap]
struct TimelineTestClock {
mut:
	now f64
}

@[heap]
struct TimelineTestLog {
mut:
	events []MotionEvent
}

fn (log &TimelineTestLog) kinds(source MotionEventSource) []MotionEventKind {
	return log.events.filter(it.source == source).map(it.kind)
}

// milestones leaves out the progress events of every frame.
fn (log &TimelineTestLog) milestones(source MotionEventSource) []MotionEventKind {
	return log.events.filter(it.source == source && it.kind != .progress).map(it.kind)
}

// timeline_test_at is what timeline presents over base at seconds.
fn timeline_test_at(timeline MotionTimeline, base MotionValues, seconds f64) MotionValues {
	program := compile_motion_timeline(timeline) or { panic(err) }
	position := program.locate(seconds)
	mut channels := motion_channels(base)
	if position.started && (!position.done || program.hold) {
		program.apply(mut channels, position.time)
	}
	return channels.values()
}

fn timeline_test_key(at f64, style MotionStyle) MotionKeyframe {
	return MotionKeyframe{
		at:    at
		style: style
	}
}

// timeline_test_mount mounts element with config driven by the clock's tick.
fn timeline_test_mount(element Element, config MotionConfig) &ElementMotionState {
	mut state := new_element_motion_state(with_motion(element, config)) or { panic(err) }
	state.mount() or { panic(err) }
	return state
}

fn timeline_test_sample(mut state ElementMotionState) MotionSample {
	return state.sample() or { panic(err) }
}

// timeline_test_deliver runs the events the state produced since the last call.
fn timeline_test_deliver(mut state ElementMotionState) {
	mut sink := []MotionDispatch{}
	state.emit_events('tile', mut sink)
	for dispatch in sink {
		dispatch.callback(dispatch.event)
	}
}

fn timeline_test_close(a f64, b f64) bool {
	return math.abs(a - b) < 1e-9
}

fn test_motion_style_sets_only_its_channels() ! {
	base := MotionValues{
		opacity:   0.5
		transform: VisualTransform{
			translate_x: 3
		}
		paint:     MotionPaint{
			background: 0x112233
			radius:     4
		}
	}
	over := MotionStyle{
		opacity:    1
		background: 0xffffff
	}.over(base)
	assert over.opacity == 1
	assert over.transform.translate_x == 3
	assert over.paint.background == 0xffffff
	assert over.paint.radius == 4
	assert MotionStyle{}.over(base) == base
	if _ := (MotionStyle{
		opacity: 2
	}).validate() {
		assert false, 'opacity above one accepted'
	}
	if _ := (MotionStyle{
		radius: -1
	}).validate() {
		assert false, 'negative radius accepted'
	}
}

fn test_motion_keyframes_interpolate_ease_and_jump() ! {
	base := MotionValues{}
	fade := motion_keyframes(2, timeline_test_key(0, MotionStyle{ opacity: 0 }), timeline_test_key(0.5,
		MotionStyle{ opacity: 1 }), timeline_test_key(1, MotionStyle{ opacity: 0.5 }))
	fade.validate()!
	assert timeline_test_close(timeline_test_at(fade, base, 0.5).opacity, 0.5)
	assert timeline_test_at(fade, base, 1).opacity == 1
	assert timeline_test_close(timeline_test_at(fade, base, 1.5).opacity, 0.75)
	// A finite timeline without hold hands its channels back when it ends.
	assert timeline_test_at(fade, base, 3).opacity == 1
	held := MotionTimeline{
		...fade
		hold: true
	}
	assert timeline_test_at(held, base, 3).opacity == 0.5
	// A channel without a key at 0 starts from the values beneath it.
	slide := motion_keyframes(1, timeline_test_key(1, MotionStyle{ translate_x: 100 }))
	assert timeline_test_at(slide, MotionValues{ transform: VisualTransform{ translate_x: 20 } },
		0.5).transform.translate_x == 60
	// The easing of a key shapes the segment that ends there.
	eased := motion_keyframes(1, timeline_test_key(0, MotionStyle{ translate_x: 0 }), MotionKeyframe{
		at:     1
		style:  MotionStyle{
			translate_x: 100
		}
		easing: .in_quad
	})
	assert timeline_test_close(timeline_test_at(eased, base, 0.5).transform.translate_x, 25)
	// Keys sharing an instant jump: the later one holds from there.
	jump := motion_keyframes(1, timeline_test_key(0, MotionStyle{ opacity: 0 }), timeline_test_key(0.5,
		MotionStyle{ opacity: 0 }), timeline_test_key(0.5, MotionStyle{ opacity: 1 }),
		timeline_test_key(1, MotionStyle{ opacity: 1 }))
	assert timeline_test_at(jump, base, 0.25).opacity == 0
	assert timeline_test_at(jump, base, 0.75).opacity == 1
	// Colors interpolate per channel and radii and shadows like numbers.
	paint := motion_keyframes(1, timeline_test_key(0, MotionStyle{
		background: 0x000000
		radius:     0
		shadow:     BoxShadow{
			blur: 0
		}
	}), timeline_test_key(1, MotionStyle{
		background: 0x00ff00
		radius:     8
		shadow:     BoxShadow{
			blur:    10
			opacity: 1
		}
	}))
	middle := timeline_test_at(paint, base, 0.5)
	assert middle.paint.background & 0xff00ff == 0
	assert (middle.paint.background >> 8) & 0xff in [u32(0x7f), 0x80]
	assert middle.paint.radius == 4
	assert middle.paint.shadow.blur == 5
}

fn test_motion_sequence_parallel_repeat_alternate_step_and_delay() ! {
	base := MotionValues{}
	there := motion_tween(MotionStyle{ translate_x: 100 }, MotionTransition{ duration: 1 })
	back := motion_tween(MotionStyle{ translate_x: 0 }, MotionTransition{ duration: 1 })
	trip := motion_sequence(there, back)
	trip.validate()!
	assert timeline_test_at(trip, base, 0.5).transform.translate_x == 50
	assert timeline_test_at(trip, base, 1).transform.translate_x == 100
	assert timeline_test_at(trip, base, 1.5).transform.translate_x == 50
	fade := motion_keyframes(2, timeline_test_key(0, MotionStyle{ opacity: 0 }), timeline_test_key(1,
		MotionStyle{ opacity: 1 }))
	both := motion_parallel(trip, fade)
	both.validate()!
	values := timeline_test_at(both, base, 1)
	assert values.transform.translate_x == 100 && values.opacity == 0.5
	// Parallel children must not animate the same channel.
	if _ := motion_parallel(there, back).validate() {
		assert false, 'parallel children animating one channel accepted'
	}
	// Repeats and loops count cycles; alternate plays every other one backwards.
	program := compile_motion_timeline(there.repeated(2))!
	assert program.locate(2.5).cycle == 2 && !program.locate(2.5).done
	assert program.locate(3.5).done
	looping := MotionTimeline{
		...there.looped()
		alternate: true
	}
	looping.validate()!
	assert timeline_test_at(looping, base, 0.25).transform.translate_x == 25
	assert timeline_test_at(looping, base, 1.25).transform.translate_x == 75
	assert compile_motion_timeline(looping)!.locate(1000.5).cycle == 1000
	// step holds values between samples; delay waits before the first key.
	stepped := MotionTimeline{
		...there
		step: 0.25
	}
	assert timeline_test_at(stepped, base, 0.49).transform.translate_x == 25
	delayed := MotionTimeline{
		...there
		delay: 1
	}
	assert timeline_test_at(delayed, base, 0.5).transform.translate_x == 0
	assert timeline_test_at(delayed, base, 1.5).transform.translate_x == 50
	// Only the outermost timeline may loop forever, alternate, step or hold.
	if _ := motion_sequence(there.looped()).validate() {
		assert false, 'nested forever loop accepted'
	}
	if _ := motion_keyframes(1, timeline_test_key(1.5, MotionStyle{ opacity: 1 })).validate() {
		assert false, 'keyframe past the end accepted'
	}
	if _ := motion_keyframes(0, timeline_test_key(1, MotionStyle{ opacity: 1 })).looped().validate() {
		assert false, 'zero-length forever loop accepted'
	}
	assert MotionTimeline{}.is_empty()
}

fn test_motion_spring_settles_and_composes_its_duration() ! {
	spring := MotionSpring{}
	settle := spring.settle_time()
	assert settle > 0.05 && settle < 2
	assert math.abs(spring.position(settle) - 1) <= 0.001 + 1e-9
	assert spring.position(0) == 0
	bouncy := MotionSpring{
		stiffness: 300
		damping:   8
	}
	mut peak := 0.0
	for i in 1 .. 200 {
		peak = math.max(peak, bouncy.position(f64(i) / 200))
	}
	assert peak > 1, 'an underdamped spring overshoots'
	assert MotionSpring{
		damping: 60
	}.position(0.2) < 1
	if _ := (MotionSpring{
		stiffness: 0
	}).validate() {
		assert false, 'zero stiffness accepted'
	}
	config := compose_motion([motion_spring(170, 26)])
	assert config.transition.spring != none
	assert config.enter_transition.duration == settle
	assert config.transition.duration == settle
	// A duration after the spring overrides its settle time.
	shorter := compose_motion([motion_spring(170, 26), motion_duration(0.1)])
	assert shorter.transition.duration == 0.1
	transition := shorter.transition
	assert transition.ease(1) == 1
	assert transition.ease(0.5) == spring.position(0.05)
}

fn test_compose_motion_merges_pieces_left_to_right() ! {
	empty := compose_motion([])
	assert empty.enter == MotionStyle{}
	assert empty.exit == MotionStyle{}
	assert empty.transition == MotionTransition{}
	assert empty.layout == .none
	card := compose_motion([motion_fade(0.2), motion_slide_y(12), motion_scale(0.96),
		motion_easing(.out_cubic), motion_layout(.position), motion_transition(0.3)])
	assert card.enter == MotionStyle{
		opacity:     0
		translate_y: 12
		scale_x:     0.96
		scale_y:     0.96
	}
	assert card.exit == card.enter
	assert card.enter_transition.duration == 0.2 && card.enter_transition.easing == .out_cubic
	assert card.exit_transition.duration == 0.2
	assert card.transition.duration == 0.3 && card.transition.easing == .out_cubic
	assert card.layout == .position
	card.validate()!
	// Later pieces win field by field; enter and exit merge channel by channel.
	split := compose_motion([motion_fade(0.2), motion_exit(MotionStyle{
		translate_x: -40
	}), motion_enter_duration(0.5), motion_exit_duration(0.1), motion_rotate(90)])
	assert split.enter == MotionStyle{
		opacity:  0
		rotation: 90
	}
	assert split.exit == MotionStyle{
		opacity:     0
		translate_x: -40
		rotation:    90
	}
	assert split.enter_transition.duration == 0.5
	assert split.exit_transition.duration == 0.1
	pulse := motion_keyframes(1, timeline_test_key(1, MotionStyle{ opacity: 1 })).looped()
	mut handle := &MotionHandle{}
	log := &TimelineTestLog{}
	wired := compose_motion([motion_timeline(pulse), motion_target('logo', pulse),
		motion_target('badge', pulse), motion_reduced(true), motion_handle(handle), motion_on(fn [log] (event MotionEvent) {
			mut events := unsafe { log }
			events.events << event
		}), motion_clock(fn () f64 {
			return 1
		})])
	assert wired.timeline == pulse
	assert wired.targets.map(it.id) == ['logo', 'badge']
	assert wired.reduced_motion
	assert wired.handle == handle
	assert wired.on_motion != unsafe { nil }
	assert wired.clock != unsafe { nil }
	assert compose_motion([motion_reduced(true), motion_reduced(false)]).reduced_motion == false
}

fn test_element_motion_transitions_paint_without_relayout() ! {
	mut clock := &TimelineTestClock{}
	config := MotionConfig{
		transition: MotionTransition{
			duration: 1
		}
		clock:      fn [clock] () f64 {
			return clock.now
		}
	}
	plain := view('tile', rect(0, 0, 40, 40), BoxStyle{
		bg:           0x000000
		border_color: 0x000000
		radius:       0
		shadow:       BoxShadow{
			blur: 0
		}
	}, []Element{})
	mut state := timeline_test_mount(plain, config)
	assert state.current.phase == .entering
	clock.now = 1
	assert timeline_test_sample(mut state).phase == .present
	lit := view('tile', rect(0, 0, 40, 40), BoxStyle{
		bg:           0xffffff
		border_color: 0x0000ff
		radius:       8
		shadow:       BoxShadow{
			blur:    6
			opacity: 1
		}
	}, []Element{})
	state.update(with_motion(lit, config))!
	assert state.current.values.paint.background == 0
	clock.now = 1.5
	middle := timeline_test_sample(mut state)
	assert middle.running
	assert middle.values.paint.background in [u32(0x7f7f7f), 0x808080]
	assert middle.values.paint.border_color in [u32(0x7f), 0x80]
	assert middle.values.paint.radius == 4
	assert middle.values.paint.shadow.blur == 3
	clock.now = 2
	end := timeline_test_sample(mut state)
	assert !end.running
	assert end.values.paint == element_motion_paint(lit)
	// Text color animates the same way.
	text := label('name', 'Name', rect(0, 0, 60, 20), TextStyle{
		color: 0x000000
	})
	mut label_state := timeline_test_mount(text, config)
	clock.now = 3
	timeline_test_sample(mut label_state)
	label_state.update(with_motion(Element{
		...text
		text_style: TextStyle{
			color: 0xff0000
		}
	}, config))!
	clock.now = 3.5
	assert (timeline_test_sample(mut label_state).values.paint.text_color >> 16) in [
		u32(0x7f),
		0x80,
	]
}

fn test_element_motion_timeline_loops_releases_and_holds() ! {
	mut clock := &TimelineTestClock{}
	tick := fn [clock] () f64 {
		return clock.now
	}
	pulse := motion_keyframes(1, timeline_test_key(0, MotionStyle{ opacity: 1 }), timeline_test_key(0.5,
		MotionStyle{ opacity: 0.5 }), timeline_test_key(1, MotionStyle{ opacity: 1 }))
	tile := view('tile', rect(0, 0, 40, 40), BoxStyle{}, []Element{})
	mut looping := timeline_test_mount(tile, compose_motion([
		motion_timeline(pulse.looped()),
		motion_clock(tick),
	]))
	assert looping.timeline_on
	clock.now = 10.5
	sample := timeline_test_sample(mut looping)
	assert sample.running && timeline_test_close(sample.values.opacity, 0.5)
	assert looping.timeline_cycle == 10
	// A finite timeline hands its channels back to the declaration, gliding
	// with the element's transition.
	clock.now = 0
	once := motion_keyframes(1, timeline_test_key(1, MotionStyle{ translate_x: 100 }))
	mut released := timeline_test_mount(tile, compose_motion([motion_timeline(once),
		motion_transition(1), motion_clock(tick)]))
	clock.now = 0.5
	assert timeline_test_sample(mut released).values.transform.translate_x == 50
	clock.now = 1.5
	ended := timeline_test_sample(mut released)
	assert released.timeline_completed
	assert ended.running && ended.values.transform.translate_x == 100
	clock.now = 2
	assert timeline_test_close(timeline_test_sample(mut released).values.transform.translate_x,
		50)
	clock.now = 2.5
	rest := timeline_test_sample(mut released)
	assert !rest.running && rest.values.transform.translate_x == 0
	// hold keeps the final values without asking for frames.
	clock.now = 0
	mut held := timeline_test_mount(tile, compose_motion([
		motion_timeline(MotionTimeline{ ...once, hold: true }),
		motion_clock(tick),
	]))
	clock.now = 5
	kept := timeline_test_sample(mut held)
	assert !kept.running && kept.values.transform.translate_x == 100
	// A hidden element plays nothing; showing it starts the timeline again.
	clock.now = 0
	config := compose_motion([motion_timeline(pulse.looped()), motion_clock(tick)])
	mut hidden := timeline_test_mount(Element{
		...tile
		hidden: true
	}, config)
	assert !hidden.timeline_on
	clock.now = 3.25
	hidden.update(with_motion(tile, config))!
	assert hidden.timeline_on && hidden.timeline_start == 3.25
	// A new timeline starts over; the same one keeps running.
	hidden.update(with_motion(tile, config))!
	assert hidden.timeline_start == 3.25
	clock.now = 4
	hidden.update(with_motion(tile, compose_motion([motion_timeline(once), motion_clock(tick)])))!
	assert hidden.timeline_start == 4 && hidden.timeline == once
}

fn test_element_motion_layout_modes_present_the_old_frame() ! {
	mut clock := &TimelineTestClock{}
	tick := fn [clock] () f64 {
		return clock.now
	}
	tile := view('tile', rect(0, 0, 40, 40), BoxStyle{}, []Element{})
	mut moving := timeline_test_mount(tile, compose_motion([motion_layout(.box), motion_transition(1),
		motion_clock(tick)]))
	// The first frame is shown where it is laid out.
	moving.observe_layout(rect(0, 0, 40, 40), true)
	assert moving.current.layout_offset == Rect{}
	moving.observe_layout(rect(100, 20, 80, 40), true)
	assert moving.current.running
	assert moving.current.layout_offset == Rect{
		x:     -100
		y:     -20
		width: -40
	}
	clock.now = 0.5
	half := timeline_test_sample(mut moving).layout_offset
	assert half.x == -50 && half.y == -10 && half.width == -20
	// A new frame mid-flight starts from where the element is shown.
	moving.observe_layout(rect(0, 0, 40, 40), true)
	assert moving.current.layout_offset == Rect{
		x:     50
		y:     10
		width: 20
	}
	clock.now = 1.5
	assert timeline_test_sample(mut moving).layout_offset == Rect{}
	assert !moving.current.running
	// position moves the element and changes its size at once.
	mut sliding := timeline_test_mount(tile, compose_motion([motion_layout(.position),
		motion_transition(1), motion_clock(tick)]))
	sliding.observe_layout(rect(0, 0, 40, 40), true)
	sliding.observe_layout(rect(10, 0, 80, 40), true)
	assert sliding.current.layout_offset == Rect{
		x: -10
	}
	// Without animate, with reduced motion or without a duration it snaps.
	sliding.observe_layout(rect(30, 0, 80, 40), false)
	assert sliding.current.layout_offset == Rect{} && !sliding.layout_running
	mut reduced := timeline_test_mount(tile, compose_motion([motion_layout(.box), motion_reduced(true),
		motion_clock(tick)]))
	reduced.observe_layout(rect(0, 0, 40, 40), true)
	reduced.observe_layout(rect(50, 0, 40, 40), true)
	assert reduced.current.layout_offset == Rect{}
	mut instant := timeline_test_mount(tile, compose_motion([motion_layout(.box), motion_transition(0),
		motion_clock(tick)]))
	instant.observe_layout(rect(0, 0, 40, 40), true)
	instant.observe_layout(rect(50, 0, 40, 40), true)
	assert instant.current.layout_offset == Rect{}
	// none ignores frame changes.
	mut still := timeline_test_mount(tile, compose_motion([motion_clock(tick)]))
	still.observe_layout(rect(0, 0, 40, 40), true)
	still.observe_layout(rect(50, 0, 40, 40), true)
	assert still.current.layout_offset == Rect{}
}

fn test_element_motion_events_report_every_run() ! {
	mut clock := &TimelineTestClock{}
	log := &TimelineTestLog{}
	config := compose_motion([
		motion_fade(1),
		motion_transition(1),
		motion_layout(.position),
		motion_on(fn [log] (event MotionEvent) {
			mut events := unsafe { log }
			events.events << event
		}),
		motion_clock(fn [clock] () f64 {
			return clock.now
		}),
	])
	tile := view('tile', rect(0, 0, 40, 40), BoxStyle{}, []Element{})
	mut state := timeline_test_mount(tile, config)
	timeline_test_deliver(mut state)
	clock.now = 0.5
	timeline_test_sample(mut state)
	timeline_test_deliver(mut state)
	clock.now = 1
	timeline_test_sample(mut state)
	timeline_test_deliver(mut state)
	// Every frame of a run reports its progress, the first one included.
	assert log.kinds(.enter) == [.start, .progress, .progress, .complete]
	assert log.events.filter(it.kind == .progress).map(it.progress) == [0.0, 0.5]
	assert log.events.all(it.id == 'tile')
	// Retargeting a running transition cancels it where it was and starts another.
	state.update(with_motion(Element{ ...tile, opacity: 0.5 }, config))!
	timeline_test_deliver(mut state)
	clock.now = 1.25
	timeline_test_sample(mut state)
	timeline_test_deliver(mut state)
	state.update(with_motion(Element{ ...tile, opacity: 0.2 }, config))!
	timeline_test_deliver(mut state)
	clock.now = 3
	timeline_test_sample(mut state)
	timeline_test_deliver(mut state)
	assert log.milestones(.transition) == [.start, .cancel, .start, .complete]
	cancelled := log.events.filter(it.kind == .cancel)
	assert cancelled.len == 1 && cancelled[0].progress == 0.25
	// Layout runs report under their own source.
	state.observe_layout(rect(0, 0, 40, 40), true)
	state.observe_layout(rect(20, 0, 40, 40), true)
	timeline_test_deliver(mut state)
	clock.now = 4
	timeline_test_sample(mut state)
	timeline_test_deliver(mut state)
	assert log.kinds(.layout) == [.start, .progress, .complete]
	// Timelines report their cycles.
	timeline_log := &TimelineTestLog{}
	clock.now = 0
	pulse := motion_keyframes(1, timeline_test_key(0.5, MotionStyle{ opacity: 0.5 }))
	mut looping := timeline_test_mount(tile, compose_motion([
		motion_timeline(pulse.repeated(1)),
		motion_on(fn [timeline_log] (event MotionEvent) {
			mut events := unsafe { timeline_log }
			events.events << event
		}),
		motion_clock(fn [clock] () f64 {
			return clock.now
		}),
	]))
	timeline_test_deliver(mut looping)
	clock.now = 1.5
	timeline_test_sample(mut looping)
	timeline_test_deliver(mut looping)
	clock.now = 2.5
	timeline_test_sample(mut looping)
	timeline_test_deliver(mut looping)
	assert timeline_log.milestones(.timeline) == [.start, .complete]
	cycles := timeline_log.events.filter(it.source == .timeline && it.kind == .progress)
	assert cycles.map(it.cycle) == [0, 1]
	assert cycles.last().progress == 0.5
	assert timeline_log.events.filter(it.source == .timeline).last().progress == 1
}

fn test_motion_handle_cancels_finishes_and_restarts() ! {
	mut clock := &TimelineTestClock{}
	mut handle := &MotionHandle{}
	log := &TimelineTestLog{}
	pulse := motion_keyframes(1, timeline_test_key(1, MotionStyle{ translate_x: 100 }))
	config := compose_motion([
		motion_fade(1),
		motion_timeline(MotionTimeline{ ...pulse, hold: true }),
		motion_handle(handle),
		motion_on(fn [log] (event MotionEvent) {
			mut events := unsafe { log }
			events.events << event
		}),
		motion_clock(fn [clock] () f64 {
			return clock.now
		}),
	])
	assert !handle.mounted() && handle.values() == none
	tile := view('tile', rect(0, 0, 40, 40), BoxStyle{}, []Element{})
	mut state := timeline_test_mount(tile, config)
	timeline_test_deliver(mut state)
	assert handle.mounted() && handle.running()
	clock.now = 0.5
	timeline_test_sample(mut state)
	timeline_test_deliver(mut state)
	// cancel stops where the element is, and building it again keeps it there.
	handle.cancel()
	timeline_test_deliver(mut state)
	frozen := handle.values() or { panic('no values') }
	assert frozen.opacity == 0.5 && frozen.transform.translate_x == 50
	assert !handle.running()
	assert log.kinds(.enter).last() == .cancel
	assert log.kinds(.timeline).last() == .cancel
	clock.now = 2
	timeline_test_sample(mut state)
	state.update(with_motion(tile, config))!
	assert state.current.values == frozen
	// A changed declaration moves on from the frozen values.
	state.update(with_motion(Element{ ...tile, opacity: 0.9 }, config))!
	assert state.current.running
	// finish jumps to the end; a held timeline keeps its final values.
	handle.restart()
	assert state.timeline_on && state.timeline_start == 2
	handle.finish()
	timeline_test_deliver(mut state)
	assert !handle.running()
	finished := handle.values() or { panic('no values') }
	assert finished.opacity == 0.9 && finished.transform.translate_x == 100
	assert log.kinds(.timeline).last() == .complete
	assert log.kinds(.transition).last() == .complete
	// A disposed element releases its handle.
	state.force_cancel()
	assert !handle.mounted() && handle.values() == none
	handle.cancel()
	handle.finish()
	handle.restart()
}

fn test_reduced_motion_preference_applies_to_every_element() ! {
	mut clock := &TimelineTestClock{}
	tick := fn [clock] () f64 {
		return clock.now
	}
	assert !reduced_motion()
	set_reduced_motion(true)
	defer {
		set_reduced_motion(false)
	}
	assert reduced_motion()
	tile := view('tile', rect(0, 0, 40, 40), BoxStyle{}, []Element{})
	mut fading := timeline_test_mount(tile, compose_motion([motion_fade(1), motion_clock(tick)]))
	assert fading.current.phase == .present && fading.current.values.opacity == 1
	// A loop does not play; a held finite timeline shows where it ends.
	pulse := motion_keyframes(1, timeline_test_key(0.5, MotionStyle{ opacity: 0.5 }))
	mut looping := timeline_test_mount(tile, compose_motion([
		motion_timeline(pulse.looped()),
		motion_clock(tick),
	]))
	clock.now = 0.5
	assert !timeline_test_sample(mut looping).running
	assert looping.current.values.opacity == 1
	slide := motion_keyframes(1, timeline_test_key(1, MotionStyle{ translate_x: 100 }))
	mut held := timeline_test_mount(tile, compose_motion([
		motion_timeline(MotionTimeline{ ...slide, hold: true }),
		motion_clock(tick),
	]))
	assert held.current.values.transform.translate_x == 100
	assert !held.current.running
	// Turning it off lets the loop play again.
	set_reduced_motion(false)
	clock.now = 1.5
	assert timeline_test_sample(mut looping).running
	assert timeline_test_close(looping.current.values.opacity, 0.5)
}
