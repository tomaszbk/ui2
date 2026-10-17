@[has_globals]
module ui2

import sync

// WindowWakeFn asks the running window for a frame. A backend installs its
// backend_invalidate when a window starts running; the custom renderer removes
// it again when its window closes. Timers wake it from their own threads;
// motion handles and the reduced motion preference wake it from the UI thread.
// Without a window running there is nothing to wake.
type WindowWakeFn = fn (reason RenderReason)

@[heap]
struct WindowWake {
	mutex &sync.Mutex = sync.new_mutex()
mut:
	wake WindowWakeFn = unsafe { nil }
}

__global g_window_wake = &WindowWake{}

fn set_window_wake(wake WindowWakeFn) {
	mut hook := g_window_wake
	hook.mutex.lock()
	hook.wake = wake
	hook.mutex.unlock()
}

fn wake_window(reason RenderReason) {
	mut hook := g_window_wake
	hook.mutex.lock()
	wake := hook.wake
	hook.mutex.unlock()
	if wake != unsafe { nil } {
		wake(reason)
	}
}
