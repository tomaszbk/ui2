// vtest vflags: -d ui2_custom_rendering
module ui2

$if linux && !ui2_headless ? {
	import time

	fn C.ui2_linux_poll(int, int, i64) int

	fn test_linux_wait_deadline_signal_and_coalescing() {
		mut signal := new_linux_wake_signal()
		defer { signal.close() }
		start := time.sys_mono_now()
		assert C.ui2_linux_poll(-1, signal.fd, 35) == 0
		assert time.sys_mono_now() - start >= 30 * time.millisecond
		for _ in 0 .. 100 { signal.send() }
		assert C.ui2_linux_poll(-1, signal.fd, -1) == 2
		C.ui2_linux_signal_drain(signal.fd)
		assert C.ui2_linux_poll(-1, signal.fd, 0) == 0
		worker := spawn fn [signal] () {
			time.sleep(35 * time.millisecond)
			signal.send()
		}()
		assert C.ui2_linux_poll(-1, signal.fd, -1) == 2
		worker.wait()
	}

	fn test_linux_close_racing_worker_cannot_signal_reused_fd() {
		mut signal := new_linux_wake_signal()
		worker := spawn fn [signal] () {
			for _ in 0 .. 1_000 { signal.send() }
		}()
		signal.close()
		mut replacement := new_linux_wake_signal()
		defer { replacement.close() }
		worker.wait()
		signal.send()
		signal.close()
		assert C.ui2_linux_poll(-1, replacement.fd, 0) == 0
	}

	fn test_linux_wait_observes_event_and_worker_without_consuming_event() {
		mut event := new_linux_wake_signal()
		defer { event.close() }
		mut signal := new_linux_wake_signal()
		defer { signal.close() }
		event.send()
		signal.send()
		assert C.ui2_linux_poll(event.fd, signal.fd, -1) == 3
		C.ui2_linux_signal_drain(signal.fd)
		assert C.ui2_linux_poll(event.fd, signal.fd, 0) == 1
	}

	fn test_linux_armed_wait_cannot_lose_post_after_scheduler_check() {
		mut scheduler := new_frame_coordinator()
		mut signal := new_linux_wake_signal()
		defer { signal.close() }
		scheduler.set_wakeup(fn [signal] () { signal.send() })
		first := scheduler.begin_frame(0) or { panic('mount') }
		scheduler.finish_frame(first)
		C.ui2_linux_signal_drain(signal.fd)
		assert scheduler.next_wake(1, 0, 10) == -1
		worker := spawn fn [mut scheduler] () {
			assert scheduler.post(fn () {})
		}()
		assert C.ui2_linux_poll(-1, signal.fd, -1) == 2
		worker.wait()
		assert scheduler.next_wake(2, 0, 10) == 2
		assert scheduler.take_tasks().len == 1
	}

	fn test_linux_nested_callback_does_not_wait_during_flush() {
		mut signal := new_linux_wake_signal()
		defer { signal.close() }
		mut app := GgApp{ linux_signal: signal, scheduler: new_frame_coordinator() }
		work := app.scheduler.begin_frame(0) or { panic('mount') }
		app.scheduler.invalidate(.paint)
		wait_linux_idle(mut app)
		assert app.scheduler.stats().waits == 0
		app.scheduler.finish_frame(work)
		assert app.scheduler.next_wake(1, 0, 10) == 1
	}
}
