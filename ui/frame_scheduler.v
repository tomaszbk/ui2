module ui2

import sync

// Platform wake resource captured by a coordinator closure. The signal lock
// protects its descriptor lifetime independently of the renderer/window.
@[heap]
struct HostWakeSignal {
	mutex &sync.Mutex = sync.new_mutex()
mut:
	fd int = -1
}

// RenderReason describes why a custom-renderer frame was requested.
pub enum RenderReason {
	build
	layout
	paint
	surface
	animation
	// Event callbacks may update the model after animation evaluation. Build
	// their next snapshot without canceling the current animated presentation.
	animation_follow_up
	timer
	worker
	presentation
}

// RenderStats separates callbacks from actual work. Skipping builds and draws
// does not imply that the platform event loop stopped waking up.
pub struct RenderStats {
pub:
	loop_callbacks        u64
	waits                 u64
	event_wakeups         u64
	worker_wakeups        u64
	deadline_wakeups      u64
	interrupted_waits     u64
	callbacks             u64
	builds                u64
	draws                 u64
	flushes               u64
	coalesced             u64
	requests              u64
	generation            u64
	finished_generation   u64
	pending               bool
	in_flight             bool
	pending_reasons       []RenderReason
	next_deadline         i64 = -1
	animation_active      bool
	presentation_required bool
	suspended             bool
	closed                bool
}

fn (mut coordinator FrameCoordinator) build_pending() bool {
	coordinator.mutex.lock()
	defer { coordinator.mutex.unlock() }
	return RenderReason.build in coordinator.pending_reasons
}

struct FrameWork {
	generation u64
	serial     u64
	build      bool
	draw       bool
	reasons    []RenderReason
}

// Each renderer context owns one coordinator. The lock protects only scheduler
// state; builders, drawing and posted callbacks always run outside it.
@[heap]
struct FrameCoordinator {
	mutex &sync.Mutex = sync.new_mutex()
mut:
	loop_callbacks        u64
	waits                 u64
	event_wakeups         u64
	worker_wakeups        u64
	deadline_wakeups      u64
	interrupted_waits     u64
	callbacks             u64
	builds                u64
	draws                 u64
	flushes               u64
	coalesced             u64
	requests              u64
	generation            u64
	finished_generation   u64
	pending_reasons       []RenderReason
	next_serial           u64
	active_serial         u64
	next_deadline         i64 = -1
	animation_active      bool
	presentation_required bool
	suspended             bool
	closed                bool
	tasks                 []fn ()
	// A lifetime-independent platform signal: it may be invoked by a worker
	// after close races with unlock. It must stay safe after the window closes
	// and must never dereference renderer state or execute application callbacks.
	wakeup fn () = unsafe { nil }
}

fn (mut coordinator FrameCoordinator) set_wakeup(wakeup fn ()) {
	coordinator.mutex.lock()
	if !coordinator.closed {
		coordinator.wakeup = wakeup
	}
	coordinator.mutex.unlock()
}

// Release the lock before signaling the embedder. This also lets tests use a
// signal that observes the coordinator without deadlocking.
fn (mut coordinator FrameCoordinator) unlock_and_wake(changed bool) {
	wakeup := coordinator.wakeup
	closed := coordinator.closed
	coordinator.mutex.unlock()
	if changed && !closed && voidptr(wakeup) != unsafe { nil } {
		wakeup()
	}
}

// Return the next absolute monotonic deadline, or -1 for an indefinite wait.
// Business tasks still wake a suspended window; visual invalidations wait for
// restore. last_frame and interval come from the embedder's presentation clock.
fn (mut coordinator FrameCoordinator) next_wake(now i64, last_frame i64, interval i64) i64 {
	coordinator.mutex.lock()
	defer { coordinator.mutex.unlock() }
	if coordinator.closed || coordinator.active_serial != 0 {
		return -1
	}
	if coordinator.tasks.len > 0 {
		return now
	}
	if coordinator.suspended {
		return -1
	}
	if coordinator.pending_reasons.len > 0 {
		return now
	}
	mut deadline := coordinator.next_deadline
	if coordinator.animation_active {
		frame_at := if last_frame < 0 {
			now
		} else {
			last_frame + if interval > 0 { interval } else { 16 }
		}
		if deadline < 0 || frame_at < deadline {
			deadline = frame_at
		}
	}
	return deadline
}

fn new_frame_coordinator() &FrameCoordinator {
	mut coordinator := &FrameCoordinator{}
	coordinator.invalidate(.surface)
	return coordinator
}

// Some platform loops present their swapchain after every callback, even when
// UI2 issues no commands. Those backends must paint the retained declaration on
// idle callbacks until the embedder can suppress presentation itself.
fn (mut coordinator FrameCoordinator) set_presentation_required(required bool) {
	coordinator.mutex.lock()
	defer { coordinator.mutex.unlock() }
	if !coordinator.closed {
		coordinator.presentation_required = required
	}
}

fn (mut coordinator FrameCoordinator) invalidate(reason RenderReason) {
	coordinator.mutex.lock()
	was_pending := coordinator.pending_reasons.len > 0
	coordinator.invalidate_locked(reason)
	coordinator.unlock_and_wake(!was_pending)
}

fn (mut coordinator FrameCoordinator) invalidate_locked(reason RenderReason) {
	if coordinator.closed {
		return
	}
	coordinator.requests++
	coordinator.generation++
	if coordinator.pending_reasons.len > 0 {
		coordinator.coalesced++
	}
	if reason !in coordinator.pending_reasons {
		coordinator.pending_reasons << reason
	}
}

// begin_frame takes a generation snapshot and detaches its reasons. Requests
// arriving while the caller works therefore belong to the following frame.
// now and deadlines use the same caller-supplied monotonic millisecond clock.
fn (mut coordinator FrameCoordinator) begin_frame(now i64) ?FrameWork {
	coordinator.mutex.lock()
	defer { coordinator.mutex.unlock() }
	coordinator.callbacks++
	if coordinator.closed || coordinator.suspended || coordinator.active_serial != 0 {
		return none
	}
	if coordinator.next_deadline >= 0 && now >= coordinator.next_deadline {
		coordinator.next_deadline = -1
		coordinator.invalidate_locked(.timer)
	}
	if coordinator.animation_active {
		coordinator.invalidate_locked(.animation)
	}
	if coordinator.pending_reasons.len == 0
		&& !coordinator.presentation_required {
		return none
	}
	reasons := if coordinator.pending_reasons.len == 0
		&& coordinator.presentation_required {
		// This is a platform presentation requirement, not a new invalidation.
		// Keep request/generation counters about actual application work.
		[RenderReason.presentation]
	} else {
		coordinator.pending_reasons
	}
	coordinator.pending_reasons = []RenderReason{}
	coordinator.next_serial++
	coordinator.active_serial = coordinator.next_serial
	mut build := false
	for reason in reasons {
		if reason in [.build, .surface, .animation, .animation_follow_up, .worker] {
			build = true
			break
		}
	}
	return FrameWork{
		generation: coordinator.generation
		serial:     coordinator.active_serial
		build:      build
		draw:       true
		reasons:    reasons
	}
}

fn (mut coordinator FrameCoordinator) finish_frame(work FrameWork) {
	coordinator.mutex.lock()
	defer { coordinator.mutex.unlock() }
	if coordinator.closed || work.serial == 0 || coordinator.active_serial != work.serial {
		return
	}
	coordinator.active_serial = 0
	coordinator.finished_generation = work.generation
	coordinator.flushes++
}

fn (mut coordinator FrameCoordinator) record_build() {
	coordinator.mutex.lock()
	defer { coordinator.mutex.unlock() }
	coordinator.builds++
}

fn (mut coordinator FrameCoordinator) record_draw() {
	coordinator.mutex.lock()
	defer { coordinator.mutex.unlock() }
	coordinator.draws++
}

fn (mut coordinator FrameCoordinator) record_loop_callback() {
	coordinator.mutex.lock()
	defer { coordinator.mutex.unlock() }
	coordinator.loop_callbacks++
}

// The Linux host reports poll outcomes separately from renderer work. A poll
// can observe both an X11 event and a worker signal; these are not draw counts.
fn (mut coordinator FrameCoordinator) record_wait(outcome int) {
	coordinator.mutex.lock()
	defer { coordinator.mutex.unlock() }
	coordinator.waits++
	if outcome > 0 && outcome & 1 != 0 { coordinator.event_wakeups++ }
	if outcome > 0 && outcome & 2 != 0 { coordinator.worker_wakeups++ }
	if outcome == 0 { coordinator.deadline_wakeups++ }
	if outcome == -2 { coordinator.interrupted_waits++ }
}

// A negative deadline cancels the pending visual timer. The renderer combines
// its tooltip, cursor and other visual timers into the earliest deadline.
fn (mut coordinator FrameCoordinator) set_deadline(at i64) {
	coordinator.mutex.lock()
	mut changed := false
	defer { coordinator.unlock_and_wake(changed) }
	if coordinator.closed || coordinator.suspended {
		return
	}
	changed = coordinator.next_deadline != at
	coordinator.next_deadline = at
}

fn (mut coordinator FrameCoordinator) set_animation_active(active bool) {
	coordinator.mutex.lock()
	mut changed := false
	defer { coordinator.unlock_and_wake(changed) }
	if !coordinator.closed {
		changed = coordinator.animation_active != active
		coordinator.animation_active = active
	}
}

fn (mut coordinator FrameCoordinator) suspend() {
	coordinator.mutex.lock()
	defer { coordinator.mutex.unlock() }
	if !coordinator.closed {
		coordinator.suspended = true
		coordinator.next_deadline = -1
	}
}

fn (mut coordinator FrameCoordinator) resume() {
	coordinator.mutex.lock()
	mut changed := false
	defer { coordinator.unlock_and_wake(changed) }
	if coordinator.closed || !coordinator.suspended {
		return
	}
	coordinator.suspended = false
	coordinator.invalidate_locked(.surface)
	changed = true
}

fn (mut coordinator FrameCoordinator) close() {
	coordinator.mutex.lock()
	defer { coordinator.mutex.unlock() }
	coordinator.closed = true
	coordinator.suspended = false
	coordinator.animation_active = false
	coordinator.next_deadline = -1
	coordinator.active_serial = 0
	coordinator.pending_reasons = []RenderReason{}
	coordinator.tasks = []fn (){}
	coordinator.wakeup = unsafe { nil }
}

fn (mut coordinator FrameCoordinator) is_closed() bool {
	coordinator.mutex.lock()
	defer { coordinator.mutex.unlock() }
	return coordinator.closed
}

fn (mut coordinator FrameCoordinator) is_flushing() bool {
	coordinator.mutex.lock()
	defer { coordinator.mutex.unlock() }
	return coordinator.active_serial != 0
}

fn (mut coordinator FrameCoordinator) post(task fn ()) bool {
	coordinator.mutex.lock()
	mut wake := false
	defer { coordinator.unlock_and_wake(wake) }
	if coordinator.closed {
		return false
	}
	wake = coordinator.tasks.len == 0
	coordinator.tasks << task
	coordinator.invalidate_locked(.worker)
	return true
}

// The UI thread drains business callbacks even while drawing is suspended.
// A callback can post another callback or invalidate without holding this lock.
// Close and callback execution belong to the UI thread; close cancels the queue.
fn (mut coordinator FrameCoordinator) take_tasks() []fn () {
	coordinator.mutex.lock()
	defer { coordinator.mutex.unlock() }
	if coordinator.closed || coordinator.active_serial != 0 {
		return []fn (){}
	}
	tasks := coordinator.tasks
	coordinator.tasks = []fn (){}
	// A callback in an earlier batch can post another task before begin_frame.
	// Its post may have been acknowledged by that frame while the task itself
	// waited for the next drain. Delivery must still invalidate its own frame.
	if tasks.len > 0 && RenderReason.worker !in coordinator.pending_reasons {
		coordinator.invalidate_locked(.worker)
	}
	return tasks
}

fn (mut coordinator FrameCoordinator) stats() RenderStats {
	coordinator.mutex.lock()
	defer { coordinator.mutex.unlock() }
	return RenderStats{
		loop_callbacks:        coordinator.loop_callbacks
		waits:                 coordinator.waits
		event_wakeups:         coordinator.event_wakeups
		worker_wakeups:        coordinator.worker_wakeups
		deadline_wakeups:      coordinator.deadline_wakeups
		interrupted_waits:     coordinator.interrupted_waits
		callbacks:             coordinator.callbacks
		builds:                coordinator.builds
		draws:                 coordinator.draws
		flushes:               coordinator.flushes
		coalesced:             coordinator.coalesced
		requests:              coordinator.requests
		generation:            coordinator.generation
		finished_generation:   coordinator.finished_generation
		pending:               coordinator.pending_reasons.len > 0
		in_flight:             coordinator.active_serial != 0
		pending_reasons:       coordinator.pending_reasons.clone()
		next_deadline:         coordinator.next_deadline
		animation_active:      coordinator.animation_active
		presentation_required: coordinator.presentation_required
		suspended:             coordinator.suspended
		closed:                coordinator.closed
	}
}

// UiDispatcher is a lifetime-safe handle for delivering worker results to the
// custom renderer's UI thread. Capture this handle before starting the worker;
// mutate the model only inside post's callback. A closed window rejects posts.
pub struct UiDispatcher {
	coordinator &FrameCoordinator = unsafe { nil }
}

pub fn (dispatcher UiDispatcher) post(task fn ()) bool {
	if isnil(dispatcher.coordinator) {
		return false
	}
	mut coordinator := dispatcher.coordinator
	return coordinator.post(task)
}

// stats is a synchronized snapshot; reading it never requests a frame.
pub fn (dispatcher UiDispatcher) stats() RenderStats {
	if isnil(dispatcher.coordinator) {
		return RenderStats{
			closed: true
		}
	}
	mut coordinator := dispatcher.coordinator
	return coordinator.stats()
}
