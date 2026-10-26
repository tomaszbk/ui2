V ?= v
VFLAGS ?= -b c

# ui2 is the project's tool: `ui2 gen` writes the V builders of VML documents.
UI2 ?= build/ui2

.PHONY: gen test ide check-ide examples examples-custom screenshot test-appkit check-macos check-ios check-android check-linux check-windows check-custom-macos check-custom-ios check-custom-windows check-custom check-headless check-document check-embedder-macos test-embedder check-backends bench-allocations c-api c-example c-test c-smoke

$(UI2): cmd/ui2/main.v $(wildcard vml/*.v)
	@mkdir -p $(dir $(UI2))
	$(V) $(VFLAGS) -o $(UI2) cmd/ui2

# Generates the builders that the V files under these directories declare
# with `// vml:` directives.
gen: $(UI2)
	$(UI2) gen ui examples tests ide benchmarks

test: gen
	$(V) $(VFLAGS) test .

# The designer previews documents with the VML interpreter.
ide: gen
	$(V) $(VFLAGS) -d vml_interpreter run ide

check-ide:
	$(V) $(VFLAGS) -d vml_interpreter -check ide

# macOS, Windows and iOS build their native controls unless a build opts in
# to the custom renderer with -d ui2_custom_rendering (ui/backend.v).
examples: gen
	$(V) $(VFLAGS) run examples/build_examples.vsh $(VFLAGS)

examples-custom: gen
	$(V) $(VFLAGS) run examples/build_examples.vsh $(VFLAGS) -d ui2_custom_rendering

# Writes one frame of an example to a PNG, e.g.
#   make screenshot EXAMPLE=message
screenshot:
	$(V) $(VFLAGS) run examples/screenshot_example.vsh $(EXAMPLE) $(VFLAGS)

# The AppKit backend's tests open real windows and controls, so they run on a
# macOS host rather than as a cross-check.
test-appkit:
	$(V) $(VFLAGS) test appkit

check-macos:
	$(V) $(VFLAGS) -shared -os macos -check .
	@set -e; for fixture in appkit/*_test.v; do \
		$(V) $(VFLAGS) -os macos -check $$fixture; \
	done

check-ios:
	$(V) $(VFLAGS) -enable-globals -shared -os ios -check .
	$(V) $(VFLAGS) -enable-globals -os ios -check uikit/ui_ios_test.v
	$(V) $(VFLAGS) -enable-globals -os ios -check uikit/focus_navigation_ios_test.v

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

check-custom-ios:
	$(V) $(VFLAGS) -d ui2_custom_rendering -enable-globals -shared -os ios -check .

check-custom-windows:
	$(V) $(VFLAGS) -d ui2_custom_rendering -enable-globals -shared -os windows -check .
	@set -e; for fixture in ui/ui_custom_test.v ui/ui_custom_runtime_test.v \
		ui/ui_scheduler_immediate_test.v ui/ui_pointer_capture_immediate_test.v \
		ui/ui_scroll_immediate_test.v ui/ui_window_state_immediate_test.v \
		ui/text_backend_vglyph_test.v ui/text_composition_test.v \
		ui/presentation_geometry_test.v ui/frame_scheduler_test.v; do \
		$(V) $(VFLAGS) -d ui2_custom_rendering -os windows -check $$fixture; \
	done
	$(V) $(VFLAGS) -d ui2_custom_rendering -os windows -check examples/runtime_smoke

check-custom: check-custom-macos check-custom-ios check-custom-windows

check-headless:
	$(V) $(VFLAGS) -d ui2_headless -shared -check .

check-document:
	$(V) $(VFLAGS) -d ui2_document_library -shared -check .

# The embedder is the macOS host variant that owns its AppKit windows and Metal
# surfaces. Its resource test opens the device, so run it on an actual macOS
# host rather than as a cross-check.
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

# Compile the test as a standalone executable so successful samples are visible.
# Keep the GC enabled; the fixture rejects unavailable allocation counters.
bench-allocations:
	$(V) $(VFLAGS) -gc boehm -d no_gc_thread_local_alloc -skip-running -d ui2_custom_rendering -d ui2_embedder \
		-o /tmp/ui2-steady-state-allocations ui/steady_state_allocation_embedder_test.v
	/tmp/ui2-steady-state-allocations

check-backends: check-macos check-ios check-android check-linux check-windows check-custom check-headless check-document check-embedder-macos

# Optional: C_API_FLAGS passes extra V compiler flags, e.g. C_API_FLAGS=-prod
c-api:
	$(V) $(VFLAGS) run c/build.vsh library $(VFLAGS) $(C_API_FLAGS)

c-example:
	$(V) $(VFLAGS) run c/build.vsh example $(VFLAGS) $(C_API_FLAGS)

c-test:
	$(V) $(VFLAGS) run c/build.vsh test $(VFLAGS) $(C_API_FLAGS)

c-smoke:
	$(V) $(VFLAGS) run c/build.vsh smoke $(VFLAGS) $(C_API_FLAGS)
