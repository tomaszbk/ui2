module ui2

import math

// MotionLayoutMode is how an element presents a change of its laid-out frame.
// Layout runs once with the new frame; the element then animates from where it
// was shown to its new frame by presentation alone, as FLIP does in browsers,
// over the element's transition.
pub enum MotionLayoutMode {
	none // frame changes show at once
	// box moves the element and resizes its own fill, border and shadow. Its
	// text and children keep their new layout and only move, so nothing stretches.
	box
	position // only the position animates; the size changes at once
	// scale maps the element and its whole content from the old frame, the
	// classic FLIP transform. Text scales with it, which is how a font size
	// change can animate without laying text out on every frame.
	scale
}

// MotionTarget plays a timeline on the descendant whose public id is id, so
// one element can orchestrate its children. A descendant without motion of its
// own runs it on the targeting element's clock and reduced motion setting; a
// timeline in the descendant's own MotionConfig takes precedence. Several
// targets on one id play together and must animate different channels.
pub struct MotionTarget {
pub:
	id       string
	timeline MotionTimeline
}

// MotionConfig belongs to one retained element. Present values are the
// element's declared opacity, transform and paint; enter and exit are partial
// styles over them. transition animates a declared value that changes while
// the element is shown and, with layout, a frame that changes; timeline plays
// keyframes over the presentation while the element is mounted.
pub struct MotionConfig {
pub:
	enter            MotionStyle = MotionStyle{
		opacity: 0
	}
	exit             MotionStyle = MotionStyle{
		opacity: 0
	}
	enter_transition MotionTransition = MotionTransition{
		duration: 0.18
	}
	exit_transition  MotionTransition = MotionTransition{
		duration: 0.12
	}
	transition       MotionTransition
	layout           MotionLayoutMode
	timeline         MotionTimeline
	targets          []MotionTarget
	on_motion        MotionEventFn = unsafe { nil }
	handle           &MotionHandle = unsafe { nil }
	clock            MotionClock   = unsafe { nil }
	reduced_motion   bool
}

pub fn with_motion(element Element, config MotionConfig) Element {
	return Element{
		...element
		motion: config
	}
}

pub fn (config MotionConfig) validate() ! {
	config.enter.validate()!
	config.exit.validate()!
	config.enter_transition.validate()!
	config.exit_transition.validate()!
	config.transition.validate()!
	if !config.timeline.is_empty() {
		config.timeline.validate()!
	}
	for target in config.targets {
		if target.id.len == 0 {
			return error('a motion target needs an element id')
		}
		target.timeline.validate()!
	}
}

// The host samples this state before layout/input/rendering. Reading its cached
// presentation does not advance a clock, so every consumer sees one frame.
@[heap]
struct ElementMotionState {
mut:
	// The window that shows the element: its app's reduced motion
	// preference applies, and handles wake it.
	window          &Window = unsafe { nil }
	controller      MotionController
	config          MotionConfig
	target          MotionValues
	authored_hidden bool
	mounted         bool
	disposed        bool
	structural_exit bool
	current         MotionSample
	completion      fn () = unsafe { nil }
	// The timeline an ancestor's MotionConfig.targets assigns, set by the tree.
	target_timeline MotionTimeline
	// The timeline playing, compiled once when it changes.
	timeline           MotionTimeline
	program            MotionProgram
	timeline_on        bool
	timeline_start     f64
	timeline_serial    u64
	timeline_progress  f64
	timeline_cycle     int
	timeline_completed bool
	// Layout transitions present offsets from the observed laid-out frame.
	layout_seen     bool
	layout_frame    Rect
	layout_from     Rect
	layout_start    f64
	layout_running  bool
	layout_serial   u64
	layout_progress f64
	// What the last event delivery saw, so events follow state changes.
	seen MotionEventCursor
}

struct MotionEventCursor {
mut:
	serial            u64
	running           bool
	source            MotionEventSource
	progress          f64
	layout_serial     u64
	layout_running    bool
	layout_progress   f64
	timeline_serial   u64
	timeline_running  bool
	timeline_cycle    int
	timeline_progress f64
}

// element_motion_values is an element's declared presentation.
fn element_motion_values(element Element) MotionValues {
	return MotionValues{
		opacity:   element.opacity
		transform: element.authored_visual_transform()
		paint:     element_motion_paint(element)
	}
}

fn element_motion_paint(element Element) MotionPaint {
	return MotionPaint{
		background:   element.box.bg
		border_color: element.box.border_color
		text_color:   element.text_style.color
		radius:       element.box.radius
		shadow:       element.box.shadow
	}
}

fn new_element_motion_state(element Element, window &Window) !&ElementMotionState {
	config := element.motion or { return error('element motion requires a configuration') }
	return new_motion_state_for(element, config, window)!
}

// new_motion_state_for also serves elements a timeline targets without a
// configuration of their own.
fn new_motion_state_for(element Element, config MotionConfig, window &Window) !&ElementMotionState {
	config.validate()!
	target := element_motion_values(element)
	target.validate()!
	reduced := config.reduced_motion || window.prefers_reduced_motion()
	if !reduced {
		if config.enter_transition.duration > 0 {
			validate_motion_path(config.enter.over(target), target)!
		}
		if config.exit_transition.duration > 0 {
			validate_motion_path(target, config.exit.over(target))!
		}
	}
	mut controller := new_motion_controller(MotionControllerConfig{
		initial:        config.enter.over(target)
		clock:          config.clock
		reduced_motion: reduced
	})!
	mut state := &ElementMotionState{
		window:          window
		controller:      controller
		config:          config
		target:          target
		authored_hidden: element.hidden
		current:         controller.sample()!
	}
	state.timeline = state.effective_timeline()
	if !state.timeline.is_empty() {
		state.program = compile_motion_timeline(state.timeline)!
	}
	return state
}

fn (state &ElementMotionState) reduced() bool {
	return state.config.reduced_motion || state.window.prefers_reduced_motion()
}

fn (state &ElementMotionState) effective_timeline() MotionTimeline {
	return if state.config.timeline.is_empty() {
		state.target_timeline
	} else {
		state.config.timeline
	}
}

fn (state &ElementMotionState) now() f64 {
	return state.controller.clock()
}

fn (mut state ElementMotionState) mount() ! {
	if state.disposed || state.mounted {
		return
	}
	now := state.now()
	if !state.authored_hidden {
		state.controller.set_present_at(true, state.target, state.config.enter_transition,
			now)!
	}
	state.mounted = true
	state.link_handle()
	state.start_timeline(now)
	state.present_at(now)!
}

// A property effect updates authored targets. A retained structural exit keeps
// its exit target even when a service or signal changes while it is leaving.
fn (mut state ElementMotionState) update(element Element) ! {
	if state.disposed {
		return
	}
	if config := element.motion {
		state.configure(config)!
	}
	state.update_values(element)!
}

fn (mut state ElementMotionState) configure(config MotionConfig) ! {
	if config == state.config {
		return
	}
	config.validate()!
	if voidptr(config.clock) != voidptr(state.config.clock) {
		if state.mounted {
			return error('an element motion clock cannot change while mounted')
		}
		state.controller = new_motion_controller(MotionControllerConfig{
			initial:        config.enter.over(state.target)
			clock:          config.clock
			reduced_motion: config.reduced_motion || state.window.prefers_reduced_motion()
		})!
	}
	if state.config.handle != config.handle {
		state.unlink_handle()
	}
	state.config = config
	state.controller.set_reduced_motion(state.reduced())
	if state.mounted {
		state.link_handle()
	}
}

fn (mut state ElementMotionState) update_values(element Element) ! {
	target := element_motion_values(element)
	target.validate()!
	was_hidden := state.authored_hidden
	declared := state.target
	state.target = target
	state.authored_hidden = element.hidden
	now := state.now()
	if state.mounted && !state.structural_exit {
		if element.hidden {
			state.controller.set_present_at(false, state.config.exit.over(target), state.config.exit_transition,
				now)!
		} else if was_hidden {
			state.controller.set_present_at(true, target, state.config.enter_transition,
				now)!
			state.start_timeline(now)
		} else if target != declared {
			// An unchanged declaration leaves the presentation alone, so values
			// a handle froze stay until the declaration changes.
			state.controller.set_present_at(true, target, state.config.transition, now)!
		}
	}
	state.sync_timeline(now)!
	state.present_at(now)!
}

// sync_timeline follows a changed timeline: the new one starts over the values
// shown, which glide back to the declaration beneath it.
fn (mut state ElementMotionState) sync_timeline(now f64) ! {
	next := state.effective_timeline()
	if next == state.timeline {
		return
	}
	program := if next.is_empty() { MotionProgram{} } else { compile_motion_timeline(next)! }
	if state.timeline_on {
		state.release_timeline(state.current.values, now)
	}
	state.timeline = next
	state.program = program
	state.start_timeline(now)
}

fn (mut state ElementMotionState) start_timeline(now f64) {
	state.timeline_on = state.mounted && !state.authored_hidden && state.program.tracks.len > 0
	state.timeline_start = now
	state.timeline_progress = 0
	state.timeline_cycle = 0
	state.timeline_completed = false
	if state.timeline_on {
		state.timeline_serial++
	}
}

// release_timeline hands the channels a timeline held back to the
// declaration, gliding from values with the element's transition.
fn (mut state ElementMotionState) release_timeline(values MotionValues, now f64) {
	state.timeline_on = false
	state.controller.rebase_at(values, state.config.transition, now) or {}
}

// False means removal is immediate and completion is never called. Deferred
// exits retain one callback; reentry or forced owner cleanup cancels that hook.
fn (mut state ElementMotionState) begin_exit(completion fn ()) !bool {
	if state.disposed || !state.mounted {
		return false
	}
	previous := state.completion
	already_exiting := state.structural_exit
	state.structural_exit = true
	now := state.now()
	state.controller.set_present_at(false, state.config.exit.over(state.target), state.config.exit_transition,
		now)!
	state.present_at(now)!
	if state.current.phase == .absent {
		return false
	}
	if already_exiting && previous != unsafe { nil } {
		state.completion = if completion == unsafe { nil } {
			previous
		} else {
			fn [previous, completion] () {
				previous()
				completion()
			}
		}
	} else {
		state.completion = completion
	}
	return true
}

fn (mut state ElementMotionState) resume_enter() ! {
	if state.disposed {
		return
	}
	state.completion = unsafe { nil }
	state.structural_exit = false
	now := state.now()
	if state.mounted && !state.authored_hidden {
		was_absent := state.current.phase == .absent
		state.controller.set_present_at(true, state.target, state.config.enter_transition,
			now)!
		if was_absent {
			state.start_timeline(now)
		}
	}
	state.present_at(now)!
}

fn (mut state ElementMotionState) sample() !MotionSample {
	return state.sample_at(state.now())!
}

fn (mut state ElementMotionState) sample_at(now f64) !MotionSample {
	if !state.disposed {
		state.present_at(now)!
		state.deliver_completion()
	}
	return state.current
}

// present_at composes the presentation of one frame: the controller's
// transition, the timeline over it and the layout offset. It allocates nothing.
fn (mut state ElementMotionState) present_at(now f64) ! {
	reduced := state.reduced()
	if reduced != state.controller.reduced_motion {
		state.controller.set_reduced_motion(reduced)
	}
	base := state.controller.sample_at(now)!
	mut values := base.values
	mut running := base.running
	if state.timeline_on && base.phase == .absent {
		state.timeline_on = false
	}
	if state.timeline_on && reduced {
		// Reduced motion plays no timeline; a held one shows where it ends.
		if state.program.hold && state.program.repeat != motion_forever {
			position := state.program.locate(state.program.end())
			mut channels := motion_channels(values)
			state.program.apply(mut channels, position.time)
			values = channels.values()
		}
	} else if state.timeline_on {
		position := state.program.locate(now - state.timeline_start)
		state.timeline_progress = position.progress
		state.timeline_cycle = position.cycle
		if position.started && (!position.done || state.program.hold) {
			mut channels := motion_channels(values)
			state.program.apply(mut channels, position.time)
			values = channels.values()
		}
		if !position.done {
			running = true
		} else if !state.program.hold {
			state.timeline_completed = true
			mut channels := motion_channels(values)
			state.program.apply(mut channels, position.time)
			state.release_timeline(channels.values(), now)
			resumed := state.controller.sample_at(now)!
			values = resumed.values
			running = resumed.running
		} else {
			state.timeline_completed = true
		}
	}
	mut offset := Rect{}
	if state.layout_running {
		duration := state.config.transition.duration
		progress := if duration > 0 { (now - state.layout_start) / duration } else { 1.0 }
		eased := state.config.transition.ease(math.max(0.0, progress))
		if progress >= 1 || reduced || !finite_number(eased) {
			state.layout_running = false
			state.layout_progress = 1
		} else {
			remaining := 1 - eased
			from := state.layout_from
			offset = Rect{
				x:      from.x * remaining
				y:      from.y * remaining
				width:  math.max(from.width * remaining, 1e-3 - state.layout_frame.width)
				height: math.max(from.height * remaining, 1e-3 - state.layout_frame.height)
			}
			state.layout_progress = progress
			running = true
		}
	}
	state.current = MotionSample{
		values:        values
		phase:         base.phase
		running:       running
		progress:      base.progress
		layout_offset: offset
	}
}

// observe_layout follows the element's laid-out frame, in its parent's
// coordinates. A changed frame starts from where the element was shown.
fn (mut state ElementMotionState) observe_layout(frame Rect, animate bool) {
	if state.disposed || !state.mounted {
		return
	}
	mode := state.config.layout
	if !state.layout_seen || !animate || mode == .none || state.reduced()
		|| state.current.phase == .absent || state.config.transition.duration <= 0 {
		state.layout_seen = true
		state.layout_frame = frame
		if state.layout_running {
			state.layout_running = false
			state.current = MotionSample{
				...state.current
				layout_offset: Rect{}
			}
		}
		return
	}
	if frame == state.layout_frame {
		return
	}
	shown := state.current.layout_offset
	old := state.layout_frame
	mut from := Rect{
		x:      old.x + shown.x - frame.x
		y:      old.y + shown.y - frame.y
		width:  old.width + shown.width - frame.width
		height: old.height + shown.height - frame.height
	}
	if mode == .position {
		from = Rect{
			x: from.x
			y: from.y
		}
	}
	state.layout_frame = frame
	if from == Rect{} || (mode == .scale && (frame.width <= 0 || frame.height <= 0)) {
		state.layout_running = false
		state.current = MotionSample{
			...state.current
			layout_offset: Rect{}
		}
		return
	}
	state.layout_from = from
	state.layout_start = state.now()
	state.layout_running = true
	state.layout_progress = 0
	state.layout_serial++
	state.current = MotionSample{
		...state.current
		running:       true
		layout_offset: from
	}
}

fn (mut state ElementMotionState) deliver_completion() {
	if !state.structural_exit || state.current.phase != .absent || state.completion == unsafe { nil } {
		return
	}
	completion := state.completion
	state.completion = unsafe { nil }
	completion()
}

fn (mut state ElementMotionState) force_cancel() {
	if state.disposed {
		return
	}
	state.disposed = true
	state.completion = unsafe { nil }
	state.structural_exit = false
	state.timeline_on = false
	state.layout_running = false
	state.unlink_handle()
	state.current = MotionSample{
		...state.current
		phase:         .absent
		running:       false
		layout_offset: Rect{}
	}
}

fn (state &ElementMotionState) presented_hidden(_authored bool) bool {
	return state.disposed || state.current.phase == .absent
}

fn (state &ElementMotionState) input_enabled() bool {
	return !state.disposed && !state.structural_exit && !state.authored_hidden
		&& state.current.phase != .absent
}

// The node owns its motion state; its declaration links the node's runtime
// record so every projection and output of the node presents the same state.
fn (mut node CompiledVmlNode) update_motion(element Element) !Element {
	mut motion_state := node.motion_state
	if element.motion == none {
		if motion_state != unsafe { nil } {
			// Removing a configuration makes its pending exit immediate. Forced
			// owner cleanup uses force_cancel instead and drops the callback.
			completion := motion_state.completion
			motion_state.force_cancel()
			node.motion_state = unsafe { nil }
			if completion != unsafe { nil } {
				completion()
			}
		}
		return Element{
			...element
			runtime: unsafe { nil }
		}
	}
	if motion_state == unsafe { nil } {
		if _ := element.motion {
			motion_state = new_element_motion_state(element, node.component.host_window())!
			node.motion_state = motion_state
			node.component.on_cleanup('motion:' + node.local_id, fn [mut node] () {
				if node.motion_state != unsafe { nil } {
					node.motion_state.force_cancel()
				}
			})!
			if node.live() {
				motion_state.mount()!
			}
		}
	} else {
		motion_state.update(element)!
	}
	if node.motion_runtime == unsafe { nil } || node.motion_runtime.motion_state != motion_state {
		node.motion_runtime = &ElementRuntime{
			motion_state: motion_state
		}
	}
	return Element{
		...element
		runtime: node.motion_runtime
	}
}

fn (mut node CompiledVmlNode) prepare_motion_mount() ! {
	if node.motion_state != unsafe { nil } {
		node.motion_state.mount()!
	}
	for mut child in node.children {
		child.prepare_motion_mount()!
	}
}

@[heap]
struct VmlPresenceExit {
mut:
	remaining  int
	completion fn () = unsafe { nil }
}

fn (mut pending VmlPresenceExit) complete() {
	if pending.remaining <= 0 {
		return
	}
	pending.remaining--
	if pending.remaining == 0 && pending.completion != unsafe { nil } {
		completion := pending.completion
		pending.completion = unsafe { nil }
		completion()
	}
}

fn (mut node CompiledVmlNode) begin_presence_exit(mut pending VmlPresenceExit) ! {
	if node.motion_state != unsafe { nil } {
		started := node.motion_state.begin_exit(fn [mut pending] () {
			pending.complete()
		})!
		if started {
			pending.remaining++
		}
	}
	for mut child in node.children {
		child.begin_presence_exit(mut pending)!
	}
}

fn (mut node CompiledVmlNode) resume_presence_enter(owner &CompiledVmlComponent) ! {
	// An inner list's removed item keeps its own exit even when an ancestor
	// comes back. Its scope, completion and logical removal remain independent.
	if node.component != owner && node.component.leaving {
		return
	}
	if node.motion_state != unsafe { nil } {
		node.motion_state.resume_enter()!
	}
	for mut child in node.children {
		child.resume_presence_enter(owner)!
	}
}
