// vtest vflags: -d ui2_custom_rendering
// vfmt off
@[has_globals]
module ui2

$if macos && ui2_custom_rendering ? && !ui2_headless ? {
import gg

fn test_custom_screen_semantics_read_current_context_before_paint_without_invalidating() {
	previous_app := g_gg_app
	previous := activate_custom_window_state(new_custom_window_state())
	mut menus := menu_state()
	previous_menus := menus.menus
	menus.menus = []Menu{}
	defer { activate_custom_window_state(previous); g_gg_app = previous_app; menus.menus = previous_menus }
	// No GPU is involved in this context geometry fixture. Rendering and host
	// lifecycle coverage keep their separate real Metal assertions.
	mut inner := &gg.Context{width: 400, height: 300, scale: 2}
	mut ctx := &DrawContext{inner: inner, width: 320, height: 240, scale: 2}
	g_gg_app = &GgApp{ctx: ctx}
	root := screen(0xffffff, [scaled_content('scaled', rect(10, 20, 200, 100), 100, 100, BoxStyle{}, [
		Element{kind: .label, id: 'caption', frame: rect(5.25, 6.5, 20.5, 10.25)},
	])])
	update_custom_focus_tree(root)
	before := render_stats()
	snapshot := semantic_tree()
	eprintln('custom current root=${snapshot[0].frame}')
	assert snapshot[0].frame == rect(0, 0, 400, 300)
	assert (semantic_node('scaled') or { panic('missing scaled viewport') }).frame == rect(10, 20, 200, 100)
	assert (semantic_node('caption') or { panic('missing scaled child') }).frame == rect(65.25, 26.5, 20.5, 10.25)
	inner.width = 520
	inner.height = 360
	inner.scale = 3
	assert semantic_tree()[0].frame == rect(0, 0, 520, 360)
	assert render_stats() == before && g_focus_navigation.root.frame == root.frame
	assert ctx.content_transform == ContentTransform{}
	// Owned contexts publish their live logical size independently of gg's
	// compatibility context and of the physical swapchain dimensions.
	ctx.owns_surface = true
	ctx.width = 640
	ctx.height = 480
	ctx.scale = 2
	assert semantic_tree()[0].frame == rect(0, 0, 640, 480)
	assert render_stats() == before
	menus.menus = [Menu{title: 'File'}]
	assert semantic_tree()[0].frame == rect(0, menu_bar_height(), 640, 480 - menu_bar_height())
	assert (semantic_node('caption') or { panic('missing menu-offset child') }).frame == rect(65.25, 26.5 + menu_bar_height(), 20.5, 10.25)
	assert render_stats() == before
	g_focus_navigation.root = root.children[0]
	assert semantic_tree()[0].frame == rect(10, 20 + menu_bar_height(), 200, 100)
}
}
