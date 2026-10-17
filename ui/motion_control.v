module ui2

// Motion events, handles and the reduced motion preference. Motion has no
// registry: an element's motion is reached through its own configuration,
// whose on_motion hears what it does and whose handle controls it.

pub enum MotionEventKind {
	start    // a run began
	progress // a frame of a running run; progress is its fraction
	complete // a run reached its end
	cancel   // a run stopped before its end: replaced, interrupted or cancelled
}

// MotionEventSource is the run an event is about.
pub enum MotionEventSource {
	enter      // the element appearing: mount, unhide or reentry
	exit       // the element leaving: hide or removal
	transition // a declared value changing while shown
	layout     // a laid-out frame changing (MotionConfig.layout)
	timeline   // the element's timeline; progress is that of the current cycle
}

pub struct MotionEvent {
pub:
	// window is the window whose element moved.
	window   &Window = unsafe { nil }
	kind     MotionEventKind
	source   MotionEventSource
	id       string // the element's id
	progress f64
	cycle    int // timeline cycles completed before this one
}

// MotionEventFn hears an element's motion events. Events are delivered on the
// UI thread after a frame has sampled every element, in tree order; a frame
// that delivered one builds again, so a handler may change application state.
pub type MotionEventFn = fn (MotionEvent)

struct MotionDispatch {
	callback MotionEventFn = unsafe { nil }
	event    MotionEvent
}

fn motion_event_source(phase PresencePhase) MotionEventSource {
	return match phase {
		.entering { .enter }
		.exiting, .absent { .exit }
		.present { .transition }
	}
}

// emit_events compares the state with what the previous delivery saw and
// appends the events that happened since. A run replaced between deliveries
// reports cancel at the progress last delivered. The sink keeps its capacity,
// so a running element's progress events allocate nothing.
fn (mut state ElementMotionState) emit_events(id string, mut sink []MotionDispatch) {
	callback := state.config.on_motion
	report := callback != unsafe { nil }
	controller := &state.controller
	mut seen := &state.seen
	if controller.serial != seen.serial {
		if seen.running && report {
			sink << motion_dispatch(callback, .cancel, seen.source, id, seen.progress, 0)
		}
		seen.serial = controller.serial
		seen.source = motion_event_source(controller.run_phase)
		seen.running = true
		seen.progress = 0
		if report {
			sink << motion_dispatch(callback, .start, seen.source, id, 0, 0)
		}
	}
	if seen.running {
		if controller.running {
			seen.progress = controller.progress
			if report {
				sink << motion_dispatch(callback, .progress, seen.source, id, controller.progress,
					0)
			}
		} else {
			seen.running = false
			if report {
				sink << motion_dispatch(callback, if controller.progress >= 1 {
					MotionEventKind.complete
				} else {
					MotionEventKind.cancel
				}, seen.source, id, controller.progress, 0)
			}
		}
	}
	if state.layout_serial != seen.layout_serial {
		if seen.layout_running && report {
			sink << motion_dispatch(callback, .cancel, .layout, id, seen.layout_progress, 0)
		}
		seen.layout_serial = state.layout_serial
		seen.layout_running = true
		seen.layout_progress = 0
		if report {
			sink << motion_dispatch(callback, .start, .layout, id, 0, 0)
		}
	}
	if seen.layout_running {
		if state.layout_running {
			seen.layout_progress = state.layout_progress
			if report {
				sink << motion_dispatch(callback, .progress, .layout, id, state.layout_progress,
					0)
			}
		} else {
			seen.layout_running = false
			if report {
				sink << motion_dispatch(callback, if state.layout_progress >= 1 {
					MotionEventKind.complete
				} else {
					MotionEventKind.cancel
				}, .layout, id, state.layout_progress, 0)
			}
		}
	}
	if state.timeline_serial != seen.timeline_serial {
		if seen.timeline_running && report {
			sink << motion_dispatch(callback, .cancel, .timeline, id, seen.timeline_progress,
				seen.timeline_cycle)
		}
		seen.timeline_serial = state.timeline_serial
		seen.timeline_running = true
		seen.timeline_cycle = 0
		seen.timeline_progress = 0
		if report {
			sink << motion_dispatch(callback, .start, .timeline, id, 0, 0)
		}
	}
	if seen.timeline_running {
		playing := state.timeline_on && !state.timeline_completed && !state.reduced()
		if playing {
			seen.timeline_cycle = state.timeline_cycle
			seen.timeline_progress = state.timeline_progress
			if report {
				sink << motion_dispatch(callback, .progress, .timeline, id, state.timeline_progress,
					state.timeline_cycle)
			}
		} else {
			seen.timeline_running = false
			if report {
				sink << motion_dispatch(callback, if state.timeline_completed {
					MotionEventKind.complete
				} else {
					MotionEventKind.cancel
				}, .timeline, id, if state.timeline_completed {
					1.0
				} else {
					state.timeline_progress
				}, state.timeline_cycle)
			}
		}
	}
}

fn motion_dispatch(callback MotionEventFn, kind MotionEventKind, source MotionEventSource, id string, progress f64, cycle int) MotionDispatch {
	return MotionDispatch{
		callback: callback
		event:    MotionEvent{
			kind:     kind
			source:   source
			id:       id
			progress: progress
			cycle:    cycle
		}
	}
}

// MotionHandle controls the motion of the element whose MotionConfig.handle
// it is, while that element is mounted. Create one per element with
// `&MotionHandle{}` and keep it with the state that builds the element.
@[heap]
pub struct MotionHandle {
mut:
	state &ElementMotionState = unsafe { nil }
}

// mounted reports whether an element is attached to the handle.
pub fn (handle &MotionHandle) mounted() bool {
	return handle.state != unsafe { nil } && !handle.state.disposed
}

// running reports whether any of the element's motion is running: a
// transition, a layout change or a timeline that has not ended.
pub fn (handle &MotionHandle) running() bool {
	return handle.mounted() && handle.state.current.running
}

// values is what the element presents at the last sampled frame.
pub fn (handle &MotionHandle) values() ?MotionValues {
	if !handle.mounted() {
		return none
	}
	return handle.state.current.values
}

// cancel stops every running motion where it stands, like Kivy's cancel: a
// transition keeps the values it reached, a timeline stops until restart and a
// layout change shows the new frame. Each stopped run reports cancel. The
// element shows those values until its declaration changes again.
pub fn (mut handle MotionHandle) cancel() {
	if !handle.mounted() {
		return
	}
	mut state := handle.state
	now := state.now()
	state.present_at(now) or { return }
	state.controller.freeze_at(state.current.values, now) or {}
	state.timeline_on = false
	state.layout_running = false
	state.layout_progress = 0
	state.present_at(now) or {}
	state.wake_window()
}

// finish ends every running motion at once, like Kivy's stop: a transition
// jumps to its target, a finite timeline to its end and a looping one stops;
// layout shows the new frame. Each finished run reports complete.
pub fn (mut handle MotionHandle) finish() {
	if !handle.mounted() {
		return
	}
	mut state := handle.state
	now := state.now()
	state.controller.finish_at(now) or { return }
	if state.timeline_on {
		state.timeline_completed = true
		if !state.program.hold || state.program.repeat == motion_forever {
			state.timeline_on = false
		} else {
			// A held finite timeline keeps its final values.
			state.timeline_start = now - state.program.end()
		}
	}
	if state.layout_running {
		state.layout_running = false
		state.layout_progress = 1
	}
	state.present_at(now) or {}
	state.wake_window()
}

// restart plays the element's timeline again from its start.
pub fn (mut handle MotionHandle) restart() {
	if !handle.mounted() {
		return
	}
	mut state := handle.state
	now := state.now()
	if state.timeline_on {
		state.release_timeline(state.current.values, now)
	}
	state.start_timeline(now)
	state.present_at(now) or {}
	state.wake_window()
}

fn (mut state ElementMotionState) link_handle() {
	mut handle := state.config.handle
	if handle != unsafe { nil } {
		handle.state = state
	}
}

fn (mut state ElementMotionState) unlink_handle() {
	mut handle := state.config.handle
	if handle != unsafe { nil } && handle.state == state {
		handle.state = unsafe { nil }
	}
}

// wake_window asks the window that shows the element for a frame, after a
// handle changed its motion outside a frame.
fn (state &ElementMotionState) wake_window() {
	if state.window != unsafe { nil } {
		mut w := state.window
		w.backend_invalidate(.motion)
	}
}
