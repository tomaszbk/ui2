module ui2

fn test_embedder_waits_indefinitely_after_flush_and_preserves_reentrant_work() {
	mut scheduler := new_frame_coordinator(.on_demand)
	assert scheduler.next_wake(100, -1, 8) == 100
	first := scheduler.begin_frame(100) or { panic('missing mount') }
	scheduler.invalidate(.build)
	assert scheduler.next_wake(101, 100, 8) == -1
	scheduler.finish_frame(first)
	assert scheduler.next_wake(101, 100, 8) == 101
	second := scheduler.begin_frame(101) or { panic('lost request') }
	scheduler.finish_frame(second)
	assert scheduler.next_wake(102, 101, 8) == -1
	scheduler.set_deadline(600)
	assert scheduler.next_wake(102, 101, 8) == 600
	scheduler.set_deadline(-1)
	assert scheduler.next_wake(102, 101, 8) == -1
}

fn test_embedder_uses_presentation_cadence_and_suspends_visual_deadlines() {
	mut scheduler := new_frame_coordinator(.on_demand)
	first := scheduler.begin_frame(100) or { panic('missing mount') }
	scheduler.finish_frame(first)
	scheduler.set_animation_active(true)
	assert scheduler.next_wake(101, 100, 8) == 108
	scheduler.set_deadline(105)
	assert scheduler.next_wake(101, 100, 8) == 105
	scheduler.suspend()
	assert scheduler.next_wake(101, 100, 8) == -1
	assert scheduler.post(fn () {})
	assert scheduler.next_wake(101, 100, 8) == 101
	assert scheduler.take_tasks().len == 1
	assert scheduler.next_wake(101, 100, 8) == -1
	scheduler.resume()
	assert scheduler.next_wake(102, 100, 8) == 102
	scheduler.close()
	assert scheduler.next_wake(103, 100, 8) == -1
	assert !scheduler.post(fn () {})
}

fn test_embedder_wakeup_runs_outside_scheduler_lock_and_coalesces_worker_posts() {
	mut scheduler := new_frame_coordinator(.on_demand)
	first := scheduler.begin_frame(100) or { panic('missing mount') }
	scheduler.finish_frame(first)
	mut signals := &[]bool{}
	scheduler.set_wakeup(fn [mut scheduler, mut signals] () {
		signals << scheduler.stats().pending
	})
	for _ in 0 .. 20 {
		assert scheduler.post(fn () {})
	}
	assert signals.len == 1
	assert unsafe { signals[0] }
	assert scheduler.take_tasks().len == 20
	work := scheduler.begin_frame(101) or { panic('lost worker work') }
	scheduler.finish_frame(work)
	scheduler.invalidate(.build)
	assert signals.len == 2
	scheduler.close()
	assert !scheduler.post(fn () {})
	assert signals.len == 2
}
