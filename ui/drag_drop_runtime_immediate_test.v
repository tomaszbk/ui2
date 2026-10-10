// vtest build: macos && ui2_custom_rendering? && ui2_drag_runtime_probe? && !ui2_embedder?
// vtest vflags: -d ui2_custom_rendering
// Opt-in macOS gg/Sokol Metal fixture: pass -d ui2_drag_runtime_probe.
// Input is injected on the UI thread through the existing gg event handler.
// It verifies the real renderer, resources and idle scheduler, not OS input.
// Unrelated desktop pointer/key/focus input is gated during the fixture.
// For raster evidence add -d gg_record -d darwin_sokol_glcore33 and set
// UI2_DRAG_CAPTURE=1 with gg's VGG_SCREENSHOT_* / VGG_STOP_AT_FRAME variables.
@[has_globals]
module ui2

$if macos && ui2_custom_rendering ? && ui2_drag_runtime_probe ? && !ui2_embedder ? {
	import gg
	import os
	import time
	import sokol.sapp

	const drag_runtime_image = @VMODROOT + '/examples/users/logo.png'
	__global drag_runtime_drops = 0
	__global drag_runtime_cancels = 0
	__global drag_runtime_highlight = false
	__global drag_runtime_composition = TextComposition{}
	__global drag_runtime_image_page = 0

	fn drag_runtime_accept(_ DragOffer) DragOperation { return .move }
	fn drag_runtime_event(event ElementEvent) {
		println('RUNTIME ${event.kind}')
		if event.kind == .drag_enter { drag_runtime_highlight = true }
		if event.kind == .drag_leave { drag_runtime_highlight = false }
		if event.kind == .drop { drag_runtime_drops++ }
		if event.kind == .drag_cancel { drag_runtime_cancels++ }
	}
	fn drag_runtime_build() Element {
		editor := text_input(id: 'editor', text: 'declared español',
			frame: rect(24, 430, 420, 40), box: BoxStyle{bg: 0xffffff},
			text_style: TextStyle{size: 18}) or { panic(err) }
		return screen(0xf1f5f9, [
			scaled_content('composition', rect(24, 100, 720, 280), 360, 140, BoxStyle{bg: 0xe2e8f0}, [
				with_event(with_drag_source(view('source', rect(10, 30, 90, 50), BoxStyle{bg: 0x3b82f6}, []),
					DragSource{preview: DragPreview{text: 'Niño / café', image_path: drag_runtime_image,
						width: 90, height: 38, offset_x: 6, offset_y: 6}}), drag_runtime_event),
				with_event(with_drop_target(view('target', rect(130, 30, 100, 70), BoxStyle{bg: if drag_runtime_highlight { u32(0x15803d) } else { u32(0x16a34a) }}, []),
					DropTarget{accept: drag_runtime_accept}), drag_runtime_event),
			]),
			image('shared-image', drag_runtime_image, rect(650, 430, 60, 60)),
			editor,
		])
	}
	fn drag_runtime_assert_editor() {
		assert text('editor') == 'niño café'
		assert g_text_editors['editor'].selection == TextSelection{anchor: 2, caret: 5}
		assert g_focused_field == 'editor'
		assert g_gg_app.composition == drag_runtime_composition
		assert g_gg_app.ctx.images.entries.len == 1
		assert g_gg_app.ctx.images.entries[image_entry_key(drag_runtime_image,0)].page == drag_runtime_image_page
	}
	fn drag_runtime_host_event(event &gg.Event, data voidptr) {
		// Keep real surface/lifecycle handling. The injected interaction owns
		// pointer/key/focus input so another app's desktop automation cannot
		// change its anchor or contaminate the idle intervals.
		if event.typ in [.resized, .iconified, .restored, .suspended, .resumed] {
			on_event(event, unsafe { &GgApp(data) })
		}
	}
	fn drag_runtime_driver(dispatcher UiDispatcher) {
		// Wait for current geometry, rather than racing the first frame/font init.
		for dispatcher.stats().draws == 0 { time.sleep(100 * time.millisecond) }
		time.sleep(100 * time.millisecond)
		dispatcher.post(fn () {
			g_gg_app.ctx.inner.config = gg.Config{...g_gg_app.ctx.inner.config, event_fn: drag_runtime_host_event}
			focus('editor')
			editor := TextEditor{text: 'niño café'.clone(), selection: TextSelection{anchor: 2, caret: 5}}
			replace_text_value('editor', editor.text)
			replace_text_editor('editor', editor)
			g_gg_app.composition.update('editor', editor, 'á', 1, 0, -1, 0)
			drag_runtime_composition = g_gg_app.composition
			drag_runtime_image_page = g_gg_app.ctx.images.entries[image_entry_key(drag_runtime_image,0)].page
			// The public example highlights in enter. A coalesced release must
			// drop after that paint-only declaration change, before another frame.
			before := g_gg_app.scheduler.stats()
			on_event(&gg.Event{typ: .mouse_down, mouse_x: 100, mouse_y: 190}, g_gg_app)
			on_event(&gg.Event{typ: .mouse_up, mouse_x: 340, mouse_y: 190}, g_gg_app)
			assert drag_runtime_drops == 1 && drag_runtime_cancels == 0
			assert g_gg_app.scheduler.stats().draws == before.draws
			println('METAL highlight coalesced release before-frame drop1 cancel0 PASS')
			on_event(&gg.Event{typ: .mouse_down, mouse_x: 100, mouse_y: 190}, g_gg_app)
			on_event(&gg.Event{typ: .mouse_move, mouse_x: 340, mouse_y: 190}, g_gg_app)
			assert drag_active() && g_touch.pointer_captured
		})
		time.sleep(1500 * time.millisecond)
		if os.getenv('UI2_DRAG_CAPTURE') == '1' {
			dispatcher.post(fn () {
				drag_runtime_assert_editor()
				on_event(&gg.Event{typ: .mouse_move, mouse_x: 748, mouse_y: 530}, g_gg_app)
			})
			return // gg's recorder closes at the requested frame
		}
		dispatcher.post(fn () {
			on_event(&gg.Event{typ: .mouse_up, mouse_x: 340, mouse_y: 190}, g_gg_app)
			assert !drag_active() && !g_touch.pointer_captured
			assert drag_runtime_drops == 2 && drag_runtime_cancels == 0
			drag_runtime_assert_editor()
		})
		time.sleep(time.second)
		before := dispatcher.stats()
		time.sleep(30 * time.second)
		after := dispatcher.stats()
		println('DROP_IDLE builds=${after.builds-before.builds} draws=${after.draws-before.draws} callbacks=${after.callbacks-before.callbacks} pending=${after.pending} deadline=${after.next_deadline}')
		assert after.builds == before.builds && after.draws == before.draws
		assert !after.pending && after.next_deadline == -1 && !after.animation_active
		dispatcher.post(fn () {
			on_event(&gg.Event{typ: .mouse_down, mouse_x: 100, mouse_y: 190}, g_gg_app)
			on_event(&gg.Event{typ: .mouse_move, mouse_x: 340, mouse_y: 190}, g_gg_app)
			on_event(&gg.Event{typ: .key_down, key_code: .escape}, g_gg_app)
			assert !drag_active() && !g_touch.pointer_captured
			assert drag_runtime_drops == 2 && drag_runtime_cancels == 1
			drag_runtime_assert_editor()
		})
		time.sleep(time.second)
		cancel_before := dispatcher.stats()
		time.sleep(30 * time.second)
		cancel_after := dispatcher.stats()
		println('CANCEL_IDLE builds=${cancel_after.builds-cancel_before.builds} draws=${cancel_after.draws-cancel_before.draws} callbacks=${cancel_after.callbacks-cancel_before.callbacks} pending=${cancel_after.pending} deadline=${cancel_after.next_deadline}')
		assert cancel_after.builds == cancel_before.builds && cancel_after.draws == cancel_before.draws
		assert !cancel_after.pending && cancel_after.next_deadline == -1 && !cancel_after.animation_active
		dispatcher.post(fn () { sapp.request_quit() })
	}
	fn test_drag_drop_metal_runtime_idle_and_edit_preservation() {
		spawn drag_runtime_driver(ui_dispatcher())
		run_window('Drag Drop Runtime Fixture', 768, 550, drag_runtime_build)
	}
}
