V ?= v
VFLAGS ?=

.PHONY: test ide check-ide examples examples-custom screenshot check-macos check-ios check-android check-linux check-windows check-custom-macos check-custom-windows check-custom check-embedder-macos test-embedder check-backends

test:
	$(V) $(VFLAGS) test .

ide:
	$(V) $(VFLAGS) run ide

check-ide:
	$(V) $(VFLAGS) -check ide

examples:
	$(V) $(VFLAGS) run examples/build_examples.vsh $(VFLAGS)

examples-custom:
	$(V) $(VFLAGS) run examples/build_examples.vsh $(VFLAGS) -d ui2_custom_rendering

# Writes one frame of a custom-rendered example to a PNG, e.g.
#   make screenshot EXAMPLE=message
screenshot:
	$(V) $(VFLAGS) run examples/screenshot_example.vsh $(EXAMPLE) $(VFLAGS)

check-macos:
	$(V) $(VFLAGS) -shared -os macos -check .

check-ios:
	$(V) $(VFLAGS) -enable-globals -shared -os ios -check .

check-android:
	$(V) $(VFLAGS) -shared -os android -check .

check-linux:
	$(V) $(VFLAGS) -shared -os linux -check .
	$(V) $(VFLAGS) -os linux -check ui/ui_linux_test.v

check-windows:
	$(V) $(VFLAGS) -enable-globals -shared -os windows -check .
	$(V) $(VFLAGS) -enable-globals -os windows -check windows/ui_windows_test.v

check-custom-macos:
	$(V) $(VFLAGS) -d ui2_custom_rendering -shared -os macos -check .
	$(V) $(VFLAGS) -d ui2_custom_rendering -os macos -check ui/ui_custom_test.v

check-custom-windows:
	$(V) $(VFLAGS) -d ui2_custom_rendering -shared -os windows -check .
	$(V) $(VFLAGS) -d ui2_custom_rendering -os windows -check ui/ui_custom_test.v

check-custom: check-custom-macos check-custom-windows

# The owned embedder currently supports macOS/Metal. Its resource test opens
# the device, so run it on an actual macOS host rather than as a cross-check.
check-embedder-macos:
	$(V) $(VFLAGS) -d ui2_custom_rendering -d ui2_embedder -shared -os macos -check .
	$(V) $(VFLAGS) -d ui2_custom_rendering -d ui2_embedder -os macos -check ui/draw_context_embedder_test.v
	$(V) $(VFLAGS) -d ui2_custom_rendering -d ui2_embedder -os macos -check ui/ui_custom_test.v

test-embedder:
	$(V) $(VFLAGS) -d ui2_custom_rendering -d ui2_embedder test ui/draw_context_embedder_test.v \
		ui/frame_embedder_test.v ui/text_composition_test.v \
		ui/ui_window_state_immediate_test.v ui/ui_scheduler_immediate_test.v \
		ui/ui_pointer_capture_immediate_test.v ui/ui_scroll_immediate_test.v \
		ui/ui_tooltip_immediate_test.v

check-backends: check-macos check-ios check-android check-linux check-windows check-custom check-embedder-macos
