module ui2

// MotionConfig belongs to one retained element. Present targets are the
// element's ordinary opacity and transform; enter and exit are explicit styles.
pub struct MotionConfig {
pub:
	enter            MotionStyle      = MotionStyle{ opacity: 0 }
	exit             MotionStyle      = MotionStyle{ opacity: 0 }
	enter_transition MotionTransition = MotionTransition{ duration: 0.18 }
	exit_transition  MotionTransition = MotionTransition{ duration: 0.12 }
	transition       MotionTransition
	clock            MotionClock = unsafe { nil }
	reduced_motion   bool
}

pub fn with_motion(element Element, config MotionConfig) Element {
	return Element{ ...element, motion: config }
}

pub fn (config MotionConfig) validate() ! {
	config.enter.validate()!
	config.exit.validate()!
	config.enter_transition.validate()!
	config.exit_transition.validate()!
	config.transition.validate()!
}

// The host samples this state before layout/input/rendering. Reading its cached
// presentation does not advance a clock, so every consumer sees one frame.
@[heap]
struct ElementMotionState {
mut:
	controller      MotionController
	config          MotionConfig
	target          MotionStyle
	authored_hidden bool
	mounted         bool
	disposed        bool
	structural_exit bool
	current         MotionSample
	completion      fn () = unsafe { nil }
}

fn element_motion_target(element Element) MotionStyle {
	return MotionStyle{ opacity: element.opacity, transform: element.authored_visual_transform() }
}

fn new_element_motion_state(element Element) !&ElementMotionState {
	config := element.motion or { return error('element motion requires a configuration') }
	config.validate()!
	target := element_motion_target(element)
	target.validate()!
	if !config.reduced_motion {
		if config.enter_transition.duration > 0 { validate_motion_path(config.enter, target)! }
		if config.exit_transition.duration > 0 { validate_motion_path(target, config.exit)! }
	}
	mut controller := new_motion_controller(MotionControllerConfig{
		initial:        config.enter
		clock:          config.clock
		reduced_motion: config.reduced_motion
	})!
	return &ElementMotionState{
		controller:      controller
		config:          config
		target:          target
		authored_hidden: element.hidden
		current:         controller.sample()!
	}
}

fn (mut state ElementMotionState) mount() ! {
	if state.disposed || state.mounted { return }
	if !state.authored_hidden {
		state.controller.set_present(true, state.target, state.config.enter_transition)!
	}
	state.refresh_sample()!
	state.mounted = true
}

// A property effect updates authored targets. A retained structural exit keeps
// its exit target even when a service or signal changes while it is leaving.
fn (mut state ElementMotionState) update(element Element) ! {
	if state.disposed { return }
	if config := element.motion {
		config.validate()!
		if state.mounted && voidptr(config.clock) != voidptr(state.config.clock) {
			return error('an element motion clock cannot change while mounted')
		}
		if !state.mounted && voidptr(config.clock) != voidptr(state.config.clock) {
			state.controller = new_motion_controller(MotionControllerConfig{
				initial:        config.enter
				clock:          config.clock
				reduced_motion: config.reduced_motion
			})!
		}
		state.config = config
		state.controller.set_reduced_motion(config.reduced_motion)
	}
	target := element_motion_target(element)
	target.validate()!
	was_hidden := state.authored_hidden
	state.target = target
	state.authored_hidden = element.hidden
	if state.mounted && !state.structural_exit {
		if element.hidden {
			state.controller.set_present(false, state.config.exit, state.config.exit_transition)!
		} else if was_hidden {
			state.controller.set_present(true, target, state.config.enter_transition)!
		} else {
			state.controller.set_present(true, target, state.config.transition)!
		}
	}
	state.refresh_sample()!
}

// False means removal is immediate and completion is never called. Deferred
// exits retain one callback; reentry or forced owner cleanup cancels that hook.
fn (mut state ElementMotionState) begin_exit(completion fn ()) !bool {
	if state.disposed || !state.mounted { return false }
	previous := state.completion
	already_exiting := state.structural_exit
	state.structural_exit = true
	state.controller.set_present(false, state.config.exit, state.config.exit_transition)!
	state.refresh_sample()!
	if state.current.phase == .absent { return false }
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
	if state.disposed { return }
	state.completion = unsafe { nil }
	state.structural_exit = false
	if state.mounted && !state.authored_hidden {
		state.controller.set_present(true, state.target, state.config.enter_transition)!
	}
	state.refresh_sample()!
}

fn (mut state ElementMotionState) refresh_sample() ! {
	state.current = state.controller.sample()!
}

fn (mut state ElementMotionState) sample() !MotionSample {
	if !state.disposed {
		state.current = state.controller.sample()!
		state.deliver_completion()
	}
	return state.current
}

fn (mut state ElementMotionState) sample_at(now f64) !MotionSample {
	if !state.disposed {
		state.current = state.controller.sample_at(now)!
		state.deliver_completion()
	}
	return state.current
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
	if state.disposed { return }
	state.disposed = true
	state.completion = unsafe { nil }
	state.structural_exit = false
	state.current = MotionSample{ ...state.current, phase: .absent, running: false }
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
			if completion != unsafe { nil } { completion() }
		}
		return Element{ ...element, runtime: unsafe { nil } }
	}
	if motion_state == unsafe { nil } {
		if _ := element.motion {
			motion_state = new_element_motion_state(element)!
			node.motion_state = motion_state
			node.component.on_cleanup('motion:' + node.local_id, fn [mut node] () {
				if node.motion_state != unsafe { nil } { node.motion_state.force_cancel() }
			})!
			if node.mounted { motion_state.mount()! }
		}
	} else {
		motion_state.update(element)!
	}
	if node.motion_runtime == unsafe { nil } || node.motion_runtime.motion_state != motion_state {
		node.motion_runtime = &ElementRuntime{ motion_state: motion_state }
	}
	return Element{ ...element, runtime: node.motion_runtime }
}

fn (mut node CompiledVmlNode) prepare_motion_mount() ! {
	if node.motion_state != unsafe { nil } { node.motion_state.mount()! }
	for mut child in node.children { child.prepare_motion_mount()! }
}

@[heap]
struct VmlPresenceExit {
mut:
	remaining  int
	completion fn () = unsafe { nil }
}

fn (mut pending VmlPresenceExit) complete() {
	if pending.remaining <= 0 { return }
	pending.remaining--
	if pending.remaining == 0 && pending.completion != unsafe { nil } {
		completion := pending.completion
		pending.completion = unsafe { nil }
		completion()
	}
}

fn (mut node CompiledVmlNode) begin_presence_exit(mut pending VmlPresenceExit) ! {
	if node.motion_state != unsafe { nil } {
		if node.motion_state.begin_exit(fn [mut pending] () { pending.complete() })! {
			pending.remaining++
		}
	}
	for mut child in node.children { child.begin_presence_exit(mut pending)! }
}

fn (mut node CompiledVmlNode) resume_presence_enter(owner &CompiledVmlComponent) ! {
	// An inner list's removed item keeps its own exit even when an ancestor
	// comes back. Its scope, completion and logical removal remain independent.
	if node.component != owner && node.component.leaving { return }
	if node.motion_state != unsafe { nil } {
		node.motion_state.resume_enter()!
	}
	for mut child in node.children { child.resume_presence_enter(owner)! }
}
