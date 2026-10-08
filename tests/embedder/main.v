@[has_globals]
module main

import os
import sync
import time
import ui2

struct WindowModel {
mut:
	name             string
	status           string = 'Static window'
	completion_built bool
	input_readonly   bool
	input_disabled   bool
}

@[heap]
struct GcLifetimeProbe {
	mutex &sync.Mutex = sync.new_mutex()
mut:
	dispatcher  ui2.UiDispatcher
	ready       bool
	collections int
	builds      int
}

struct IdleSample {
	first        ui2.RenderStats
	second       ui2.RenderStats
	first_pumps  u64
	second_pumps u64
}

__global first_model = WindowModel{ name: 'First' }
__global second_model = WindowModel{ name: 'Second' }
__global first_window = ui2.CustomWindow{}
__global second_window = ui2.CustomWindow{}
__global japanese_ime_requested = false
__global japanese_ime_scheduled = false
__global japanese_ime_session = voidptr(unsafe { nil })
__global fixture_interactive = false
__global interactive_font = ''

fn main() {
	mut seconds := 30
	mut interactive := false
	for index, argument in os.args {
		if argument == '--seconds' {
			if index + 1 >= os.args.len || os.args[index + 1].int() <= 0 {
				panic('--seconds needs a positive integer')
			}
			seconds = os.args[index + 1].int()
		} else if argument == '--interactive' {
			interactive = true
		} else if argument == '--japanese-ime' {
			japanese_ime_requested = true
		}
	}
	if japanese_ime_requested && !interactive {
		panic('--japanese-ime requires --interactive')
	}
	fixture_interactive = interactive
	if japanese_ime_requested {
		// The protocol suite does not depend on a particular font. The optional
		// visual session uses an existing TrueType face with Japanese coverage.
		path := '/System/Library/Fonts/Supplemental/Arial Unicode.ttf'
		if os.is_file(path) { interactive_font = path }
	}
	first_window = ui2.open_window('UI2 embedder acceptance — First', 520, 460, first_build) or { panic(err) }
	second_window = ui2.open_window('UI2 embedder acceptance — Second', 520, 460, second_build) or { panic(err) }
	assert C.ui2_fixture_place(first_window.native_handle(), 30, 160)
	assert C.ui2_fixture_place(second_window.native_handle(), 590, 160)
	first_host := C.ui2_fixture_host_handle(first_window.native_handle())
	second_host := C.ui2_fixture_host_handle(second_window.native_handle())
	assert first_host != unsafe { nil } && second_host != unsafe { nil }
	first := first_window.dispatcher()
	second := second_window.dispatcher()
	if interactive {
		println('Interactive: type with a Japanese input method, select text, scroll, hover the heading, minimize/restore and close each window.')
	} else {
		spawn acceptance(first, second, first_host, second_host, seconds)
	}
	ui2.run_windows()
	end_japanese_ime()
	assert first.stats().closed && second.stats().closed
	if !interactive {
		println('PASS: two owned windows, idle sleep, target worker wake, local editor state, tooltip deadline, animation, NSTextInputClient composition, native lifecycle and independent close')
	}
}

fn first_build() ui2.Element {
	if japanese_ime_requested && !japanese_ime_scheduled {
		japanese_ime_scheduled = true
		assert first_window.dispatcher().post(fn () {
			ui2.focus('input')
			ui2.set_text('input', '')
			// Begin after the frame publishes textEnabled to the native client.
			assert first_window.dispatcher().post(fn () {
				japanese_ime_session = C.ui2_test_ime_begin(first_window.native_handle())
				assert japanese_ime_session != unsafe { nil }, 'Japanese input source unavailable'
				assert C.ui2_test_ime_selected(japanese_ime_session)
				println('Japanese IME active in first input context; type nihon, Space, Return. Previous input source will be restored on close.')
			})
		})
	}
	if first_model.status == 'Animation completed' {
		first_model.completion_built = true
	}
	return build_window(first_model, first_change, first_animate, first_close)
}

fn second_build() ui2.Element {
	return build_window(second_model, second_change, second_animate, second_close)
}

fn build_window(model WindowModel, on_change ui2.ElementCallback, on_animate ui2.ElementCallback, on_close ui2.ElementCallback) ui2.Element {
	style := ui2.TextStyle{ size: 14, color: 0x243247 }
	editor_style := ui2.TextStyle{ ...style, font_family: interactive_font }
	box := ui2.BoxStyle{ bg: 0xe2e8f0, radius: 6 }
	input := ui2.text_input(
		id:          'input'
		on_event:    on_change
		placeholder: 'Japanese IME input'
		text:        'A😀Z'
		frame:       ui2.rect(24, 58, 300,
			36)
		box:         box
		text_style:  editor_style
		keyboard:    0
		multiline:   false
	) or { panic(err) }
	area := ui2.text_input(
		id:         'editor'
		on_event:   on_change
		text:       '${model.name} declared body'
		frame:      ui2.rect(24, 108, 300,
			70)
		box:        box
		text_style: editor_style
		multiline:  true
	) or { panic(err) }
	mut rows := []ui2.Element{}
	for index in 0 .. 30 {
		rows << ui2.label('row-${index}', '${model.name} row ${index}', ui2.rect(8,
			index * 26, 210, 24), style)
	}
	return ui2.screen(0xf8fafc, [
		ui2.with_tooltip(ui2.label('heading', '${model.name}: ${model.status}', ui2.rect(24,
			16, 470, 28), ui2.TextStyle{ size: 18, color: 0x0f172a }),
			'Stationary pointer deadline belongs to this window.'),
		ui2.Element{
			...input
			readonly: model.input_readonly
			enabled:  !model.input_disabled
		},
		area,
		ui2.with_event(ui2.button('animate', 'Animate', ui2.rect(350, 58, 138, 36), box, style), on_animate),
		ui2.with_event(ui2.button('close', 'Close this window', ui2.rect(350, 108, 138, 36), box, style), on_close),
		ui2.view('moving', ui2.rect(350, 156, 30, 24), ui2.BoxStyle{ bg: 0x2563eb }, []ui2.Element{}),
		ui2.scroll('rows', ui2.rect(24, 206, 250, 228), 0xe2e8f0, rows),
		ui2.label('instructions', 'Equal ids in both windows.\nEdits, selection and scroll\nmust remain independent.\nHover heading for tooltip.\nTry IME in either editor.',
			ui2.rect(294, 214, 202, 154), ui2.TextStyle{ ...style, lines: 5 }),
	])
}

fn first_close(event ui2.ElementEvent) {
	if event.kind == .tap {
		end_japanese_ime()
		first_window.close()
	}
}

fn first_animate(event ui2.ElementEvent) {
	if event.kind == .tap { start_first_animation() }
}

fn first_change(event ui2.ElementEvent) {
	if fixture_interactive && event.kind == .change {
		println('First committed ${event.id}: ${event.text}')
	}
}

fn end_japanese_ime() {
	if japanese_ime_session != unsafe { nil } {
		C.ui2_test_ime_end(japanese_ime_session)
		japanese_ime_session = unsafe { nil }
	}
}

fn second_close(event ui2.ElementEvent) {
	if event.kind == .tap { second_window.close() }
}

fn second_animate(event ui2.ElementEvent) {
	if event.kind == .tap { ui2.animation(duration: 0.8, x: 440.0).start('moving') }
}

fn second_change(event ui2.ElementEvent) {
	if fixture_interactive && event.kind == .change {
		println('Second committed ${event.id}: ${event.text}')
	}
}

fn assert_first_editor() {
	assert ui2.text('editor') == 'first local draft'
	assert ui2.focused_id() == 'editor'
	assert ui2.text_area_caret('editor') == 5
	assert ui2.text_area_selection_length('editor') == 4
	assert ui2.scroll_offset('rows') == 70
}

fn assert_second_editor() {
	assert ui2.text('editor') == 'second local draft'
	assert ui2.focused_id() == 'editor'
	assert ui2.text_area_caret('editor') == 5
	assert ui2.text_area_selection_length('editor') == 3
	assert ui2.scroll_offset('rows') == 180
}

fn start_first_animation() {
	ui2.clear_animation('moving')
	ui2.animation(
		duration: 0.5
		x:        440.0
		on_event: fn (event ui2.AnimationEvent) {
			if event.kind == .complete {
				first_model.status = 'Animation completed'
			}
		}
	).start('moving')
}

fn settled(dispatcher ui2.UiDispatcher) ui2.RenderStats {
	mut before := dispatcher.stats()
	mut stable := 0
	for _ in 0 .. 100 {
		time.sleep(50 * time.millisecond)
		after := dispatcher.stats()
		if !after.pending && !after.in_flight && !after.animation_active
			&& after.next_deadline < 0 && after.callbacks == before.callbacks {
			stable++
			if stable == 4 {
				return after
			}
		} else {
			stable = 0
		}
		before = after
	}
	panic('window did not settle: ${before}')
}

fn unchanged(before ui2.RenderStats, after ui2.RenderStats) {
	assert after.callbacks == before.callbacks
	assert after.builds == before.builds
	assert after.draws == before.draws
}

fn report(phase string, before ui2.RenderStats, after ui2.RenderStats, native_delta u64) {
	println('${phase}: host_callbacks=${native_delta} callbacks=${after.callbacks - before.callbacks} builds=${after.builds - before.builds} draws=${after.draws - before.draws}')
}

fn sample_idle(first ui2.UiDispatcher, second ui2.UiDispatcher, first_host voidptr,
	second_host voidptr, seconds int) IdleSample {
	for attempt in 1 .. 4 {
		settled(first)
		settled(second)
		first_events := C.ui2_embedder_event_count(first_host)
		second_events := C.ui2_embedder_event_count(second_host)
		before_first := first.stats()
		before_second := second.stats()
		assert !before_first.suspended && !before_second.suspended
		first_pumps := C.ui2_embedder_pump_count(first_host)
		second_pumps := C.ui2_embedder_pump_count(second_host)
		println('static sample: attempt=${attempt}/3 seconds=${seconds}, two windows, on_demand, normal GC')
		mut interrupted := false
		mut sampled_first := before_first
		mut sampled_second := before_second
		for _ in 0 .. seconds {
			time.sleep(time.second)
			events_first := C.ui2_embedder_event_count(first_host)
			events_second := C.ui2_embedder_event_count(second_host)
			sampled_first = first.stats()
			sampled_second = second.stats()
			pumps_first := C.ui2_embedder_pump_count(first_host)
			pumps_second := C.ui2_embedder_pump_count(second_host)
			// Re-read after the work counters so a native event racing with the
			// observation cannot look like an unexplained periodic wakeup.
			verified_first := C.ui2_embedder_event_count(first_host)
			verified_second := C.ui2_embedder_event_count(second_host)
			if events_first != first_events || events_second != second_events
				|| verified_first != first_events || verified_second != second_events {
				println('static sample attempt=${attempt} interrupted by native input/lifecycle: first_events=${verified_first - first_events} second_events=${verified_second - second_events}; restarting after both windows settle')
				interrupted = true
				break
			}
			// Only real native events permit another attempt. A pump, build or
			// draw without an event remains an immediate acceptance failure.
			unchanged(before_first, sampled_first)
			unchanged(before_second, sampled_second)
			assert pumps_first == first_pumps, 'first window woke without a native event'
			assert pumps_second == second_pumps, 'second window woke without a native event'
		}
		if interrupted { continue }
		report('first static', before_first, sampled_first, 0)
		report('second static', before_second, sampled_second, 0)
		println('PASS: uninterrupted ${seconds}s static sample with zero native events, host callbacks, builds and draws in both windows')
		return IdleSample{
			first:        sampled_first
			second:       sampled_second
			first_pumps:  first_pumps
			second_pumps: second_pumps
		}
	}
	panic('static sample interrupted by native input/lifecycle in all three attempts')
}

fn acceptance(first ui2.UiDispatcher, second ui2.UiDispatcher, first_host voidptr,
	second_host voidptr, seconds int) {
	time.sleep(2 * time.second)
	assert first.stats().draws > 0 && second.stats().draws > 0
	assert first.post(fn () {
		ui2.set_text('editor', 'first local draft')
		ui2.focus('editor')
		ui2.text_area_set_selection('editor', 1, 4)
		ui2.scroll_to_offset('rows', 70)
		assert_first_editor()
	})
	assert second.post(fn () {
		ui2.set_text('editor', 'second local draft')
		ui2.focus('editor')
		ui2.text_area_set_selection('editor', 2, 3)
		ui2.scroll_to_offset('rows', 180)
		assert_second_editor()
	})
	sample := sample_idle(first, second, first_host, second_host, seconds)
	after_first := sample.first
	after_second := sample.second
	first_pumps := sample.first_pumps
	second_pumps := sample.second_pumps

	assert first.post(fn () {
		assert_first_editor()
		first_model.status = 'Worker delivered to first'
		for _ in 0 .. 20 {
			ui2.request_refresh()
		}
	})
	worker := settled(first)
	report('worker wakes only first', after_first, worker, C.ui2_embedder_pump_count(first_host) - first_pumps)
	assert worker.builds == after_first.builds + 1
	assert worker.draws == after_first.draws + 1
	unchanged(after_second, second.stats())
	assert C.ui2_embedder_pump_count(second_host) == second_pumps

	animation_pumps := C.ui2_embedder_pump_count(first_host)
	assert first.post(fn () {
		assert_first_editor()
		start_first_animation()
	})
	animation := settled(first)
	assert animation.draws > worker.draws + 1
	animation_peer := second.stats()
	report('first animation', worker, animation,
		C.ui2_embedder_pump_count(first_host) - animation_pumps)
	report('peer during first animation', after_second, animation_peer,
		C.ui2_embedder_pump_count(second_host) - second_pumps)
	if animation_peer.callbacks != after_second.callbacks {
		println('peer animation diagnostics: ${animation_peer}')
	}
	unchanged(after_second, second.stats())
	assert first.post(fn () {
		assert ui2.animation_info('moving').status == .completed
		assert first_model.completion_built
		assert_first_editor()
		assert second_window.update(fn () {
			assert_second_editor()
			assert !ui2.has_animated_properties('moving')
		})
		assert_first_editor()
	})
	settled(first)
	settled(second)
	check_tooltip(first, second, first_host, second_host)
	check_ime(first, second)
	check_text_input_guards(first, second)
	check_lifecycle(first, second)
	check_gc_lifetime(first)

	assert first.post(fn [first] () {
		first_window.close()
		assert first.stats().closed
		assert !first.post(fn () { panic('late callback ran on a closed window') })
		assert !first_window.update(fn () { panic('closed window accepted update') })
	})
	for _ in 0 .. 100 {
		if first.stats().closed { break }
		time.sleep(20 * time.millisecond)
	}
	assert first.stats().closed && !second.stats().closed
	peer_before := settled(second)
	peer_pumps := C.ui2_embedder_pump_count(second_host)
	time.sleep(time.second)
	unchanged(peer_before, second.stats())
	assert C.ui2_embedder_pump_count(second_host) == peer_pumps
	assert second.post(fn () {
		assert_second_editor()
		second_window.close()
	})
}

// Return only the coordinator-backed dispatcher. No CustomWindow handle or
// application pointer escapes this helper, so the embedder must own its live
// callback target while Objective-C retains only opaque userData.
fn dispatcher_only_window(probe &GcLifetimeProbe) ui2.UiDispatcher {
	window := ui2.open_window('UI2 embedder GC lifetime acceptance', 280, 180,
		fn [probe] () ui2.Element {
			mut observed := unsafe { probe }
			observed.mutex.lock()
			observed.builds++
			observed.mutex.unlock()
			return ui2.screen(0xf8fafc, [
				ui2.text_input(
					id:          'gc-editor'
					placeholder: ''
					text:        'before collection'
					frame:       ui2.rect(16, 24, 248,
						36)
					box:         ui2.BoxStyle{ bg: 0xe2e8f0 }
					text_style:  ui2.TextStyle{ size: 14 }
					keyboard:    0
					multiline:   false
				) or { panic(err) },
			])
		}) or { panic(err) }
	return window.dispatcher()
}

fn check_gc_lifetime(ui_thread ui2.UiDispatcher) {
	probe := &GcLifetimeProbe{}
	assert ui_thread.post(fn [probe] () {
		dispatcher := dispatcher_only_window(probe)
		mut observed := unsafe { probe }
		observed.mutex.lock()
		observed.dispatcher = dispatcher
		observed.ready = true
		observed.mutex.unlock()
	})
	mut third := ui2.UiDispatcher{}
	mut ready := false
	for _ in 0 .. 100 {
		probe.mutex.lock()
		ready = probe.ready
		third = probe.dispatcher
		probe.mutex.unlock()
		if ready { break }
		time.sleep(20 * time.millisecond)
	}
	assert ready
	before := settled(third)
	assert before.draws > 0
	// Collect from a later callback, after the helper's local handle has left
	// the active stack, and churn allocations between collections.
	assert ui_thread.post(fn [probe] () {
		mut checksum := 0
		for index in 0 .. 8 {
			mut pressure := []u8{len: 512 * 1024}
			pressure[index] = u8(index)
			gc_collect()
			checksum += int(pressure[index])
		}
		assert checksum == 28
		mut observed := unsafe { probe }
		observed.mutex.lock()
		observed.collections = 8
		observed.mutex.unlock()
	})
	mut collections := 0
	for _ in 0 .. 100 {
		probe.mutex.lock()
		collections = probe.collections
		probe.mutex.unlock()
		if collections == 8 { break }
		time.sleep(20 * time.millisecond)
	}
	assert collections == 8
	assert third.post(fn () {
		ui2.set_text('gc-editor', 'survived collection')
		assert ui2.text('gc-editor') == 'survived collection'
		ui2.request_refresh()
	})
	after := settled(third)
	assert after.builds > before.builds && after.draws > before.draws
	probe.mutex.lock()
	builds := probe.builds
	probe.mutex.unlock()
	assert builds >= 2
	assert third.post(fn () { ui2.quit() })
	for _ in 0 .. 100 {
		if third.stats().closed { break }
		time.sleep(20 * time.millisecond)
	}
	assert third.stats().closed
	assert !third.post(fn () { panic('closed dispatcher-only window accepted a callback') })
	println('PASS: dispatcher-only third window survived allocation pressure and eight main-thread GC collections, rebuilt, drew and rejected work after close')
}

fn check_tooltip(first ui2.UiDispatcher, second ui2.UiDispatcher, first_host voidptr,
	second_host voidptr) {
	peer := settled(second)
	peer_pumps := C.ui2_embedder_pump_count(second_host)
	// Visiting an unrelated surface clears a tooltip dismissed by an earlier
	// native focus event, regardless of the user's original pointer position.
	assert first.post(fn () {
		assert C.ui2_fixture_move_pointer(first_window.native_handle(), 500, 440)
	})
	settled(first)
	assert first.post(fn () {
		assert C.ui2_fixture_move_pointer(first_window.native_handle(), 40, 26)
	})
	mut waiting := first.stats()
	for _ in 0 .. 40 {
		if waiting.next_deadline >= 0 { break }
		time.sleep(10 * time.millisecond)
		waiting = first.stats()
	}
	assert waiting.next_deadline >= 0
	deadline_pumps := C.ui2_embedder_pump_count(first_host)
	time.sleep(700 * time.millisecond)
	shown := settled(first)
	report('stationary tooltip deadline', waiting, shown, C.ui2_embedder_pump_count(first_host) - deadline_pumps)
	assert shown.builds == waiting.builds
	assert shown.draws == waiting.draws + 1
	unchanged(peer, second.stats())
	assert C.ui2_embedder_pump_count(second_host) == peer_pumps
}

fn check_ime(first ui2.UiDispatcher, second ui2.UiDispatcher) {
	assert first.post(fn () {
		ui2.focus('input')
		ui2.set_text('input', 'A😀Z')
	})
	settled(first)
	assert first.post(fn () {
		assert C.ui2_fixture_preedit(first_window.native_handle(), c'にほん')
		assert ui2.text('input') == 'A😀Z'
		assert C.ui2_fixture_has_preedit(first_window.native_handle())
		ui2.refresh()
		assert second_window.update(fn () {
			assert_second_editor()
			assert ui2.text('input') == 'A😀Z'
			assert !C.ui2_fixture_has_preedit(second_window.native_handle())
		})
		assert C.ui2_fixture_has_preedit(first_window.native_handle())
	})
	settled(first)
	settled(second)
	assert first.post(fn () {
		assert C.ui2_fixture_has_preedit(first_window.native_handle())
		assert C.ui2_fixture_candidate_inside_window(first_window.native_handle())
		assert ui2.text('input') == 'A😀Z'
		assert C.ui2_fixture_commit(first_window.native_handle(), c'日本')
		assert ui2.text('input') == 'A日本Z'
		assert !C.ui2_fixture_has_preedit(first_window.native_handle())
		ui2.focus('editor')
		ui2.text_area_set_selection('editor', 1, 4)
		assert_first_editor()
	})
	settled(first)
	println('PASS: native NSTextInputClient preedit, UTF-16 emoji replacement, candidate rectangle, commit and composition isolation')
}

fn check_text_input_guards(first ui2.UiDispatcher, second ui2.UiDispatcher) {
	peer := settled(second)
	for readonly in [true, false] {
		assert first.post(fn () {
			ui2.focus('input')
			ui2.set_text('input', 'A😀Z')
		})
		settled(first)
		assert first.post(fn [readonly] () {
			assert C.ui2_fixture_preedit(first_window.native_handle(), c'にほん')
			assert C.ui2_fixture_has_preedit(first_window.native_handle())
			assert ui2.text('input') == 'A😀Z'
			first_model.input_readonly = readonly
			first_model.input_disabled = !readonly
			ui2.request_refresh()
		})
		settled(first)
		assert first.post(fn () {
			assert !C.ui2_fixture_has_preedit(first_window.native_handle())
			assert ui2.text('input') == 'A😀Z'
			// The disabled native client falls back to character callbacks;
			// retained focus must not let that fallback edit the committed model.
			assert C.ui2_fixture_commit(first_window.native_handle(), c'blocked')
			assert ui2.text('input') == 'A😀Z'
			assert C.ui2_fixture_preedit(first_window.native_handle(), c'にほん')
			assert !C.ui2_fixture_has_preedit(first_window.native_handle())
			assert ui2.text('input') == 'A😀Z'
			first_model.input_readonly = false
			first_model.input_disabled = false
			ui2.request_refresh()
		})
		settled(first)
		assert first.post(fn () {
			assert !C.ui2_fixture_has_preedit(first_window.native_handle())
			assert ui2.text('input') == 'A😀Z'
			assert C.ui2_fixture_commit(first_window.native_handle(), c'B')
			assert ui2.text('input') == 'A😀ZB'
			ui2.focus('editor')
			ui2.text_area_set_selection('editor', 1, 4)
			assert_first_editor()
		})
		settled(first)
	}
	unchanged(peer, second.stats())
	println('PASS: readonly and disabled transitions discard preedit, reject native commit/character fallback, preserve committed text and resume editing when enabled')
}

fn check_lifecycle(first ui2.UiDispatcher, second ui2.UiDispatcher) {
	assert first.post(fn () {
		assert C.ui2_fixture_minimize_restore(first_window.native_handle(), 1500)
	})
	mut suspended := first.stats()
	for _ in 0 .. 100 {
		if suspended.suspended { break }
		time.sleep(20 * time.millisecond)
		suspended = first.stats()
	}
	assert suspended.suspended
	peer := settled(second)
	time.sleep(300 * time.millisecond)
	midpoint := first.stats()
	assert midpoint.suspended
	assert midpoint.draws == suspended.draws
	assert midpoint.builds == suspended.builds
	unchanged(peer, second.stats())
	mut restored := midpoint
	for _ in 0 .. 200 {
		time.sleep(20 * time.millisecond)
		restored = first.stats()
		if !restored.suspended && restored.draws > midpoint.draws { break }
	}
	assert !restored.suspended
	assert restored.draws > midpoint.draws
	assert restored.builds > midpoint.builds
	assert first.post(fn () { assert_first_editor() })
	idle := settled(first)
	time.sleep(300 * time.millisecond)
	unchanged(idle, first.stats())
	println('PASS: real NSWindow minimized, restored with a complete frame, retained editor/scroll state and returned to idle')
}
