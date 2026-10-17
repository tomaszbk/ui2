module ui2

import math
import sync
import time

// TimerFn runs on the UI thread, where it may change application state; the
// window is rebuilt afterwards so the change shows.
pub type TimerFn = fn ()

// TimerId names a pending `after` call so it can be cancelled. Zero is never
// handed out.
pub type TimerId = u64

struct PendingTimer {
	deadline i64 // time.ticks() milliseconds
	callback TimerFn = unsafe { nil }
}

struct DueTimer {
	id       u64
	deadline i64
}

// TimerRuntime holds a window's pending `after` callbacks. Every backend's
// Window keeps one as `timers`. `after` may be called from any thread, so the
// table is locked.
@[heap]
struct TimerRuntime {
	mutex &sync.Mutex = sync.new_mutex()
mut:
	next    u64
	pending map[u64]PendingTimer
}

// after runs callback on the window's UI thread once `seconds` have passed,
// and then rebuilds the window. It is how a toast dismisses itself or a
// debounce fires without the application owning a thread. A negative, NaN or
// infinite delay runs at the next build. Pass the returned id to cancel_timer
// to call it off.
//
// Callbacks run on the UI thread just before the window's next build, so
// whatever they change is in the tree that build declares.
pub fn (mut w Window) after(seconds f64, callback TimerFn) TimerId {
	delay := if math.is_nan(seconds) || math.is_inf(seconds, 0) || seconds <= 0 {
		i64(0)
	} else {
		i64(math.ceil(seconds * 1000.0))
	}
	mut runtime := w.timers
	runtime.mutex.lock()
	runtime.next++
	id := runtime.next
	runtime.pending[id] = PendingTimer{
		deadline: time.ticks() + delay
		callback: callback
	}
	runtime.mutex.unlock()
	spawn timer_wake_after(w, delay)
	return TimerId(id)
}

// cancel_timer calls off a pending `after`. It reports whether the timer was
// still pending; a timer whose callback has already run cannot be cancelled.
pub fn (mut w Window) cancel_timer(id TimerId) bool {
	mut runtime := w.timers
	runtime.mutex.lock()
	pending := u64(id) in runtime.pending
	runtime.pending.delete(u64(id))
	runtime.mutex.unlock()
	return pending
}

// timer_pending reports whether an `after` callback has yet to run.
pub fn (w &Window) timer_pending(id TimerId) bool {
	runtime := w.timers
	runtime.mutex.lock()
	pending := u64(id) in runtime.pending
	runtime.mutex.unlock()
	return pending
}

// The waiting thread only asks the window for a build; the callback itself
// runs on the UI thread before that build, never on this one. A window that
// has closed meanwhile ignores the request.
fn timer_wake_after(window &Window, delay i64) {
	if delay > 0 {
		time.sleep(delay * time.millisecond)
	}
	mut w := unsafe { window }
	w.backend_invalidate(.build)
}

// run_due runs, in deadline order, every callback whose time has come
// by `now`, and reports whether any did. Callbacks are taken out of the table
// before they run, so one may schedule or cancel timers itself.
fn (mut runtime TimerRuntime) run_due(now i64) bool {
	runtime.mutex.lock()
	mut due := []DueTimer{}
	for id, timer in runtime.pending {
		if timer.deadline <= now {
			due << DueTimer{
				id:       id
				deadline: timer.deadline
			}
		}
	}
	due.sort_with_compare(fn (a &DueTimer, b &DueTimer) int {
		if a.deadline != b.deadline {
			return if a.deadline < b.deadline { -1 } else { 1 }
		}
		return if a.id < b.id { -1 } else { 1 }
	})
	mut callbacks := []TimerFn{cap: due.len}
	for timer in due {
		callbacks << runtime.pending[timer.id].callback
		runtime.pending.delete(timer.id)
	}
	runtime.mutex.unlock()
	for callback in callbacks {
		if voidptr(callback) != unsafe { nil } {
			callback()
		}
	}
	return callbacks.len > 0
}

// run_due_timers runs the window's callbacks that are due now. Each backend
// calls it on the UI thread right before building the window's tree.
fn (mut w Window) run_due_timers() bool {
	mut runtime := w.timers
	return runtime.run_due(time.ticks())
}
