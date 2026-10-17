// vfmt off
// Keep the imports inside the platform block. Hoisting gg imports makes the
// AppKit backend compile Sokol's ARC sources together with Objective-C MRC.
@[has_globals]
module ui2

$if (android || linux || ((macos || windows) && ui2_custom_rendering ?)) && !ui2_headless ? && !ui2_document_library ? {
	import gg
	import math
	import sokol.sapp
	import sokol.gfx
	import time
	import arena

	struct HitTarget {
		is_image bool
		image_geometry ImageGeometry
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
		drag_source ?&DragSource
		drop_target ?DropTarget
		drag_generation u64
		drag_mount_generation u64
		pointer_publication u64
		pointer_owner_identity string
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
		drag DragSession
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
		// Which scroller a scrollbar drag holds: the one along the bottom when set.
		scrollbar_horizontal bool
		scrollbar_grab_x     f64
	}

	struct BuildArena {
	mut:
		allocator arena.Arena
	}

	@[heap]
	struct GgApp {
	mut:
		ctx &DrawContext = unsafe { nil }
		scheduler &FrameCoordinator = new_frame_coordinator()
		layout_tree &LayoutTree = &LayoutTree{}
		motion_tree &MotionTree = &MotionTree{}
		overlay_tree &OverlayTree = &OverlayTree{}
		overlay_focus OverlayFocusState
		overlay_offsets map[string]f64
		overlay_offsets_x map[string]f64
		overlay_unavailable map[string]OverlayTriggerOwner
		overlay_triggers map[string]OverlayTrigger
		overlay_trigger_revision u64
		layout_environment LayoutEnvironment
		layout_patches []LayoutPatch
		// Every queued patch gets a serial. A compiled declaration contains the
		// retained state of all compiled patches up to declared_patch_serial.
		layout_patch_serial u64
		declared_patch_serial u64
		compiled_snapshot bool
		compiled_snapshot_serial u64
		suppressed_compiled_patches bool
		declared_root Element
		declaration_pending bool
		building_declaration bool
		declaration_generation u64
		releasing_drag bool
		has_root bool
		iconified bool
		suspended bool
		dpi_scale f32
		draining_tasks bool
		window_state &CustomWindowState = unsafe { nil }
		native_window voidptr
		last_frame i64 = -1
		linux_signal &HostWakeSignal = unsafe { nil }
		frame_interval i64
		surface_retry_at i64 = -1
		callback_depth int
		cleanup_pending bool
		composition TextComposition
		text_caret Rect
		editable_fields map[string]bool
		presentation_revision u64
		visual_geometries map[string]VisualGeometry
		visual_geometry_buffer map[string]VisualGeometry
		visual_geometry_generation u64
		visual_geometry_count int
		visual_geometry_serial u64
		pointer_geometry_serial u64
		mounted_hit_count int
		pointer_popup_owner string
		pointer_popup_scroll f64
		pointer_popup_selected string
		controls_root Element
		controls_initialized bool
		controls_prune_pending bool
		focus_offsets map[string]f64
		focus_offsets_x map[string]f64
		build_arena &BuildArena = unsafe { nil }
	}

	// DropdownPopup caches the geometry of the open dropdown list. The list is
	// drawn after the element tree so it floats above every other control, and
	// it is refreshed when its owner, selection or presentation geometry changes.
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
		is_image bool
		image_geometry ImageGeometry
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
	__global g_backend_text_focus = BackendTextFocus{}
	// Like :focus-visible: a pointer press focuses quietly; keyboard input shows
	// the focus ring again. Text editors always show their focus.
	__global g_focus_visible = true
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
		g_gg_app.layout_patch_serial++
		g_gg_app.layout_patches << LayoutPatch{ id: id, element: element, serial: g_gg_app.layout_patch_serial }
		g_gg_app.scheduler.invalidate(.layout)
	}

	// refresh_compiled_element queues a compiled document's patch, addressed by
	// its authored id when it has one, otherwise by its retained node.
	fn refresh_compiled_element(id string, node &CompiledVmlNode, element Element) {
		if g_gg_app.scheduler.is_closed() { return }
		// The declaration being produced already contains this node's state.
		if g_gg_app.compiled_snapshot {
			g_gg_app.suppressed_compiled_patches = true
			return
		}
		g_gg_app.layout_patch_serial++
		g_gg_app.layout_patches << LayoutPatch{ id: id, compiled: if id.len > 0 { unsafe { nil } } else { node }, element: element, serial: g_gg_app.layout_patch_serial, document: true }
		g_gg_app.scheduler.invalidate(.layout)
	}

	// begin_compiled_snapshot marks a compiled document producing its complete
	// declaration. Patches published meanwhile are part of that declaration.
	fn begin_compiled_snapshot() {
		g_gg_app.compiled_snapshot = true
	}

	fn end_compiled_snapshot() {
		g_gg_app.compiled_snapshot = false
		g_gg_app.compiled_snapshot_serial = g_gg_app.layout_patch_serial
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
		set_custom_focus(id,true)
	}

	// set_backend_text_focus records the focus an input backend in another
	// process owns, so this renderer paints it; an empty id clears it.
	pub fn set_backend_text_focus(focus BackendTextFocus) {
		g_backend_text_focus = focus
		invalidate_custom_paint()
	}

	pub fn backend_text_focus() BackendTextFocus {
		return g_backend_text_focus
	}

	fn custom_focus_ring_visible(el Element) bool {
		return el.id.len > 0 && el.id == g_focused_field
			&& (g_focus_visible || el.kind in [.text_field, .text_area])
	}

	fn set_custom_focus(id string, reveal bool) {
		dispatch := custom_input_dispatch(g_gg_app)
		if !dispatch.valid() { return }
		sync_focus_navigation()
		if !g_focus_navigation.set_focus(id) { return }
		if g_focused_field != id { g_gg_app.composition = TextComposition{} }
		g_focused_field = id
		if g_open_dropdown.len > 0 && g_open_dropdown != id { close_dropdown() }
		if reveal { reveal_custom_focus(id) }
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
		dispatch := custom_input_dispatch(g_gg_app)
		cancel_touch()
		if !dispatch.valid() { return }
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
	// asked and register_scroll_view_in_parent clamps it to the real range on the next frame.
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

	// scroll_horizontal_offset returns how far a Scroll element is scrolled sideways.
	// It stays zero for one whose scroll_mode leaves the horizontal axis out.
	pub fn scroll_horizontal_offset(id string) f64 {
		return scroll_state_offset_x(named_scroll_state_id(id))
	}

	// A request for an unmounted pane waits for its first layout, like the
	// vertical API. Refresh the tree before scrolling to newly added content.
	pub fn scroll_to_horizontal_offset(id string, offset f64) {
		if id.len == 0 { return }
		state_id := named_scroll_state_id(id)
		wanted := if offset < 0 { 0.0 } else { offset }
		if state_id in g_scroll_viewports {
			set_scroll_offset_x(state_id, wanted, scroll_maximum_x(state_id))
			return
		}
		g_pending_scroll_x[state_id] = wanted
		invalidate_custom_paint()
	}

	pub fn scroll_to_rect(id string, x f64, y f64, width f64, height f64) {
		state_id := named_scroll_state_id(id)
		area := g_scroll_viewports[state_id] or { return }
		dispatch := custom_input_dispatch(g_gg_app)
		ctx := dispatch.app.ctx
		root := g_focus_navigation.root_revision
		current := scroll_state_offset(state_id)
		mut next := current
		if y < current { next = y }
		else if y + height > current + area.height { next = y + height - area.height }
		set_scroll_offset(state_id, next, scroll_maximum(state_id))
		if !custom_scroll_dispatch_current(dispatch, ctx, root) { return }
		current_x := scroll_state_offset_x(state_id)
		mut next_x := current_x
		if x < current_x { next_x = x }
		else if x + width > current_x + area.width { next_x = x + width - area.width }
		set_scroll_offset_x(state_id, next_x, scroll_maximum_x(state_id))
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

	fn configure_custom_presentation(app &GgApp, backend gfx.Backend) {
		// Sokol's GL/EGL/D3D loops swap even when frame_fn returns early. Their
		// discarded backbuffers need a full paint; only the Metal path can skip
		// submission safely until UI2 owns presentation in the platform embedder.
		app.scheduler.set_presentation_required(backend != .metal_macos)
	}

	fn on_init(app &GgApp) {
		$if linux {
			mut state := unsafe { app }
			setup_linux_idle(mut state)
		}
		mut ctx := app.ctx
		ctx.sync_gg()
		configure_custom_presentation(app, gfx.query_backend())
	}

	fn on_cleanup(app &GgApp) {
		cancel_drag_session(.cancelled)
		dispose_compiled_vml()
		app.scheduler.close()
		g_drag_registry = DragRegistry{}
		mut state := unsafe { app }
		$if linux {
			if state.linux_signal != unsafe { nil } { state.linux_signal.close() }
		}
		if state.ctx != unsafe { nil } {
			mut ctx := state.ctx
			ctx.destroy()
		}
		state.ctx = unsafe { nil }
		clear_text_area_layouts()
		state.declared_root = Element{}
		state.controls_root = Element{}
		state.controls_initialized = false
		state.controls_prune_pending = false
		state.focus_offsets.clear()
		state.focus_offsets_x.clear()
		// A canceled callback can close this owner after its geometry rollback.
		// Keep its last published snapshot until the owner itself is released.
		state.visual_geometry_buffer.clear()
		state.visual_geometry_generation = 0
		state.visual_geometry_count = 0
		state.pointer_geometry_serial = 0
		state.visual_geometry_serial = 0
		state.mounted_hit_count = 0
		state.pointer_popup_owner = ''
		state.pointer_popup_scroll = 0
		state.pointer_popup_selected = ''
		state.declaration_pending = false
		state.layout_tree.clear()
		if state.build_arena != unsafe { nil } {
			state.build_arena.allocator.free()
			state.build_arena = unsafe { nil }
		}
		state.layout_patches.clear()
		state.has_root = false
		state.overlay_tree = &OverlayTree{}
		state.overlay_focus = OverlayFocusState{}
		state.overlay_offsets.clear()
		state.overlay_offsets_x.clear()
		state.overlay_unavailable.clear()
		state.overlay_triggers.clear()
		state.editable_fields.clear()
		state.motion_tree.dispose()
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
		g_hover = HoverState{}
	}

	// The next visual deadline is replaced after every frame. A canceled hover,
	// unmounted target or released pointer therefore cannot leave a live timer.
	fn custom_visual_deadline() i64 {
		mut deadline := i64(-1)
		if g_tooltip.pointer_in && g_tooltip.key.len > 0 && !g_tooltip.dismissed
			&& !g_tooltip.visible && !g_touch.down && !menu_bar_open() && g_open_dropdown.len == 0 {
			deadline = g_tooltip.rest_since + tooltip_delay_ms
		}
		overlay_at := overlay_deadline()
		if overlay_at >= 0 && (deadline < 0 || overlay_at < deadline) { deadline = overlay_at }
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
		return resolve_custom_layout_snapshot(mut app,work,measure,patches,false)!
	}
	fn resolve_custom_layout_snapshot(mut app GgApp, work FrameWork, measure LayoutTextMeasureFn, patches []LayoutPatch, input bool) !Element {
		dispatch := custom_input_dispatch(&app)
		ctx := app.ctx
		mut animated := if input { app.declared_root } else { apply_custom_widget_animations(app.declared_root) }
		if !dispatch.valid() || voidptr(app.ctx) != voidptr(ctx) || (ctx != unsafe { nil } && !custom_layout_owner_current(dispatch,ctx,input)) {
			return error('layout frame canceled')
		}
		if work.build || app.declaration_pending || app.layout_tree.root.len == 0 {
			animated = app.motion_tree.prepare(animated)!
			app.declared_root = animated
			app.layout_tree.replace(animated)!
			app.declaration_pending = false
		}
		for patch in patches {
			// A compiled declaration already contains this or a newer state.
			if patch.document && patch.serial <= app.declared_patch_serial { continue }
			element := if input { patch.element } else { apply_custom_widget_animations(patch.element) }
			if !dispatch.valid() || voidptr(app.ctx) != voidptr(ctx) || (ctx != unsafe { nil } && !custom_layout_owner_current(dispatch,ctx,input)) {
				return error('layout frame canceled')
			}
			if patch.compiled != unsafe { nil } {
				app.layout_tree.patch_compiled(patch.compiled, element) or { eprintln('ui2 layout: ${err}'); continue }
			} else {
				app.layout_tree.patch(patch.id, element) or { eprintln('ui2 layout: ${err}'); continue }
			}
			app.declared_root = app.layout_tree.declaration()
		}
		if patches.len > 0 {
			prepared := app.motion_tree.prepare(app.declared_root)!
			if prepared != app.declared_root {
				app.declared_root = prepared
				app.layout_tree.replace(prepared)!
			}
		}
		if !input && app.motion_tree.sample(app.declared_root)! {
			if app.motion_tree.geometry_changed { g_focus_navigation.motion_serial++ }
			app.presentation_revision++
		}
		// A target setter can finish an exit before the host samples it. Pending
		// retirement still has to run when that next sample is unchanged.
		if !input && app.motion_tree.prune_pending {
			pruned := app.motion_tree.prune(app.declared_root)
			app.motion_tree.prune_pending = false
			if pruned != app.declared_root {
				app.declared_root = pruned
				app.presentation_revision++
				app.layout_tree.replace(pruned)!
			}
		}
		if !dispatch.valid() || (ctx != unsafe { nil } && !custom_layout_owner_current(dispatch, ctx, input)) { return error('motion frame canceled') }
		resolved := app.layout_tree.resolve(LayoutConstraints{}, measure, app.layout_environment)!
		app.motion_tree.previous = resolved
		return resolve_custom_overlays(mut app, resolved, measure)!
	}

	fn custom_layout_owner_current(dispatch CustomInputDispatch, ctx &DrawContext, input bool) bool {
		return if input { dispatch.valid() && voidptr(dispatch.app.ctx)==voidptr(ctx) && !ctx.destroyed && !ctx.destroying
			&& !dispatch.app.iconified && !dispatch.app.suspended } else { custom_frame_current(dispatch,ctx) }
	}

	// Only pure declaration validation uses this arena. Builders, reactive
	// callbacks, retained nodes and text caches keep their normal GC ownership.
	// Copy a diagnostic after popping, before releasing any temporary storage.
	fn validate_custom_build(mut app GgApp, root Element) ! {
		if app.build_arena == unsafe { nil } {
			app.build_arena = &BuildArena{ allocator: arena.new() }
		}
		mut scratch := &app.build_arena.allocator
		scratch.push()
		mut message := ''
		mut code := 0
		validate_element_tree(root) or { message = err.msg(); code = err.code() }
		scratch.pop()
		if message.len > 0 {
			owned := message.clone()
			scratch.reset()
			return error_with_code(owned, code)
		}
		scratch.reset()
	}

	fn build_custom_declaration(mut app GgApp, input bool) bool {
		dispatch := custom_input_dispatch(&app)
		ctx := app.ctx
		if !dispatch.valid() || app.iconified || app.suspended || app.building_declaration { return false }
		if voidptr(g_build_screen)==unsafe { nil } { return true }
		app.building_declaration=true
		defer { app.building_declaration=false }
		generation := app.scheduler.stats().generation
		app.scheduler.record_build()
		app.compiled_snapshot_serial = 0
		app.suppressed_compiled_patches = false
		declared := g_build_screen()
		mut adopted := false
		// A discarded declaration must not lose patches its snapshot absorbed.
		defer {
			if app.suppressed_compiled_patches && !adopted { app.scheduler.invalidate(.build) }
		}
		// Input needs the same token. A canceled paint keeps a completed builder's
		// declaration under the owner/context guard so retained recovery never
		// replays business callbacks merely because window input changed.
		current := if input {
			dispatch.valid() && voidptr(app.ctx)==voidptr(ctx) && app.scheduler.stats().generation==generation && !app.iconified && !app.suspended
		} else { custom_frame_owner_current(dispatch,ctx) && !dispatch.scheduler.build_pending() }
		if !current { return false }
		validate_custom_build(mut app, declared) or { eprintln('ui2: ${err}'); return false }
		app.declared_root=declared
		app.declared_patch_serial=math.max(app.declared_patch_serial, app.compiled_snapshot_serial)
		app.declaration_pending=true
		app.declaration_generation=generation
		app.has_root=true
		adopted=true
		return true
	}

	// Update input from the same resolved LayoutTree and mounted affine producer
	// before release or pointer dispatch, without a surface, tasks or animation.
	fn sync_custom_input_geometry(dispatch CustomInputDispatch) bool {
		if !dispatch.valid() || (dispatch.app.ctx!=unsafe { nil } && (dispatch.app.ctx.destroyed || dispatch.app.ctx.destroying)) { return false }
		mut app := dispatch.app
		ctx := app.ctx
		stats := app.scheduler.stats()
		if stats.suspended || app.suspended || app.iconified || app.building_declaration { return false }
		if stats.in_flight { return dispatch.valid() }
		if stats.generation!=app.declaration_generation && stats.pending_reasons.any(it in [.build,.worker,.animation_follow_up]) {
			if !build_custom_declaration(mut app,true) { return false }
		}
		if !app.has_root { return dispatch.valid() }
		patches := take_custom_layout_patches(mut app)
		root := resolve_custom_layout_snapshot(mut app,FrameWork{},measure_layout_text,patches,true) or {
			eprintln('ui2 input layout: ${err}')
			if dispatch.owner_current() && !app.scheduler.is_closed() {
				mut pending := patches.clone(); pending << app.layout_patches
				app.layout_patches=pending
				app.scheduler.invalidate(.layout)
			}
			return false
		}
		if !dispatch.valid() || voidptr(app.ctx) != voidptr(ctx)
			|| (ctx != unsafe { nil } && !custom_layout_owner_current(dispatch, ctx, true)) { return false }
		// Input adopts the same declaration as paint. Publish its editor buffers,
		// edit permissions and live control state before focus can notify user code.
		reconcile_mounted_focus_controls(root)
		update_custom_focus_tree(root)
		if !dispatch.valid() || voidptr(app.ctx) != voidptr(ctx) || g_focus_navigation.root != root
			|| (ctx != unsafe { nil } && !custom_layout_owner_current(dispatch, ctx, true)) { return false }
		return dispatch.valid()
	}

	fn custom_frame_current(dispatch CustomInputDispatch, ctx &DrawContext) bool {
		mut scheduler := dispatch.scheduler
		return dispatch.valid() && voidptr(dispatch.app.ctx) == voidptr(ctx) && !ctx.destroyed && !ctx.destroying
			&& !dispatch.app.iconified && !dispatch.app.suspended
			&& !scheduler.build_pending()
	}

	// Only retained work may survive an input-generation change. Presentation
	// still uses custom_frame_current, and never crosses a replaced owner/context.
	fn custom_frame_owner_current(dispatch CustomInputDispatch, ctx &DrawContext) bool {
		return dispatch.owner_current() && voidptr(dispatch.app.ctx) == voidptr(ctx) && !ctx.destroyed && !ctx.destroying
	}

	fn on_frame(mut app GgApp) {
		app.scheduler.record_loop_callback()
		if app.scheduler.is_closed() || app.ctx == unsafe { nil } || app.draining_tasks { return }
		dispatch := custom_input_dispatch(&app)
		$if linux {
			wait_linux_idle(mut app)
			if !dispatch.valid() { return }
		}
		drain_custom_tasks(mut app)
		if !dispatch.valid() { return }
		// `after` callbacks run on the UI thread before the frame begins, so the
		// build this asks for already sees what they changed.
		if run_due_timers_now() && dispatch.valid() { app.scheduler.invalidate(.build) }
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
			if !patches_resolved && patches.len > 0 && voidptr(app.scheduler) == voidptr(scheduler) && !scheduler.is_closed() {
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
		if work.build && !build_custom_declaration(mut app,false) { return }
		if !custom_frame_current(dispatch, ctx) {
			return
		}
		root := resolve_custom_layout(mut app, work, measure_layout_text, patches) or { eprintln('ui2 layout: ${err}'); return }
		patches_resolved = true
		// Animation callbacks are user code and may close or suspend the window.
		if !custom_frame_current(dispatch, ctx) {
			return
		}
		// Restoring focus can notify user code. Its mounted control state must
		// already agree with the new root, including editors outside the viewport.
		reconcile_mounted_focus_controls(root)
		update_custom_focus_tree(root)
		if !custom_frame_current(dispatch, ctx) || g_focus_navigation.root != root { return }
		update_overlay_triggers(now)
		if !custom_frame_current(dispatch, ctx) || g_focus_navigation.root != root { return }
		mounted := g_focus_navigation.root_revision
		// Mounted targets survive paint-only frames. Drop only the previous paint
		// tail (popup/fallback targets), before adding this frame's overlays.
		g_hit_targets.trim(app.mounted_hit_count)
		g_tooltip_targets.clear()
		g_tooltip_owners = 0
		app.text_caret = Rect{}
		g_scroll_order.clear()
		// Paint-time clamping can also notify user code before another pane is
		// painted. Keep every mounted Scroll available to nested public calls.
		sync_mounted_scroll_views()
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
		sync_drag_session()
		if !custom_frame_current(dispatch,ctx) || g_focus_navigation.root_revision != mounted { return }
		ctx.images.begin_frame()
		preload_images(mut ctx)
		preload_drag_preview(mut ctx)
		previous_geometry := unsafe { app.visual_geometries }
		app.visual_geometry_count = 0
		geometry_changed := app.visual_geometry_serial != g_focus_navigation.presentation_serial
		if geometry_changed {
			// Reuse both published and draft maps. Clearing a map would clone every
			// string key again on insertion during an animated transform frame.
			app.visual_geometries = unsafe { app.visual_geometry_buffer }
			app.visual_geometry_generation++
		}
		defer {
			if !custom_frame_current(dispatch, ctx) || g_focus_navigation.root_revision != mounted {
				if geometry_changed {
					app.visual_geometry_buffer = unsafe { app.visual_geometries }
					app.visual_geometries = previous_geometry
				}
			} else if geometry_changed {
				// V snapshots a map iterated while deleting keys. Only structural
				// retirement needs that scan; all ids in a motion frame stay mounted.
				if app.visual_geometries.len > app.visual_geometry_count {
					for id, geometry in app.visual_geometries {
						if geometry.generation != app.visual_geometry_generation {
							app.visual_geometries.delete(id)
						}
					}
				}
				app.visual_geometry_buffer = previous_geometry
			}
		}
		ctx.content_transform = ContentTransform{}
		ctx.opacity = 1
		ctx.clip_base = ClipRegion{}
		ctx.clip_region = ClipRegion{}
		ctx.begin()
		defer {
			if custom_frame_current(dispatch, ctx) && g_focus_navigation.root_revision == mounted { ctx.end() } else { ctx.cancel() }
		}
		if app.has_root {
			top := menu_bar_height()
			begin_hover_frame()
			render_element(ctx, root, 0, top, rect(0, top, f64(ctx.width), f64(ctx.height) - top), '', presentation_root_path(root))
			if !custom_frame_current(dispatch, ctx) || g_focus_navigation.root_revision != mounted { return }
			if g_open_dropdown.len > 0 {
				if g_dropdown_popup.mounted {
					draw_dropdown_popup(ctx)
				} else {
					close_dropdown()
				}
			}
			sync_drag_session()
			if !custom_frame_current(dispatch,ctx) || g_focus_navigation.root_revision != mounted { return }
			draw_drag_preview(ctx)
			draw_menu_bar(ctx)
			update_tooltip(now)
			draw_tooltip(ctx)
			if app.controls_prune_pending {
				prune_unmounted_state()
				app.controls_prune_pending = false
			}
			if app.composition.field_id.len > 0 && app.composition.field_id != g_focused_field {
				app.composition = TextComposition{}
			}
		}
		check_long_press()
		if !custom_frame_current(dispatch, ctx) || g_focus_navigation.root_revision != mounted { return }
		$if android {
			// Android's legacy gg atlas uploads glyphs introduced by this frame.
			if ctx.font_inited { ctx.ft.flush() }
		}
		app.scheduler.record_draw()
		app.visual_geometry_serial = g_focus_navigation.presentation_serial
		app.last_frame = renderer_now_ms()
		app.scheduler.set_deadline(custom_visual_deadline())
		app.scheduler.set_animation_active(custom_animations_need_frame(app.declared_root))
		app.scheduler.set_motion_active(motion_tree_needs_frame(app.declared_root))
		// Content can move under a pointer that stays put.
		update_hover()
	}

	fn on_event(e &gg.Event, app &GgApp) {
		if app.scheduler.is_closed() {
			return
		}
		mut state := unsafe { app }
		// The modifier keys of the last event, for key_modifiers on platforms
		// with no other way to ask.
		g_key_modifiers = KeyModifiers{
			shift: e.modifiers & u32(gg.Modifier.shift) != 0
			ctrl: e.modifiers & u32(gg.Modifier.ctrl) != 0
			alt: e.modifiers & u32(gg.Modifier.alt) != 0
			cmd: e.modifiers & u32(gg.Modifier.super) != 0
		}
		// Local hover, focus and scroll repaint retained geometry. Business
		// callbacks request a build; keyboard/drop hooks may mutate the model.
		state.scheduler.invalidate(if e.typ in [.key_down, .key_up, .char, .files_dropped] { RenderReason.build } else { RenderReason.paint })
		match e.typ {
			.mouse_down {
				if e.mouse_button == .right { overlay_context_press(app, f64(e.mouse_x), f64(e.mouse_y)); return }
				custom_mouse_down(app, f64(e.mouse_x), f64(e.mouse_y))
			}
			.mouse_move {
				// Recorded before any handler below can claim the move, so the
				// tooltip always knows where the pointer is.
				g_tooltip.pointer_moved(f64(e.mouse_x), f64(e.mouse_y), renderer_now_ms())
				hover_pointer_moved(f64(e.mouse_x), f64(e.mouse_y))
				update_hover()
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
				mut delta_x := f64(e.scroll_x)
				mut delta_y := f64(e.scroll_y)
				// Shift turns a plain wheel sideways, for a mouse with nothing
				// that reports a horizontal delta of its own.
				if delta_x == 0 && e.modifiers & u32(gg.Modifier.shift) != 0 {
					delta_x = delta_y
					delta_y = 0
				}
				handle_mouse_scroll_vector(f64(e.mouse_x), f64(e.mouse_y), delta_x, delta_y)
			}
			.mouse_leave {
				g_tooltip.pointer_left()
				hover_pointer_left()
				update_hover()
			}
			.mouse_up {
				if e.mouse_button == .right { return }
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
				if e.typ == .touches_cancelled && (g_touch.drag.pending || g_touch.drag.active) {
					cancel_drag_session(.cancelled)
				} else { cancel_touch() }
			}
			.char {
				// Sokol can emit the shortcut letter as CHAR after Cmd/Ctrl+A.
				// Primary-modifier input is a command; AltGr/Option remain text.
				if !text_navigation_primary_modifier(e.modifiers & u32(gg.Modifier.ctrl) != 0,
					e.modifiers & u32(gg.Modifier.alt) != 0, e.modifiers & u32(gg.Modifier.super) != 0) {
					custom_character_input(app, e.char_code)
				}
			}
			.key_down {
				if !g_focus_visible {
					g_focus_visible = true
					invalidate_custom_paint()
				}
				if drag_owned_escape(e.key_code) { return }
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
		if !sync_custom_input_geometry(dispatch) || overlay_pointer_down(x, y) || !dispatch.valid() { return dispatch }
		if menu_bar_handle_down(x, y) || !dispatch.valid() { return dispatch }
		return handle_touch_down(x, y)
	}

	fn discard_custom_pointer_start(dispatch CustomInputDispatch) {
		if voidptr(dispatch.window) == voidptr(g_active_custom_window_state) {
			if g_touch.input_generation == dispatch.generation { g_touch = TouchState{} }
		} else {
			mut owner := dispatch.window
			if owner.touch.input_generation == dispatch.generation { owner.touch = TouchState{} }
		}
	}

	fn handle_touch_down(x f64, y f64) CustomInputDispatch {
		previous := custom_input_dispatch(g_gg_app)
		if g_touch.down { cancel_touch() }
		if !previous.valid() { return previous }
		dispatch := begin_custom_input_dispatch(g_gg_app)
		if !sync_custom_input_geometry(dispatch) { return dispatch }
		if overlay_pointer_down(x, y) || !dispatch.valid() { return dispatch }
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
		// Opening a partially clipped dropdown must not move its surface away
		// from this press. Keyboard/public focus still reveal it normally.
		if g_focus_navigation.can_focus(target.id) {
			g_focus_visible = false
			set_custom_focus(target.id,!target.dropdown)
		}
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
		begin_drag_candidate(target)
		if target.drag_source != none { return dispatch }
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
		if move_drag_session(x, y) { return }
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
			// Below the drag threshold the press is a click, toggled on release.
			if g_touch.moved { commit_switch(target, switch_pointer_right(target, x, y)) }
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

	fn clamped_scroll_offset(requested f64, maximum f64) f64 {
		max_scroll := if maximum > 0 { maximum } else { 0.0 }
		return if requested < 0 {
			0.0
		} else if requested > max_scroll {
			max_scroll
		} else {
			requested
		}
	}

	fn set_scroll_offset(id string, requested f64, maximum f64) {
		next := clamped_scroll_offset(requested, maximum)
		previous := g_scroll_offsets[id] or { 0.0 }
		g_scroll_offsets[id] = next
		if next != previous {
			invalidate_custom_paint()
			target := g_scroll_targets[id] or { HitTarget{} }
			fire_target_event(target, ElementEvent{ kind: .scroll, id: target.id, value: next, x: scroll_state_offset_x(id), y: next })
		}
	}

	fn set_scroll_offset_x(id string, requested f64, maximum f64) {
		next := clamped_scroll_offset(requested, maximum)
		previous := g_scroll_offsets_x[id] or { 0.0 }
		g_scroll_offsets_x[id] = next
		if next != previous {
			invalidate_custom_paint()
			target := g_scroll_targets[id] or { HitTarget{} }
			fire_target_event(target, ElementEvent{ kind: .scroll, id: target.id, value: scroll_state_offset(id),
				x: next, y: scroll_state_offset(id) })
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
		if release_drag_session(x, y) { return }
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
			if activate { fire_target_event(target, ElementEvent{ kind: .click, id: target.id }) }
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
		fire_target_event(target, ElementEvent{ kind: .click, id: target.id })
	}

	// Finish a captured gesture on focus loss/cancellation so an IDE drag cannot
	// remain stuck. Ordinary taps are cancelled without activating a control.
	fn cancel_touch() {
		if g_touch.drag.pending || g_touch.drag.active { cancel_drag_session(.focus_lost); return }
		captured := g_touch.pointer_target
		x := g_touch.current_x
		y := g_touch.current_y
		g_touch = TouchState{}
		if voidptr(captured.on_event) != unsafe { nil } && (captured.clickable || captured.draggable) {
			fire_pointer_event(.pointer_up, captured, x, y)
		}
	}

	fn check_long_press() {
		if !g_touch.down || g_touch.moved || g_touch.long_press_fired || g_touch.scrollbar_drag || g_touch.drag.pending || g_touch.drag.active {
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
			t := current_pointer_target(g_hit_targets[i]) or { continue }
			if hit_target_contains(t, x, y) {
				return t
			}
		}
		return HitTarget{}
	}

	fn hit_target_contains(target HitTarget, x f64, y f64) bool {
		broad := presentation_bounds_contains(rect(target.x,target.y,target.w,target.h),x,y)
		if !broad || (target.has_geometry && !transformed_contains(target.local_frame, target.content_transform, target.clip_region, x, y)) { return false }
		local_x, local_y := target.content_transform.inverse(x, y)
		if (target.is_vector_canvas || target.vector_shapes.len > 0) && !vector_shapes_contain(target.vector_shapes,
			local_x - target.vector_origin.x, local_y - target.vector_origin.y, target.vector_hit_mode) { return false }
		return !target.is_image || target.image_geometry.contains(local_x,local_y)
	}

	// A semantic press keeps the action chosen on pointer-down, but the surface
	// must still exist and be enabled when it is released. Hit targets are rebuilt
	// every frame, so use the current geometry rather than the captured rectangle.
	fn current_pointer_target(captured HitTarget) ?HitTarget {
		if captured.id.len > 0 {
			for i := g_hit_targets.len - 1; i >= 0; i-- {
				current := g_hit_targets[i]
				if current.id == captured.id && current.dropdown_option==captured.dropdown_option
					&& (!captured.dropdown_option || current.option_index==captured.option_index) {
					return eligible_pointer_target(captured, current)
				}
			}
			if captured.dropdown_option { return none }
			if node := g_focus_navigation.node(captured.id) {
				return eligible_pointer_target(captured, HitTarget{ ...captured, identity: node.path, kind: node.el.kind, on_event: node.el.on_event })
			}
			return none
		}
		if captured.identity.len == 0 { return captured }
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
			if current.dropdown_option { return current }
			canonical := custom_focus_target(mounted)
			owner := g_drag_registry.owners[drag_owner_key(canonical)] or { HitTarget{} }
			return HitTarget{...canonical,drag_generation:owner.drag_generation,drag_mount_generation:owner.drag_mount_generation}
		}
		return current
	}

	fn fire_target_event(target HitTarget, event ElementEvent) {
		if voidptr(target.on_event) != unsafe { nil } {
			dispatch := custom_input_dispatch(g_gg_app)
			revision := g_gg_app.presentation_revision
			menu_owner := if event.kind == .click { overlay_selection_owner(target.id) } else { none }
			target.on_event(event)
			if dispatch.valid() {
				if owner := menu_owner { request_overlay_dismiss(owner, .selection) }
			}
			// A presentation setter already requested a paint; pure visual callbacks
			// do not rebuild their retained layout. Mixed model changes call refresh().
			if dispatch.valid() && revision == g_gg_app.presentation_revision { refresh() }
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
		// gg synthesizes CHAR(127) after Delete on Windows/X11; editing already
		// happened in KEY_DOWN. C0 controls and DEL are commands, not text. Sokol
		// supplies Unicode scalars (Win32 surrogate pairs are decoded by the host).
		if ch < 32 || ch == 127 || ch > 0x10ffff || (ch >= 0xd800 && ch <= 0xdfff) {
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
			fire_target_event(target, ElementEvent{ kind: .click, id: target.id })
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
		g_hit_targets = g_hit_targets.filter(!it.dropdown_option)
		g_gg_app.pointer_geometry_serial = 0
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
		if ctx==unsafe { nil } { return }
		track_dropdown_popup_for(el,rect(x,y,el.frame.width,el.frame.height),ctx.content_transform,
			options,selected,rect(0,0,f64(ctx.width),f64(ctx.height)))
	}

	fn track_dropdown_popup_for(el Element, area Rect, transform ContentTransform, options []string, selected string, window Rect) {
		mut selected_index := -1
		for index, option in options {
			if option == selected {
				selected_index = index
				break
			}
		}
		row_height := dropdown_row_height(el.text_style) * transform.footprint_scale()
		anchor := transform.project(area)
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
			text_style: scaled_overlay_text_style(el.text_style, transform.footprint_scale())
			radius:     el.box.radius * transform.footprint_scale()
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

	fn dropdown_list_frame(state DropdownPopup, window Rect) Rect {
		return intersect_rect(rect(state.x+1,state.y+dropdown_popup_padding,state.width-2,
			state.height-dropdown_popup_padding*2),window)
	}
	fn dropdown_row_target(state DropdownPopup, index int, list Rect) HitTarget {
		frame := rect(state.x,state.y+dropdown_popup_padding+f64(index)*state.row_height-g_dropdown_scroll,state.width,state.row_height)
		visible := intersect_rect(frame,list)
		return HitTarget{kind:.dropdown,id:state.id,on_event:state.on_event,dropdown_option:true,
			option_index:index,options:state.options,local_frame:frame,has_geometry:true,
			clip_region:paint_transformed_clip(list,ContentTransform{}),x:visible.x,y:visible.y,w:visible.width,h:visible.height}
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
		list := dropdown_list_frame(dropdown_state,window)
		if list.width <= 0 || list.height <= 0 {
			return
		}
		apply_clip(ctx, list)
		row_style := TextStyle{
			...dropdown_state.text_style
			align: .left
		}
		for index, option in dropdown_state.options {
			row := dropdown_row_target(dropdown_state,index,list)
			if row.w<=0 || row.h<=0 { continue }
			row_y := row.local_frame.y
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
				vector_hit_mode: target.vector_hit_mode, vector_origin: target.vector_origin,
				is_image: target.is_image, image_geometry: target.image_geometry}, x, y) {
				return targets[i]
			}
		}
		return TooltipTarget{}
	}

	// Mounted targets retain their key across paint and scroll. Unmounted
	// callers use their explicit id or their supplied drawing area.
	fn tooltip_key(el Element, area Rect) string {
		mounted := el.mounted_tooltip_key()
		if mounted.len > 0 { return mounted }
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
		visible := retained_paint_clip(region, area, current_content_transform()).bounds()
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
			host_window := if voidptr(g_gg_app.ctx) == voidptr(ctx) { g_gg_app.native_window } else { unsafe { nil } }
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
			g_scroll_offsets_x.delete(id)
			g_scroll_content_w.delete(id)
		}
		for id in g_text_area_layouts.keys() {
			if id !in g_active_fields || (g_text_kinds[id] or { Kind.screen }) != .text_area {
				forget_text_area_layout(id)
			}
		}
	}

	// ── Rendering ──────────────────────────────────────────────────────

	fn element_hit_geometry(el Element, area Rect, transform ContentTransform, clip ClipRegion) HitTarget {
		visible := retained_paint_clip(clip, area, transform).bounds()
		return HitTarget{x: visible.x, y: visible.y, w: visible.width, h: visible.height,
			local_frame: area, content_transform: transform, clip_region: clip, has_geometry: true,
			is_vector_canvas: el.is_vector_canvas, vector_shapes: el.vector_shapes,
			vector_hit_mode: el.vector_hit_mode, vector_origin: area, is_image: el.kind == .image,
			image_geometry: if el.kind == .image {
				if g_gg_app.ctx!=unsafe { nil } { g_gg_app.ctx.image_hit_geometry_for(el,area,
					f64(g_gg_app.ctx.scale)*transform.footprint_scale()) or { ImageGeometry{} } } else { ImageGeometry{} }
			} else { ImageGeometry{} }}
	}

	fn resolve_custom_visual_style(declared Element, area Rect, clip Rect, transform ContentTransform) Element {
		region := current_clip_region(clip)
		geometry := element_hit_geometry(declared, area, transform, region)
		inert := g_gg_app.ctx != unsafe { nil } && g_gg_app.ctx.overlay_inert
		hovered := !inert && g_tooltip.pointer_in && hit_target_contains(geometry,g_tooltip.pointer_x,g_tooltip.pointer_y)
		focused := !inert && ((declared.id.len > 0 && declared.id == g_backend_text_focus.id)
			|| custom_focus_ring_visible(declared))
		pressed_style_active := !inert && g_touch.down && declared.id.len > 0
			&& (declared.id == g_touch.pressed_id || declared.id == g_touch.pointer_target.id)
			&& (!g_touch.pointer_captured || declared.kind == g_touch.pointer_target.kind)
			&& !g_touch.moved && !g_touch.scrollbar_drag
			&& hit_target_contains(geometry,g_touch.current_x,g_touch.current_y)
		return Element{...declared,
			box: interaction_box(declared, hovered, focused, pressed_style_active)
			text_style: interaction_text_style(declared, hovered, focused, pressed_style_active)}
	}

	fn render_scaled_content(ctx &DrawContext, el Element, off_x f64, off_y f64, clip Rect, scroll_parent_id string, path string) {
		dispatch := custom_input_dispatch(g_gg_app)
		root := g_focus_navigation.root_revision
		if el.presented_hidden() { return }
		viewport := rect(el.frame.x + off_x, el.frame.y + off_y, el.frame.width, el.frame.height)
		local := contain_content(viewport, el.content_size.width, el.content_size.height) or { return }
		render_element_body(ctx, Element{ ...el, children: [], content_size: LayoutSize{} }, off_x, off_y, clip, scroll_parent_id, path)
		if !custom_frame_current(dispatch, ctx) || g_focus_navigation.root_revision != root { return }
		outer := ctx.content_transform
		base := ctx.clip_base
		region := ctx.clip_region
		exact := ctx.retained_clip(base, viewport, outer)
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
			if !custom_frame_current(dispatch, ctx) || g_focus_navigation.root_revision != root { return }
		}
	}

	fn render_element(ctx &DrawContext, declared_el Element, off_x f64, off_y f64, clip Rect, scroll_parent_id string, path string) {
		if declared_el.presented_hidden() { return }
		outer := ctx.content_transform
		base := ctx.clip_base
		region := ctx.clip_region
		enabled := ctx.interaction_enabled
		opacity := ctx.opacity
		inert := ctx.overlay_inert
		parent_clip := ctx.retained_clip(base, clip, outer)
		area := element_area(ctx, declared_el, off_x, off_y)
		visual := declared_el.visual_transform().matrix(area) or { return }
		inv := visual.inverted() or { return }
		local_clip := inv.project(clip)
		unsafe {
			ctx.content_transform = outer.compose(visual)
			ctx.clip_base = parent_clip
			ctx.clip_region = parent_clip
			ctx.interaction_enabled = enabled && declared_el.presented_enabled()
			ctx.opacity = opacity * declared_el.presented_opacity()
			ctx.overlay_inert = inert || declared_el.overlay_inert()
		}
		defer { unsafe {
			ctx.content_transform = outer
			ctx.clip_base = base
			ctx.clip_region = region
			ctx.interaction_enabled = enabled
			ctx.opacity = opacity
			ctx.overlay_inert = inert
		}
		ctx.sync_scissor()
		 }
		el := Element{ ...declared_el, enabled: enabled && declared_el.presented_enabled() }
		if el.id.len > 0 {
			g_gg_app.visual_geometry_count++
			g_gg_app.visual_geometries[el.id] = VisualGeometry{ generation: g_gg_app.visual_geometry_generation, frame: area, transform: ctx.content_transform, parent_transform: outer, clip: parent_clip }
		}
		render_element_body(ctx, el, off_x, off_y, local_clip, scroll_parent_id, path)
	}

	fn render_element_body(ctx &DrawContext, declared_el Element, off_x f64, off_y f64, clip Rect, scroll_parent_id string, path string) {
		dispatch := custom_input_dispatch(g_gg_app)
		root := g_focus_navigation.root_revision
		if declared_el.presented_hidden() {
			return
		}
		// Hover chains follow paint order, so whatever is drawn later over an
		// element takes the pointer from it, as CSS :hover does.
		outer_hover := enter_hover_element(declared_el, path, element_area(ctx, declared_el, off_x, off_y), clip, ctx.overlay_inert)
		defer { leave_hover_element(outer_hover) }
		if declared_el.content_size.width > 0 || declared_el.content_size.height > 0 {
			render_scaled_content(ctx, declared_el, off_x, off_y, clip, scroll_parent_id, path)
			return
		}
		sync_mounted_control(Element{ ...declared_el, enabled: declared_el.enabled && !ctx.overlay_inert })
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
		owns_tooltip := el.tooltip.len > 0 && el.kind != .image
		if owns_tooltip {
			add_element_tooltip(tooltip_key(el, area), el.tooltip, el, area, clip)
			g_tooltip_owners++
		} else if g_tooltip_owners == 0 && g_tooltip_targets.len > 0 && tooltip_hides_beneath(el) && el.kind != .image {
			add_element_tooltip('', '', el, area, clip)
		}
		defer {
			if owns_tooltip {
				g_tooltip_owners--
			}
		}
		// A declared focus outline replaces the default ring instead of doubling it.
		if !ctx.overlay_inert && custom_focus_ring_visible(el) && el.kind !in [.text_field, .text_area]
			&& el.interaction_style.focus.outline_width == none {
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
					if !custom_frame_current(dispatch, ctx) || g_focus_navigation.root_revision != root { return }
				}
			}
			.view {
				x := el.frame.x + off_x
				y := el.frame.y + off_y
				draw_box_fill(ctx, x, y, el.frame.width, el.frame.height, el.box)
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
						|| el.swipe_left || el.drag_source != none || el.drop_target != none) {
					add_hit_target(HitTarget{
						identity:        path
						drag_source: el.drag_source
						drop_target: el.drop_target
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
				child_clip := if el.overlay != none { intersect_rect(area, clip) } else { clip }
				child_base := ctx.clip_base
				if el.overlay != none {
					unsafe { ctx.clip_base = ctx.retained_clip(child_base, area, ctx.content_transform) }
				}
				defer { unsafe { ctx.clip_base = child_base } }
				for index, child in el.children {
					render_element(ctx, child, x, y, child_clip, scroll_parent_id, reconciliation_child_key(path,index,child))
					if !custom_frame_current(dispatch, ctx) || g_focus_navigation.root_revision != root { return }
				}
			}
			.scroll {
				x := el.frame.x + off_x
				y := el.frame.y + off_y
				frame := rect(x, y, el.frame.width, el.frame.height)
				if box_draws_fill(el.box) {
					draw_rect(ctx, x, y, el.frame.width, el.frame.height, el.box.bg, 0)
				}
				draw_box_borders(ctx, x, y, el.frame.width, el.frame.height, el.box)
				scrolls_x := el.scroll_mode != .vertical_only
				scrolls_y := el.scroll_mode != .horizontal_only
				content_h := scroll_content_height(el)
				content_w := if scrolls_x { scroll_content_width(el.children) } else { 0.0 }
				scroll_id := scroll_view_state_id(el, path)
				scroll_y := register_scroll_view_in_parent(scroll_id, scroll_parent_id, frame, clip, content_h, el.enabled,
					scrolls_y, el.persistent_scrollbars, HitTarget{ id: el.id, kind: .scroll, on_event: el.on_event })
				if !custom_frame_current(dispatch, ctx) || g_focus_navigation.root_revision != root { return }
				beside_vertical := scrolls_y && scrollbar_geometry(frame, content_h, scroll_y, el.persistent_scrollbars).track.height > 0
				scroll_x := register_scroll_view_width(scroll_id, content_w, scrolls_x, el.persistent_scrollbars, beside_vertical)
				if !custom_frame_current(dispatch, ctx) || g_focus_navigation.root_revision != root { return }
				child_scroll_parent_id := scroll_id
				child_clip := intersect_rect(frame, clip)
				for index, child in el.children {
					child_screen_x := child.frame.x - scroll_x
					child_screen_y := child.frame.y - scroll_y
					if !subtree_has_visual_transform(child) && (child_screen_y + child.frame.height < 0 || child_screen_y > el.frame.height || child_screen_x + child.frame.width < 0 || child_screen_x > el.frame.width) {
						retain_culled_scroll_state(child, reconciliation_child_key(path, index, child))
						continue
					}
					render_element(ctx, child, x - scroll_x, y - scroll_y, child_clip, child_scroll_parent_id, reconciliation_child_key(path,index,child))
					if !custom_frame_current(dispatch, ctx) || g_focus_navigation.root_revision != root { return }
				}
				if child_clip.width > 0 && child_clip.height > 0 {
					apply_clip(ctx, child_clip)
					if scrolls_y {
						draw_scrollbar(ctx, x, y, el.frame.width, el.frame.height, content_h, scroll_y,
							el.persistent_scrollbars)
					}
					if scrolls_x {
						draw_scrollbar_x(ctx, frame, content_w, scroll_x, el.persistent_scrollbars,
							beside_vertical)
					}
				}
				apply_clip(ctx, clip)
			}
			.label {
				x := el.frame.x + off_x
				y := el.frame.y + off_y
				if box_draws_fill(el.box) {
					draw_rect(ctx, x, y, el.frame.width, el.frame.height, el.box.bg, el.box.radius)
				}
				draw_box_borders(ctx, x, y, el.frame.width, el.frame.height, el.box)
				shortened := draw_rich_label_text(ctx, el, x, y, clip)
				add_full_text_tooltip(el, area, clip, el.text, shortened)
			}
			.image {
				if name := symbol_name(el.image_path) {
					draw_symbol_image(ctx, name, area.x, area.y, area.width, area.height, el.text_style.color)
					if el.tooltip.len > 0 {
						add_tooltip_target(tooltip_key(el, area), el.tooltip, area, clip)
					}
					if el.enabled && voidptr(el.on_event) != unsafe { nil } && (el.clickable || el.draggable || el.drag_source != none || el.drop_target != none) {
						add_hit_target(HitTarget{identity:path,kind:el.kind,id:el.id,on_event:el.on_event,
							x:area.x,y:area.y,w:area.width,h:area.height,
							drag_source:el.drag_source,drop_target:el.drop_target,
							clickable:el.clickable,draggable:el.draggable},clip)
					}
					return
				}
				geometry := ctx.image_geometry_for(el,area) or {
					if el.image_path.len > 0 { draw_rect(ctx,area.x,area.y,area.width,area.height,0xe8ecef,0) }
					return
				}
				ctx.draw_asset_image(el,geometry)
				if el.tooltip.len > 0 || (g_tooltip_owners == 0 && g_tooltip_targets.len > 0) {
					count := g_tooltip_targets.len
					add_tooltip_target(tooltip_key(el,area),el.tooltip,area,clip)
					if g_tooltip_targets.len > count {
						last := g_tooltip_targets.last()
						g_tooltip_targets[g_tooltip_targets.len-1] = TooltipTarget{...last,is_image:true,image_geometry:geometry}
					}
				}
				if el.enabled && voidptr(el.on_event) != unsafe { nil } && (el.clickable || el.draggable || el.drag_source != none || el.drop_target != none) {
					add_hit_target(HitTarget{identity:path,kind:el.kind,id:el.id,on_event:el.on_event,
						x:area.x,y:area.y,w:area.width,h:area.height,is_image:true,image_geometry:geometry,
						drag_source:el.drag_source,drop_target:el.drop_target,
						clickable:el.clickable,draggable:el.draggable},clip)
				}
			}
			.button {
				x := el.frame.x + off_x
				y := el.frame.y + off_y
				if el.native_style && el.box.bg == unstyled_box_bg {
					draw_button_bezel(ctx, x, y, el.frame.width, el.frame.height, el.box.radius,
						el.enabled)
				} else {
					// Gradients fill views; a button keeps its solid fill, as natively.
					draw_box_fill(ctx, x, y, el.frame.width, el.frame.height, BoxStyle{ ...el.box, gradient: Gradient{} })
				}
				draw_box_borders(ctx, x, y, el.frame.width, el.frame.height, el.box)
				content := button_content_rect(el)
				image_layout := button_image_layout(content.width, content.height, el.text,
					el.image_path)
				if image_layout.visible {
					draw_button_image(ctx, el, x + content.x + image_layout.image.x,
						y + content.y + image_layout.image.y, image_layout.image.width, image_layout.image.height,
						el.text_style)
				}
				if el.text.len > 0 && image_layout.has_title_area() {
					shortened := draw_text_centered(ctx, el.text, x + content.x + image_layout.text.x,
						y + content.y + image_layout.text.y, image_layout.text.width, image_layout.text.height,
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
				box := if pressed { el.toggle_down_box() } else { el.box }
				style := if pressed { el.toggle_down_text_style() } else { el.text_style }
				if el.native_style && box.bg == unstyled_box_bg {
					draw_button_bezel(ctx, x, y, el.frame.width, el.frame.height, box.radius,
						el.enabled)
				} else {
					draw_box_fill(ctx, x, y, el.frame.width, el.frame.height, BoxStyle{ ...box, gradient: Gradient{} })
				}
				draw_box_borders(ctx, x, y, el.frame.width, el.frame.height, box)
				content := button_content_rect(el)
				shortened := draw_text_centered(ctx, el.text, x + content.x, y + content.y, content.width, content.height,
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
						toggle_group:              el.toggle_group()
						toggle_allow_no_selection: el.toggle_allow_no_selection()
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
					options := mounted_menu_options(el, path)
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
						visible := ctx.retained_clip(ctx.clip_region, area, ctx.content_transform).bounds()
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
				display_text := ctx.field_display_text(editor.text, el.secure)
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
							caret_text := ctx.field_prefix_text(editor.text, editor.selection.caret, el.secure)
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
									marked_start := ctx.field_prefix_text(editor.text, composition.start + composition.mark_start, el.secure)
									left := text_origin + f64(ctx.text_width(marked_start))
									marked_end := ctx.field_prefix_text(editor.text, composition.start + composition.mark_start + composition.mark_length, el.secure)
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

	fn retained_paint_clip(base ClipRegion, frame Rect, transform ContentTransform) ClipRegion {
		if g_gg_app.ctx != unsafe { nil } { return g_gg_app.ctx.retained_clip(base, frame, transform) }
		return base.intersect(paint_transformed_clip(frame, transform))
	}

	fn current_presentation_rect(area Rect) Rect {
		transform := current_content_transform()
		region := if g_gg_app.ctx != unsafe { nil } {
			g_gg_app.ctx.clip_region
		} else {
			ClipRegion{}
		}
		projected := retained_paint_clip(region, area, transform).bounds()
		return if g_gg_app.ctx != unsafe { nil } {
			presentation_rect(projected, f64(g_gg_app.ctx.scale))
		} else {
			projected
		}
	}

	fn current_clip_region(clip Rect) ClipRegion {
		base := if g_gg_app.ctx != unsafe { nil } { g_gg_app.ctx.clip_base } else { ClipRegion{} }
		return retained_paint_clip(base, clip, current_content_transform())
	}
	fn add_hit_target(declared HitTarget, clip Rect) {
		if !declared.dropdown_option && declared.identity.len>0 && g_focus_navigation.path_node(declared.identity)!=none { return }
		owner := g_drag_registry.owners[drag_owner_key(declared)] or { HitTarget{} }
		if (declared.drag_source!=none || declared.drop_target!=none) && owner.drag_generation==0 { return }
		target := HitTarget{...declared,drag_source:owner.drag_source,drop_target:owner.drop_target,drag_generation:owner.drag_generation}
		frame := rect(target.x, target.y, target.w, target.h)
		transform := current_content_transform()
		region := current_clip_region(clip)
		visible := retained_paint_clip(region, frame, transform).bounds()
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

	fn draw_button_image(ctx &DrawContext, el Element, x f64, y f64, width f64, height f64, style TextStyle) {
		image_path := el.image_path
		if image_path.starts_with('symbol:') {
			symbol := symbol_glyph(image_path['symbol:'.len..])
			draw_text_centered(ctx, symbol, x, y, width, height, TextStyle{
				...style
				font_family: 'Material Icons'
				size:        math.max(math.min(width, height) * 0.75, 8.0)
			})
			return
		}
		image_el := Element{...el, frame:rect(x,y,width,height),rotation:0}
		geometry := ctx.image_geometry_for(image_el,image_el.frame) or {
			draw_outline(ctx, x, y, width, height, 0x94a3b8, 2)
			return
		}
		if !ctx.draw_asset_image(image_el, geometry) {
			draw_outline(ctx, x, y, width, height, 0x94a3b8, 2)
		}
	}

	// draw_symbol_image draws a `symbol:` image as its Material Icons glyph, as large
	// as the frame allows and in the element's text color, which is what tints a
	// symbol image on every backend.
	fn draw_symbol_image(ctx &DrawContext, name string, x f64, y f64, width f64, height f64, color u32) {
		size := math.min(width, height)
		if size <= 0 {
			return
		}
		draw_text_centered(ctx, symbol_glyph(name), x, y, width, height, TextStyle{
			color:       color
			font_family: 'Material Icons'
			size:        size
		})
	}

	fn preload_images(mut ctx DrawContext) {
		// The all-mounted producer already resolved frames, scroll and affine
		// bases. Offscreen consumers use that same current footprint as paint.
		for node in g_focus_navigation.nodes {
			if node.hidden { continue }
			el := node.el
			quality := f64(ctx.scale) * node.transform.footprint_scale()
			if el.kind == .image && el.image_path.len > 0 && !el.image_path.starts_with('symbol:') {
				ctx.prepare_image(el,quality) or { eprintln('ui2: ${err}') }
			} else if el.kind == .button && el.image_path.len > 0 && !el.image_path.starts_with('symbol:') {
				layout := button_image_layout(el.frame.width,el.frame.height,el.text,el.image_path)
				ctx.prepare_image(Element{...el,frame:layout.image},quality) or { eprintln('ui2: ${err}') }
			}
		}
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

	fn draw_rect_alpha(ctx &DrawContext, x f64, y f64, w f64, h f64, color_hex u32, alpha f64, radius f64) {
		if w <= 0 || h <= 0 || alpha <= 0 {
			return
		}
		c := gg.Color{
			...hex_color(color_hex)
			a: u8(math.round(unit_clamp(alpha) * 255))
		}
		if radius > 0 {
			ctx.draw_rounded_rect_filled(f32(x), f32(y), f32(w), f32(h), f32(radius), c)
		} else {
			ctx.draw_rect_filled(f32(x), f32(y), f32(w), f32(h), c)
		}
	}

	// draw_box_fill paints what a BoxStyle puts beneath its borders: the drop
	// shadow, then the gradient or the solid color at the box's fill opacity.
	fn draw_box_fill(ctx &DrawContext, x f64, y f64, w f64, h f64, box BoxStyle) {
		if box_has_shadow(box) {
			draw_box_shadow(ctx, x, y, w, h, box.radius, box.shadow)
		}
		opacity := box_fill_opacity(box)
		if opacity <= 0 {
			return
		}
		if box_has_gradient(box) {
			draw_gradient_rect(ctx, x, y, w, h, box.radius, box.gradient, opacity)
		} else if opacity >= 1 {
			draw_rect(ctx, x, y, w, h, box.bg, box.radius)
		} else {
			draw_rect_alpha(ctx, x, y, w, h, box.bg, opacity, box.radius)
		}
	}

	// draw_box_shadow stands in for a Gaussian blur with a stack of translucent
	// rounded rectangles, from `blur / 2` outside the shadow's edge to `blur / 2`
	// inside it. Where k of the n layers overlap the alpha is 1 - (1 - a)^k, so
	// it rises across the blur and reaches the shadow's opacity inside it.
	fn draw_box_shadow(ctx &DrawContext, x f64, y f64, w f64, h f64, radius f64, shadow BoxShadow) {
		opacity := unit_clamp(shadow.opacity)
		sx := x + shadow.x - shadow.spread
		sy := y + shadow.y - shadow.spread
		sw := w + 2 * shadow.spread
		sh := h + 2 * shadow.spread
		sr := math.max(radius + shadow.spread, 0)
		blur := if math.is_nan(shadow.blur) { 0.0 } else { math.max(shadow.blur, 0) }
		if blur < 1 {
			draw_rect_alpha(ctx, sx, sy, sw, sh, shadow.color, opacity, sr)
			return
		}
		steps := int(math.min(math.max(blur / 2 + 2, 3), 10))
		per_layer := 1 - math.pow(1 - opacity, 1.0 / f64(steps))
		for i in 0 .. steps {
			grow := blur / 2 - blur * f64(i) / f64(steps - 1)
			layer_w := sw + 2 * grow
			layer_h := sh + 2 * grow
			if layer_w <= 0 || layer_h <= 0 {
				continue
			}
			layer_r := math.min(math.max(sr + grow, 0), math.min(layer_w, layer_h) / 2)
			draw_rect_alpha(ctx, sx - grow, sy - grow, layer_w, layer_h, shadow.color, per_layer,
				layer_r)
		}
	}

	// rounded_inset is how far in from the side a rounded box's edge is at height
	// `y` from its top, for corner radius r.
	fn rounded_inset(y f64, h f64, r f64) f64 {
		dy := if y < r { r - y } else if y > h - r { y - (h - r) } else { 0.0 }
		if dy <= 0 || r <= 0 {
			return 0
		}
		return r - math.sqrt(math.max(r * r - dy * dy, 0))
	}

	fn gradient_vertex_color(line GradientLine, stops []GradientStop, opacity f64, lx f64, ly f64) gg.Color {
		color, alpha := gradient_color_at(stops, gradient_position(line, lx, ly))
		return gg.Color{
			r: u8((color >> 16) & 0xff)
			g: u8((color >> 8) & 0xff)
			b: u8(color & 0xff)
			a: u8(math.round(unit_clamp(alpha * opacity) * 255))
		}
	}

	// draw_gradient_cell fills one quad of a gradient mesh, its corners given in
	// the box's own coordinates and colored by the gradient there.
	fn draw_gradient_cell(ctx &DrawContext, x f64, y f64, line GradientLine, stops []GradientStop, opacity f64, corners [4]Point) {
		mut points := []Point{len: 4}
		mut colors := []gg.Color{len: 4}
		for i, corner in corners {
			points[i] = Point{x + corner.x, y + corner.y}
			colors[i] = gradient_vertex_color(line, stops, opacity, corner.x, corner.y)
		}
		ctx.draw_local_colored_polygon(points, colors)
	}

	// draw_gradient_rect fills a (rounded) box with a linear gradient. The box is
	// cut into rows that follow its rounded edge and the rows into small cells,
	// each a quad whose corners take the gradient's color there; the GPU blends
	// across a cell, which is exact for a gradient between two stops and close for
	// more. About 16 cells each way keeps a gradient to a few thousand vertices.
	fn draw_gradient_rect(ctx &DrawContext, x f64, y f64, w f64, h f64, radius f64, gradient Gradient, opacity f64) {
		if w <= 0 || h <= 0 {
			return
		}
		stops := gradient_sorted_stops(gradient)
		line := gradient_line(gradient.angle, w, h)
		r := math.max(0, math.min(radius, math.min(w, h) / 2))
		if r < 0.5 && stops.len == 2 {
			// Two stops are linear across the whole box: one quad is exact.
			draw_gradient_cell(ctx, x, y, line, stops, opacity, [Point{0, 0}, Point{w, 0}, Point{w, h}, Point{0, h}]!)
			return
		}
		cell_w := math.max(4.0, w / 16)
		cell_h := math.max(4.0, (h - 2 * r) / 16)
		arc_rows := int(math.min(math.max(math.sqrt(r * f64(ctx.scale)) * 1.5, 2), 16))
		mut rows := [0.0]
		if r > 0 {
			for k in 1 .. arc_rows + 1 {
				rows << r - r * math.cos(math.pi / 2 * f64(k) / f64(arc_rows))
			}
		}
		for rows[rows.len - 1] + cell_h < h - r {
			rows << rows[rows.len - 1] + cell_h
		}
		if r > 0 {
			for k in 0 .. arc_rows + 1 {
				rows << h - r + r * math.sin(math.pi / 2 * f64(k) / f64(arc_rows))
			}
		} else {
			rows << h
		}
		columns := int(math.ceil(w / cell_w))
		for i in 1 .. rows.len {
			top := rows[i - 1]
			bottom := math.min(rows[i], h)
			if bottom <= top {
				continue
			}
			inset_top := rounded_inset(top, h, r)
			inset_bottom := rounded_inset(bottom, h, r)
			for c in 0 .. columns {
				f0 := f64(c) / f64(columns)
				f1 := f64(c + 1) / f64(columns)
				draw_gradient_cell(ctx, x, y, line, stops, opacity, [
					Point{inset_top + (w - 2 * inset_top) * f0, top},
					Point{inset_top + (w - 2 * inset_top) * f1, top},
					Point{inset_bottom + (w - 2 * inset_bottom) * f1, bottom},
					Point{inset_bottom + (w - 2 * inset_bottom) * f0, bottom},
				]!)
			}
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
		mut triangles := unsafe { &ctx.border_triangles }
		box_border_triangles_into(frame, box, mut triangles)
		for triangle in unsafe { *triangles } {
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

	fn draw_scrollbar_x(ctx &DrawContext, frame Rect, content_width f64, offset f64, persistent bool, beside_vertical bool) {
		bar := scrollbar_geometry_x(frame, content_width, offset, persistent, beside_vertical)
		if bar.track.width <= 0 || bar.track.height <= 0 { return }
		draw_rect(ctx, bar.track.x, bar.track.y, bar.track.width, bar.track.height, 0xf1f5f9, 2.5)
		draw_rect(ctx, bar.thumb.x, bar.thumb.y, bar.thumb.width, bar.thumb.height, 0xcbd5e1, 2.5)
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
				shaped := ctx.shape_runs(el.text_runs, el.text_style, math.max(0.0, el.frame.width), text_line_budget(el.text_style.lines), true) or {
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
				for selected in ctx.shaped_selection(shaped, start, end) {
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
					for marked in ctx.shaped_selection(shaped, start, start + composition.mark_length) {
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
			budget := text_line_budget(style.lines)
			parts := if budget > 1 {
				wrap_text_lines(ctx, t, w, budget, cfg)
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
				if style.underline || style.strikethrough {
					draw_text_decorations(ctx, line, f64(text_x), line_y, cfg, style)
				}
			}
			if bounded {
				apply_clip(ctx, clip)
			}
			return shortened
		} $else {
			// A shaped block supplies both its geometry and the glyphs painted here.
			// Editors pass an unbounded width so their value is clipped, not ellipsized.
			budget := text_line_budget(style.lines)
			width := if fit || budget > 1 { math.max(0.0, w) } else { -1.0 }
			shaped := ctx.shape_text(t, style, width, budget, fit) or {
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

	$if android {
		// draw_text_decorations rules a line drawn at text_x (its anchor for the
		// line's alignment) and centred on line_y. Desktop text is shaped with its
		// decorations; Android's gg text is not, so a link is underlined here.
		fn draw_text_decorations(ctx &DrawContext, line string, text_x f64, line_y f64, cfg gg.TextCfg, style TextStyle) {
			ctx.set_text_cfg(cfg)
			width := f64(ctx.text_width_f(line))
			if width <= 0 {
				return
			}
			left := match style.align {
				.left { text_x }
				.center { text_x - width / 2 }
				.right { text_x - width }
			}
			size := f64(cfg.size)
			thickness := math.max(1.0, math.round(size / 14))
			if style.underline {
				draw_rect(ctx, left, line_y + size * 0.42, width, thickness, style.color, 0)
			}
			if style.strikethrough {
				draw_rect(ctx, left, line_y - thickness / 2, width, thickness, style.color, 0)
			}
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
