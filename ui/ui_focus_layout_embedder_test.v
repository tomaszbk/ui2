// vtest vflags: -d ui2_custom_rendering -d ui2_embedder
// vfmt off
@[has_globals]
module ui2

$if macos && ui2_custom_rendering ? && ui2_embedder ? && !ui2_headless ? {
	import sokol.gfx
	import sokol.sgl as _

	#include "@VMODROOT/tests/render_scheduler/draw_commands.h"
	fn C.ui2_test_pump(data voidptr, pump fn (voidptr) i64) i64

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
		mut w := event.window
		if event.kind != .scroll || !focus_layout_reenter { return }
		focus_layout_events << 'A'
		w.scroll_to_offset('pane_b', 10_000)
	}
	fn focus_layout_b_old(event ElementEvent) {
		if event.kind == .scroll { focus_layout_events << 'old B' }
	}
	fn focus_layout_b(event ElementEvent) {
		mut w := event.window
		if event.kind != .scroll { return }
		focus_layout_events << 'current B:${event.value}'
		focus_layout_reenter = false
		focus_layout_tail = 'next generation ñ'
		w.refresh_element('tail', Element{kind: .label, id: 'tail', text: focus_layout_tail, frame: rect(0, 0, 120, 30)})
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
	fn focus_layout_build(mut w Window) Element {
		focus_layout_builds++
		declared := focus_layout_root()
		if focus_layout_build_cancel {
			focus_layout_build_cancel = false
			w.request_refresh()
		}
		if focus_layout_build_reenter {
			focus_layout_build_reenter = false
			focus_layout_tail = 'builder next generation'
			w.refresh_element('tail', Element{kind: .label, id: 'tail', text: focus_layout_tail, frame: rect(0, 170, 120, 30)})
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
		mut app := new_app()
		mut w := app.new_window(title: 'Retained layout and focus combination', width: 320, height: 240, build: focus_layout_build)!
		defer { w.quit() }
		assert C.ui2_test_pump(w, embedder_pump) == -1
		builds := focus_layout_builds
		w.focus('edit')
		assert w.focused_id() == 'edit'
		w.set_text('edit', 'ñ café🙂')
		w.text_area_set_selection('edit', 1, 2)
		embedder_text(w, &C.ui2_embedder_text_event{kind: 2, text: 'á'.str, replacement_start: -1, selection_start: 1})
		focus_layout_before = (w.semantic_node('edit') or { panic('missing editor') }).frame
		focus_layout_local = w.text('edit')
		assert focus_layout_before.y > 0 && focus_layout_before.height == 40
		composition := w.composition
		assert C.ui2_test_pump(w, embedder_pump) == -1
		w.layout_tree.reset_stats()
		caption := focus_layout_root().children[0].children[0].children[0]
		w.refresh_element('caption', Element{...caption, text_style: TextStyle{...caption.text_style, color: 0xff0000}})
		assert C.ui2_test_pump(w, embedder_pump) == -1
		assert w.layout_tree.stats().measure_visits == 0 && w.layout_tree.stats().layout_visits == 0
		assert focus_layout_builds == builds
		focus_layout_caption = 'palabra palabra palabra palabra palabra palabra palabra palabra palabra palabra palabra palabra'
		w.refresh_element('caption', focus_layout_root().children[0].children[0].children[0])
		assert C.ui2_test_pump(w, embedder_pump) == -1
		assert focus_layout_builds == builds && w.layout_tree.stats().builds == 0
		assert w.composition == composition
		assert w.focused_id() == 'edit' && w.text('edit') == focus_layout_local
		assert w.text_area_caret('edit') == 3 && w.text_area_selection_length('edit') == 2
		assert (w.semantic_node('edit') or { panic('missing moved editor') }).frame.y > focus_layout_before.y
		assert w.scroll_offset('pane_a') == 0, 'unrelated size patch retains the current scroll offset'
		// Entering a scope clears the previous editor composition by contract.
		w.scroll_to_offset('pane_a', 0)
		assert w.enter_focus_scope('scope') && w.focused_id() == 'inside'
		// Publish a changed offscreen B before the scope restoration can notify A.
		focus_layout_b_current = true
		focus_layout_scope_enabled = false
		focus_layout_reenter = true
		focus_layout_events.clear()
		w.refresh_element('pane_b', focus_layout_pane_b())
		w.refresh_element('scope', focus_layout_root().children[2])
		draws := w.scheduler.stats().draws
		gpu_frame := gfx.query_frame_stats().frame_index
		assert C.ui2_test_pump(w, embedder_pump) == 0
		assert focus_layout_events == ['A', 'current B:86.0']
		assert w.scheduler.stats().draws == draws, 'restoration callback cancels stale paint'
		assert gfx.query_frame_stats().frame_index == gpu_frame
		assert w.layout_patches.len == 1, 'callback patch survives the detached current batch'
		assert w.active_focus_scope() == '' && w.focused_id() == 'edit'
		assert w.scroll_offset('pane_b') == 86
		assert w.scroll_viewports[named_scroll_state_id('pane_b')].height == 120
		assert w.scroll_parents[named_scroll_state_id('pane_b')] == named_scroll_state_id('outer_b')
		assert (w.semantic_node('inside') or { panic('missing disabled control') }).state.disabled
		assert !w.perform_semantic_action('inside', .focus)
		assert C.ui2_test_pump(w, embedder_pump) == -1
		assert w.scheduler.stats().draws == draws + 1
		assert w.layout_patches.len == 0
		assert (w.semantic_node('tail') or { panic('missing reentrant patch') }).label == focus_layout_tail
		assert w.focused_id() == 'edit' && w.text('edit') == focus_layout_local
		assert w.text_area_caret('edit') == 3 && w.text_area_selection_length('edit') == 2
		// Builder reentry also belongs to the next generation, independently of
		// animation and focus-restoration callback reentry.
		focus_layout_build_reenter = true
		w.request_refresh()
		assert C.ui2_test_pump(w, embedder_pump) == 0
		assert (w.semantic_node('tail') or { panic('missing current tail') }).label == 'next generation ñ'
		assert C.ui2_test_pump(w, embedder_pump) == -1
		assert (w.semantic_node('tail') or { panic('missing deferred tail') }).label == 'builder next generation'
		// Cancellation before resolve must retain the detached, unapplied batch.
		focus_layout_build_cancel = true
		focus_layout_tail = 'retained after canceled builder'
		w.refresh_element('tail', Element{kind: .label, id: 'tail', text: focus_layout_tail, frame: rect(0, 170, 120, 30)})
		w.request_refresh()
		before_cancel_draws := w.scheduler.stats().draws
		assert C.ui2_test_pump(w, embedder_pump) == 0
		assert w.scheduler.stats().draws == before_cancel_draws
		assert (w.semantic_node('tail') or { panic('missing old tail') }).label == 'builder next generation'
		assert C.ui2_test_pump(w, embedder_pump) == -1
		assert w.scheduler.stats().draws == before_cancel_draws + 1
		assert (w.semantic_node('tail') or { panic('lost canceled batch') }).label == 'retained after canceled builder'
		eprintln('owned retained layout focus current offscreen Scroll reentrant patch and repaint passed')
	}
}
