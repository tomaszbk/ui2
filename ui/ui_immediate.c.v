// vfmt off
// Keep the imports inside the platform block. Hoisting gg imports makes the
// AppKit backend compile Sokol's ARC sources together with Objective-C MRC.
@[has_globals]
module ui2

$if ( android || linux || ( ( macos || windows ) && ui2_custom_rendering ?) ) && !ui2_headless ? {
	import gg
	import math
	import os
	import sokol.sapp
	import sokol.gfx
	import time

	struct HitTarget {
		is_vector_canvas bool
		vector_shapes []VectorShape
		vector_hit_mode VectorHitMode
		vector_origin Rect
		identity                  string
		kind                      Kind = .view
		content_transform         ContentTransform
		local_frame               Rect
		clip_region               ClipRegion
		has_geometry              bool
		id                        string
		on_event                  ElementCallback = unsafe { nil }
		x                         f64
		y                         f64
		w                         f64
		h                         f64
		long_press                bool
		swipe_left                bool
		text_field                bool
		text_area                 bool
		checkbox                  bool
		checkbox_state            bool
		dropdown                  bool
		slider                    bool
		switch_control            bool
		switch_state              bool
		toggle_button             bool
		toggle_group              string
		toggle_allow_no_selection bool
		slider_frame              Rect
		slider_padding            f64
		slider_spec               SliderSpec
		options                   []string
		// dropdown_option marks one row of the open dropdown list; id names the
		// owning dropdown and option_index the value the row selects.
		dropdown_option bool
		option_index    int
		clickable       bool
		button_behavior bool
		draggable       bool
	}

	struct TouchState {
	mut:
		// The generation that started this gesture, not the current window
		// generation. An aborted focus reveal must preserve a newer gesture.
		input_generation   u64
		// A rebuild can move a dragged view away from the initial press.
		// Keep its event identity until release instead of hit-testing it again.
		pointer_captured   bool
		pointer_target     HitTarget
		pressed_id         string // visual press owner, including ordinary controls
		down               bool
		start_x            f64
		start_y            f64
		current_x          f64
		current_y          f64
		start_time         i64
		moved              bool
		scroll_id          string
		scroll_chain       []string
		long_press_fired   bool
		scrollbar_drag     bool
		scrollbar_grab_y   f64
	}

	@[heap]
	struct GgApp {
	mut:
		ctx &DrawContext = unsafe { nil }
		scheduler &FrameCoordinator = new_frame_coordinator()
		layout_tree &LayoutTree = &LayoutTree{}
		layout_environment LayoutEnvironment
		layout_patches []LayoutPatch
		declared_root Element
		declaration_pending bool
		has_root bool
		iconified bool
		suspended bool
		dpi_scale f32
		draining_tasks bool
		window_state &CustomWindowState = unsafe { nil }
		native_window voidptr
		last_frame i64 = -1
		surface_retry_at i64 = -1
		callback_depth int
		cleanup_pending bool
		composition TextComposition
		text_caret Rect
		editable_fields map[string]bool
		presentation_revision u64
		visual_geometries map[string]VisualGeometry
	}

	// DropdownPopup caches the geometry of the open dropdown list. The list is
	// drawn after the element tree so it floats above every other control, and
	// it is recomputed each frame to stay anchored to a moving control.
	struct DropdownPopup {
	mut:
		id         string
		on_event   ElementCallback = unsafe { nil }
		x          f64
		y          f64
		width      f64
		height     f64
		row_height f64
		options    []string
		selected   int = -1
		text_style TextStyle
		radius     f64
		max_scroll f64
		mounted    bool
	}

	const dropdown_popup_padding = 4.0
	const dropdown_popup_gap = 4.0
	const dropdown_popup_margin = 4.0
	const dropdown_popup_min_row_height = 24.0

	// TooltipTarget is a region of the window with hover text: an element's
	// declared tooltip, or the full text of a line the renderer had to shorten
	// to fit it. A target without text is an opaque surface drawn over earlier
	// targets, which hides their tooltips just as it hides the targets.
	struct TooltipTarget {
		is_vector_canvas bool
		vector_shapes []VectorShape
		vector_hit_mode VectorHitMode
		vector_origin Rect
		// key tells the pointer resting on one target apart from moving on to
		// another, across frames that rebuild every target from scratch.
		key               string
		text              string
		frame             Rect
		local_frame       Rect
		content_transform ContentTransform
		clip_region       ClipRegion
		has_geometry      bool
	}

	// TooltipState follows the pointer. Its cancelable deadline belongs to the
	// window coordinator, so a stationary pointer also works in on-demand mode.
	struct TooltipState {
	mut:
		pointer_x  f64
		pointer_y  f64
		pointer_in bool
		key        string
		rest_since i64
		// dismissed is a tooltip closed by a click or a key press. It stays
		// closed until the pointer reaches another target, so it does not pop
		// back up over what the user is now doing with this one.
		dismissed  bool
		visible    bool
		anchor_x   f64
		anchor_y   f64
		text       string
	}

	const tooltip_delay_ms = i64(500)
	const tooltip_offset_x = 12.0
	const tooltip_offset_y = 20.0
	const tooltip_gap = 6.0
	const tooltip_margin = 4.0
	const tooltip_padding = 6.0
	const tooltip_radius = 4.0
	const tooltip_text_size = 12.0
	const tooltip_max_text_width = 360.0
	const tooltip_max_lines = 12
	const tooltip_background = u32(0xfffff0)
	const tooltip_border = u32(0x94a3b8)
	const tooltip_shadow = u32(0xdbe2ea)
	const tooltip_text_color = u32(0x1f2937)

	__global g_build_screen = BuildFn(unsafe { nil })
	__global g_key_handler = KeyFn(unsafe { nil })
	__global g_key_event_handler = KeyEventFn(unsafe { nil })
	__global g_drop_handler = DropFn(unsafe { nil })
	__global g_key_consumed = false
	__global g_gg_app = &GgApp{}
	__global g_text_values = map[string]string{}
	__global g_text_props = map[string]string{}
	__global g_text_editors = map[string]TextEditor{}
	__global g_text_kinds = map[string]Kind{}
	__global g_slider_values = map[string]f64{}
	__global g_slider_declared = map[string]f64{}
	__global g_slider_specs = map[string]SliderSpec{}
	__global g_switch_values = map[string]bool{}
	__global g_switch_declared = map[string]bool{}
	__global g_checkbox_values = map[string]bool{}
	__global g_checkbox_declared = map[string]bool{}
	__global g_toggle_values = map[string]bool{}
	__global g_toggle_declared = map[string]bool{}
	__global g_toggle_groups = map[string]string{}
	__global g_toggle_allow_no_selection = map[string]bool{}
	__global g_focused_field = ''
	__global g_scroll_targets = map[string]HitTarget{}
	__global g_scroll_offsets = map[string]f64{}
	__global g_scroll_content_h = map[string]f64{}
	__global g_hit_targets = []HitTarget{}
	__global g_touch = TouchState{}
	__global g_scroll_areas = map[string]Rect{}
	__global g_scroll_transforms = map[string]ContentTransform{}
	__global g_active_fields = map[string]bool{}
	__global g_active_sliders = map[string]bool{}
	__global g_active_switches = map[string]bool{}
	__global g_active_checkboxes = map[string]bool{}
	__global g_active_toggles = map[string]bool{}
	__global g_active_scrolls = map[string]bool{}
	__global g_image_ids = map[string]int{}
	$if android {
		__global g_font_metrics = FontMetrics{}
		__global g_font_files = map[string]string{}
		__global g_font_indexed = false
		__global g_font_family_files = map[string]string{}
		__global g_font_family_metrics = map[string]FontMetrics{}
		__global g_font_symbol_ids = []int{}
		__global g_font_symbol_bases = map[int]bool{}
		__global g_font_symbol_fons = voidptr(unsafe { nil })
	}
	__global g_active_images = map[string]bool{}
	__global g_open_dropdown = ''
	__global g_dropdown_popup = DropdownPopup{}
	__global g_dropdown_hover = -1
	__global g_dropdown_scroll = 0.0
	__global g_tooltip_targets = []TooltipTarget{}
	__global g_tooltip = TooltipState{}
	// g_tooltip_owners counts the elements being rendered that declared a
	// tooltip. Their tooltip covers their descendants too, so a surface drawn
	// inside one must not hide it the way an unrelated overlay would.
	__global g_tooltip_owners = 0

	// Map values are copied byte-for-byte when an existing key is replaced.
	// Unlike keys, their nested strings are not released by map.set. The text
	// state below changes on every keystroke, so it owns clones explicitly and
	// disposes the previous value before overwriting it.
	@[manualfree]
	fn free_owned_string(value string) {
		unsafe { value.free() }
	}

	@[manualfree]
	fn replace_text_value(id string, value string) {
		owned := value.clone()
		if previous := g_text_values[id] {
			free_owned_string(previous)
		}
		g_text_values[id] = owned
	}

	@[manualfree]
	fn replace_text_prop(id string, value string) {
		owned := value.clone()
		if previous := g_text_props[id] {
			free_owned_string(previous)
		}
		g_text_props[id] = owned
	}

	@[manualfree]
	fn replace_text_editor(id string, editor TextEditor) {
		if previous := g_text_editors[id] {
			// Caret-only updates retain the editor's text allocation. Releasing
			// it in that case would leave the replacement editor pointing at
			// freed memory.
			if previous.text.str != editor.text.str {
				free_owned_string(previous.text)
			}
		}
		g_text_editors[id] = editor
	}

	@[manualfree]
	fn forget_text_state(id string) {
		if value := g_text_values[id] {
			free_owned_string(value)
		}
		if prop := g_text_props[id] {
			free_owned_string(prop)
		}
		if editor := g_text_editors[id] {
			free_owned_string(editor.text)
		}
		g_text_values.delete(id)
		g_text_props.delete(id)
		g_text_editors.delete(id)
		g_text_kinds.delete(id)
		forget_text_area_layout(id)
	}

	// ── Public API ─────────────────────────────────────────────────────

	pub fn bounds() Rect {
		if g_gg_app.ctx == unsafe { nil } {
			$if linux || macos || windows {
				return Rect{
					width: 800
					height: 600
				}
			}
			return Rect{
				width: 400
				height: 800
			}
		}
		// The drawn menu bar owns the top strip of the window, so the screen
		// an app lays out is the rest of it.
		viewport := g_gg_app.ctx.logical_viewport(g_gg_app.native_window)
		return Rect{
			width: viewport.width
			height: viewport.height - menu_bar_height()
		}
	}

	pub fn run(build_fn BuildFn) {
		$if linux || macos || windows {
			run_window('App', 800, 600, build_fn)
		} $else {
			run_window('App', 400, 800, build_fn)
		}
	}

	pub fn run_window(title string, width int, height int, build_fn BuildFn) {
		run_window_with_min_size(title, width, height, 0, 0, build_fn)
	}

	fn run_window_with_min_size(title string, width int, height int, min_width int, min_height int, build_fn BuildFn) {
		$if macos && ui2_embedder ? {
			open_embedder_window(title, width, height, min_width, min_height, build_fn) or {
				panic('ui2: ${err}')
			}
			C.ui2_embedder_run()
			return
		}
		// A dispatcher retained by an old worker stays attached to its closed window.
		if g_gg_app.scheduler.is_closed() {
			g_gg_app = &GgApp{}
		}
		g_build_screen = build_fn
		configure_animation_driver(refresh_animation_frame, false)
		publish_menu_context(title, unsafe { nil })
		// Pick the bundled font before constructing either drawing adapter.
		font_regular, font_bold := font_paths()
		$if android {
			if font_regular.len > 0 {
				g_font_metrics = font_file_metrics(font_regular) or { FontMetrics{} }
			}
		}
		g_gg_app.ctx = gg_draw_context(gg.new_context(
			bg_color: hex_color(0xf4f6f8)
			font_path: font_regular
			custom_bold_font_path: font_bold
			width: width
			height: height
			min_width: min_width
			min_height: min_height
			sample_count: 4
			create_window: true
			window_title: title
			user_data: unsafe { voidptr(g_gg_app) }
			init_fn: on_init
			// gg's ui_mode suppresses this callback before it can drain worker
			// messages or deadlines, and refresh_ui is not thread safe. Keep the
			// presentation callback and gate builds/draws in our coordinator (1A).
			ui_mode: false
			cleanup_fn: on_cleanup
			frame_fn: on_frame
			event_fn: on_event
			enable_dragndrop: true
			max_dropped_files: 32
			max_dropped_file_path_length: 4096
		))
		g_gg_app.ctx.inner.run()
	}

	pub fn render_stats() RenderStats {
		return g_gg_app.scheduler.stats()
	}

	// Capture this handle on the UI thread. Workers post model mutations through
	// it instead of touching controls, gg, or a shared model themselves.
	pub fn ui_dispatcher() UiDispatcher {
		return UiDispatcher{coordinator: g_gg_app.scheduler}
	}

	pub fn refresh() {
		g_gg_app.scheduler.invalidate(.build)
	}

	// Custom refresh remains asynchronous; native refresh semantics are unchanged.
	pub fn request_refresh() {
		g_gg_app.scheduler.invalidate(.build)
	}

	pub fn refresh_element(id string, element Element) {
		if g_gg_app.scheduler.is_closed() { return }
		g_gg_app.layout_patches << LayoutPatch{ id: id, element: element }
		g_gg_app.scheduler.invalidate(.layout)
	}

	pub fn layout_stats() LayoutStats { return g_gg_app.layout_tree.stats() }

	pub fn invalidate_layout_environment(environment LayoutEnvironment) {
		g_gg_app.layout_environment = environment
		$if !android {
			g_text_font_mutex.lock()
			if g_cpu_text_engine != unsafe { nil } { g_cpu_text_engine.invalidate_environment() }
			if g_gg_app.ctx != unsafe { nil } && g_gg_app.ctx.text != unsafe { nil } {
				if g_gg_app.ctx.text != g_cpu_text_engine { g_gg_app.ctx.text.invalidate_environment() }
				g_gg_app.ctx.text_font_generation = -1
			}
			g_text_font_mutex.unlock()
		}
		g_gg_app.scheduler.invalidate(.layout)
	}

	fn invalidate_custom_paint() {
		g_gg_app.scheduler.invalidate(.paint)
	}

	fn renderer_now_ms() i64 {
		return i64(time.sys_mono_now() / u64(time.millisecond))
	}

	pub fn on_key(handler KeyFn) {
		g_key_handler = handler
	}

	pub fn on_key_event(handler KeyEventFn) {
		g_key_event_handler = handler
	}

	pub fn on_drop(handler DropFn) {
		g_drop_handler = handler
	}

	pub fn text(id string) string {
		// State maps store owned strings so that replacing their values can
		// release the previous allocation. Callers, in particular QML bindings,
		// may retain the returned value after the next edit, so give them their
		// own copy rather than exposing the map's storage.
		return (g_text_values[id] or { '' }).clone()
	}

	pub fn set_text(id string, t string) {
		if id !in g_active_fields {
			return
		}
		replace_text_value(id, t)
		if (g_text_kinds[id] or { Kind.dropdown }) in [.text_field, .text_area] {
			mut editor := g_text_editors[id] or { text_editor(t.clone()) }
			editor.set_text(t.clone())
			replace_text_editor(id, editor)
		}
		if g_gg_app.composition.field_id == id {
			g_gg_app.composition = TextComposition{}
		}
		invalidate_custom_paint()
	}

	// slider_value returns the live value currently displayed by a mounted
	// slider, including a value changed by pointer input before the next build.
	pub fn slider_value(id string) f64 {
		return g_slider_values[id] or { 0 }
	}

	pub fn set_slider_value(id string, value f64) {
		if id !in g_active_sliders {
			return
		}
		spec := g_slider_specs[id] or { return }
		g_slider_values[id] = slider_clamped_value(value, spec.min, spec.max)
		invalidate_custom_paint()
	}

	// switch_active returns the live value, including a pointer change made
	// before the declarative tree is rebuilt.
	pub fn switch_active(id string) bool {
		return g_switch_values[id] or { false }
	}

	pub fn set_switch_active(id string, active bool) {
		if id !in g_active_switches {
			return
		}
		g_switch_values[id] = active
		invalidate_custom_paint()
	}

	// checkbox_checked returns the live value currently displayed by a mounted
	// checkbox, including a value changed by pointer input before the next build.
	fn checkbox_checked(id string) bool {
		return g_checkbox_values[id] or { false }
	}

	fn set_checkbox_checked(id string, checked bool) {
		if id !in g_active_checkboxes {
			return
		}
		g_checkbox_values[id] = checked
		invalidate_custom_paint()
	}

	pub fn toggle_button_pressed(id string) bool {
		return g_toggle_values[id] or { false }
	}

	pub fn set_toggle_button_pressed(id string, pressed bool) {
		if id !in g_active_toggles {
			return
		}
		if pressed {
			release_custom_toggle_group(id)
		}
		g_toggle_values[id] = pressed
		invalidate_custom_paint()
	}

	pub fn toggle_button_group_members(id string) []string {
		group := g_toggle_groups[id] or { return [] }
		if group.len == 0 {
			return [id]
		}
		mut members := []string{}
		for member, member_group in g_toggle_groups {
			if member_group == group && member in g_active_toggles {
				members << member
			}
		}
		return members
	}

	fn release_custom_toggle_group(id string) {
		group := g_toggle_groups[id] or { return }
		if group.len == 0 {
			return
		}
		for member, member_group in g_toggle_groups {
			if member != id && member_group == group {
				g_toggle_values[member] = false
			}
		}
	}

	pub fn focus(id string) {
		dispatch := custom_input_dispatch(g_gg_app)
		if !dispatch.valid() { return }
		sync_focus_navigation()
		if !g_focus_navigation.set_focus(id) { return }
		if g_focused_field != id { g_gg_app.composition = TextComposition{} }
		g_focused_field = id
		if g_open_dropdown.len > 0 && g_open_dropdown != id { close_dropdown() }
		reveal_custom_focus(id)
		if !dispatch.valid() { return }
		invalidate_custom_paint()
	}

	pub fn focused_id() string {
		return g_focused_field
	}

	pub fn focused_text_area_id() string {
		node := g_focus_navigation.node(g_focused_field) or { return '' }
		return if node.el.kind == .text_area { g_focused_field } else { '' }
	}

	pub fn dismiss_keyboard() {
		g_focused_field = ''
		g_focus_navigation.current = ''
		g_gg_app.composition = TextComposition{}
		invalidate_custom_paint()
	}

	pub fn quit() {
		if g_gg_app.scheduler.is_closed() {
			return
		}
		reset_custom_keyboard()
		g_gg_app.scheduler.close()
		$if macos && ui2_embedder ? {
			C.ui2_embedder_close(g_gg_app.native_window)
			return
		}
		if g_gg_app.ctx != unsafe { nil } {
			g_gg_app.ctx.inner.quit()
		}
	}

	pub fn consume_key() {
		g_key_consumed = true
	}

	pub fn consume_text_key() {
		consume_key()
	}

	pub fn safe_area_top() f64 {
		return 0
	}

	pub fn start_barcode_scan(on_result ScanCallback) {
		if voidptr(on_result) != unsafe { nil } {
			on_result(ScanResult{ kind: .error, text: 'barcode scanner unavailable' })
		}
	}

	pub fn insert_text_area_text(id string, value string) {
		if id !in g_active_fields || (g_text_kinds[id] or { Kind.screen }) != .text_area {
			return
		}
		mut editor := g_text_editors[id] or { text_editor((g_text_values[id] or { '' }).clone()) }
		editor.insert_text(value)
		replace_text_value(id, editor.text)
		replace_text_editor(id, editor)
		fire_field_change(id)
		invalidate_custom_paint()
	}

	pub fn scroll_offset(id string) f64 {
		return scroll_state_offset(named_scroll_state_id(id))
	}

	// scroll_to_offset puts a Scroll element at the given vertical offset. Before the
	// element has been laid out its range is not known yet, so the offset is stored as
	// asked and register_scroll_view clamps it to the real range on the next frame.
	// That is what lets a screen open where it was last left.
	pub fn scroll_to_offset(id string, offset f64) {
		if id.len == 0 {
			return
		}
		state_id := named_scroll_state_id(id)
		wanted := if offset < 0 { 0.0 } else { offset }
		if state_id in g_scroll_viewports {
			set_scroll_offset(state_id, wanted, scroll_maximum(state_id))
			return
		}
		// The view does not exist yet, so its range is unknown and the offset cannot be
		// stored as a live position: the next frame rendered without the view would
		// prune it. Hold the request until the view registers and can clamp it.
		g_pending_scroll[state_id] = wanted
		invalidate_custom_paint()
	}

	pub fn scroll_to_rect(id string, _x f64, y f64, _width f64, height f64) {
		state_id := named_scroll_state_id(id)
		area := g_scroll_viewports[state_id] or { return }
		current := scroll_state_offset(state_id)
		mut next := current
		if y < current {
			next = y
		} else if y + height > current + area.height {
			next = y + height - area.height
		}
		set_scroll_offset(state_id, next, scroll_maximum(state_id))
	}

	pub fn clipboard_has_image() bool {
		return false
	}

	pub fn save_clipboard_image_png(_path string) bool {
		return false
	}

	pub fn text_area_runs(id string) []TextRun {
		value := text(id)
		return if value.len == 0 { []TextRun{} } else { [TextRun{text: value}] }
	}

	pub fn text_area_format_state(_id string) TextFormatState {
		return TextFormatState{}
	}

	pub fn toggle_text_area_format(id string, _format TextFormat) TextFormatState {
		return text_area_format_state(id)
	}

	pub fn set_text_area_font_family(id string, _family string) TextFormatState {
		return text_area_format_state(id)
	}

	pub fn set_text_area_font_size(id string, _size f64) TextFormatState {
		return text_area_format_state(id)
	}

	pub fn set_text_area_color(id string, _color u32) TextFormatState {
		return text_area_format_state(id)
	}

	pub fn set_text_area_background_color(id string, _color u32) TextFormatState {
		return text_area_format_state(id)
	}

	pub fn set_text_area_effect(id string, _effect string) TextFormatState {
		return text_area_format_state(id)
	}

	pub fn toggle_text_area_superscript(id string) TextFormatState {
		return text_area_format_state(id)
	}

	pub fn toggle_text_area_subscript(id string) TextFormatState {
		return text_area_format_state(id)
	}

	pub fn toggle_text_area_vertical_align(id string, _align string) TextFormatState {
		return text_area_format_state(id)
	}

	// ── Frame & event loop ─────────────────────────────────────────────

	fn on_init(app &GgApp) {
		mut ctx := app.ctx
		ctx.sync_gg()
		// Sokol's GL/EGL/D3D loops swap even when frame_fn returns early. Their
		// discarded backbuffers need a full paint; only the Metal path can skip
		// submission safely until UI2 owns presentation in the platform embedder.
		app.scheduler.set_presentation_required(gfx.query_backend() != .metal_macos)
		if voidptr(g_build_screen) == unsafe { nil } {
			return
		}
		// gg/Sokol must receive images during initialization to make their GPU
		// textures available for the first rendered frame.
		g_gg_app.scheduler.record_build()
		preload_images(g_build_screen())
	}

	fn on_cleanup(app &GgApp) {
		app.scheduler.close()
		mut state := unsafe { app }
		if state.ctx != unsafe { nil } {
			mut ctx := state.ctx
			ctx.destroy()
		}
		state.ctx = unsafe { nil }
		clear_text_area_layouts()
		state.declared_root = Element{}
		state.declaration_pending = false
		state.layout_tree.clear()
		state.layout_patches.clear()
		state.has_root = false
		state.editable_fields.clear()
		configure_animation_driver(unsafe { nil }, false)
		reset_widget_animations()
		g_tooltip = TooltipState{}
		g_touch = TouchState{}
		g_focus_navigation = &FocusManager{}
		g_focused_field = ''
		reset_custom_keyboard()
		state.composition = TextComposition{}
		g_hit_targets = []HitTarget{}
		g_tooltip_targets = []TooltipTarget{}
	}

	// The next visual deadline is replaced after every frame. A canceled hover,
	// unmounted target or released pointer therefore cannot leave a live timer.
	fn custom_visual_deadline() i64 {
		mut deadline := i64(-1)
		if g_tooltip.pointer_in && g_tooltip.key.len > 0 && !g_tooltip.dismissed
			&& !g_tooltip.visible && !g_touch.down && !menu_bar_open() && g_open_dropdown.len == 0 {
			deadline = g_tooltip.rest_since + tooltip_delay_ms
		}
		if g_touch.down && !g_touch.moved && !g_touch.long_press_fired && !g_touch.scrollbar_drag {
			target := hit_test(g_touch.start_x, g_touch.start_y)
			if target.long_press && voidptr(target.on_event) != unsafe { nil } {
				press_deadline := g_touch.start_time + 450
				if deadline < 0 || press_deadline < deadline {
					deadline = press_deadline
				}
			}
		}
		return deadline
	}

	fn drain_custom_tasks(mut app GgApp) {
		if app.scheduler.is_closed() || app.ctx == unsafe { nil } || app.draining_tasks {
			return
		}
		// Callbacks run outside the coordinator lock, on this UI thread. Business
		// messages may run while minimized, but visual work stays suspended.
		app.draining_tasks = true
		for task in app.scheduler.take_tasks() {
			if app.scheduler.is_closed() {
				break
			}
			task()
		}
		app.draining_tasks = false
	}

	fn take_custom_layout_patches(mut app GgApp) []LayoutPatch {
		patches := app.layout_patches
		app.layout_patches = []LayoutPatch{}
		return patches
	}

	fn resolve_custom_layout(mut app GgApp, work FrameWork, measure LayoutTextMeasureFn, patches []LayoutPatch) !Element {
		dispatch := custom_input_dispatch(&app)
		ctx := app.ctx
		animated := apply_custom_widget_animations(app.declared_root)
		if !dispatch.valid() || app.ctx != ctx || (ctx != unsafe { nil } && !custom_frame_current(dispatch, ctx)) {
			return error('layout frame canceled')
		}
		if work.build || app.declaration_pending || app.layout_tree.root.len == 0 {
			app.layout_tree.replace(animated)!
			app.declaration_pending = false
		}
		for patch in patches {
			element := apply_custom_widget_animations(patch.element)
			if !dispatch.valid() || app.ctx != ctx || (ctx != unsafe { nil } && !custom_frame_current(dispatch, ctx)) {
				return error('layout frame canceled')
			}
			app.layout_tree.patch(patch.id, element) or { eprintln('ui2 layout: ${err}'); continue }
			app.declared_root = app.layout_tree.declaration()
		}
		resolved := app.layout_tree.resolve(LayoutConstraints{}, measure, app.layout_environment)!
		return effective_element_state(resolved, true)
	}

	fn custom_frame_current(dispatch CustomInputDispatch, ctx &DrawContext) bool {
		return dispatch.valid() && dispatch.app.ctx == ctx && !ctx.destroyed
			&& !dispatch.app.iconified && !dispatch.app.suspended
			&& !dispatch.scheduler.build_pending()
	}

	// Only retained work may survive an input-generation change. Presentation
	// still uses custom_frame_current, and never crosses a replaced owner/context.
	fn custom_frame_owner_current(dispatch CustomInputDispatch, ctx &DrawContext) bool {
		return dispatch.owner_current() && dispatch.app.ctx == ctx && !ctx.destroyed
	}

	fn on_frame(mut app GgApp) {
		if app.scheduler.is_closed() || app.ctx == unsafe { nil } || app.draining_tasks { return }
		dispatch := custom_input_dispatch(&app)
		drain_custom_tasks(mut app)
		if !dispatch.valid() { return }
		mut ctx := app.ctx
		if !ctx.owns_surface {
			ctx.sync_gg()
			live_size := ctx.logical_viewport(app.native_window)
			if live_size.width > 0 && live_size.height > 0
				&& (ctx.width != live_size.width || ctx.height != live_size.height) {
				ctx.width = int(live_size.width)
				ctx.height = int(live_size.height)
				ctx.inner.width = int(live_size.width)
				ctx.inner.height = int(live_size.height)
				ctx.inner.window.width = int(live_size.width)
				ctx.inner.window.height = int(live_size.height)
				app.scheduler.invalidate(.surface)
			}
			dpi := sapp.dpi_scale()
			if dpi != app.dpi_scale {
				app.dpi_scale = dpi
				app.scheduler.invalidate(.surface)
			}
		}
		now := renderer_now_ms()
		scheduler := app.scheduler
		work := scheduler.begin_frame(now) or { return }
		defer { scheduler.finish_frame(work) }
		// The builder, animation and focus callbacks may enqueue patches. Take
		// only the batch that existed when this scheduler generation started.
		patches := take_custom_layout_patches(mut app)
		mut patches_resolved := false
		defer {
			if !patches_resolved && patches.len > 0 && app.scheduler == scheduler && !scheduler.is_closed() {
				// A canceled frame must not drop its unapplied work. New callback
				// patches follow it so their newer declarations win next time.
				mut pending := patches.clone()
				pending << app.layout_patches
				app.layout_patches = pending
				scheduler.invalidate(.layout)
			}
			if !custom_frame_current(dispatch, ctx) && custom_frame_owner_current(dispatch, ctx)
				&& !scheduler.build_pending() && app.has_root {
				// begin_frame detached the original request. Retry its retained
				// declaration, not its builder or already delivered business tasks.
				scheduler.invalidate(.layout)
			}
		}
		$if android { ensure_symbol_fallbacks(ctx) }
		if work.build && voidptr(g_build_screen) != unsafe { nil } {
			app.scheduler.record_build()
			declared := g_build_screen()
			if !custom_frame_owner_current(dispatch, ctx) || scheduler.build_pending() { return }
			validate_element_tree(declared) or {
				eprintln('ui2: ${err}')
				return
			}
			app.declared_root = declared
			app.declaration_pending = true
			app.has_root = true
		}
		if !custom_frame_current(dispatch, ctx) {
			return
		}
		root := resolve_custom_layout(mut app, work, measure_layout_text, patches) or { eprintln('ui2 layout: ${err}'); return }
		patches_resolved = true
		// Animation callbacks are user code and may close or suspend the window.
		if !custom_frame_current(dispatch, ctx) {
			return
		}
		validate_element_tree(root) or {
			eprintln('ui2: ${err}')
			return
		}

		// Restoring focus can notify user code. Leave retained input state in
		// place until ownership is revalidated, so a newer gesture survives.
		update_custom_focus_tree(root)
		if !custom_frame_current(dispatch, ctx) || g_focus_navigation.root != root { return }
		g_hit_targets = []HitTarget{}
		g_tooltip_targets.clear()
		g_tooltip_owners = 0
		app.text_caret = Rect{}
		reset_scroll_frame()
		// Paint-time clamping can also notify user code before another pane is
		// painted. Keep every mounted Scroll available to nested public calls.
		sync_mounted_scroll_views()
		g_active_fields = map[string]bool{}
		app.editable_fields.clear()
		g_active_sliders = map[string]bool{}
		g_active_switches = map[string]bool{}
		g_active_checkboxes = map[string]bool{}
		g_active_toggles = map[string]bool{}
		g_active_scrolls = map[string]bool{}
		g_active_images = map[string]bool{}
		sync_mounted_focus_controls(root, 'root')
		host_window := app.native_window
		owned_surface := ctx.owns_surface
		$if macos && ui2_embedder ? {
			if owned_surface {
				if !acquire_embedder_surface(mut app) { return }
			}
		}
		// Keep the captured drawable through submission or cancellation. A defer
		// in the acquisition block would release it before painting starts.
		defer {
			$if macos && ui2_embedder ? {
				if owned_surface { C.ui2_embedder_frame_done(host_window) }
			}
		}
		// Image resources must be available before starting the GPU pass.
		preload_images(root)
		previous_geometry := app.visual_geometries
		app.visual_geometries = map[string]VisualGeometry{}
		defer {
			if !custom_frame_current(dispatch, ctx) || g_focus_navigation.root != root {
				app.visual_geometries = previous_geometry
			}
		}
		ctx.content_transform = ContentTransform{}
		ctx.clip_base = ClipRegion{}
		ctx.clip_region = ClipRegion{}
		ctx.begin()
		defer {
			if custom_frame_current(dispatch, ctx) && g_focus_navigation.root == root { ctx.end() } else { ctx.cancel() }
		}
		if app.has_root {
			g_dropdown_popup.mounted = false
			top := menu_bar_height()
			render_element(ctx, root, 0, top, rect(0, top, f64(ctx.width), f64(ctx.height) - top), '', 'root')
			if !custom_frame_current(dispatch, ctx) || g_focus_navigation.root != root { return }
			if g_open_dropdown.len > 0 {
				if g_dropdown_popup.mounted {
					draw_dropdown_popup(ctx)
				} else {
					close_dropdown()
				}
			}
			draw_menu_bar(ctx)
			update_tooltip(now)
			draw_tooltip(ctx)
			prune_unmounted_state()
			if app.composition.field_id.len > 0 && app.composition.field_id != g_focused_field {
				app.composition = TextComposition{}
			}
		}
		check_long_press()
		if !custom_frame_current(dispatch, ctx) || g_focus_navigation.root != root { return }
		$if android {
			// Android's legacy gg atlas uploads glyphs introduced by this frame.
			if ctx.font_inited { ctx.ft.flush() }
		}
		app.scheduler.record_draw()
		app.scheduler.set_deadline(custom_visual_deadline())
		app.scheduler.set_animation_active(custom_animations_need_frame(app.declared_root))
	}

	fn on_event(e &gg.Event, app &GgApp) {
		if app.scheduler.is_closed() {
			return
		}
		mut state := unsafe { app }
		// Local hover, focus and scroll repaint retained geometry. Business
		// callbacks request a build; keyboard/drop hooks may mutate the model.
		state.scheduler.invalidate(if e.typ in [.key_down, .key_up, .char, .files_dropped] { RenderReason.build } else { RenderReason.paint })
		match e.typ {
			.mouse_down {
				custom_mouse_down(app, f64(e.mouse_x), f64(e.mouse_y))
			}
			.mouse_move {
				// Recorded before any handler below can claim the move, so the
				// tooltip always knows where the pointer is.
				g_tooltip.pointer_moved(f64(e.mouse_x), f64(e.mouse_y), renderer_now_ms())
				if g_touch.down && g_touch.pointer_captured {
					handle_touch_move(f64(e.mouse_x), f64(e.mouse_y))
					return
				}
				if menu_bar_handle_move(f64(e.mouse_x), f64(e.mouse_y)) {
					return
				}
				if g_open_dropdown.len > 0 {
					update_dropdown_hover(f64(e.mouse_x), f64(e.mouse_y))
				}
				if g_touch.down {
					handle_touch_move(f64(e.mouse_x), f64(e.mouse_y))
				}
			}
			.mouse_scroll {
				// The content moves under a pointer that stays put, so whatever
				// ends up beneath it waits for a fresh rest.
				g_tooltip.restart(renderer_now_ms())
				if menu_bar_open() {
					return
				}
				handle_mouse_scroll_vector(f64(e.mouse_x), f64(e.mouse_y), f64(e.scroll_x), f64(e.scroll_y))
			}
			.mouse_leave {
				g_tooltip.pointer_left()
			}
			.mouse_up {
				if g_touch.down && g_touch.pointer_captured {
					handle_touch_up(f64(e.mouse_x), f64(e.mouse_y))
					return
				}
				if menu_bar_handle_up(f64(e.mouse_x), f64(e.mouse_y)) {
					return
				}
				handle_touch_up(f64(e.mouse_x), f64(e.mouse_y))
			}
			.touches_began {
				if e.num_touches > 0 {
					handle_touch_down(f64(e.touches[0].pos_x), f64(e.touches[0].pos_y))
				}
			}
			.touches_moved {
				if e.num_touches > 0 {
					handle_touch_move(f64(e.touches[0].pos_x), f64(e.touches[0].pos_y))
				}
			}
			.touches_ended {
				if e.num_touches > 0 {
					handle_touch_up(f64(e.touches[0].pos_x), f64(e.touches[0].pos_y))
				} else {
					handle_touch_up(g_touch.current_x, g_touch.current_y)
				}
			}
			.iconified, .suspended {
				reset_custom_keyboard()
				if e.typ == .iconified {
					state.iconified = true
				} else {
					state.suspended = true
				}
				state.scheduler.suspend()
				g_tooltip.pointer_left()
				cancel_touch()
			}
			.restored, .resumed {
				if e.typ == .restored {
					state.iconified = false
				} else {
					state.suspended = false
				}
				if !state.iconified && !state.suspended {
					state.scheduler.resume()
				}
			}
			.resized, .focused {
				state.scheduler.invalidate(.surface)
			}
			.touches_cancelled, .unfocused {
				if e.typ == .unfocused { reset_custom_keyboard() }
				g_tooltip.dismiss()
				cancel_touch()
			}
			.char {
				custom_character_input(app, e.char_code)
			}
			.key_down {
				g_tooltip.dismiss()
				dispatch := begin_custom_input_dispatch(app)
				if !custom_key_down(e, false, state.composition.field_id.len > 0, dispatch) && dispatch.valid() {
					handle_key_down(e.key_code, e.modifiers)
				}
			}
			.key_up { custom_key_up(e.key_code) }
			.files_dropped {
				handle_files_dropped(e)
			}
			else {}
		}
	}

	// ── Touch handling ─────────────────────────────────────────────────

	fn fire_pointer_event(kind ElementEventKind, target HitTarget, x f64, y f64) {
		current := current_pointer_target(target) or { target }
		logical_x, logical_y := current.content_transform.inverse(x, y)
		fire_target_event(target, ElementEvent{ kind: kind, id: target.id, x: logical_x, y: logical_y })
	}

	fn custom_mouse_down(app &GgApp, x f64, y f64) CustomInputDispatch {
		dispatch := begin_custom_input_dispatch(app)
		if !dispatch.valid() { return dispatch }
		// Pointer bookkeeping is paint-only. Business callbacks request their
		// build through fire_target_event; explicit refresh remains blocking.
		app.scheduler.invalidate(.paint)
		g_tooltip.dismiss()
		if menu_bar_handle_down(x, y) || !dispatch.valid() { return dispatch }
		return handle_touch_down(x, y)
	}

	fn discard_custom_pointer_start(dispatch CustomInputDispatch) {
		if dispatch.window == g_active_custom_window_state {
			if g_touch.input_generation == dispatch.generation { g_touch = TouchState{} }
		} else {
			mut owner := dispatch.window
			if owner.touch.input_generation == dispatch.generation { owner.touch = TouchState{} }
		}
	}

	fn handle_touch_down(x f64, y f64) CustomInputDispatch {
		dispatch := begin_custom_input_dispatch(g_gg_app)
		if !dispatch.valid() { return dispatch }
		g_touch = TouchState{
			input_generation: dispatch.generation
			down: true
			start_x: x
			start_y: y
			current_x: x
			current_y: y
			start_time: renderer_now_ms()
			moved: false
			long_press_fired: false
		}
		if g_open_dropdown.len > 0 {
			update_dropdown_hover(x, y)
			return dispatch
		}
		target := hit_test(x, y)
		if g_focus_navigation.can_focus(target.id) { focus(target.id) }
		if !dispatch.valid() {
			discard_custom_pointer_start(dispatch)
			return dispatch
		}
		g_touch.pointer_target = target
		g_touch.pointer_captured = target.w > 0 && target.h > 0
		g_touch.pressed_id = target.id
		if target.slider {
			commit_slider(target, x, y)
			return dispatch
		}
		if target.switch_control {
			return dispatch
		}
		g_touch.scroll_id = scroll_hit_test(x, y)
		g_touch.scroll_chain = scroll_ancestor_chain(g_touch.scroll_id)
		if begin_scrollbar_drag(x, y) {
			return dispatch
		}
		if voidptr(target.on_event) != unsafe { nil }
			&& (target.clickable || target.button_behavior || target.draggable) {
			g_touch.pointer_target = target
			if target.clickable || target.draggable {
				fire_pointer_event(.pointer_down, target, x, y)
			}
		}
		return dispatch
	}

	fn handle_touch_move(x f64, y f64) {
		if !g_touch.down {
			return
		}
		previous_x := g_touch.current_x
		previous_y := g_touch.current_y
		dx := x - g_touch.start_x
		dy := y - g_touch.start_y
		if dx * dx + dy * dy > 100 {
			g_touch.moved = true
		}
		g_touch.current_x = x
		g_touch.current_y = y
		target := if g_touch.pointer_captured {
			g_touch.pointer_target
		} else {
			hit_test(g_touch.start_x, g_touch.start_y)
		}
		if g_touch.pointer_captured && !target.clickable && !target.draggable && current_pointer_target(target) == none {
			return
		}
		if target.slider {
			commit_slider(target, x, y)
			return
		}
		if target.switch_control {
			commit_switch(target, switch_pointer_right(target, x, y))
			return
		}
		if g_touch.scrollbar_drag {
			drag_scrollbar_at(x, y)
			return
		}
		if g_touch.scroll_chain.len > 0 && !target.draggable {
			apply_scroll_vector(g_touch.scroll_chain, previous_x - x, previous_y - y)
		}
		if voidptr(target.on_event) != unsafe { nil } && target.draggable {
			fire_pointer_event(.pointer_drag, target, x, y)
		}
	}

	fn handle_mouse_scroll_vector(x f64, y f64, delta_x f64, delta_y f64) {
		if g_open_dropdown.len > 0 {
			g_dropdown_scroll = clamped_dropdown_scroll(g_dropdown_scroll - delta_y * 24)
			update_dropdown_hover(x, y)
			return
		}
		id := scroll_hit_test(x, y)
		if id.len == 0 {
			return
		}
		apply_scroll_vector(scroll_ancestor_chain(id), -delta_x * 48, -delta_y * 48)
	}

	fn set_scroll_offset(id string, requested f64, maximum f64) {
		max_scroll := if maximum > 0 { maximum } else { 0.0 }
		next := if requested < 0 {
			0.0
		} else if requested > max_scroll {
			max_scroll
		} else {
			requested
		}
		previous := g_scroll_offsets[id] or { 0.0 }
		g_scroll_offsets[id] = next
		if next != previous {
			invalidate_custom_paint()
			target := g_scroll_targets[id] or { HitTarget{} }
			fire_target_event(target, ElementEvent{ kind: .scroll, id: target.id, value: next })
		}
	}

	fn handle_touch_up(x f64, y f64) {
		if !g_touch.down {
			return
		}
		release_dx := x - g_touch.start_x
		release_dy := y - g_touch.start_y
		if release_dx * release_dx + release_dy * release_dy > 100 {
			g_touch.moved = true
		}
		g_touch.current_x = x
		g_touch.current_y = y
		captured := g_touch.pointer_target
		was_captured := g_touch.pointer_captured
		g_touch.pointer_captured = false
		g_touch.pointer_target = HitTarget{}
		g_touch.down = false
		slider_target := if was_captured {
			captured
		} else {
			hit_test(g_touch.start_x, g_touch.start_y)
		}
		if was_captured && !captured.clickable && !captured.draggable && current_pointer_target(captured) == none {
			return
		}
		if slider_target.slider {
			commit_slider(slider_target, x, y)
			return
		}
		if slider_target.switch_control {
			if g_touch.moved {
				commit_switch(slider_target, switch_pointer_right(slider_target, x, y))
			} else {
				current := if slider_target.id.len > 0 {
					switch_active(slider_target.id)
				} else {
					slider_target.switch_state
				}
				commit_switch(slider_target, !current)
			}
			return
		}
		if g_touch.long_press_fired || g_touch.scrollbar_drag {
			return
		}
		if g_open_dropdown.len > 0 && !was_captured {
			handle_dropdown_release(x, y)
			return
		}
		mut target := if was_captured {
			captured
		} else {
			hit_test(g_touch.start_x, g_touch.start_y)
		}
		dx := x - g_touch.start_x
		if g_touch.moved && dx < -72 && target.swipe_left && voidptr(target.on_event) != unsafe { nil } {
			if current := current_pointer_target(target) {
				if current.swipe_left {
					fire_target_event(target, ElementEvent{ kind: .swipe_left, id: target.id })
					return
				}
			}
		}
		mut activate := false
		if voidptr(target.on_event) != unsafe { nil } && target.button_behavior {
			if !g_touch.moved {
				if current := current_pointer_target(target) {
					if current.button_behavior && voidptr(current.on_event) != unsafe { nil } && hit_target_contains(current, x, y) {
						activate = true
					}
				}
			}
		}
		if voidptr(target.on_event) != unsafe { nil } && (target.clickable || target.draggable) {
			fire_pointer_event(.pointer_up, target, x, y)
		}
		if target.button_behavior {
			if activate { fire_target_event(target, ElementEvent{ kind: .tap, id: target.id }) }
			return
		}
		if voidptr(target.on_event) != unsafe { nil } && (target.clickable || target.draggable) {
			return
		}
		if g_touch.moved {
			return
		}
		if was_captured {
			current := current_pointer_target(target) or { return }
			if !hit_target_contains(current, x, y) { return }
		} else {
			target = hit_test(x, y)
		}
		if target.checkbox {
			commit_checkbox(target)
			return
		}
		if target.id.len == 0 && voidptr(target.on_event) == unsafe { nil } {
			if g_focused_field.len > 0 {
				dismiss_keyboard()
			}
			return
		}
		if target.text_field {
			if !g_focus_navigation.can_focus(target.id) { return }
			g_focused_field = target.id
			mut editor := g_text_editors[target.id] or {
				text_editor((g_text_values[target.id] or { '' }).clone())
			}
			editor.set_caret(rune_len(editor.text))
			replace_text_editor(target.id, editor)
			return
		}
		if target.text_area {
			if !g_focus_navigation.can_focus(target.id) { return }
			g_focused_field = target.id
			mut editor := g_text_editors[target.id] or {
				text_editor((g_text_values[target.id] or { '' }).clone())
			}
			editor.set_caret(rune_len(editor.text))
			replace_text_editor(target.id, editor)
			return
		}
		if target.dropdown {
			open_dropdown(target)
			return
		}
		if target.toggle_button {
			commit_toggle_button(target)
			return
		}
		fire_target_event(target, ElementEvent{ kind: .tap, id: target.id })
	}

	// Finish a captured gesture on focus loss/cancellation so an IDE drag cannot
	// remain stuck. Ordinary taps are cancelled without activating a control.
	fn cancel_touch() {
		captured := g_touch.pointer_target
		x := g_touch.current_x
		y := g_touch.current_y
		g_touch = TouchState{}
		if voidptr(captured.on_event) != unsafe { nil } && (captured.clickable || captured.draggable) {
			fire_pointer_event(.pointer_up, captured, x, y)
		}
	}

	fn check_long_press() {
		if !g_touch.down || g_touch.moved || g_touch.long_press_fired || g_touch.scrollbar_drag {
			return
		}
		elapsed := renderer_now_ms() - g_touch.start_time
		if elapsed < 450 {
			return
		}
		target := if g_touch.pointer_captured { g_touch.pointer_target } else { hit_test(g_touch.start_x, g_touch.start_y) }
		current := current_pointer_target(target) or { return }
		if voidptr(target.on_event) != unsafe { nil } && target.long_press && current.long_press {
			g_touch.long_press_fired = true
			fire_target_event(target, ElementEvent{ kind: .long_press, id: target.id })
		}
	}

	fn hit_test(x f64, y f64) HitTarget {
		for i := g_hit_targets.len - 1; i >= 0; i-- {
			t := g_hit_targets[i]
			if hit_target_contains(t, x, y) {
				return t
			}
		}
		return HitTarget{}
	}

	fn hit_target_contains(target HitTarget, x f64, y f64) bool {
		broad := presentation_bounds_contains(rect(target.x,target.y,target.w,target.h),x,y)
		if !broad || (target.has_geometry && !transformed_contains(target.local_frame, target.content_transform, target.clip_region, x, y)) { return false }
		if !target.is_vector_canvas && target.vector_shapes.len == 0 { return true }
		local_x, local_y := target.content_transform.inverse(x, y)
		return vector_shapes_contain(target.vector_shapes, local_x - target.vector_origin.x,
			local_y - target.vector_origin.y, target.vector_hit_mode)
	}

	// A semantic press keeps the action chosen on pointer-down, but the surface
	// must still exist and be enabled when it is released. Hit targets are rebuilt
	// every frame, so use the current geometry rather than the captured rectangle.
	fn current_pointer_target(captured HitTarget) ?HitTarget {
		if captured.id.len > 0 {
			for i := g_hit_targets.len - 1; i >= 0; i-- {
				current := g_hit_targets[i]
				if current.id == captured.id {
					return eligible_pointer_target(captured, current)
				}
			}
			if node := g_focus_navigation.node(captured.id) {
				return eligible_pointer_target(captured, HitTarget{ ...captured, identity: node.path, kind: node.el.kind, on_event: node.el.on_event })
			}
			return none
		}
		if captured.identity.len == 0 { return none }
		for current in g_hit_targets {
			if current.identity == captured.identity { return eligible_pointer_target(captured, current) }
		}
		if node := g_focus_navigation.path_node(captured.identity) {
			return eligible_pointer_target(captured, HitTarget{ ...captured, kind: node.el.kind, on_event: node.el.on_event })
		}
		return none
	}

	fn eligible_pointer_target(captured HitTarget, current HitTarget) ?HitTarget {
		if captured.kind != current.kind { return none }
		if voidptr(captured.on_event) != unsafe { nil } && voidptr(current.on_event) == unsafe { nil } { return none }
		node := if current.id.len > 0 { g_focus_navigation.node(current.id) } else { g_focus_navigation.path_node(current.identity) }
		if mounted := node {
			if mounted.hidden || !mounted.enabled || mounted.el.kind != current.kind { return none }
			frame := mounted.transform.project(mounted.local_frame)
			return HitTarget{ ...current, identity: mounted.path, on_event: mounted.el.on_event,
				x: frame.x, y: frame.y, w: frame.width, h: frame.height,
				local_frame: mounted.local_frame, content_transform: mounted.transform,
				clip_region: mounted.clip, has_geometry: true,
				is_vector_canvas: mounted.el.is_vector_canvas, vector_shapes: mounted.el.vector_shapes,
				vector_hit_mode: mounted.el.vector_hit_mode, vector_origin: mounted.local_frame }
		}
		return current
	}

	fn fire_target_event(target HitTarget, event ElementEvent) {
		if voidptr(target.on_event) != unsafe { nil } {
			revision := g_gg_app.presentation_revision
			target.on_event(event)
			// A presentation setter already requested a paint; pure visual callbacks
			// do not rebuild their retained layout. Mixed model changes call refresh().
			if revision == g_gg_app.presentation_revision { refresh() }
		}
	}

	fn slider_target_value(target HitTarget, x f64, y f64) f64 {
		current := current_pointer_target(target) or { target }
		logical_x, logical_y := current.content_transform.inverse(x, y)
		normalized := slider_normalized_from_point(current.slider_frame, current.slider_spec.orientation, current.slider_padding, logical_x, logical_y)
		return slider_value_from_normalized(normalized, current.slider_spec.min, current.slider_spec.max, current.slider_spec.step)
	}

	fn commit_slider(target HitTarget, x f64, y f64) {
		if !target.slider {
			return
		}
		next := slider_target_value(target, x, y)
		previous := g_slider_values[target.id] or { target.slider_spec.min }
		if target.id.len > 0 {
			g_slider_values[target.id] = next
		}
		if next != previous {
			fire_target_event(target, ElementEvent{ kind: .change, id: target.id, value: next })
		}
	}

	fn commit_switch(target HitTarget, active bool) {
		if !target.switch_control {
			return
		}
		previous := if target.id.len > 0 { switch_active(target.id) } else { target.switch_state }
		if target.id.len > 0 {
			g_switch_values[target.id] = active
		}
		if active != previous {
			fire_target_event(target, ElementEvent{ kind: .change, id: target.id, checked: active })
		}
	}

	fn commit_checkbox(target HitTarget) {
		if !target.checkbox {
			return
		}
		previous := if target.id.len > 0 { checkbox_checked(target.id) } else { target.checkbox_state }
		if target.id.len > 0 {
			g_checkbox_values[target.id] = !previous
		}
		fire_target_event(target, ElementEvent{ kind: .change, id: target.id, checked: !previous })
	}

	fn commit_toggle_button(target HitTarget) {
		if !target.toggle_button {
			return
		}
		previous := toggle_button_pressed(target.id)
		mut pressed := !previous
		if target.toggle_group.len > 0 && previous && !target.toggle_allow_no_selection {
			pressed = true
		}
		if target.id.len > 0 {
			if pressed {
				release_custom_toggle_group(target.id)
			}
			g_toggle_values[target.id] = pressed
		}
		fire_target_event(target, ElementEvent{ kind: .change, id: target.id, checked: pressed })
	}

	fn handle_files_dropped(e &gg.Event) {
		if voidptr(g_drop_handler) == unsafe { nil } {
			return
		}
		mut paths := []string{cap: sapp.get_num_dropped_files()}
		for index in 0 .. sapp.get_num_dropped_files() {
			path := sapp.get_dropped_file_path(index)
			if path.len > 0 {
				paths << path
			}
		}
		g_drop_handler(DropEvent{
			paths: paths
			x: f64(e.mouse_x)
			y: f64(e.mouse_y)
		})
	}

	// ── Keyboard input ─────────────────────────────────────────────────

	fn dispatch_key_event(e &gg.Event, dispatch CustomInputDispatch) bool {
		if !dispatch.valid() { return true }
		if voidptr(g_key_event_handler) != unsafe { nil } {
			g_key_consumed = false
			g_key_event_handler(immediate_key_event(e))
			if !dispatch.valid() { return true }
			if g_key_consumed {
				g_key_consumed = false
				return true
			}
		}
		if voidptr(g_key_handler) == unsafe { nil } {
			return false
		}
		key := immediate_normalized_key(e)
		if key.len == 0 {
			return false
		}
		mut event_key := key
		for target in g_hit_targets {
			if target.id == g_focused_field && target.text_area {
				event_key = 'text:${target.id}:${key}'
				break
			}
		}
		g_key_consumed = false
		g_key_handler(event_key)
		if !dispatch.valid() { return true }
		consumed := g_key_consumed
		g_key_consumed = false
		return consumed
	}

	fn immediate_key_event(e &gg.Event) KeyEvent {
		return KeyEvent{
			code: unsafe { KeyCode(int(e.key_code)) }
			shift: e.modifiers & u32(gg.Modifier.shift) != 0
			ctrl: e.modifiers & u32(gg.Modifier.ctrl) != 0
			alt: e.modifiers & u32(gg.Modifier.alt) != 0
			cmd: e.modifiers & u32(gg.Modifier.super) != 0
		}
	}

	fn immediate_normalized_key(e &gg.Event) string {
		code := int(e.key_code)
		mut key := match e.key_code {
			.backspace { 'backspace' }
			.tab { 'tab' }
			.enter, .kp_enter { 'enter' }
			.escape { 'escape' }
			.page_up { 'page_up' }
			.page_down { 'page_down' }
			.end { 'end' }
			.home { 'home' }
			.left { 'left' }
			.up { 'up' }
			.right { 'right' }
			.down { 'down' }
			.delete { 'forward_delete' }
			else {
				if code >= int(gg.KeyCode.f1) && code <= int(gg.KeyCode.f25) {
					'f${code - int(gg.KeyCode.f1) + 1}'
				} else if code >= int(gg.KeyCode.space) && code <= int(gg.KeyCode.z) {
					rune(code).str().to_lower()
				} else {
					''
				}
			}
		}
		if key.len == 0 {
			return ''
		}
		mut modifiers := []string{}
		if e.modifiers & u32(gg.Modifier.super) != 0 {
			modifiers << 'cmd'
		}
		if e.modifiers & u32(gg.Modifier.ctrl) != 0 {
			modifiers << 'ctrl'
		}
		if e.modifiers & u32(gg.Modifier.alt) != 0 {
			modifiers << 'alt'
		}
		if e.modifiers & u32(gg.Modifier.shift) != 0 {
			modifiers << 'shift'
		}
		if modifiers.len > 0 {
			key = modifiers.join('+') + '+' + key
		}
		return key
	}

	fn handle_char_input(ch u32) {
		if g_focused_field.len == 0 || g_focused_field !in g_text_editors {
			return
		}
		focused_node := g_focus_navigation.node(g_focused_field) or { return }
		if focused_node.el.kind !in [.text_field, .text_area] { return }
		if !(g_gg_app.editable_fields[g_focused_field] or { true }) { return }
		if ch < 32 {
			return
		}
		mut editor := g_text_editors[g_focused_field] or {
			text_editor((g_text_values[g_focused_field] or { '' }).clone())
		}
		editor.insert_text(rune(ch).str())
		replace_text_value(g_focused_field, editor.text)
		replace_text_editor(g_focused_field, editor)
		fire_field_change(g_focused_field)
	}

	fn handle_key_down(key gg.KeyCode, modifiers u32) {
		dispatch := custom_input_dispatch(g_gg_app)
		if !dispatch.valid() { return }
		if g_focused_field.len == 0 || g_focused_field !in g_text_editors {
			return
		}
		focused_node := g_focus_navigation.node(g_focused_field) or { return }
		if focused_node.el.kind !in [.text_field, .text_area] { return }
		mut editor := g_text_editors[g_focused_field] or {
			text_editor((g_text_values[g_focused_field] or { '' }).clone())
		}
		if key in [.backspace, .delete, .enter, .kp_enter] && !(g_gg_app.editable_fields[g_focused_field] or { true }) { return }
		if key == .backspace {
			if editor.backspace() {
				replace_text_value(g_focused_field, editor.text)
				replace_text_editor(g_focused_field, editor)
				fire_field_change(g_focused_field)
				if !dispatch.valid() { return }
			}
		}
		if key == .delete {
			if editor.delete_forward() {
				replace_text_value(g_focused_field, editor.text)
				replace_text_editor(g_focused_field, editor)
				fire_field_change(g_focused_field)
				if !dispatch.valid() { return }
			}
		}
		mut navigation_key := match key {
			.left { 'left' }
			.right { 'right' }
			.up { 'up' }
			.down { 'down' }
			.home { 'home' }
			.end { 'end' }
			.page_up { 'page_up' }
			.page_down { 'page_down' }
			.a { 'a' }
			else { '' }
		}
		focused_text_area := focused_node.el.kind == .text_area
		if focused_text_area && (navigation_key == 'page_up' || navigation_key == 'page_down') {
			page_focused_text_area(if navigation_key == 'page_up' { -1 } else { 1 })
			return
		}
		primary_modifier := text_navigation_primary_modifier(
			modifiers & u32(gg.Modifier.ctrl) != 0,
			modifiers & u32(gg.Modifier.alt) != 0,
			modifiers & u32(gg.Modifier.super) != 0,
		)
		word_modifier := text_navigation_word_modifier(
			modifiers & u32(gg.Modifier.ctrl) != 0,
			modifiers & u32(gg.Modifier.alt) != 0,
		)
		boundary_modifier := text_navigation_boundary_modifier(
			modifiers & u32(gg.Modifier.super) != 0,
		)
		if focused_text_area && (navigation_key == 'up' || navigation_key == 'down') {
			if move_focused_text_area_caret(mut editor, if navigation_key == 'up' { -1 } else { 1 },
				modifiers & u32(gg.Modifier.shift) != 0) {
				g_text_editors[g_focused_field] = editor
			}
			return
		}
		if focused_text_area && (navigation_key == 'home' || navigation_key == 'end')
			&& !primary_modifier {
			if move_focused_text_area_line_boundary(mut editor, navigation_key == 'end',
				modifiers & u32(gg.Modifier.shift) != 0) {
				g_text_editors[g_focused_field] = editor
			}
			return
		}
		if boundary_modifier && navigation_key == 'left' {
			navigation_key = 'home'
		} else if boundary_modifier && navigation_key == 'right' {
			navigation_key = 'end'
		}
		navigation_modifier := if navigation_key == 'a' { primary_modifier } else { word_modifier }
		if navigation_key.len > 0 && apply_text_editor_navigation(mut editor, navigation_key,
			modifiers & u32(gg.Modifier.shift) != 0, navigation_modifier) {
			g_text_editors[g_focused_field] = editor
		}
		if key == .enter || key == .kp_enter {
			if focused_text_area {
				editor.insert_text('\n')
				replace_text_value(g_focused_field, editor.text)
				replace_text_editor(g_focused_field, editor)
				fire_field_change(g_focused_field)
				return
			}
			id := g_focused_field
			dismiss_keyboard()
			if focused_node.el.kind == .text_field {
				fire_target_event(custom_focus_target(focused_node), ElementEvent{ kind: .submit, id: id, text: text(id) })
			}
		}
	}

	// text_navigation_primary_modifier keeps the native text-editing shortcuts
	// available without treating AltGr (reported as Ctrl+Alt on Windows) as
	// Control. Command is the primary modifier on macOS.
	fn text_navigation_primary_modifier(ctrl bool, alt bool, super_ bool) bool {
		$if macos {
			return super_
		} $else {
			return ctrl && !alt
		}
	}

	// text_navigation_word_modifier follows native word movement: Option on
	// macOS, and Control everywhere else. Excluding Alt on non-macOS systems
	// keeps AltGr from being interpreted as a Control shortcut.
fn text_navigation_word_modifier(ctrl bool, alt bool) bool {
		$if macos {
			return alt
		} $else {
			return ctrl && !alt
		}
}

	// text_navigation_boundary_modifier maps Command+Arrow to line boundaries on
	// macOS. On other platforms Ctrl+Arrow must remain word navigation.
fn text_navigation_boundary_modifier(super_ bool) bool {
	$if macos {
		return super_
	} $else {
		return false
	}
}

fn page_focused_text_area(direction int) {
		state_id := named_scroll_state_id(g_focused_field)
		viewport := g_scroll_viewports[state_id] or { return }
		set_scroll_offset(state_id, scroll_state_offset(state_id) + f64(direction) * viewport.height,
			scroll_maximum(state_id))
	}

	fn fire_field_change(id string) {
		if node := g_focus_navigation.node(id) {
			fire_target_event(custom_focus_target(node), ElementEvent{kind: .change, id: id, text: text(id)})
		}
	}

	// ── Dropdown popup ─────────────────────────────────────────────────

	// A dropdown click opens a floating list of its options. Without an id there
	// is nowhere to keep the selection, so such a control only reports the tap.
	fn open_dropdown(target HitTarget) {
		if target.id.len == 0 || target.options.len == 0 {
			fire_target_event(target, ElementEvent{ kind: .tap, id: target.id })
			return
		}
		close_dropdown()
		g_open_dropdown = target.id
		focus(target.id)
	}

	fn close_dropdown() {
		g_open_dropdown = ''
		g_dropdown_hover = -1
		g_dropdown_scroll = 0.0
		g_dropdown_popup = DropdownPopup{}
	}

	// While the list is open it owns every release: pick the row under the
	// pointer, or dismiss on any release outside it (including the control).
	fn handle_dropdown_release(x f64, y f64) {
		release := hit_test(x, y)
		if release.dropdown_option && release.id == g_open_dropdown {
			select_dropdown_option(release)
			return
		}
		close_dropdown()
	}

	fn select_dropdown_option(target HitTarget) {
		if target.option_index < 0 || target.option_index >= target.options.len {
			close_dropdown()
			return
		}
		commit_dropdown(target.id, target.on_event, target.options[target.option_index])
	}

	fn commit_dropdown(id string, on_event ElementCallback, value string) {
		close_dropdown()
		replace_text_value(id, value)
		fire_target_event(HitTarget{ id: id, on_event: on_event }, ElementEvent{ kind: .change, id: id, text: value })
	}

	fn handle_dropdown_key(key gg.KeyCode) bool {
		dropdown_state := g_dropdown_popup
		if dropdown_state.options.len == 0 {
			return false
		}
		highlighted := if g_dropdown_hover >= 0 { g_dropdown_hover } else { dropdown_state.selected }
		match key {
			.escape {
				close_dropdown()
				return true
			}
			.up, .down {
				step := if key == .down { 1 } else { -1 }
				mut next := highlighted + step
				if next < 0 {
					next = dropdown_state.options.len - 1
				} else if next >= dropdown_state.options.len {
					next = 0
				}
				g_dropdown_hover = next
				reveal_dropdown_row(next)
				return true
			}
			.enter, .kp_enter {
				if highlighted < 0 || highlighted >= dropdown_state.options.len {
					close_dropdown()
					return true
				}
				commit_dropdown(dropdown_state.id, dropdown_state.on_event,
					dropdown_state.options[highlighted])
				return true
			}
			else {
				return false
			}
		}
	}

	fn update_dropdown_hover(x f64, y f64) {
		mut hover := -1
		for target in g_hit_targets {
			if !target.dropdown_option || target.id != g_open_dropdown {
				continue
			}
			if hit_target_contains(target, x, y) {
				hover = target.option_index
			}
		}
		g_dropdown_hover = hover
	}

	fn clamped_dropdown_scroll(offset f64) f64 {
		if offset < 0 {
			return 0.0
		}
		max_scroll := g_dropdown_popup.max_scroll
		return if offset > max_scroll { max_scroll } else { offset }
	}

	fn reveal_dropdown_row(index int) {
		dropdown_state := g_dropdown_popup
		if index < 0 || dropdown_state.max_scroll <= 0 {
			g_dropdown_scroll = clamped_dropdown_scroll(g_dropdown_scroll)
			return
		}
		view_height := dropdown_state.height - dropdown_popup_padding * 2
		row_top := f64(index) * dropdown_state.row_height
		row_bottom := row_top + dropdown_state.row_height
		mut offset := g_dropdown_scroll
		if row_top < offset {
			offset = row_top
		} else if row_bottom > offset + view_height {
			offset = row_bottom - view_height
		}
		g_dropdown_scroll = clamped_dropdown_scroll(offset)
	}

	fn dropdown_row_height(style TextStyle) f64 {
		row_height := style.size + 13
		return if row_height < dropdown_popup_min_row_height {
			dropdown_popup_min_row_height
		} else {
			row_height
		}
	}

	// dropdown_popup_frame drops the list below its control, flips it above when
	// more rows fit there, and keeps whole rows inside the window so a clipped
	// half row never looks selectable.
	fn dropdown_popup_frame(anchor Rect, options int, row_height f64, window Rect) Rect {
		chrome := dropdown_popup_padding * 2
		below := window.height - (anchor.y + anchor.height) - dropdown_popup_gap - dropdown_popup_margin
		above := anchor.y - dropdown_popup_gap - dropdown_popup_margin
		rows_below := int((below - chrome) / row_height)
		rows_above := int((above - chrome) / row_height)
		flip := rows_above > rows_below
		mut rows := if flip { rows_above } else { rows_below }
		if rows > options {
			rows = options
		}
		if rows < 1 {
			rows = 1
		}
		height := f64(rows) * row_height + chrome
		mut x := anchor.x
		if x + anchor.width > window.width - dropdown_popup_margin {
			x = window.width - dropdown_popup_margin - anchor.width
		}
		if x < dropdown_popup_margin {
			x = dropdown_popup_margin
		}
		mut y := if flip {
			anchor.y - dropdown_popup_gap - height
		} else {
			anchor.y + anchor.height + dropdown_popup_gap
		}
		if y + height > window.height - dropdown_popup_margin {
			y = window.height - dropdown_popup_margin - height
		}
		if y < dropdown_popup_margin {
			y = dropdown_popup_margin
		}
		return rect(x, y, anchor.width, height)
	}

	fn track_dropdown_popup(el Element, x f64, y f64, options []string, selected string) {
		ctx := g_gg_app.ctx
		if ctx == unsafe { nil } {
			return
		}
		mut selected_index := -1
		for index, option in options {
			if option == selected {
				selected_index = index
				break
			}
		}
		row_height := dropdown_row_height(el.text_style) * ctx.content_transform.footprint_scale()
		anchor := ctx.content_transform.project(rect(x, y, el.frame.width, el.frame.height))
		window := rect(0, 0, f64(ctx.width), f64(ctx.height))
		frame := dropdown_popup_frame(anchor, options.len, row_height, window)
		content_height := f64(options.len) * row_height
		view_height := frame.height - dropdown_popup_padding * 2
		opening := g_dropdown_popup.id != el.id
		g_dropdown_popup = DropdownPopup{
			id:         el.id
			on_event:   el.on_event
			x:          frame.x
			y:          frame.y
			width:      frame.width
			height:     frame.height
			row_height: row_height
			options:    options
			selected:   selected_index
			text_style: scaled_overlay_text_style(el.text_style, ctx.content_transform.footprint_scale())
			radius:     el.box.radius * ctx.content_transform.footprint_scale()
			max_scroll: if content_height > view_height {
				content_height - view_height
			} else {
				0.0
			}
			mounted:    true
		}
		if opening {
			g_dropdown_scroll = 0.0
			g_dropdown_hover = -1
			reveal_dropdown_row(selected_index)
		} else {
			g_dropdown_scroll = clamped_dropdown_scroll(g_dropdown_scroll)
		}
	}

	fn draw_dropdown_popup(ctx &DrawContext) {
		dropdown_state := g_dropdown_popup
		if dropdown_state.options.len == 0 || dropdown_state.width <= 0
			|| dropdown_state.height <= 0 {
			return
		}
		window := rect(0, 0, f64(ctx.width), f64(ctx.height))
		apply_clip(ctx, window)
		draw_rect(ctx, dropdown_state.x + 1, dropdown_state.y + 2, dropdown_state.width,
			dropdown_state.height, 0xdbe2ea, dropdown_state.radius)
		draw_rect(ctx, dropdown_state.x, dropdown_state.y, dropdown_state.width,
			dropdown_state.height, 0xffffff, dropdown_state.radius)
		draw_outline(ctx, dropdown_state.x, dropdown_state.y, dropdown_state.width,
			dropdown_state.height, 0xb8c2cf, dropdown_state.radius)
		list := intersect_rect(rect(dropdown_state.x + 1,
			dropdown_state.y + dropdown_popup_padding, dropdown_state.width - 2,
			dropdown_state.height - dropdown_popup_padding * 2), window)
		if list.width <= 0 || list.height <= 0 {
			return
		}
		apply_clip(ctx, list)
		row_style := TextStyle{
			...dropdown_state.text_style
			align: .left
		}
		for index, option in dropdown_state.options {
			row_y := dropdown_state.y + dropdown_popup_padding + f64(index) * dropdown_state.row_height -
				g_dropdown_scroll
			if row_y + dropdown_state.row_height <= list.y || row_y >= list.y + list.height {
				continue
			}
			if index == g_dropdown_hover {
				draw_rect(ctx, dropdown_state.x + 2, row_y, dropdown_state.width - 4,
					dropdown_state.row_height, 0xdbeafe, 4)
			} else if index == dropdown_state.selected {
				draw_rect(ctx, dropdown_state.x + 2, row_y, dropdown_state.width - 4,
					dropdown_state.row_height, 0xf1f5f9, 4)
			}
			if index == dropdown_state.selected {
				mark := if dropdown_state.row_height < 13 { dropdown_state.row_height } else { 13.0 }
				draw_check_mark(ctx, dropdown_state.x + 7,
					row_y + (dropdown_state.row_height - mark) / 2, mark, row_style.color)
			}
			draw_text(ctx, option, dropdown_state.x + 26, row_y, dropdown_state.width - 34,
				dropdown_state.row_height, row_style)
			add_hit_target(HitTarget{
				kind: .dropdown
				id: dropdown_state.id
				on_event: dropdown_state.on_event
				x: dropdown_state.x
				y: row_y
				w: dropdown_state.width
				h: dropdown_state.row_height
				dropdown_option: true
				option_index: index
				options: dropdown_state.options
			}, list)
		}
		draw_scrollbar(ctx, dropdown_state.x, dropdown_state.y, dropdown_state.width,
			dropdown_state.height, f64(dropdown_state.options.len) * dropdown_state.row_height +
			dropdown_popup_padding * 2, g_dropdown_scroll, false)
		apply_clip(ctx, window)
	}

	// ── Tooltips ───────────────────────────────────────────────────────

	// pointer_moved restarts the rest a tooltip waits for. One already showing
	// stays where it opened while the pointer moves within its target, as the
	// native ones do, rather than chasing the cursor.
	fn (mut state TooltipState) pointer_moved(x f64, y f64, now i64) {
		state.pointer_x = x
		state.pointer_y = y
		state.pointer_in = true
		if !state.visible {
			state.rest_since = now
		}
	}

	fn (mut state TooltipState) pointer_left() {
		state.pointer_in = false
		state.visible = false
		state.dismissed = false
		state.key = ''
	}

	fn (mut state TooltipState) dismiss() {
		state.visible = false
		state.dismissed = true
	}

	fn (mut state TooltipState) restart(now i64) {
		state.visible = false
		state.rest_since = now
	}

	// update settles the tooltip for a frame, given the target now under the
	// pointer. A blocked frame is one where something else holds the pointer's
	// attention; the rest only starts once it lets go.
	fn (mut state TooltipState) update(target TooltipTarget, blocked bool, now i64) {
		if !state.pointer_in || target.text.len == 0 {
			state.key = ''
			state.dismissed = false
			state.visible = false
			return
		}
		if target.key != state.key {
			state.key = target.key
			state.rest_since = now
			state.dismissed = false
			state.visible = false
		}
		if blocked {
			state.visible = false
			state.rest_since = now
			return
		}
		if state.dismissed {
			return
		}
		if !state.visible && now - state.rest_since >= tooltip_delay_ms {
			state.visible = true
			state.anchor_x = state.pointer_x
			state.anchor_y = state.pointer_y
		}
		// A label that changes while its tooltip is open shows the new text.
		state.text = target.text
	}

	// tooltip_target_at finds the target under a point. Targets are registered
	// in drawing order, so the last one containing the point is the one drawn
	// on top, whether it has text to show or only hides what is beneath it.
	fn tooltip_target_at(targets []TooltipTarget, x f64, y f64) TooltipTarget {
		for i := targets.len - 1; i >= 0; i-- {
			frame := targets[i].frame
			target := targets[i]
			if hit_target_contains(HitTarget{x: frame.x, y: frame.y, w: frame.width, h: frame.height,
				local_frame: target.local_frame, content_transform: target.content_transform,
				clip_region: target.clip_region, has_geometry: target.has_geometry,
				is_vector_canvas: target.is_vector_canvas, vector_shapes: target.vector_shapes,
				vector_hit_mode: target.vector_hit_mode, vector_origin: target.vector_origin}, x, y) {
				return targets[i]
			}
		}
		return TooltipTarget{}
	}

	// tooltip_key names an element's target. An id stays the same while the
	// element moves; an element without one is known by where it is drawn,
	// which holds for as long as nothing, such as a scroll, moves it.
	fn tooltip_key(el Element, area Rect) string {
		if el.id.len > 0 {
			return '${el.kind}#${el.id}'
		}
		return '${el.kind}@${area.x},${area.y},${area.width},${area.height}'
	}

	// add_tooltip_target registers the part of a target that is visible under
	// the clip it was drawn with, so a control scrolled out of its viewport
	// cannot answer for the pointer.
	fn add_tooltip_target(key string, text string, area Rect, clip Rect) {
		region := current_clip_region(clip)
		visible := region.intersect(transformed_clip(area, current_content_transform())).bounds()
		if visible.width <= 0 || visible.height <= 0 {
			return
		}
		g_tooltip_targets << TooltipTarget{
			key:               key
			text:              text
			frame:             visible
			local_frame:       area
			content_transform: current_content_transform()
			clip_region:       region
			has_geometry:      true
		}
	}

	// add_full_text_tooltip lets the pointer read text the renderer had to
	// shorten, the way a truncated cell expands to its full text on hover in
	// the native toolkits. A tooltip the element declared is more specific
	// about it and was registered already, so it is kept instead.
	fn add_full_text_tooltip(el Element, area Rect, clip Rect, full string, shortened bool) {
		if !shortened || el.tooltip.len > 0 || full.len == 0 {
			return
		}
		add_tooltip_target(tooltip_key(el, area), full, area, clip)
	}

	// tooltip_hides_beneath reports a surface that covers whatever was drawn
	// before it: a filled view, such as a dialog or its backdrop, or a scroll
	// view, which always paints its background. Without one, a truncated label
	// underneath would still answer for the pointer through it.
	fn tooltip_hides_beneath(el Element) bool {
		return (el.kind == .view && (!el.box.transparent || el.vector_shapes.len > 0)) || el.kind == .scroll
	}

	// element_area is where an element is drawn in the window. The screen
	// fills the window below its offset, whatever its frame says.
	fn element_area(ctx &DrawContext, el Element, off_x f64, off_y f64) Rect {
		if el.kind == .screen {
			host_window := if g_gg_app.ctx == ctx { g_gg_app.native_window } else { unsafe { nil } }
			viewport := ctx.logical_viewport(host_window)
			return mounted_root_frame(el, rect(off_x, off_y, viewport.width - off_x, viewport.height - off_y))
		}
		return rect(el.frame.x + off_x, el.frame.y + off_y, el.frame.width, el.frame.height)
	}

	// update_tooltip settles the tooltip once the frame's targets are known.
	// Nothing shows while an open dropdown list or menu has the pointer, or
	// while a press or a drag is still in progress.
	fn update_tooltip(now i64) {
		target := tooltip_target_at(g_tooltip_targets, g_tooltip.pointer_x, g_tooltip.pointer_y)
		blocked := g_open_dropdown.len > 0 || menu_bar_open() || g_touch.down
		g_tooltip.update(target, blocked, now)
	}

	// tooltip_frame puts a tooltip below and to the right of the pointer, clear
	// of the cursor, and keeps it inside the window: it is pushed in from the
	// right edge, and opens above the pointer when there is no room below.
	fn tooltip_frame(pointer_x f64, pointer_y f64, width f64, height f64, window Rect) Rect {
		right := window.x + window.width - tooltip_margin
		bottom := window.y + window.height - tooltip_margin
		mut x := pointer_x + tooltip_offset_x
		mut y := pointer_y + tooltip_offset_y
		if y + height > bottom {
			y = pointer_y - tooltip_gap - height
		}
		if x + width > right {
			x = right - width
		}
		if x < window.x + tooltip_margin {
			x = window.x + tooltip_margin
		}
		if y < window.y + tooltip_margin {
			y = window.y + tooltip_margin
		}
		return rect(x, y, width, height)
	}

	fn draw_tooltip(ctx &DrawContext) {
		if !g_tooltip.visible || g_tooltip.text.len == 0 {
			return
		}
		style := TextStyle{
			color: tooltip_text_color
			size: tooltip_text_size
			align: .left
		}
		$if android {
			// Measured with the configuration draw_text_in_box draws with, so no
			// line that fits here is shortened when it is drawn.
			ctx.set_text_cfg(gg.TextCfg{
				size: int(font_render_size(style.size, text_font_metrics('')) + 0.5)
				align: .left
				vertical_align: .middle
			})
			lines, text_width := tooltip_lines(g_tooltip.text, fn [ctx] (line string) f64 {
				return f64(ctx.text_width_f(line))
			})
			if lines.len == 0 {
				return
			}
			line_h := font_line_height(style.size)
			window := rect(0, 0, f64(ctx.width), f64(ctx.height))
			frame := tooltip_frame(g_tooltip.anchor_x, g_tooltip.anchor_y,
				text_width + tooltip_padding * 2, f64(lines.len) * line_h + tooltip_padding * 2, window)
			apply_clip(ctx, window)
			draw_rect(ctx, frame.x + 1, frame.y + 2, frame.width, frame.height, tooltip_shadow,
				tooltip_radius)
			draw_rect(ctx, frame.x, frame.y, frame.width, frame.height, tooltip_background,
				tooltip_radius)
			draw_outline(ctx, frame.x, frame.y, frame.width, frame.height, tooltip_border,
				tooltip_radius)
			for i, line in lines {
				draw_text_in_box(ctx, line, frame.x + tooltip_padding,
					frame.y + tooltip_padding + f64(i) * line_h, text_width, line_h, style, true, Rect{})
			}
		} $else {
			shaped := ctx.shape_text(g_tooltip.text.trim_right(' \t\r\n'), style,
				tooltip_max_text_width, tooltip_max_lines, true) or {
				eprintln('ui2: tooltip text: ${err}')
				return
			}
			text_width := math.min(math.ceil(shaped.size.width), tooltip_max_text_width)
			window := rect(0, 0, f64(ctx.width), f64(ctx.height))
			frame := tooltip_frame(g_tooltip.anchor_x, g_tooltip.anchor_y,
				text_width + tooltip_padding * 2, shaped.size.height + tooltip_padding * 2, window)
			apply_clip(ctx, window)
			draw_rect(ctx, frame.x + 1, frame.y + 2, frame.width, frame.height, tooltip_shadow,
				tooltip_radius)
			draw_rect(ctx, frame.x, frame.y, frame.width, frame.height, tooltip_background,
				tooltip_radius)
			draw_outline(ctx, frame.x, frame.y, frame.width, frame.height, tooltip_border,
				tooltip_radius)
			ctx.draw_shaped(shaped, frame.x + tooltip_padding, frame.y + tooltip_padding)
		}
	}

	fn prune_unmounted_state() {
		mut stale_fields := []string{}
		for id, _ in g_text_values {
			if id !in g_active_fields {
				stale_fields << id
			}
		}
		for id in stale_fields {
			forget_text_state(id)
			forget_portable_text_area_selection(id)
			if g_focused_field == id {
				g_focused_field = ''
			}
		}
		mut stale_sliders := []string{}
		for id, _ in g_slider_values {
			if id !in g_active_sliders {
				stale_sliders << id
			}
		}
		for id in stale_sliders {
			g_slider_values.delete(id)
			g_slider_declared.delete(id)
			g_slider_specs.delete(id)
		}
		mut stale_switches := []string{}
		for id, _ in g_switch_values {
			if id !in g_active_switches {
				stale_switches << id
			}
		}
		for id in stale_switches {
			g_switch_values.delete(id)
			g_switch_declared.delete(id)
		}
		mut stale_checkboxes := []string{}
		for id, _ in g_checkbox_values {
			if id !in g_active_checkboxes {
				stale_checkboxes << id
			}
		}
		for id in stale_checkboxes {
			g_checkbox_values.delete(id)
			g_checkbox_declared.delete(id)
		}
		mut stale_toggles := []string{}
		for id, _ in g_toggle_values {
			if id !in g_active_toggles {
				stale_toggles << id
			}
		}
		for id in stale_toggles {
			g_toggle_values.delete(id)
			g_toggle_declared.delete(id)
			g_toggle_groups.delete(id)
			g_toggle_allow_no_selection.delete(id)
		}
		mut stale_scrolls := []string{}
		for id, _ in g_scroll_offsets {
			if id !in g_active_scrolls {
				stale_scrolls << id
			}
		}
		for id in stale_scrolls {
			g_scroll_offsets.delete(id)
			g_scroll_content_h.delete(id)
			g_scroll_transforms.delete(id)
		}
		for id in g_text_area_layouts.keys() {
			if id !in g_active_fields || (g_text_kinds[id] or { Kind.screen }) != .text_area {
				forget_text_area_layout(id)
			}
		}
		mut stale_images := []string{}
		for path, _ in g_image_ids {
			if path !in g_active_images {
				stale_images << path
			}
		}
		mut image_ctx := g_gg_app.ctx
		for path in stale_images {
			image_id := g_image_ids[path] or { continue }
			image_ctx.remove_cached_image_by_idx(image_id)
			g_image_ids.delete(path)
		}
	}

	// ── Rendering ──────────────────────────────────────────────────────

	fn element_hit_geometry(el Element, area Rect, transform ContentTransform, clip ClipRegion) HitTarget {
		visible := clip.intersect(transformed_clip(area, transform)).bounds()
		return HitTarget{x: visible.x, y: visible.y, w: visible.width, h: visible.height,
			local_frame: area, content_transform: transform, clip_region: clip, has_geometry: true,
			is_vector_canvas: el.is_vector_canvas, vector_shapes: el.vector_shapes,
			vector_hit_mode: el.vector_hit_mode, vector_origin: area}
	}

	fn resolve_custom_visual_style(declared Element, area Rect, clip Rect, transform ContentTransform) Element {
		region := current_clip_region(clip)
		geometry := element_hit_geometry(declared, area, transform, region)
		hovered := g_tooltip.pointer_in && hit_target_contains(geometry,g_tooltip.pointer_x,g_tooltip.pointer_y)
		focused := declared.focused || (declared.id.len > 0 && declared.id == g_focused_field)
		style_pressed := g_touch.down && declared.id.len > 0
			&& (declared.id == g_touch.pressed_id || declared.id == g_touch.pointer_target.id)
			&& (!g_touch.pointer_captured || declared.kind == g_touch.pointer_target.kind)
			&& !g_touch.moved && !g_touch.scrollbar_drag
			&& hit_target_contains(geometry,g_touch.current_x,g_touch.current_y)
		return Element{...declared,
			box: interaction_box(declared, hovered, focused, style_pressed)
			text_style: interaction_text_style(declared, hovered, focused, style_pressed)}
	}

	fn render_scaled_content(ctx &DrawContext, el Element, off_x f64, off_y f64, clip Rect, scroll_parent_id string, path string) {
		dispatch := custom_input_dispatch(g_gg_app)
		root := g_focus_navigation.root
		if el.hidden { return }
		viewport := rect(el.frame.x + off_x, el.frame.y + off_y, el.frame.width, el.frame.height)
		local := contain_content(viewport, el.content_size.width, el.content_size.height) or { return }
		render_element_body(ctx, Element{ ...el, children: [], content_size: LayoutSize{} }, off_x, off_y, clip, scroll_parent_id, path)
		if !custom_frame_current(dispatch, ctx) || g_focus_navigation.root != root { return }
		outer := ctx.content_transform
		base := ctx.clip_base
		region := ctx.clip_region
		exact := base.intersect(transformed_clip(viewport, outer))
		unsafe {
			ctx.content_transform = outer.compose(local)
			ctx.clip_base = exact
			ctx.clip_region = exact
		}
		defer { unsafe {
			ctx.content_transform = outer
			ctx.clip_base = base
			ctx.clip_region = region
		}
		ctx.sync_scissor()
		 }
		// Fixed composition clips in its own coordinates. Never inverse an AABB to
		// recover an ancestor clip; exact window polygons survive nested transforms.
		content_clip := rect(0, 0, el.content_size.width, el.content_size.height)
		apply_clip(ctx, content_clip)
		for index, child in el.children {
			render_element(ctx, child, 0, 0, content_clip, scroll_parent_id, reconciliation_child_key(path, index, child))
			if !custom_frame_current(dispatch, ctx) || g_focus_navigation.root != root { return }
		}
	}

	fn render_element(ctx &DrawContext, declared_el Element, off_x f64, off_y f64, clip Rect, scroll_parent_id string, path string) {
		if declared_el.hidden { return }
		outer := ctx.content_transform
		base := ctx.clip_base
		region := ctx.clip_region
		enabled := ctx.interaction_enabled
		parent_clip := base.intersect(transformed_clip(clip, outer))
		area := element_area(ctx, declared_el, off_x, off_y)
		visual := declared_el.visual_transform().matrix(area) or { return }
		inv := visual.inverted() or { return }
		local_clip := inv.project(clip)
		unsafe {
			ctx.content_transform = outer.compose(visual)
			ctx.clip_base = parent_clip
			ctx.clip_region = parent_clip
			ctx.interaction_enabled = enabled && declared_el.enabled
		}
		defer { unsafe {
			ctx.content_transform = outer
			ctx.clip_base = base
			ctx.clip_region = region
			ctx.interaction_enabled = enabled
		}
		ctx.sync_scissor()
		 }
		el := Element{ ...declared_el, enabled: enabled && declared_el.enabled }
		if el.id.len > 0 {
			g_gg_app.visual_geometries[el.id] = VisualGeometry{ frame: area, transform: ctx.content_transform, parent_transform: outer, clip: parent_clip }
		}
		render_element_body(ctx, el, off_x, off_y, local_clip, scroll_parent_id, path)
	}

	fn render_element_body(ctx &DrawContext, declared_el Element, off_x f64, off_y f64, clip Rect, scroll_parent_id string, path string) {
		dispatch := custom_input_dispatch(g_gg_app)
		root := g_focus_navigation.root
		if declared_el.content_size.width > 0 || declared_el.content_size.height > 0 {
			render_scaled_content(ctx, declared_el, off_x, off_y, clip, scroll_parent_id, path)
			return
		}
		if declared_el.hidden {
			return
		}
		sync_mounted_control(declared_el)
		apply_clip(ctx, clip)
		area := element_area(ctx, declared_el, off_x, off_y)
		el := resolve_custom_visual_style(declared_el, area, clip, ctx.content_transform)
		if el.box.outline_width > 0 {
			outline_frame, outline_box := box_outline_geometry(area, el.box)
			draw_box_borders(ctx, outline_frame.x, outline_frame.y, outline_frame.width, outline_frame.height, outline_box)
		}

		// A declared tooltip covers the element's whole area and is registered
		// before its children, so a child with hover text of its own wins over
		// it where they overlap. A surface only has anything to hide once some
		// target has been registered before it.
		owns_tooltip := el.tooltip.len > 0
		if owns_tooltip {
			add_element_tooltip(tooltip_key(el, area), el.tooltip, el, area, clip)
			g_tooltip_owners++
		} else if g_tooltip_owners == 0 && g_tooltip_targets.len > 0 && tooltip_hides_beneath(el) {
			add_element_tooltip('', '', el, area, clip)
		}
		defer {
			if owns_tooltip {
				g_tooltip_owners--
			}
		}
		if el.id.len > 0 && el.id == g_focused_field && el.kind !in [.text_field, .text_area] {
			draw_outline(ctx, area.x - 2, area.y - 2, area.width + 4, area.height + 4, 0x2563eb, el.box.radius)
		}
		match el.kind {
			.screen {
				if !el.box.transparent {
					draw_rect(ctx, area.x, area.y, area.width, area.height, el.box.bg, 0)
				}
				draw_box_borders(ctx, area.x, area.y, area.width, area.height, el.box)
				for index, child in el.children {
					render_element(ctx, child, off_x, off_y, clip, scroll_parent_id, reconciliation_child_key(path,index,child))
					if !custom_frame_current(dispatch, ctx) || g_focus_navigation.root != root { return }
				}
			}
			.view {
				x := el.frame.x + off_x
				y := el.frame.y + off_y
				if !el.box.transparent {
					draw_rect(ctx, x, y, el.frame.width, el.frame.height, el.box.bg, el.box.radius)
				}
				draw_box_borders(ctx, x, y, el.frame.width, el.frame.height, el.box)
				if el.vector_shapes.len > 0 {
					region := ctx.clip_region
					apply_clip(ctx, intersect_rect(area, clip))
					draw_vector_shapes(ctx, el.vector_shapes, x, y)
					unsafe { ctx.clip_region = region }
					ctx.sync_scissor()
				}
				if el.enabled && voidptr(el.on_event) != unsafe { nil }
					&& (el.clickable || el.button_behavior || el.draggable || el.long_press
						|| el.swipe_left) {
					add_hit_target(HitTarget{
						identity:        path
						kind:            el.kind
						id:              el.id
						on_event:        el.on_event
						x:               x
						y:               y
						w:               el.frame.width
						h:               el.frame.height
						long_press:      el.long_press
						swipe_left:      el.swipe_left
						clickable:       el.clickable
						button_behavior: el.button_behavior
						draggable:       el.draggable
						vector_shapes: el.vector_shapes
						is_vector_canvas: el.is_vector_canvas
						vector_hit_mode: el.vector_hit_mode
						vector_origin: area
					}, clip)
				}
				for index, child in el.children {
					render_element(ctx, child, x, y, clip, scroll_parent_id, reconciliation_child_key(path,index,child))
					if !custom_frame_current(dispatch, ctx) || g_focus_navigation.root != root { return }
				}
			}
			.scroll {
				x := el.frame.x + off_x
				y := el.frame.y + off_y
				frame := rect(x, y, el.frame.width, el.frame.height)
				draw_rect(ctx, x, y, el.frame.width, el.frame.height, el.box.bg, 0)
				draw_box_borders(ctx, x, y, el.frame.width, el.frame.height, el.box)
				content_h := scroll_content_height(el)
				scroll_id := scroll_view_state_id(el, path)
				scroll_y := register_scroll_view_in_parent(scroll_id, scroll_parent_id, frame, clip, content_h, el.enabled,
					true, el.persistent_scrollbars, HitTarget{ id: el.id, kind: .scroll, on_event: el.on_event })
				if !custom_frame_current(dispatch, ctx) || g_focus_navigation.root != root { return }
				child_scroll_parent_id := scroll_id
				child_clip := intersect_rect(frame, clip)
				for index, child in el.children {
					child_screen_y := child.frame.y - scroll_y
					if !subtree_has_visual_transform(child) && (child_screen_y + child.frame.height < 0 || child_screen_y > el.frame.height) {
						retain_culled_scroll_state(child, reconciliation_child_key(path, index, child))
						continue
					}
					render_element(ctx, child, x, y - scroll_y, child_clip, child_scroll_parent_id, reconciliation_child_key(path,index,child))
					if !custom_frame_current(dispatch, ctx) || g_focus_navigation.root != root { return }
				}
				if child_clip.width > 0 && child_clip.height > 0 {
					apply_clip(ctx, child_clip)
					draw_scrollbar(ctx, x, y, el.frame.width, el.frame.height, content_h, scroll_y,
						el.persistent_scrollbars)
				}
				apply_clip(ctx, clip)
			}
			.label {
				x := el.frame.x + off_x
				y := el.frame.y + off_y
				draw_box_borders(ctx, x, y, el.frame.width, el.frame.height, el.box)
				shortened := draw_rich_label_text(ctx, el, x, y, clip)
				add_full_text_tooltip(el, area, clip, el.text, shortened)
			}
			.image {
				x := el.frame.x + off_x
				y := el.frame.y + off_y
				if el.image_path.trim_space().len > 0
					&& !draw_cached_image(ctx, el.image_path, x, y, el.frame.width, el.frame.height) {
					draw_rect(ctx, x, y, el.frame.width, el.frame.height, 0xe8ecef, 0)
				}
				if el.enabled && voidptr(el.on_event) != unsafe { nil }
					&& (el.clickable || el.draggable) {
					add_hit_target(HitTarget{
						identity:  path
						kind:      el.kind
						id:        el.id
						on_event:  el.on_event
						x:         x
						y:         y
						w:         el.frame.width
						h:         el.frame.height
						clickable: el.clickable
						draggable: el.draggable
					}, clip)
				}
			}
			.button {
				x := el.frame.x + off_x
				y := el.frame.y + off_y
				if el.native_style && el.box.bg == unstyled_box_bg {
					draw_button_bezel(ctx, x, y, el.frame.width, el.frame.height, el.box.radius,
						el.enabled)
				} else {
					draw_rect(ctx, x, y, el.frame.width, el.frame.height, el.box.bg, el.box.radius)
				}
				draw_box_borders(ctx, x, y, el.frame.width, el.frame.height, el.box)
				image_layout := button_image_layout(el.frame.width, el.frame.height, el.text,
					el.image_path)
				if image_layout.visible {
					draw_button_image(ctx, el.image_path, x + image_layout.image.x,
						y + image_layout.image.y, image_layout.image.width, image_layout.image.height,
						el.text_style)
				}
				if el.text.len > 0 && image_layout.has_title_area() {
					shortened := draw_text_centered(ctx, el.text, x + image_layout.text.x,
						y + image_layout.text.y, image_layout.text.width, image_layout.text.height,
						el.text_style)
					add_full_text_tooltip(el, area, clip, el.text, shortened)
				}
				if el.enabled {
					add_hit_target(HitTarget{
						identity:   path
						kind:       el.kind
						id:         el.id
						on_event:   el.on_event
						x:          x
						y:          y
						w:          el.frame.width
						h:          el.frame.height
						long_press: el.long_press
					}, clip)
				}
			}
			.toggle_button {
				x := el.frame.x + off_x
				y := el.frame.y + off_y
				pressed := g_toggle_values[el.id] or { el.checked }
				box := if pressed { el.toggle_down_box } else { el.box }
				style := if pressed { el.toggle_down_text_style } else { el.text_style }
				if el.native_style && box.bg == unstyled_box_bg {
					draw_button_bezel(ctx, x, y, el.frame.width, el.frame.height, box.radius,
						el.enabled)
				} else {
					draw_rect(ctx, x, y, el.frame.width, el.frame.height, box.bg, box.radius)
				}
				draw_box_borders(ctx, x, y, el.frame.width, el.frame.height, box)
				shortened := draw_text_centered(ctx, el.text, x, y, el.frame.width, el.frame.height,
					style)
				add_full_text_tooltip(el, area, clip, el.text, shortened)
				if el.enabled {
					add_hit_target(HitTarget{
						identity:                  path
						kind:                      el.kind
						id:                        el.id
						on_event:                  el.on_event
						x:                         x
						y:                         y
						w:                         el.frame.width
						h:                         el.frame.height
						toggle_button:             true
						toggle_group:              el.toggle_group
						toggle_allow_no_selection: el.toggle_allow_no_selection
					}, clip)
				}
			}
			.checkbox {
				x := el.frame.x + off_x
				y := el.frame.y + off_y
				checked := g_checkbox_values[el.id] or { el.checked }
				box_size := if el.frame.height < 18 { el.frame.height } else { 18.0 }
				box_y := y + (el.frame.height - box_size) / 2
				fill := if checked {
					if el.enabled { u32(0x3478d4) } else { u32(0x94a3b8) }
				} else {
					u32(0xffffff)
				}
				border := if checked {
					if el.enabled { u32(0x2f6fc4) } else { u32(0x94a3b8) }
				} else if el.enabled {
					u32(0x64748b)
				} else {
					u32(0xcbd5e1)
				}
				draw_rect(ctx, x, box_y, box_size, box_size, fill, 4)
				draw_outline(ctx, x, box_y, box_size, box_size, border, 4)
				if checked {
					draw_check_mark(ctx, x, box_y, box_size, if el.enabled {
						u32(0xffffff)
					} else {
						u32(0xf8fafc)
					})
				}
				shortened := draw_text(ctx, el.text, x + box_size + 8, y, el.frame.width - box_size - 8,
					el.frame.height, el.text_style)
				add_full_text_tooltip(el, area, clip, el.text, shortened)
				if el.enabled {
					add_hit_target(HitTarget{
						identity:       path
						kind:           el.kind
						id:             el.id
						on_event:       el.on_event
						x:              x
						y:              y
						w:              el.frame.width
						h:              el.frame.height
						checkbox:       true
						checkbox_state: checked
					}, clip)
				}
			}
			.dropdown {
				x := el.frame.x + off_x
				y := el.frame.y + off_y
				selected := g_text_values[el.id] or { el.text }
				list_open := el.enabled && el.id.len > 0 && g_open_dropdown == el.id
				draw_control_surface(ctx, x, y, el.frame.width, el.frame.height, el.box,
					list_open, el.enabled)
				padding := if el.padding_left > 0 { el.padding_left } else { 12.0 }
				text_width := if el.frame.width > padding + 32 {
					el.frame.width - padding - 32
				} else {
					0.0
				}
				shortened := draw_text(ctx, selected, x + padding, y, text_width, el.frame.height,
					el.text_style)
				add_full_text_tooltip(el, area, clip, selected, shortened)
				draw_chevron_down(ctx, x + el.frame.width - 17, y + el.frame.height / 2,
					if el.enabled { u32(0x475569) } else { u32(0x94a3b8) })
				if el.enabled {
					mut options := []string{cap: el.menu.len}
					for entry in el.menu {
						options << entry.title
					}
					add_hit_target(HitTarget{
						identity: path
						kind:     el.kind
						id:       el.id
						on_event: el.on_event
						x:        x
						y:        y
						w:        el.frame.width
						h:        el.frame.height
						dropdown: true
						options:  options
					}, clip)
					if list_open {
						// The inverse clip AABB only accelerates traversal. Decide
						// overlay ownership with the same exact window clip used
						// for paint and fresh pointer hits.
						visible := ctx.clip_region.intersect(transformed_clip(area,
							ctx.content_transform)).bounds()
						if options.len > 0 && visible.width > 0 && visible.height > 0 {
							track_dropdown_popup(el, x, y, options, selected)
						} else {
							close_dropdown()
						}
					}
				} else if el.id.len > 0 && g_open_dropdown == el.id {
					close_dropdown()
				}
			}
			.text_field {
				x := el.frame.x + off_x
				y := el.frame.y + off_y
				padding_left := if el.padding_left > 0 { el.padding_left } else { f64(0) }
				content_width := if el.frame.width > padding_left + 8 {
					el.frame.width - padding_left - 8
				} else {
					f64(0)
				}
				current_text := g_text_values[el.id] or { el.text }
				mut editor := g_text_editors[el.id] or { text_editor(current_text.clone()) }
				if editor.text != current_text {
					editor.set_text(current_text.clone())
					replace_text_editor(el.id, editor)
				}
				$if macos && ui2_embedder ? {
					editor = custom_composition_editor(el.id, editor)
				}
				display_text := text_field_display_text(editor.text, el.secure)
				is_focused := g_focused_field == el.id
				draw_control_surface(ctx, x, y, el.frame.width, el.frame.height, el.box,
					is_focused, el.enabled)
				// Editable text is not ellipsized: keep its full value for caret and
				// selection measurement, but paint only inside the input's viewport.
				content_clip := intersect_rect(text_field_content_rect(rect(x, y,
					el.frame.width, el.frame.height), padding_left), clip)
				if content_clip.width > 0 && content_clip.height > 0 {
					apply_clip(ctx, content_clip)
					$if android {
						if is_focused && !editor.selection.collapsed() {
							draw_text_field_selection(ctx, display_text, editor.selection, x + padding_left,
								y, content_width, el.frame.height, el.text_style)
						}
						if editor.text.len > 0 {
							draw_editable_text(ctx, display_text, x + padding_left, y, content_width, el.frame.height, el.text_style)
						} else if el.placeholder.len > 0 {
							placeholder_style := TextStyle{
								...el.text_style
								color: 0x999999
							}
							draw_editable_text(ctx, el.placeholder, x + padding_left, y, content_width, el.frame.height, placeholder_style)
						}
						if is_focused {
							before := editor.text.runes()[..editor.selection.caret].string()
							caret_text := text_field_display_text(before, el.secure)
							text_w := f64(ctx.text_width(caret_text))
							text_origin := text_field_aligned_text_origin(x + padding_left, content_width,
								f64(ctx.text_width(display_text)), el.text_style.align)
							cursor_x := text_origin + text_w
							cursor_y := y + el.frame.height * 0.2
							cursor_h := el.frame.height * 0.6
							draw_rect(ctx, cursor_x, cursor_y, 2, cursor_h, el.text_style.color, 0)
							g_gg_app.text_caret = current_presentation_rect(rect(cursor_x, cursor_y, 2, cursor_h))
							$if macos && ui2_embedder ? {
								composition := g_gg_app.composition
								if composition.field_id == el.id {
									marked_start := text_field_display_text(editor.text.runes()[..composition.start + composition.mark_start].string(), el.secure)
									marked_end := text_field_display_text(editor.text.runes()[..composition.start + composition.mark_start + composition.mark_length].string(), el.secure)
									left := text_origin + f64(ctx.text_width(marked_start))
									right := text_origin + f64(ctx.text_width(marked_end))
									draw_rect(ctx, left, cursor_y + cursor_h, right - left, 1, el.text_style.color, 0)
								}
							}
						}
					} $else {
						draw_shaped_text_field(ctx, el, editor, display_text, x + padding_left,
							y, content_width, el.frame.height, is_focused)
					}
					apply_clip(ctx, clip)
				}
				if el.enabled {
					add_hit_target(HitTarget{
						identity:   path
						kind:       el.kind
						id:         el.id
						on_event:   el.on_event
						x:          x
						y:          y
						w:          el.frame.width
						h:          el.frame.height
						text_field: true
					}, clip)
				}
			}
			.text_area {
				x := el.frame.x + off_x
				y := el.frame.y + off_y
				current_text := g_text_values[el.id] or { el.text }
				draw_control_surface(ctx, x, y, el.frame.width, el.frame.height, el.box,
					g_focused_field == el.id, el.enabled)
				draw_text_area_content(ctx, el, current_text, x, y, clip, scroll_parent_id)
				if el.enabled {
					add_hit_target(HitTarget{
						identity:  path
						kind:      el.kind
						id:        el.id
						on_event:  el.on_event
						x:         x
						y:         y
						w:         el.frame.width
						h:         el.frame.height
						text_area: true
					}, clip)
				}
			}
			.slider {
				x := el.frame.x + off_x
				y := el.frame.y + off_y
				frame := rect(x, y, el.frame.width, el.frame.height)
				spec := slider_spec(el)
				current := g_slider_values[el.id] or { el.value }
				normalized := slider_value_normalized(current, spec.min, spec.max)
				track_width := if el.slider_style.track_width > 0 {
					el.slider_style.track_width
				} else {
					4.0
				}
				thumb_size := if el.slider_style.thumb_size > 0 {
					el.slider_style.thumb_size
				} else {
					20.0
				}
				track_color := if el.enabled { el.slider_style.track_color } else { u32(0xe2e8f0) }
				value_color := if el.enabled {
					el.slider_style.value_track_color
				} else {
					u32(0x94a3b8)
				}
				thumb_color := if el.enabled { el.slider_style.thumb_color } else { u32(0x94a3b8) }
				if el.orientation == .vertical {
					inset := slider_track_padding(el.padding, frame.height)
					extent := frame.height - inset * 2
					track_x := frame.x + (frame.width - track_width) / 2
					track_y := frame.y + inset
					draw_rect(ctx, track_x, track_y, track_width, extent, track_color,
						track_width / 2)
					thumb_y := track_y + (1 - normalized) * extent
					if el.value_track {
						draw_rect(ctx, track_x, thumb_y, track_width, track_y + extent - thumb_y,
							value_color, track_width / 2)
					}
					draw_rect(ctx, frame.x + (frame.width - thumb_size) / 2,
						thumb_y - thumb_size / 2, thumb_size, thumb_size, thumb_color,
						thumb_size / 2)
				} else {
					inset := slider_track_padding(el.padding, frame.width)
					extent := frame.width - inset * 2
					track_x := frame.x + inset
					track_y := frame.y + (frame.height - track_width) / 2
					draw_rect(ctx, track_x, track_y, extent, track_width, track_color,
						track_width / 2)
					thumb_x := track_x + normalized * extent
					if el.value_track {
						draw_rect(ctx, track_x, track_y, thumb_x - track_x, track_width,
							value_color, track_width / 2)
					}
					draw_rect(ctx, thumb_x - thumb_size / 2,
						frame.y + (frame.height - thumb_size) / 2, thumb_size, thumb_size,
						thumb_color, thumb_size / 2)
				}
				if el.enabled {
					add_hit_target(HitTarget{
						identity:       path
						kind:           el.kind
						id:             el.id
						on_event:       el.on_event
						x:              frame.x
						y:              frame.y
						w:              frame.width
						h:              frame.height
						slider:         true
						slider_frame:   frame
						slider_padding: el.padding
						slider_spec:    spec
					}, clip)
				}
			}
			.switch_control {
				frame := rect(el.frame.x + off_x, el.frame.y + off_y, el.frame.width,
					el.frame.height)
				active := g_switch_values[el.id] or { el.checked }
				track := switch_track_frame(frame)
				thumb := switch_thumb_frame(track, active)
				track_color := if el.enabled {
					if active {
						el.switch_style.active_track_color
					} else {
						el.switch_style.inactive_track_color
					}
				} else {
					el.switch_style.disabled_track_color
				}
				thumb_color := if el.enabled {
					el.switch_style.thumb_color
				} else {
					el.switch_style.disabled_thumb_color
				}
				draw_rect(ctx, track.x, track.y, track.width, track.height, track_color,
					track.height / 2)
				draw_rect(ctx, thumb.x, thumb.y, thumb.width, thumb.height, thumb_color,
					thumb.height / 2)
				if el.enabled {
					add_hit_target(HitTarget{
						identity:       path
						kind:           el.kind
						id:             el.id
						on_event:       el.on_event
						x:              frame.x
						y:              frame.y
						w:              frame.width
						h:              frame.height
						switch_control: true
						switch_state:   active
					}, clip)
				}
			}
		}
	}

	fn apply_clip(ctx &DrawContext, clip Rect) {
		ctx.scissor_rect(clip.x, clip.y, clip.width, clip.height)
	}

	fn current_content_transform() ContentTransform {
		return if g_gg_app.ctx != unsafe { nil } { g_gg_app.ctx.content_transform } else { ContentTransform{} }
	}

	fn current_presentation_rect(area Rect) Rect {
		transform := current_content_transform()
		region := if g_gg_app.ctx != unsafe { nil } {
			g_gg_app.ctx.clip_region
		} else {
			ClipRegion{}
		}
		projected := region.intersect(transformed_clip(area, transform)).bounds()
		return if g_gg_app.ctx != unsafe { nil } {
			presentation_rect(projected, f64(g_gg_app.ctx.scale))
		} else {
			projected
		}
	}

	fn current_clip_region(clip Rect) ClipRegion {
		base := if g_gg_app.ctx != unsafe { nil } { g_gg_app.ctx.clip_base } else { ClipRegion{} }
		return base.intersect(transformed_clip(clip, current_content_transform()))
	}
	fn add_hit_target(target HitTarget, clip Rect) {
		frame := rect(target.x, target.y, target.w, target.h)
		transform := current_content_transform()
		region := current_clip_region(clip)
		visible := region.intersect(transformed_clip(frame, transform)).bounds()
		// A clipped owner remains mounted for capture, with its current matrix.
		// Empty bounds reject fresh hits without losing terminal/drag coordinates.
		g_hit_targets << HitTarget{
			...target
			content_transform: transform
			local_frame:       frame
			clip_region:       region
			has_geometry:      true
			x:                 visible.x
			y:                 visible.y
			w:                 visible.width
			h:                 visible.height
		}
	}

	fn draw_cached_image(ctx &DrawContext, path string, x f64, y f64, width f64, height f64) bool {
		if !cache_image(path) { return false }
		image_id := g_image_ids[path] or { return false }
		mut image_ctx := g_gg_app.ctx
		cached_image := image_ctx.get_cached_image_by_idx(image_id)
		if !cached_image.ok {
			return false
		}
		ctx.draw_image_with_config(
			img:      cached_image
			img_rect: gg.Rect{
				x:      f32(x)
				y:      f32(y)
				width:  f32(width)
				height: f32(height)
			}
		)
		return true
	}

	struct ButtonImageLayout {
		visible bool
		image   Rect
		text    Rect
	}

	fn (layout ButtonImageLayout) has_title_area() bool {
		return layout.text.width > 0 && layout.text.height > 0
	}

	// button_image_layout mirrors the native desktop button arrangements: compact
	// buttons put a 13-point image beside their title, while tall ribbon buttons
	// put a larger image above it. Image-only title-bar buttons stay centered.
	fn button_image_layout(width f64, height f64, title string, image_path string) ButtonImageLayout {
		if image_path.trim_space().len == 0 {
			return ButtonImageLayout{
				text: rect(0, 0, width, height)
			}
		}
		if title.len == 0 {
			// Image-only ribbon controls still use the large-button treatment when
			// they are tall. Compact controls need only a two-point inset on each
			// side; the previous four-point inset made 17px toolbar symbols nearly
			// illegible on Windows.
			size := if height >= 42 {
				math.min(32.0, math.max(math.min(width - 8.0, height - 12.0), 1.0))
			} else {
				math.min(18.0, math.max(math.min(width, height) - 4.0, 1.0))
			}
			return ButtonImageLayout{
				visible: true
				image: rect((width - size) / 2, (height - size) / 2, size, size)
				text: rect(0, 0, 0, 0)
			}
		}
		if height >= 42 {
			size := math.min(32.0, math.max(math.min(width, height - 22.0) - 8.0, 1.0))
			return ButtonImageLayout{
				visible: true
				image: rect((width - size) / 2, 4, size, size)
				text: rect(2, height - 23, math.max(width - 4.0, 0.0), 20)
			}
		}
		size := math.min(13.0, math.max(height - 8.0, 1.0))
		return ButtonImageLayout{
			visible: true
			image: rect(5, (height - size) / 2, size, size)
			text: rect(size + 9, 0, math.max(width - size - 13.0, 0.0), height)
		}
	}

	fn draw_button_image(ctx &DrawContext, image_path string, x f64, y f64, width f64, height f64, style TextStyle) {
		if image_path.starts_with('symbol:') {
			symbol := system_symbol_fallback(image_path['symbol:'.len..])
			draw_text_centered(ctx, symbol, x, y, width, height, TextStyle{
				...style
				font_family: 'Material Icons'
				size:        math.max(math.min(width, height) * 0.75, 8.0)
			})
			return
		}
		if !draw_cached_image(ctx, image_path, x, y, width, height) {
			draw_outline(ctx, x, y, width, height, 0x94a3b8, 2)
		}
	}

	// SF Symbols are used as native AppKit button images. Other custom-rendered
	// desktops use equivalent glyphs from the bundled Material Icons face, which
	// keeps the controls recognizable without depending on a host symbol font.
	fn system_symbol_fallback(name string) string {
		return match name {
			'align.horizontal.center' { '\ue00f' }
			'line.3.horizontal' { '\ue5d2' }
			'text.justify' { '\ue235' }
			'align.vertical.center' { '\ue011' }
			'arrow.up.and.down', 'arrow.up.arrow.down' { '\ue8d5' }
			'arrow.up.and.down.text.horizontal' { '\ue25b' }
			'arrow.2.squarepath', 'arrow.triangle.2.circlepath' { '\ue627' }
			'arrow.left.and.right' { '\ue8d4' }
			'arrow.left.and.right.square' { '\ue933' }
			'arrow.clockwise', 'arrow.clockwise.circle' { '\ue5d5' }
			'clock.arrow.circlepath' { '\ue889' }
			'arrow.down.right.and.arrow.up.left', 'arrow.up.and.down.and.arrow.left.and.right',
			'move.3d' { '\uf1ce' }
			'arrow.down.to.line' { '\ue258' }
			'icloud.and.arrow.down' { '\ue2c0' }
			'arrow.right.to.line', 'increase.indent' { '\ue23e' }
			'arrow.uturn.backward' { '\ue166' }
			'arrow.uturn.forward' { '\ue15a' }
			'icloud.and.arrow.up' { '\ue2c3' }
			'square.and.arrow.up' { '\ue2c6' }
			'square.and.arrow.down' { '\ue161' }
			'asterisk' { '\ue83a' }
			'character.book.closed' { '\uea19' }
			'textformat', 'textformat.abc' { '\ue262' }
			'chart.bar', 'chart.bar.doc.horizontal', 'chart.bar.xaxis' { '\ue26b' }
			'crop' { '\ue3be' }
			'cube.transparent' { '\ue9fe' }
			'square.on.circle' { '\ue574' }
			'curlybraces' { '\ue86f' }
			'cursorarrow' { '\ue323' }
			'doc.badge.arrow.up' { '\ue9fc' }
			'doc.badge.plus', 'text.badge.plus' { '\ue89c' }
			'plus.rectangle' { '\ue146' }
			'plus.rectangle.on.rectangle', 'plus.square.on.square' { '\ue02e' }
			'doc.on.doc' { '\ue14d' }
			'list.bullet.clipboard' { '\ue85d' }
			'ellipsis' { '\ue5d3' }
			'eye' { '\ue8f4' }
			'eye.slash' { '\ue8f5' }
			'folder' { '\ue2c7' }
			'function' { '\ue24a' }
			'gearshape' { '\ue8b8' }
			'grid', 'rectangle.grid.2x2', 'rectangle.split.3x3', 'tablecells' { '\ue3ec' }
			'info.circle' { '\ue88e' }
			'line.vertical' { '\ue5d4' }
			'list.number' { '\ue242' }
			'number' { '\ue9ef' }
			'lock', 'lock.doc' { '\ue897' }
			'magnifyingglass', 'rectangle.and.text.magnifyingglass' { '\ue8b6' }
			'minus' { '\ue15b' }
			'minus.rectangle' { '\ue909' }
			'number.circle' { '\ue400' }
			'paintbrush' { '\ue3ae' }
			'paintpalette' { '\ue40a' }
			'pencil', 'pencil.line' { '\ue3c9' }
			'person.2' { '\ue7ef' }
			'person.crop.circle' { '\ue853' }
			'person.crop.circle.badge.plus' { '\ue7fe' }
			'photo' { '\ue410' }
			'textbox' { '\ue262' }
			'plus' { '\ue145' }
			'printer' { '\ue8ad' }
			'rectangle.3.group' { '\ue8f0' }
			'rectangle.split.1x2' { '\uf114' }
			'rectangle.split.2x1' { '\ue8f2' }
			'rectangle.split.3x1' { '\ue8ec' }
			'rectangle.bottomthird.inset.filled', 'rectangle.portrait.and.arrow.right',
			'rectangle.righthalf.inset.filled.arrow.right',
			'rectangle.topthird.inset.filled', 'sidebar.right' { '\uf114' }
			'scissors' { '\ue14e' }
			'seal' { '\uef76' }
			'slider.horizontal.3' { '\ue429' }
			'square.2.layers.3d.bottom.filled', 'square.2.layers.3d.top.filled',
			'square.stack.3d.up' { '\ue53b' }
			'star' { '\ue838' }
			'star.circle' { '\ue8d0' }
			'tag' { '\ue892' }
			'text.alignleft' { '\ue236' }
			'text.alignright' { '\ue237' }
			'text.bubble' { '\ue0cb' }
			'textformat.123' { '\ueb8d' }
			'textformat.size' { '\ue245' }
			'textformat.size.larger' { '\ueae2' }
			'trash' { '\ue872' }
			'xmark' { '\ue5cd' }
			else { '\ue8fd' }
		}
	}

	fn preload_images(el Element) {
		if el.hidden {
			return
		}
		if el.kind == .image
			|| (el.kind == .button && el.image_path.trim_space().len > 0
			&& !el.image_path.starts_with('symbol:')) {
			cache_image(el.image_path)
		}
		for child in el.children {
			preload_images(child)
		}
	}

	fn cache_image(path string) bool {
		if path.trim_space() == '' {
			return false
		}
		g_active_images[path] = true
		if path in g_image_ids {
			return true
		}
		mut image_ctx := g_gg_app.ctx
		// `create_image` keeps an uninitialized copy in gg's post-startup image
		// cache on the Linux renderer. Loading from bytes uses the initialized
		// cache path, so raster images added after startup are drawable too.
		image_bytes := os.read_bytes(path) or {
			eprintln('ui2: could not read image `${path}`: ${err}')
			return false
		}
		loaded_image := image_ctx.create_image_from_byte_array(image_bytes, gg.ImageConfig{}) or {
			eprintln('ui2: could not load image `${path}`: ${err}')
			return false
		}
		g_image_ids[path] = loaded_image.id
		return true
	}

	// ── Drawing helpers ────────────────────────────────────────────────

	fn hex_color(hex u32) gg.Color {
		return gg.Color{
			r: u8((hex >> 16) & 0xFF)
			g: u8((hex >> 8) & 0xFF)
			b: u8(hex & 0xFF)
			a: 255
		}
	}

	fn draw_rect(ctx &DrawContext, x f64, y f64, w f64, h f64, color_hex u32, radius f64) {
		c := hex_color(color_hex)
		if radius > 0 {
			ctx.draw_rounded_rect_filled(f32(x), f32(y), f32(w), f32(h), f32(radius), c)
		} else {
			ctx.draw_rect_filled(f32(x), f32(y), f32(w), f32(h), c)
		}
	}

	fn draw_outline(ctx &DrawContext, x f64, y f64, w f64, h f64, color_hex u32, radius f64) {
		if w <= 0 || h <= 0 {
			return
		}
		c := hex_color(color_hex)
		if radius > 0 {
			ctx.draw_rounded_rect_empty(f32(x), f32(y), f32(w), f32(h), f32(radius), c)
		} else {
			ctx.draw_rect_empty(f32(x), f32(y), f32(w), f32(h), c)
		}
	}

	fn draw_box_borders(ctx &DrawContext, x f64, y f64, w f64, h f64, box BoxStyle) {
		frame := ctx.content_transform.rounded_local_rect(rect(x, y, w, h), f64(ctx.scale))
		for triangle in box_border_triangles(frame, box) {
			ctx.draw_triangle_filled(f32(triangle.a.x), f32(triangle.a.y),
				f32(triangle.b.x), f32(triangle.b.y), f32(triangle.c.x), f32(triangle.c.y),
				hex_color(triangle.color))
		}
	}

	fn draw_control_surface(ctx &DrawContext, x f64, y f64, w f64, h f64, box BoxStyle, focused bool, enabled bool) {
		draw_rect(ctx, x, y, w, h, box.bg, box.radius)
		border := if focused {
			u32(0x3478d4)
		} else if enabled {
			u32(0xd7dee8)
		} else {
			u32(0xe2e8f0)
		}
		draw_outline(ctx, x, y, w, h, border, box.radius)
		if focused && w > 2 && h > 2 {
			inner_radius := if box.radius > 1 { box.radius - 1 } else { 0.0 }
			draw_outline(ctx, x + 1, y + 1, w - 2, h - 2, border, inner_radius)
		}
		draw_box_borders(ctx, x, y, w, h, box)
	}

	// unstyled_box_bg is BoxStyle's default background: the button was left
	// the colour it was given rather than painted by the application.
	const unstyled_box_bg = u32(0xffffff)
	const button_bezel_radius = f64(6)

	// A button that asked for the platform's styling gets its bezel from
	// AppKit or Win32 on the native backends. The immediate renderer is the
	// platform in its own window, so it draws one itself; without it a
	// `native` button that was never painted is a bare caption, invisible on a
	// white card. A button the application did colour keeps that colour, since
	// the styling it asked the platform for stops where its own begins.
	fn draw_button_bezel(ctx &DrawContext, x f64, y f64, w f64, h f64, radius f64, enabled bool) {
		mut fill := u32(0xeef2f7)
		mut border := u32(0xb4bfcd)
		if !enabled {
			fill = 0xf6f8fa
			border = 0xdde4ec
		} else if touch_is_held_inside(x, y, w, h) {
			fill = 0xdbe3ec
			border = 0x94a3b8
		}
		bezel_radius := if radius > 0 { radius } else { button_bezel_radius }
		draw_rect(ctx, x, y, w, h, fill, bezel_radius)
		draw_outline(ctx, x, y, w, h, border, bezel_radius)
	}

	// touch_is_held_inside reports the pointer being down on this box, which
	// is what a pressed button looks like. The press has to have started there
	// too, so dragging across the window does not light up everything it
	// passes over.
	fn touch_is_held_inside(x f64, y f64, w f64, h f64) bool {
		if !g_touch.down {
			return false
		}
		sx, sy := current_content_transform().inverse(g_touch.start_x, g_touch.start_y)
		nx, ny := current_content_transform().inverse(g_touch.current_x, g_touch.current_y)
		inside_start := sx >= x && sx <= x + w && sy >= y
			&& sy <= y + h
		inside_now := nx >= x && nx <= x + w && ny >= y && ny <= y + h
		return inside_start && inside_now
	}

	fn draw_check_mark(ctx &DrawContext, x f64, y f64, size f64, color_hex u32) {
		pen := gg.PenConfig{
			color: hex_color(color_hex)
			thickness: 2
		}
		ctx.draw_line_with_config(f32(x + size * 0.22), f32(y + size * 0.50),
			f32(x + size * 0.42), f32(y + size * 0.70), pen)
		ctx.draw_line_with_config(f32(x + size * 0.40), f32(y + size * 0.69),
			f32(x + size * 0.79), f32(y + size * 0.29), pen)
	}

	fn draw_chevron_down(ctx &DrawContext, center_x f64, center_y f64, color_hex u32) {
		pen := gg.PenConfig{
			color: hex_color(color_hex)
			thickness: 1.5
		}
		ctx.draw_line_with_config(f32(center_x - 4), f32(center_y - 2), f32(center_x),
			f32(center_y + 2), pen)
		ctx.draw_line_with_config(f32(center_x), f32(center_y + 2), f32(center_x + 4),
			f32(center_y - 2), pen)
	}

	fn draw_scrollbar(ctx &DrawContext, x f64, y f64, width f64, height f64, content_height f64, offset f64, persistent bool) {
		bar := scrollbar_geometry(rect(x, y, width, height), content_height, offset, persistent)
		if bar.track.width <= 0 || bar.track.height <= 0 {
			return
		}
		draw_rect(ctx, bar.track.x, bar.track.y, bar.track.width, bar.track.height, 0xf1f5f9, 2.5)
		draw_rect(ctx, bar.thumb.x, bar.thumb.y, bar.thumb.width, bar.thumb.height, 0xcbd5e1, 2.5)
	}

	// draw_text draws text that belongs to a box, shortening it when it does
	// not fit, and reports whether it had to. A control draws its text down the
	// middle of the box whatever the style says, because a label is the only
	// thing the native backends let place its text, and a style shared with one
	// must not move a button.
	fn draw_text(ctx &DrawContext, t string, x f64, y f64, w f64, h f64, style TextStyle) bool {
		return draw_text_in_box(ctx, t, x, y, w, h, centered_text_style(style), true, Rect{})
	}

	// draw_label_text draws a label, the one control whose style says where its
	// text sits in a box with room to spare. It is drawn against the clip it was
	// rendered under, so a block of lines too tall for the label stops at the
	// label rather than running on over what comes after it.
	fn draw_label_text(ctx &DrawContext, t string, x f64, y f64, w f64, h f64, style TextStyle, clip Rect) bool {
		return draw_text_in_box(ctx, t, x, y, w, h, style, true, clip)
	}

	fn draw_rich_label_text(ctx &DrawContext, el Element, x f64, y f64, clip Rect) bool {
		$if !android {
			if el.text_runs.len > 0 {
				shaped := ctx.shape_runs(el.text_runs, el.text_style, math.max(0.0, el.frame.width), math.max(1, el.text_style.lines), true) or {
					eprintln('ui2: rich label: ${err}')
					return false
				}
				inside := if clip.width > 0 && clip.height > 0 {
					intersect_rect(rect(x, y, el.frame.width, el.frame.height), clip)
				} else {
					rect(x, y, el.frame.width, el.frame.height)
				}
				if inside.width <= 0 || inside.height <= 0 { return false }
				// Culling whole runs is insufficient for partial glyphs and baseline
				// rises: install the label's physical scissor as well.
				apply_clip(ctx, inside)
				ctx.draw_shaped_clipped(shaped, x, text_block_top(y, el.frame.height, shaped.size.height, el.text_style.valign), inside)
				apply_clip(ctx, clip)
				return shaped.truncated || shaped.size.height > el.frame.height
			}
		}
		return draw_label_text(ctx, el.text, x, y, el.frame.width, el.frame.height, el.text_style, clip)
	}

	// A style that draws down the middle of its box. The caret and the selection
	// of an editable field are measured from the middle, so its text has to be
	// drawn there too.
	fn centered_text_style(style TextStyle) TextStyle {
		return TextStyle{
			...style
			valign: .middle
		}
	}

	$if !android {
		// Keep the editor's rune offsets while obtaining all painted geometry from
		// the same full shaped line, including ligatures and mixed direction runs.
		fn draw_shaped_text_field(ctx &DrawContext, el Element, editor TextEditor, display_text string,
			x f64, y f64, w f64, h f64, focused bool) {
			shown := if editor.text.len > 0 { display_text } else { el.placeholder }
			style := TextStyle{
				...el.text_style
				align: .left
				color: if editor.text.len > 0 { el.text_style.color } else { u32(0x999999) }
			}
			shaped := ctx.shape_text(shown, style, -1, 1, false) or {
				eprintln('ui2: text field `${el.id}`: ${err}')
				return
			}
			origin := text_field_aligned_text_origin(x, w, shaped.size.width, el.text_style.align)
			top := text_block_top(y, h, shaped.size.height, .middle)
			if focused && editor.text.len > 0 && !editor.selection.collapsed() {
				start, end := editor.selection.ordered()
				for selected in shaped.selection(start, end) {
					draw_rect(ctx, origin + selected.x, top + selected.y, selected.width,
						selected.height, 0xb8d7ff, 0)
				}
			}
			ctx.draw_shaped(shaped, origin, top)
			if !focused { return }
			// A placeholder is painted text, but the editor caret still addresses
			// its empty value and follows that value's horizontal alignment.
			mut caret_shape := shaped
			mut caret_origin := origin
			mut caret_top := top
			if editor.text.len == 0 {
				caret_shape = ctx.shape_text('', style, -1, 1, false) or {
					eprintln('ui2: text field caret `${el.id}`: ${err}')
					return
				}
				caret_origin = text_field_aligned_text_origin(x, w, caret_shape.size.width, el.text_style.align)
				caret_top = text_block_top(y, h, caret_shape.size.height, .middle)
			}
			cursor := caret_shape.cursor(editor.selection.caret)
			cursor_h := if cursor.height > 0 { cursor.height } else { font_line_height(el.text_style.size) }
			caret := rect(caret_origin + cursor.x, caret_top + cursor.y, 2, cursor_h)
			draw_rect(ctx, caret.x, caret.y, caret.width, caret.height, el.text_style.color, 0)
			g_gg_app.text_caret = current_presentation_rect(caret)
			$if macos && ui2_embedder ? {
				composition := g_gg_app.composition
				if composition.field_id == el.id {
					start := composition.start + composition.mark_start
					for marked in shaped.selection(start, start + composition.mark_length) {
						draw_rect(ctx, origin + marked.x, top + marked.y + marked.height - 1,
							marked.width, 1, el.text_style.color, 0)
					}
				}
			}
		}
	}

	fn text_field_aligned_text_origin(x f64, w f64, text_width f64, align Align) f64 {
		return match align {
			.left { x }
			.center { x + (w - text_width) / 2 }
			.right { x + w - text_width }
		}
	}

	// clip is the region the caller is drawn under, and is what a block of text too
	// tall for its box is held inside. An empty one is a caller that does not bound
	// its text, which draws under whatever clip is already in force.
	//
	// The result reports text the reader cannot see: a line cut short with the
	// ellipsis, or a line of a bounded block that falls mostly below its box and is
	// clipped away. A caller offers the full text on hover when there is any.
	fn draw_text_in_box(ctx &DrawContext, t string, x f64, y f64, w f64, h f64, style TextStyle, fit bool, clip Rect) bool {
		if t.len == 0 {
			return false
		}
		$if android {
			text_x := match style.align {
				.left { int(x) }
				.center { int(x + w / 2) }
				.right { int(x + w) }
			}
			family := text_font_file(style.font_family, style.bold, style.italic)
			ensure_family_fallbacks(ctx, family)
			cfg := gg.TextCfg{
				color: hex_color(style.color)
				size: int(font_render_size(style.size, text_font_metrics(family)) + 0.5)
				bold: style.bold
				italic: style.italic
				family: family
				align: text_align(style.align)
				vertical_align: .middle
			}
			line_h := font_line_height(style.size)
			parts := if style.lines > 1 {
				wrap_text_lines(ctx, t, w, style.lines, cfg)
			} else {
				[t]
			}
			block_h := f64(parts.len) * line_h
			// A block with more lines than its box has room for is anchored at the top of
			// the box and would run on out of the bottom of it, over whatever is drawn
			// below. A native control draws only inside itself, so the lines that do not
			// fit are cut off at the box rather than drawn past it.
			bounded := block_h > h && clip.width > 0 && clip.height > 0
			if bounded {
				inside := intersect_rect(Rect{
					x:      x
					y:      y
					width:  w
					height: h
				}, clip)
				if inside.width <= 0 || inside.height <= 0 {
					return false
				}
				apply_clip(ctx, inside)
			}
			// The text block is as tall as the lines it ended up with, and valign says
			// where that block sits in a frame with room to spare. draw_text is given the
			// centre of each line because the config centres a line on its baseline box.
			start_y := text_block_top(y, h, block_h, style.valign) + line_h / 2
			mut shortened := false
			for i, part in parts {
				line_y := start_y + f64(i) * line_h
				line := if fit { fit_text(ctx, part, w, cfg) } else { part }
				if line != part || (bounded && line_y > y + h) {
					shortened = true
				}
				ctx.draw_text(int(text_x), int(line_y), line, cfg)
			}
			if bounded {
				apply_clip(ctx, clip)
			}
			return shortened
		} $else {
			// A shaped block supplies both its geometry and the glyphs painted here.
			// Editors pass an unbounded width so their value is clipped, not ellipsized.
			width := if fit || style.lines > 1 { math.max(0.0, w) } else { -1.0 }
			shaped := ctx.shape_text(t, style, width, if style.lines > 1 { style.lines } else { 1 }, fit) or {
				eprintln('ui2: text: ${err}')
				return false
			}
			block_h := shaped.size.height
			bounded := block_h > h && clip.width > 0 && clip.height > 0
			if bounded {
				inside := intersect_rect(rect(x, y, w, h), clip)
				if inside.width <= 0 || inside.height <= 0 { return false }
				apply_clip(ctx, inside)
			}
			top := text_block_top(y, h, block_h, style.valign)
			ctx.draw_shaped(shaped, x, top)
			if bounded { apply_clip(ctx, clip) }
			return shaped.truncated || (bounded && block_h > h)
		}
	}

	fn draw_text_centered(ctx &DrawContext, t string, x f64, y f64, w f64, h f64, style TextStyle) bool {
		centered_style := TextStyle{
			...style
			align: .center
		}
		return draw_text(ctx, t, x, y, w, h, centered_style)
	}
}
