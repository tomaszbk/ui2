// ui2 profiles: custom (custom font family)
module main

import math
import sync
import time
import ui2

const timer_width = 600
const timer_height = 380

@[heap]
pub struct TimerDemo {
pub mut:
	duration       f64    = 15
	duration_label string = '15 seconds'
	duration_ratio f64    = 0.5
	elapsed        f64
	elapsed_label  string = '0.0 s'
	progress       f64
	running        bool
	start_label    string = 'Start'
	status         string = 'Choose a duration, then start the timer.'
mut:
	started_at   i64
	base_elapsed f64
}

const timer_state = &TimerDemo{}

// Workers own only this cancellation token. The model is read and updated on
// the UI thread; a deadline wakes it to sample elapsed time.
@[heap]
struct TimerRefresh {
	mutex &sync.Mutex = sync.new_mutex()
mut:
	generation u64
	active     bool
}

const timer_refresh = &TimerRefresh{}

fn schedule_timer_refresh() {
	mut wake := unsafe { timer_refresh }
	wake.mutex.lock()
	wake.generation++
	wake.active = true
	generation := wake.generation
	wake.mutex.unlock()
	spawn refresh_timer_until_cancelled(generation)
}

fn cancel_timer_refresh() {
	mut wake := unsafe { timer_refresh }
	wake.mutex.lock()
	wake.active = false
	wake.mutex.unlock()
}

fn (mut app TimerDemo) update_labels() {
	app.duration_label = '${int(math.round(app.duration))} seconds'
	app.duration_ratio = app.duration / 30.0
	app.elapsed_label = '${app.elapsed:.1f} s'
	app.progress = if app.duration <= 0 { 1.0 } else { app.elapsed / app.duration }
	if app.progress > 1 {
		app.progress = 1
	}
}

fn (mut app TimerDemo) set_duration_fraction(fraction f64) {
	clamped := math.max(0.0, math.min(1.0, fraction))
	app.set_duration(clamped * 29.0 + 1.0)
}

fn (mut app TimerDemo) set_duration(value f64) {
	app.duration = math.round(math.max(1.0, math.min(30.0, value)))
	if app.elapsed > app.duration {
		app.elapsed = app.duration
		app.base_elapsed = app.elapsed
		app.running = false
		app.start_label = 'Restart'
		app.status = 'Timer complete.'
	} else {
		app.status = 'Duration set to ${int(app.duration)} seconds.'
	}
	app.update_labels()
}

fn (mut app TimerDemo) start_at(now i64) {
	app.elapsed = 0
	app.base_elapsed = 0
	app.started_at = now
	app.running = true
	app.start_label = 'Restart'
	app.status = 'Timer running…'
	app.update_labels()
}

fn (mut app TimerDemo) pause_at(now i64) {
	app.sync_at(now)
	if app.running {
		app.base_elapsed = app.elapsed
		app.running = false
		app.start_label = 'Restart'
		app.status = 'Timer paused.'
	}
}

fn (mut app TimerDemo) resume_at(now i64) {
	if app.elapsed >= app.duration {
		app.start_at(now)
		return
	}
	app.base_elapsed = app.elapsed
	app.started_at = now
	app.running = true
	app.start_label = 'Restart'
	app.status = 'Timer running…'
}

fn (mut app TimerDemo) sync_at(now i64) {
	if !app.running {
		app.update_labels()
		return
	}
	app.elapsed = app.base_elapsed + f64(now - app.started_at) / 1000.0
	if app.elapsed >= app.duration {
		app.elapsed = app.duration
		app.base_elapsed = app.elapsed
		app.running = false
		app.start_label = 'Restart'
		app.status = 'Timer complete.'
	}
	app.update_labels()
}

fn refresh_timer_until_cancelled(generation u64) {
	mut wake := unsafe { timer_refresh }
	for {
		time.sleep(50 * time.millisecond)
		wake.mutex.lock()
		active := wake.active && wake.generation == generation
		wake.mutex.unlock()
		if !active { return }
		ui2.request_refresh()
	}
}

fn timer_callbacks() map[string]ui2.ElementCallback {
	return {
		'start':           fn (_event ui2.ElementEvent) {
			mut state := unsafe { timer_state }
			state.start_at(time.ticks())
			schedule_timer_refresh()
			ui2.refresh()
		}
		'pause':           fn (_event ui2.ElementEvent) {
			mut state := unsafe { timer_state }
			if state.running {
				state.pause_at(time.ticks())
				cancel_timer_refresh()
			} else {
				state.resume_at(time.ticks())
				schedule_timer_refresh()
			}
			ui2.refresh()
		}
		'duration_slider': fn (event ui2.ElementEvent) {
			mut state := unsafe { timer_state }
			state.set_duration(event.value)
			ui2.refresh()
		}
	}
}

fn main() {
	ui2.run_compiled_vml[TimerDemo](
		build:  build_timer
		model:  timer_state
		title:  'Timer'
		width:  timer_width
		height: timer_height
		update: update_timer
	) or { panic(err) }
}

fn build_timer(mut app TimerDemo) ui2.Element {
	callbacks := timer_callbacks()
	callback_duration_slider := callbacks['duration_slider'] or { panic('missing duration_slider callback') }
	callback_start := callbacks['start'] or { panic('missing start callback') }
	callback_pause := callbacks['pause'] or { panic('missing pause callback') }
	return $vml('timer.vml')
}

fn timer_tree(mut app TimerDemo, frame ui2.Rect) ui2.Element {
	callbacks := timer_callbacks()
	callback_duration_slider := callbacks['duration_slider'] or { panic('missing duration_slider callback') }
	callback_start := callbacks['start'] or { panic('missing start callback') }
	callback_pause := callbacks['pause'] or { panic('missing pause callback') }
	return $vml('timer.vml', frame)
}

fn update_timer(mut app TimerDemo) {
	app.sync_at(time.ticks())
	if !app.running { cancel_timer_refresh() }
}
