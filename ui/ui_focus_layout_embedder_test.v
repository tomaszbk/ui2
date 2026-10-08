// vtest vflags: -d ui2_custom_rendering -d ui2_embedder
// vfmt off
@[has_globals]
module ui2

$if macos && ui2_custom_rendering ? && ui2_embedder ? && !ui2_headless ? {
	import sokol.gfx
	import sokol.sgl as _

	#include "@VMODROOT/tests/render_scheduler/draw_commands.h"
	fn C.ui2_test_pump(data voidptr, pump fn (voidptr) i64) i64

	// Execute synthetic public API calls in this owned window without the
	// CustomWindow.update contract's unconditional model-build request.
	fn focus_layout_update(window CustomWindow, task fn ()) bool {
		previous_app := g_gg_app
		previous_state := activate_custom_window_state(window.app.window_state)
		g_gg_app = window.app
		defer { activate_custom_window_state(previous_state); g_gg_app = previous_app }
		task()
		return true
	}
	__global focus_layout_before Rect
	__global focus_layout_local string
	__global focus_layout_build_cancel bool
	__global focus_layout_build_reenter bool
	__global focus_layout_builds int
	__global focus_layout_caption = 'breve'
	__global focus_layout_b_current bool
	__global focus_layout_scope_enabled = true
	__global focus_layout_reenter bool
	__global focus_layout_tail = 'before'
	__global focus_layout_events = []string{}

	fn focus_layout_a(event ElementEvent) {
		if event.kind != .scroll || !focus_layout_reenter { return }
		focus_layout_events << 'A'
		scroll_to_offset('pane_b', 10_000)
	}
	fn focus_layout_b_old(event ElementEvent) {
		if event.kind == .scroll { focus_layout_events << 'old B' }
	}
	fn focus_layout_b(event ElementEvent) {
		if event.kind != .scroll { return }
		focus_layout_events << 'current B:${event.value}'
		focus_layout_reenter = false
		focus_layout_tail = 'next generation ñ'
		refresh_element('tail', Element{kind: .label, id: 'tail', text: focus_layout_tail, frame: rect(0, 0, 120, 30)})
	}
	fn focus_layout_pane_b() Element {
		return Element{kind: .scroll, id: 'pane_b', frame: rect(0, 500, 130, if focus_layout_b_current { 120 } else { 100 }),
			on_event: if focus_layout_b_current { focus_layout_b } else { focus_layout_b_old },
			children: [Element{kind: .label, id: 'b_bottom', text: 'B content', frame: rect(0, if focus_layout_b_current { 160 } else { 300 }, 110, 30)}]}
	}
	fn focus_layout_root() Element {
		caption := label('caption', focus_layout_caption, Rect{}, TextStyle{size: 18, lines: 30})
		column := flex(FlexConfig{id: 'column', frame: rect(0, 0, 120, 600), orientation: .vertical, align: .stretch,
			children: [FlexChild{element: caption, shrink: 0}, FlexChild{element: Element{kind: .text_area, id: 'edit', key: 'editor', text: 'declarado', disable_scroll: true, frame: rect(0, 0, 0, 40)}, shrink: 0}]}) or { panic(err) }
		return screen(0xffffff, [
			Element{kind: .scroll, id: 'pane_a', frame: rect(0.5, 0.25, 140, 100), on_event: focus_layout_a, children: [column]},
			Element{kind: .scroll, id: 'outer_b', frame: rect(160, 0, 140, 100), children: [focus_layout_pane_b()]},
			Element{kind: .view, id: 'scope', enabled: focus_layout_scope_enabled, focus_scope: true, frame: rect(160, 110, 140, 50), children: [Element{kind: .button, id: 'inside', text: 'Inside', frame: rect(0, 0, 100, 30)}]},
			Element{kind: .label, id: 'tail', text: focus_layout_tail, frame: rect(0, 170, 120, 30)},
		])
	}
	fn focus_layout_build() Element {
		focus_layout_builds++
		declared := focus_layout_root()
		if focus_layout_build_cancel {
			focus_layout_build_cancel = false
			refresh()
		}
		if focus_layout_build_reenter {
			focus_layout_build_reenter = false
			focus_layout_tail = 'builder next generation'
			refresh_element('tail', Element{kind: .label, id: 'tail', text: focus_layout_tail, frame: rect(0, 170, 120, 30)})
		}
		return declared
	}
	fn test_owned_retained_layout_focus_scroll_and_reentrant_patch_combination() {
		focus_layout_builds = 0
		focus_layout_caption = 'breve'
		focus_layout_b_current = false
		focus_layout_scope_enabled = true
		focus_layout_reenter = false
		focus_layout_tail = 'before'
		focus_layout_events.clear()
		window := open_window('Retained layout and focus combination', 320, 240, focus_layout_build)!
		defer { window.close() }
		assert C.ui2_test_pump(window.app, embedder_pump) == -1
		builds := focus_layout_builds
		assert focus_layout_update(window, fn () {
			focus('edit')
			assert focused_id() == 'edit'
			set_text('edit', 'ñ café🙂')
			text_area_set_selection('edit', 1, 2)
			embedder_text(g_gg_app, &C.ui2_embedder_text_event{kind: 2, text: 'á'.str, replacement_start: -1, selection_start: 1})
			focus_layout_before = (semantic_node('edit') or { panic('missing editor') }).frame
			focus_layout_local = text('edit')
			assert focus_layout_before.y > 0 && focus_layout_before.height == 40
		})
		composition := window.app.composition
		assert C.ui2_test_pump(window.app, embedder_pump) == -1
		assert focus_layout_update(window, fn () { g_gg_app.layout_tree.reset_stats() })
		assert focus_layout_update(window, fn () {
			caption := focus_layout_root().children[0].children[0].children[0]
			refresh_element('caption', Element{...caption, text_style: TextStyle{...caption.text_style, color: 0xff0000}})
		})
		assert C.ui2_test_pump(window.app, embedder_pump) == -1
		assert window.app.layout_tree.stats().measure_visits == 0 && window.app.layout_tree.stats().layout_visits == 0
		assert focus_layout_builds == builds
		focus_layout_caption = 'palabra palabra palabra palabra palabra palabra palabra palabra palabra palabra palabra palabra'
		assert focus_layout_update(window, fn () { refresh_element('caption', focus_layout_root().children[0].children[0].children[0]) })
		assert C.ui2_test_pump(window.app, embedder_pump) == -1
		assert focus_layout_builds == builds && window.app.layout_tree.stats().builds == 0
		assert window.app.composition == composition
		assert focus_layout_update(window, fn () {
			assert focused_id() == 'edit' && text('edit') == focus_layout_local
			assert text_area_caret('edit') == 3 && text_area_selection_length('edit') == 2
			assert (semantic_node('edit') or { panic('missing moved editor') }).frame.y > focus_layout_before.y
			assert scroll_offset('pane_a') == 0, 'unrelated size patch retains the current scroll offset'
			// Entering a scope clears the previous editor composition by contract.
			scroll_to_offset('pane_a', 0)
			assert enter_focus_scope('scope') && focused_id() == 'inside'
		})
		// Publish a changed offscreen B before the scope restoration can notify A.
		focus_layout_b_current = true
		focus_layout_scope_enabled = false
		focus_layout_reenter = true
		focus_layout_events.clear()
		assert focus_layout_update(window, fn () {
			refresh_element('pane_b', focus_layout_pane_b())
			refresh_element('scope', focus_layout_root().children[2])
		})
		draws := window.app.scheduler.stats().draws
		gpu_frame := gfx.query_frame_stats().frame_index
		assert C.ui2_test_pump(window.app, embedder_pump) == 0
		assert focus_layout_events == ['A', 'current B:86.0']
		assert window.app.scheduler.stats().draws == draws, 'restoration callback cancels stale paint'
		assert gfx.query_frame_stats().frame_index == gpu_frame
		assert window.app.layout_patches.len == 1, 'callback patch survives the detached current batch'
		assert focus_layout_update(window, fn () {
			assert active_focus_scope() == '' && focused_id() == 'edit'
			assert scroll_offset('pane_b') == 86
			assert g_scroll_viewports[named_scroll_state_id('pane_b')].height == 120
			assert g_scroll_parents[named_scroll_state_id('pane_b')] == named_scroll_state_id('outer_b')
			assert (semantic_node('inside') or { panic('missing disabled control') }).state.disabled
			assert !perform_semantic_action('inside', .focus)
		})
		assert C.ui2_test_pump(window.app, embedder_pump) == -1
		assert window.app.scheduler.stats().draws == draws + 1
		assert window.app.layout_patches.len == 0
		assert focus_layout_update(window, fn () {
			assert (semantic_node('tail') or { panic('missing reentrant patch') }).label == focus_layout_tail
			assert focused_id() == 'edit' && text('edit') == focus_layout_local
			assert text_area_caret('edit') == 3 && text_area_selection_length('edit') == 2
		})
		// Builder reentry also belongs to the next generation, independently of
		// animation and focus-restoration callback reentry.
		focus_layout_build_reenter = true
		assert focus_layout_update(window, fn () { refresh() })
		assert C.ui2_test_pump(window.app, embedder_pump) == 0
		assert focus_layout_update(window, fn () {
			assert (semantic_node('tail') or { panic('missing current tail') }).label == 'next generation ñ'
		})
		assert C.ui2_test_pump(window.app, embedder_pump) == -1
		assert focus_layout_update(window, fn () {
			assert (semantic_node('tail') or { panic('missing deferred tail') }).label == 'builder next generation'
		})
		// Cancellation before resolve must retain the detached, unapplied batch.
		focus_layout_build_cancel = true
		focus_layout_tail = 'retained after canceled builder'
		assert focus_layout_update(window, fn () {
			refresh_element('tail', Element{kind: .label, id: 'tail', text: focus_layout_tail, frame: rect(0, 170, 120, 30)})
			refresh()
		})
		before_cancel_draws := window.app.scheduler.stats().draws
		assert C.ui2_test_pump(window.app, embedder_pump) == 0
		assert window.app.scheduler.stats().draws == before_cancel_draws
		assert focus_layout_update(window, fn () {
			assert (semantic_node('tail') or { panic('missing old tail') }).label == 'builder next generation'
		})
		assert C.ui2_test_pump(window.app, embedder_pump) == -1
		assert window.app.scheduler.stats().draws == before_cancel_draws + 1
		assert focus_layout_update(window, fn () {
			assert (semantic_node('tail') or { panic('lost canceled batch') }).label == 'retained after canceled builder'
		})
		eprintln('owned retained layout focus current offscreen Scroll reentrant patch and repaint passed')
	}
}
