// vfmt off
@[has_globals]
module ui2

$if (android || ios || linux || macos || windows) && !ui2_headless ? && !ui2_document_library ? {
	$if android || ios {
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
		legacy_fonts CustomFontState
	}

	__global g_active_custom_window_state = &CustomWindowState(unsafe { nil })

	fn new_custom_window_state() &CustomWindowState {
		return &CustomWindowState{}
	}

	// The first window adopts declarations made before run_window, including
	// menus, event handlers and render state. Further windows begin
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
		empty := new_custom_window_state()
		empty.restore()
		mut owned := unsafe { state }
		owned.capture()
		activate_custom_window_state(previous)
	}

	fn (mut state CustomWindowState) capture() {
		$if android || ios {
			state.legacy_fonts.font_metrics = g_font_metrics
			state.legacy_fonts.font_files = g_font_files
			state.legacy_fonts.font_indexed = g_font_indexed
			state.legacy_fonts.font_family_files = g_font_family_files
			state.legacy_fonts.font_family_metrics = g_font_family_metrics
			state.legacy_fonts.font_symbol_ids = g_font_symbol_ids
			state.legacy_fonts.font_symbol_bases = g_font_symbol_bases
			state.legacy_fonts.font_symbol_fons = g_font_symbol_fons
		}
	}

	fn (state &CustomWindowState) restore() {
		$if android || ios {
			g_font_metrics = state.legacy_fonts.font_metrics
			g_font_files = state.legacy_fonts.font_files
			g_font_indexed = state.legacy_fonts.font_indexed
			g_font_family_files = state.legacy_fonts.font_family_files
			g_font_family_metrics = state.legacy_fonts.font_family_metrics
			g_font_symbol_ids = state.legacy_fonts.font_symbol_ids
			g_font_symbol_bases = state.legacy_fonts.font_symbol_bases
			g_font_symbol_fons = state.legacy_fonts.font_symbol_fons
		}
	}
}
