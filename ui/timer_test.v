module ui2

import math
import time

struct TimerLog {
mut:
	calls     []string
	follow_up TimerId
}

fn test_after_runs_due_callbacks_in_deadline_order_once() {
	mut w := &Window{}
	mut log := &TimerLog{}
	late := w.after(0.2, fn [mut log] () {
		log.calls << 'late'
	})
	early := w.after(0.1, fn [mut log] () {
		log.calls << 'early'
	})
	now := w.after(0, fn [mut log] () {
		log.calls << 'now'
	})
	assert w.timer_pending(late) && w.timer_pending(early) && w.timer_pending(now)
	start := time.ticks()
	assert w.timers.run_due(start)
	assert log.calls == ['now']
	assert !w.timers.run_due(start)
	assert w.timers.run_due(start + 1000)
	assert log.calls == ['now', 'early', 'late']
	assert !w.timer_pending(late) && !w.timer_pending(early)
	assert !w.timers.run_due(start + 2000)
}

fn test_cancel_timer_stops_a_pending_callback_only() {
	mut w := &Window{}
	mut log := &TimerLog{}
	id := w.after(0.05, fn [mut log] () {
		log.calls << 'cancelled'
	})
	assert w.cancel_timer(id)
	assert !w.cancel_timer(id)
	assert !w.timers.run_due(time.ticks() + 1000)
	assert log.calls.len == 0
	assert !w.cancel_timer(TimerId(0))
}

fn test_timer_callbacks_can_schedule_and_cancel_timers() {
	mut w := &Window{}
	mut log := &TimerLog{}
	victim := w.after(5, fn [mut log] () {
		log.calls << 'victim'
	})
	w.after(0, fn [mut log, mut w, victim] () {
		log.calls << 'first'
		w.cancel_timer(victim)
		log.follow_up = w.after(0, fn [mut log] () {
			log.calls << 'second'
		})
	})
	assert w.timers.run_due(time.ticks())
	assert log.calls == ['first']
	assert w.timer_pending(log.follow_up)
	assert w.timers.run_due(time.ticks() + 10)
	assert log.calls == ['first', 'second']
	assert !w.timers.run_due(time.ticks() + 10000)
}

fn test_after_treats_invalid_delays_as_immediate() {
	mut w := &Window{}
	mut log := &TimerLog{}
	for delay in [-1.0, math.nan(), math.inf(1)] {
		w.after(delay, fn [mut log] () {
			log.calls << 'ran'
		})
	}
	assert w.timers.run_due(time.ticks())
	assert log.calls.len == 3
}
