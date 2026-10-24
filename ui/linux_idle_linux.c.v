// vfmt off
module ui2

$if (android || linux || ((ios || macos || windows) && ui2_custom_rendering ?)) && !ui2_headless ? && !ui2_document_library ? {
	import sokol.sapp

	#include "@VMODROOT/ui/linux_idle.h"
	fn C.ui2_linux_signal_create() int
	fn C.ui2_linux_signal_send(int)
	fn C.ui2_linux_signal_drain(int)
	fn C.ui2_linux_wait(voidptr, int, i64) int
	fn C.ui2_linux_host_close_pending() bool
	fn C.sapp_x11_get_display() voidptr

	// Captured by the coordinator's signal closure, independent of app/window
	// lifetime. close and a worker racing after scheduler unlock share this lock.
	fn new_linux_wake_signal() &HostWakeSignal {
		fd := C.ui2_linux_signal_create()
		if fd < 0 { panic('ui2: cannot create Linux eventfd') }
		return &HostWakeSignal{fd: fd}
	}

	fn (signal &HostWakeSignal) send() {
		signal.mutex.lock()
		defer { signal.mutex.unlock() }
		if signal.fd >= 0 { C.ui2_linux_signal_send(signal.fd) }
	}

	fn (mut signal HostWakeSignal) close() {
		signal.mutex.lock()
		defer { signal.mutex.unlock() }
		if signal.fd >= 0 {
			C.close(signal.fd)
			signal.fd = -1
		}
	}

	fn (mut w Window) setup_linux_idle() {
		// The pinned Sokol default is X11/GLX (also usable under XWayland).
		// Reject other hosts rather than silently reverting to periodic polling.
		if C.sapp_x11_get_display() == unsafe { nil } {
			panic('ui2: Linux idle wait requires the Sokol X11 host')
		}
		signal := new_linux_wake_signal()
		w.linux_signal = signal
		interval := i64(sapp.frame_duration() * 1000)
		w.frame_interval = if interval > 0 { interval } else { 1 }
		w.scheduler.set_wakeup(fn [signal] () { signal.send() })
	}

	fn (mut w Window) wait_linux_idle() {
		// A nested callback must let the outer flush finish before it can wait
		// or deliver tasks. next_wake deliberately suppresses nested scheduling.
		if w.linux_signal == unsafe { nil } || w.scheduler.is_flushing() { return }
		// Sokol consumes WM_DELETE_WINDOW before this frame but dispatches its
		// cancellable quit request afterwards. Let it reach that dispatch/cleanup.
		if C.ui2_linux_host_close_pending() { return }
		// Retain Sokol's measured presentation cadence. Samples spanning idle
		// waits are not refresh intervals; keep the last usable sample instead.
		sample := i64(sapp.frame_duration() * 1000)
		if sample > 0 && sample <= 100 { w.frame_interval = sample }
		for {
			// Drain BEFORE checking scheduler state. A concurrent post either is
			// observed by next_wake or leaves a readable eventfd for poll.
			C.ui2_linux_signal_drain(w.linux_signal.fd)
			now := renderer_now_ms()
			wake_at := w.scheduler.next_wake(now, w.last_frame, w.frame_interval)
			if wake_at >= 0 && wake_at <= now { return }
			delay := if wake_at < 0 { i64(-1) } else { wake_at - now }
			// Recheck on every retry, including worker wakes, deadlines and EINTR.
			if C.ui2_linux_host_close_pending() { return }
			outcome := C.ui2_linux_wait(C.sapp_x11_get_display(), w.linux_signal.fd, delay)
			w.scheduler.record_wait(outcome)
			if outcome == -1 { panic('ui2: Linux event wait failed') }
			if outcome > 0 && outcome & 1 != 0 {
				// Sokol dispatches the event on the following iteration. This
				// callback still swaps, so always repaint the complete retained tree.
				// In particular Expose must repaint even without a model mutation.
				w.scheduler.invalidate(.paint)
				return
			}
			// EINTR, worker signals and expired waits re-read the absolute deadline.
			// A signal changing/cancelling a timer need not present immediately.
		}
	}
}
