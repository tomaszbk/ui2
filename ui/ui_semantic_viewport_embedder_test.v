// vtest vflags: -d ui2_custom_rendering -d ui2_embedder
// vfmt off
@[has_globals]
module ui2

$if macos && ui2_custom_rendering ? && ui2_embedder ? && !ui2_headless ? {
import macos

fn semantic_viewport_host_root() Element {
	return screen(0xffffff, [scaled_content('scaled', rect(10, 20, 200, 100), 100, 100, BoxStyle{}, [
		Element{kind: .label, id: 'caption', frame: rect(5.25, 6.5, 20.5, 10.25)},
	])])
}

fn test_owned_screen_semantics_read_resized_native_viewport_before_render_pump() {
	pool := macos.autorelease_pool_new()
	defer { macos.release(pool) }
	previous_app := g_gg_app
	previous := activate_custom_window_state(new_custom_window_state())
	defer { activate_custom_window_state(previous); g_gg_app = previous_app }
	// Use the normal real NSWindow/Metal creation route. An unavailable device
	// fails this host fixture; there is no substitute GPU or skipped assertion.
	window := open_window('Semantic viewport before paint', 400, 300, semantic_viewport_host_root) or { panic(err) }
	defer { window.close() }
	g_gg_app = window.app
	activate_custom_window_state(window.app.window_state)
	update_custom_focus_tree(semantic_viewport_host_root())
	before := render_stats()
	assert before.draws == 0
	assert semantic_tree()[0].frame == rect(0, 0, 400, 300)
	assert render_stats() == before
	macos.msg_void_point(window.native_handle(), 'setContentSize:', macos.point(520, 360))
	resized := render_stats()
	assert window.app.ctx.width == 400 && window.app.ctx.height == 300
	assert semantic_tree()[0].frame == rect(0, 0, 520, 360)
	assert (semantic_node('caption') or { panic('missing scaled host child') }).frame == rect(65.25, 26.5, 20.5, 10.25)
	assert render_stats() == resized && resized.draws == 0
	assert window.app.ctx.width == 400 && window.app.ctx.height == 300
}
}
