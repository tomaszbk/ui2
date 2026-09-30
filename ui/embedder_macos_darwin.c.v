module ui2

$if macos && ui2_embedder ?&& !ui2_headless ? {
	#flag darwin -fobjc-arc
	#flag darwin -framework Cocoa -framework Metal -framework QuartzCore
	#include "@VMODROOT/ui/embedder_macos.h"
	#include "@VMODROOT/ui/embedder_macos.m"

	@[typedef]
	struct C.ui2_embedder_config {
	mut:
		title      &char
		width      int
		height     int
		min_width  int
		min_height int
		resizable  bool
		visible    bool
	}

	@[typedef]
	struct C.ui2_embedder_event {
	mut:
		kind               int
		key_code           int
		mouse_button       int
		char_code          u32
		modifiers          u32
		repeat             bool
		text_input         bool
		skip_dispatch      bool
		x                  f32
		y                  f32
		scroll_x           f32
		scroll_y           f32
		dpi_scale          f32
		width              int
		height             int
		framebuffer_width  int
		framebuffer_height int
		path               &char
		paths              &&char
		path_count         int
	}

	@[typedef]
	struct C.ui2_embedder_text_event {
	mut:
		kind               int
		text               &char
		replacement_start  int
		replacement_length int
		selection_start    int
		selection_length   int
	}

	@[typedef]
	struct C.ui2_embedder_callbacks {
	mut:
		pump   fn (voidptr) i64
		event  fn (voidptr, &C.ui2_embedder_event) bool
		text   fn (voidptr, &C.ui2_embedder_text_event)
		closed fn (voidptr)
	}

	@[typedef]
	struct C.ui2_embedder_surface {
	mut:
		width              int
		height             int
		framebuffer_width  int
		framebuffer_height int
		dpi_scale          f32
		drawable           voidptr
		color_texture      voidptr
	}

	fn C.ui2_embedder_create(&C.ui2_embedder_config, &C.ui2_embedder_callbacks, voidptr) voidptr
	fn C.ui2_embedder_run()
	fn C.ui2_embedder_is_main_thread() bool
	fn C.ui2_embedder_close(voidptr)
	fn C.ui2_embedder_wakeup(voidptr)
	fn C.ui2_embedder_metal_device() voidptr
	fn C.ui2_embedder_native_window(voidptr) voidptr
	fn C.ui2_embedder_frame_interval(voidptr) i64
	fn C.ui2_embedder_pump_count(voidptr) u64
	fn C.ui2_embedder_event_count(voidptr) u64
	fn C.ui2_embedder_acquire_frame(voidptr, &C.ui2_embedder_surface) bool
	fn C.ui2_embedder_frame_done(voidptr)
	fn C.ui2_embedder_metrics(voidptr, &C.ui2_embedder_surface)
	fn C.ui2_embedder_sync_text(voidptr, bool, &char, int, int, int, int, f64, f64, f64, f64)
	fn C.ui2_embedder_set_title(voidptr, &char)
	fn C.ui2_embedder_show(voidptr)
	fn C.ui2_embedder_set_cursor(int)
	fn C.ui2_embedder_clipboard_get() &char
	fn C.ui2_embedder_clipboard_set(&char)
}
