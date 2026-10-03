// vfmt off
@[has_globals]
module ui2

$if (android || linux || ((macos || windows) && ui2_custom_rendering ?)) && !ui2_headless ? {
	$if android {
		struct CustomFontState {
		mut:
			font_metrics FontMetrics
			font_files map[string]string
			font_indexed bool
			font_family_files map[string]string
			font_family_metrics map[string]FontMetrics
			font_symbol_ids []int
			font_symbol_bases map[int]bool
			font_symbol_fons voidptr
		}
	} $else {
		// Desktop font state and atlas now belong to DrawContext.
		struct CustomFontState {}
	}

	// The old drawing/input helpers address the current window through globals.
	// The embedder changes that current window at each callback boundary. These
	// are owning snapshots: map and array headers move between a window and the
	// current globals, without cloning their owned text or GPU resource handles.
	// Keep activation on the UI thread; workers use the window's UiDispatcher.
	@[heap]
	struct CustomWindowState {
	mut:
		build_screen BuildFn = unsafe { nil }
		event_handler EventFn = unsafe { nil }
		key_handler KeyFn = unsafe { nil }
		key_event_handler KeyEventFn = unsafe { nil }
		scroll_handler ScrollFn = unsafe { nil }
		drop_handler DropFn = unsafe { nil }
		key_consumed bool
		text_values map[string]string
		text_props map[string]string
		text_editors map[string]TextEditor
		text_kinds map[string]Kind
		text_area_selections map[string]TextAreaSelectionRange
		text_area_layouts map[string]TextAreaLayout
		slider_values map[string]f64
		slider_declared map[string]f64
		slider_specs map[string]SliderSpec
		switch_values map[string]bool
		switch_declared map[string]bool
		checkbox_values map[string]bool
		checkbox_declared map[string]bool
		toggle_values map[string]bool
		toggle_declared map[string]bool
		toggle_groups map[string]string
		toggle_allow_no_selection map[string]bool
		focused_field string
		scroll_offsets map[string]f64
		scroll_content_h map[string]f64
		scroll_areas map[string]Rect
		scroll_viewports map[string]Rect
		pending_scroll map[string]f64
		scroll_order []string
		scroll_parents map[string]string
		scrollbar_geometries map[string]ScrollbarGeometry
		hit_targets []HitTarget
		touch TouchState
		active_fields map[string]bool
		active_sliders map[string]bool
		active_switches map[string]bool
		active_checkboxes map[string]bool
		active_toggles map[string]bool
		active_scrolls map[string]bool
		image_ids map[string]int
		active_images map[string]bool
		legacy_fonts CustomFontState
		open_dropdown string
		dropdown_popup DropdownPopup
		dropdown_hover int = -1
		dropdown_scroll f64
		tooltip_targets []TooltipTarget
		tooltip TooltipState
		tooltip_owners int
		menu_context MenuState
		menu_open_path []int
		menu_hover_path []int
		menu_hits []MenuBarHit
		menu_panels []Rect
		menu_swallow_up bool
		animation_runtime &AnimationRuntime = &AnimationRuntime{
			runs: map[string]AnimationRun{}
		}
	}

	__global g_active_custom_window_state = &CustomWindowState(unsafe { nil })

	fn new_custom_window_state() &CustomWindowState {
		return &CustomWindowState{}
	}

	// The first window adopts declarations made before run_window, including
	// menus, event handlers, render state and animations. Further windows begin
	// with new_custom_window_state, so equal element ids never share state.
	fn capture_custom_window_state() &CustomWindowState {
		mut state := new_custom_window_state()
		state.capture()
		return state
	}

	// Transfer pre-run declarations to the first window without leaving a
	// second snapshot that aliases its owned maps. The caller leaves this window
	// current until another window temporarily enters an event/frame callback.
	fn adopt_custom_window_state() &CustomWindowState {
		state := capture_custom_window_state()
		g_active_custom_window_state = state
		return state
	}

	// Returns the previous window's state for a deferred restoration. The
	// identity check permits nested callbacks for the same window without
	// loading an older snapshot over scalar changes in the enclosing callback.
	fn activate_custom_window_state(state &CustomWindowState) &CustomWindowState {
		mut previous := g_active_custom_window_state
		if previous == unsafe { nil } {
			previous = capture_custom_window_state()
		}
		if previous == state {
			return previous
		}
		previous.capture()
		state.restore()
		g_active_custom_window_state = state
		return previous
	}

	// A closed window may remain reachable through an old public handle or
	// dispatcher. Release its UI state after destroying the drawing context,
	// so that keeping such a handle cannot retain the mounted tree's text and
	// resource caches. Disposing one window also leaves a nested caller intact.
	fn discard_custom_window_state(state &CustomWindowState) {
		previous := activate_custom_window_state(state)
		for id in g_text_values.keys() {
			forget_text_state(id)
		}
		for id in g_text_props.keys() {
			forget_text_state(id)
		}
		for id in g_text_editors.keys() {
			forget_text_state(id)
		}
		reset_widget_animations()
		empty := new_custom_window_state()
		empty.restore()
		mut owned := unsafe { state }
		owned.capture()
		activate_custom_window_state(previous)
	}

	fn (mut state CustomWindowState) capture() {
		state.build_screen = g_build_screen
		state.event_handler = g_event_handler
		state.key_handler = g_key_handler
		state.key_event_handler = g_key_event_handler
		state.scroll_handler = g_scroll_handler
		state.drop_handler = g_drop_handler
		state.key_consumed = g_key_consumed
		state.text_values = g_text_values
		state.text_props = g_text_props
		state.text_editors = g_text_editors
		state.text_kinds = g_text_kinds
		state.text_area_selections = portable_text_area_selections
		state.text_area_layouts = g_text_area_layouts
		state.slider_values = g_slider_values
		state.slider_declared = g_slider_declared
		state.slider_specs = g_slider_specs
		state.switch_values = g_switch_values
		state.switch_declared = g_switch_declared
		state.checkbox_values = g_checkbox_values
		state.checkbox_declared = g_checkbox_declared
		state.toggle_values = g_toggle_values
		state.toggle_declared = g_toggle_declared
		state.toggle_groups = g_toggle_groups
		state.toggle_allow_no_selection = g_toggle_allow_no_selection
		state.focused_field = g_focused_field
		state.scroll_offsets = g_scroll_offsets
		state.scroll_content_h = g_scroll_content_h
		state.scroll_areas = g_scroll_areas
		state.scroll_viewports = g_scroll_viewports
		state.pending_scroll = g_pending_scroll
		state.scroll_order = g_scroll_order
		state.scroll_parents = g_scroll_parents
		state.scrollbar_geometries = g_scrollbar_geometries
		state.hit_targets = g_hit_targets
		state.touch = g_touch
		state.active_fields = g_active_fields
		state.active_sliders = g_active_sliders
		state.active_switches = g_active_switches
		state.active_checkboxes = g_active_checkboxes
		state.active_toggles = g_active_toggles
		state.active_scrolls = g_active_scrolls
		state.image_ids = g_image_ids
		state.active_images = g_active_images
		$if android {
			state.legacy_fonts.font_metrics = g_font_metrics
			state.legacy_fonts.font_files = g_font_files
			state.legacy_fonts.font_indexed = g_font_indexed
			state.legacy_fonts.font_family_files = g_font_family_files
			state.legacy_fonts.font_family_metrics = g_font_family_metrics
			state.legacy_fonts.font_symbol_ids = g_font_symbol_ids
			state.legacy_fonts.font_symbol_bases = g_font_symbol_bases
			state.legacy_fonts.font_symbol_fons = g_font_symbol_fons
		}
		state.open_dropdown = g_open_dropdown
		state.dropdown_popup = g_dropdown_popup
		state.dropdown_hover = g_dropdown_hover
		state.dropdown_scroll = g_dropdown_scroll
		state.tooltip_targets = g_tooltip_targets
		state.tooltip = g_tooltip
		state.tooltip_owners = g_tooltip_owners
		state.menu_context = *menu_state()
		state.menu_open_path = g_menu_open_path
		state.menu_hover_path = g_menu_hover_path
		state.menu_hits = g_menu_hits
		state.menu_panels = g_menu_panels
		state.menu_swallow_up = g_menu_swallow_up
		state.animation_runtime = g_animation_runtime
	}

	fn (state &CustomWindowState) restore() {
		g_build_screen = state.build_screen
		g_event_handler = state.event_handler
		g_key_handler = state.key_handler
		g_key_event_handler = state.key_event_handler
		g_scroll_handler = state.scroll_handler
		g_drop_handler = state.drop_handler
		g_key_consumed = state.key_consumed
		g_text_values = state.text_values
		g_text_props = state.text_props
		g_text_editors = state.text_editors
		g_text_kinds = state.text_kinds
		portable_text_area_selections = state.text_area_selections
		g_text_area_layouts = state.text_area_layouts
		g_slider_values = state.slider_values
		g_slider_declared = state.slider_declared
		g_slider_specs = state.slider_specs
		g_switch_values = state.switch_values
		g_switch_declared = state.switch_declared
		g_checkbox_values = state.checkbox_values
		g_checkbox_declared = state.checkbox_declared
		g_toggle_values = state.toggle_values
		g_toggle_declared = state.toggle_declared
		g_toggle_groups = state.toggle_groups
		g_toggle_allow_no_selection = state.toggle_allow_no_selection
		g_focused_field = state.focused_field
		g_scroll_offsets = state.scroll_offsets
		g_scroll_content_h = state.scroll_content_h
		g_scroll_areas = state.scroll_areas
		g_scroll_viewports = state.scroll_viewports
		g_pending_scroll = state.pending_scroll
		g_scroll_order = state.scroll_order
		g_scroll_parents = state.scroll_parents
		g_scrollbar_geometries = state.scrollbar_geometries
		g_hit_targets = state.hit_targets
		g_touch = state.touch
		g_active_fields = state.active_fields
		g_active_sliders = state.active_sliders
		g_active_switches = state.active_switches
		g_active_checkboxes = state.active_checkboxes
		g_active_toggles = state.active_toggles
		g_active_scrolls = state.active_scrolls
		g_image_ids = state.image_ids
		g_active_images = state.active_images
		$if android {
			g_font_metrics = state.legacy_fonts.font_metrics
			g_font_files = state.legacy_fonts.font_files
			g_font_indexed = state.legacy_fonts.font_indexed
			g_font_family_files = state.legacy_fonts.font_family_files
			g_font_family_metrics = state.legacy_fonts.font_family_metrics
			g_font_symbol_ids = state.legacy_fonts.font_symbol_ids
			g_font_symbol_bases = state.legacy_fonts.font_symbol_bases
			g_font_symbol_fons = state.legacy_fonts.font_symbol_fons
		}
		g_open_dropdown = state.open_dropdown
		g_dropdown_popup = state.dropdown_popup
		g_dropdown_hover = state.dropdown_hover
		g_dropdown_scroll = state.dropdown_scroll
		g_tooltip_targets = state.tooltip_targets
		g_tooltip = state.tooltip
		g_tooltip_owners = state.tooltip_owners
		mut menu := menu_state()
		menu.menus = state.menu_context.menus
		menu.tray = state.menu_context.tray
		menu.tray_visible = state.menu_context.tray_visible
		menu.dispatch = state.menu_context.dispatch
		menu.app_name = state.menu_context.app_name
		menu.window = state.menu_context.window
		g_menu_open_path = state.menu_open_path
		g_menu_hover_path = state.menu_hover_path
		g_menu_hits = state.menu_hits
		g_menu_panels = state.menu_panels
		g_menu_swallow_up = state.menu_swallow_up
		g_animation_runtime = state.animation_runtime
	}
}
