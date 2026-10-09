@[has_globals]
module main

import os
import json2
import time
import ui2

__global g_acceptance_started = false
__global g_acceptance_sample_seconds = 30
__global g_acceptance_interactive = false
__global g_acceptance_message = 'Static scene — waiting for worker'
__global g_acceptance_worker_builds = 0
__global g_acceptance_verify_reentrant = false
__global g_acceptance_dispatcher = ui2.UiDispatcher{}
__global g_acceptance_completion_built = false
__global g_acceptance_lifecycle = false
__global g_acceptance_state_file = ''
__global g_acceptance_snapshot_serial = 0
__global g_acceptance_drags = 0
__global g_acceptance_releases = 0

struct PlatformSnapshot {
	serial              int
	message             string
	editor              string
	caret               int
	selection           int
	focused             string
	scroll              f64
	drags               int
	releases            int
	animation_completed bool
	stats               ui2.RenderStats
}

fn main() {
	for i, arg in os.args {
		match arg {
			'--state-file' {
				g_acceptance_state_file = os.args[i + 1]
				g_acceptance_interactive = true
				ui2.on_key_event(platform_key)
			}
			'--interactive' { g_acceptance_interactive = true }
			'--lifecycle' { g_acceptance_lifecycle = true }
			'--seconds' {
				if i + 1 >= os.args.len || os.args[i + 1].int() <= 0 {
					panic('--seconds needs a positive integer')
				}
				g_acceptance_sample_seconds = os.args[i + 1].int()
			}
			else {}
		}
	}
	ui2.run_window('UI2 renderer scheduler acceptance', 640, 480, build)
	if '--reopen' in os.args {
		// Sokol has destroyed the first GL context. A new run must reconstruct
		// the renderer resources and paint the whole image on its fresh context.
		g_acceptance_started = false
		g_acceptance_message = 'New GL context after normal close'
		g_acceptance_completion_built = false
		g_acceptance_worker_builds = 0
		ui2.run_window('UI2 renderer scheduler acceptance recreated', 640, 480, build)
	}
}

fn build() ui2.Element {
	if !g_acceptance_started {
		g_acceptance_started = true
		g_acceptance_dispatcher = ui2.ui_dispatcher()
		if !g_acceptance_interactive {
			spawn acceptance(g_acceptance_dispatcher, g_acceptance_sample_seconds,
				g_acceptance_lifecycle)
		} else {
			spawn observe(g_acceptance_dispatcher)
		}
	}
	if g_acceptance_message == 'Animation completed' {
		g_acceptance_completion_built = true
	}
	if g_acceptance_verify_reentrant {
		g_acceptance_worker_builds++
		if g_acceptance_worker_builds == 1 {
			// A request issued while the current generation is being built must
			// survive its acknowledgement and produce one subsequent build.
			ui2.request_refresh()
		}
	}
	style := ui2.TextStyle{ size: 14, color: 0x243247 }
	box := ui2.BoxStyle{ bg: 0xe2e8f0, radius: 6 }
	mut rows := []ui2.Element{}
	for i in 0 .. 30 {
		rows << ui2.label('row-${i}', 'Scroll row ${i + 1}', ui2.rect(8, i * 26, 240, 24), style)
	}
	return ui2.screen(0xf8fafc, [
		ui2.label('heading', 'Renderer scheduler acceptance', ui2.rect(24, 16, 590, 28),
			ui2.TextStyle{ size: 20, color: 0x0f172a }),
		ui2.with_tooltip(ui2.label('status', g_acceptance_message, ui2.rect(24, 52, 590, 28), style),
			'Tooltip appears after 500 ms with a stationary pointer.'),
		ui2.text_input(
			id:          'editor'
			placeholder: 'Type, select, then refresh'
			text:        ''
			frame:       ui2.rect(24, 96, 340, 34)
			box:         box
			text_style:  style
			keyboard:    0
			multiline:   true
		) or { panic(err) },
		ui2.with_event(ui2.button('refresh', 'Refresh', ui2.rect(380, 96, 100, 34), box, style), fn (event ui2.ElementEvent) {
			if event.kind == .tap { ui2.refresh() }
		}),
		ui2.with_event(ui2.button('worker', 'Worker', ui2.rect(496, 96, 112, 34), box, style), fn (event ui2.ElementEvent) {
			if event.kind == .tap { spawn delayed_update(ui2.ui_dispatcher()) }
		}),
		ui2.with_event(ui2.button('animate', 'Animate', ui2.rect(24, 148, 112, 34), box, style), fn (event ui2.ElementEvent) {
			if event.kind == .tap { start_animation() }
		}),
		ui2.with_event(ui2.draggable_view('moving', ui2.rect(160, 148, 36, 34), ui2.BoxStyle{ bg: 0x2563eb, radius: 6 }, []ui2.Element{}), fn (event ui2.ElementEvent) {
			if event.kind == .pointer_drag { g_acceptance_drags++ }
			if event.kind == .pointer_up { g_acceptance_releases++ }
		}),
		ui2.image('surface-texture', os.join_path(@VMODROOT, 'tests', 'render_scheduler', 'surface.png'),
			ui2.rect(552, 148, 32, 32)),
		ui2.scroll('rows', ui2.rect(24, 208, 300, 232), 0xe2e8f0, rows),
		ui2.label('instructions', 'Hover status for tooltip.\nEdit, select, scroll, resize.\nMinimize and restore.\nContent must stay intact.', ui2.rect(348, 220, 268, 140), ui2.TextStyle{ ...style, lines: 4 }),
	])
}

fn platform_key(event ui2.KeyEvent) {
	if event.code == .f1 {
		g_acceptance_snapshot_serial++
		os.write_file(g_acceptance_state_file, json2.encode(PlatformSnapshot{
			serial:              g_acceptance_snapshot_serial
			message:             g_acceptance_message
			editor:              ui2.text('editor')
			caret:               ui2.text_area_caret('editor')
			selection:           ui2.text_area_selection_length('editor')
			focused:             ui2.focused_id()
			scroll:              ui2.scroll_offset('rows')
			drags:               g_acceptance_drags
			releases:            g_acceptance_releases
			animation_completed: g_acceptance_completion_built
			stats:               ui2.render_stats()
		},
			escape_unicode: true
			time_as_unix:   true
		)) or { panic(err) }
		ui2.consume_key()
	} else if event.code == .f2 {
		spawn delayed_update(ui2.ui_dispatcher())
		ui2.consume_key()
	} else if event.code == .f3 {
		start_animation()
		ui2.consume_key()
	} else if event.code == .f4 {
		ui2.quit()
		ui2.consume_key()
	}
}

fn start_animation() {
	ui2.clear_animation('moving')
	ui2.animation(
		duration: 0.8
		x:        280.0
		on_event: fn (event ui2.AnimationEvent) {
			if event.kind == .complete {
				// Event callbacks can mutate the model without their own refresh.
				g_acceptance_message = 'Animation completed'
			}
		}
	).start('moving')
}

fn observe(dispatcher ui2.UiDispatcher) {
	mut before := dispatcher.stats()
	for !before.closed {
		time.sleep(time.second)
		after := dispatcher.stats()
		report('interactive suspended=${after.suspended}', before, after)
		before = after
	}
}

fn delayed_update(dispatcher ui2.UiDispatcher) {
	time.sleep(750 * time.millisecond)
	assert dispatcher.post(fn () {
		g_acceptance_message = 'Worker delivered on UI thread'
	})
}

fn report(phase string, before ui2.RenderStats, after ui2.RenderStats) {
	println('${phase}: callbacks=${after.callbacks - before.callbacks} loop_callbacks=${after.loop_callbacks - before.loop_callbacks} waits=${after.waits - before.waits} event_wakeups=${after.event_wakeups - before.event_wakeups} worker_wakeups=${after.worker_wakeups - before.worker_wakeups} deadline_wakeups=${after.deadline_wakeups - before.deadline_wakeups} interrupted_waits=${after.interrupted_waits - before.interrupted_waits} builds=${after.builds - before.builds} draws=${after.draws - before.draws} flushes=${after.flushes - before.flushes} requests=${after.requests - before.requests} coalesced=${after.coalesced - before.coalesced} pending=${after.pending} in_flight=${after.in_flight}')
}

fn acceptance(dispatcher ui2.UiDispatcher, seconds int, lifecycle bool) {
	// Observe counters directly from the worker: posting an observer callback
	// would itself invalidate the scene and contaminate the static sample.
	time.sleep(2 * time.second)
	mut before := dispatcher.stats()
	$if linux {
		// Software GL may compile an image pipeline on its first use. Do not
		// sample an idle-looking window before it has completed its first paint.
		for _ in 0 .. 1500 {
			if before.draws > 0 && !before.in_flight && !before.pending { break }
			time.sleep(20 * time.millisecond)
			before = dispatcher.stats()
		}
		assert before.draws > 0 && !before.in_flight && !before.pending
		time.sleep(2 * time.second)
		before = dispatcher.stats()
		assert !before.in_flight && !before.pending
	}
	$if linux {
		sample_cpu_start()
	}
	warmup := $if linux { 'first-paint+2s-settle' } $else { '2s' }
	println('sample: seconds=${seconds} warmup=${warmup} presentation_required=${before.presentation_required}')
	time.sleep(seconds * time.second)
	after := dispatcher.stats()
	report('static', before, after)
	$if linux {
		print_sample_cpu(seconds)
		assert after.loop_callbacks == before.loop_callbacks
		assert after.callbacks == before.callbacks
		assert after.waits == before.waits
		assert after.event_wakeups == before.event_wakeups
		assert after.worker_wakeups == before.worker_wakeups
		assert after.deadline_wakeups == before.deadline_wakeups
		assert after.draws == before.draws
	} $else {
		assert after.callbacks > before.callbacks
	}
	assert after.builds == before.builds
	if !before.presentation_required {
		assert after.draws == before.draws
	}
	assert dispatcher.post(fn () {
		g_acceptance_message = 'Worker delivered on UI thread'
		g_acceptance_verify_reentrant = true
		for _ in 0 .. 20 {
			ui2.request_refresh()
		}
	})
	time.sleep(500 * time.millisecond)
	worker_after := dispatcher.stats()
	report('worker + burst + reentrant build', after, worker_after)
	assert worker_after.builds - after.builds == 2
	if !after.presentation_required {
		assert worker_after.draws - after.draws == 2
	}
	assert dispatcher.post(fn () {
		assert g_acceptance_worker_builds >= 2
		assert g_acceptance_message == 'Worker delivered on UI thread'
		g_acceptance_verify_reentrant = false
		start_animation()
	})
	time.sleep(1500 * time.millisecond)
	settled := dispatcher.stats()
	report('animation', worker_after, settled)
	assert settled.draws > worker_after.draws
	time.sleep(time.second)
	idle := dispatcher.stats()
	report('idle after animation', settled, idle)
	assert idle.builds == settled.builds
	if !settled.presentation_required || os.user_os() == 'linux' {
		assert idle.draws == settled.draws
	}
	if lifecycle {
		$if macos {
			check_lifecycle(dispatcher)
		} $else {
			println('SKIP: native lifecycle helper currently supports macOS only')
		}
	}
	assert dispatcher.post(fn [dispatcher] () {
		assert ui2.animation_info('moving').status == .completed
		assert g_acceptance_completion_built
		println('PASS: static, worker, coalescing, reentrant request, animation, return to idle')
		ui2.quit()
		assert dispatcher.stats().closed
		assert !dispatcher.post(fn () {
			assert false, 'closed window must reject a late worker callback'
		})
		println('PASS: closed dispatcher rejected late worker callback')
	})
}

fn check_lifecycle(dispatcher ui2.UiDispatcher) {
	assert dispatcher.post(fn () {
		assert schedule_real_window_lifecycle(2000)
	})
	mut suspended := dispatcher.stats()
	for _ in 0 .. 100 {
		if suspended.suspended {
			break
		}
		time.sleep(20 * time.millisecond)
		suspended = dispatcher.stats()
	}
	assert suspended.suspended, 'native window must become iconified'
	time.sleep(500 * time.millisecond)
	midpoint := dispatcher.stats()
	report('real window iconified', suspended, midpoint)
	assert midpoint.suspended
	assert midpoint.builds == suspended.builds
	assert midpoint.draws == suspended.draws
	mut restored := midpoint
	for _ in 0 .. 200 {
		time.sleep(20 * time.millisecond)
		restored = dispatcher.stats()
		if !restored.suspended && restored.draws > midpoint.draws {
			break
		}
	}
	report('real window restored', midpoint, restored)
	assert !restored.suspended, 'native window must restore before timeout'
	assert restored.builds > midpoint.builds
	assert restored.draws > midpoint.draws
	time.sleep(500 * time.millisecond)
	settled := dispatcher.stats()
	time.sleep(500 * time.millisecond)
	idle := dispatcher.stats()
	report('idle after restore', settled, idle)
	assert idle.builds == settled.builds
	if !settled.presentation_required {
		assert idle.draws == settled.draws
	}
	println('PASS: real window minimize, suspended draw suppression, restore, return to idle')
}
