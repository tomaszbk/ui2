#!/usr/bin/env bash
# Runs the Linux CI test steps locally. Run from anywhere; the repository must
# live in a directory named `ui2` because `import ui2` resolves through it.
# Usage: scripts/test-linux.sh [step-name-substring]
set -u
cd "$(dirname "$0")/../.."
V=${V:-v}
F=${VFLAGS:-"-b c -cc gcc"}
only=${1:-}
failed=()

step() {
	local name=$1
	shift
	if [[ -n "$only" && "$name" != *"$only"* ]]; then return; fi
	echo "=== $name"
	if ! (set -e; eval "$@"); then
		failed+=("$name")
	fi
}

step "ide check" "$V $F -check ui2/ide"
step "layout geometry" "$V $F test ui2/ui/incremental_layout_test.v ui2/ui/incremental_layout_axes_test.v"
step "compiled vml layout" "$V $F test ui2/ui/vml_modern_layout_test.v ui2/ui/vml_keyed_list_test.v ui2/ui/vml_keyed_dependencies_test.v"
step "designer" "$V $F test ui2/ide"
step "menubar" "$V $F test ui2/examples/menubar"
step "counter" "$V $F test ui2/examples/counter"
step "compiled vml contracts" "$V $F test ui2/tests/compiled_vml"
step "styles" "$V $F test ui2/ui/style_test.v && $V $F test ui2/ui/style_immediate_test.v"
step "motion controllers" "$V $F test ui2/ui/motion_test.v ui2/ui/frame_scheduler_test.v"
step "motion presence" "$V $F test ui2/ui/vml_presence_test.v ui2/ui/motion_runtime_immediate_test.v"
step "overlay geometry" "$V $F test ui2/ui/overlay_test.v ui2/ui/overlay_tree_test.v ui2/ui/overlay_focus_test.v ui2/ui/overlay_availability_test.v ui2/ui/overlay_layout_test.v ui2/ui/overlay_retained_test.v ui2/ui/overlay_scroll_allocation_test.v"
step "backend contract" "$V $F test ui2/ui/backend_guard_test.v ui2/ui/backend_headless_test.v"
step "compiled overlays" "$V $F test ui2/ui/vml_overlay_compiled_test.v ui2/ui/overlay_geometry_runtime_test.v ui2/ui/overlay_runtime_immediate_test.v ui2/ui/overlay_trigger_identity_test.v ui2/ui/shortcut_character_input_test.v && $V $F test ui2/examples/dialog ui2/examples/profile_dialog ui2/examples/overlays"
step "scrolling" "$V $F test ui2/ui/ui_scroll_immediate_test.v && $V $F test ui2/examples/scrollview ui2/examples/horizontal_scroll && $V $F -gc boehm -d no_gc_thread_local_alloc test ui2/ui/horizontal_scroll_retained_test.v ui2/ui/incremental_scroll_axes_test.v"
step "text" "$V $F test ui2/ui/text_backend_vglyph_test.v && $V $F test ui2/thirdparty/vglyph/ui2_context_test.v && $V $F test ui2/thirdparty/vglyph/ui2_host_ime_test.v"
step "allocations" "$V $F -gc boehm -d no_gc_thread_local_alloc test ui2/ui/gc_allocation_test.v ui2/ui/vml_allocation_test.v ui2/ui/vml_geometry_runtime_test.v ui2/ui/paint_allocation_test.v ui2/ui/retained_motion_clip_test.v ui2/ui/motion_preparation_test.v ui2/ui/retained_layout_snapshot_test.v ui2/ui/retained_focus_geometry_test.v ui2/ui/retained_patch_validation_test.v ui2/ui/retained_transform_snapshot_test.v ui2/ui/retained_scroll_identity_test.v ui2/ui/retained_tooltip_identity_test.v ui2/ui/retained_menu_options_test.v ui2/ui/build_arena_immediate_test.v ui2/benchmarks/vml_build/allocation_test.v"
step "c abi" "$V $F test ui2/c/api_test.v && $V $F run ui2/c/build.vsh test $F && $V $F run ui2/c/build.vsh example $F"

if ((${#failed[@]})); then
	echo "FAILED: ${failed[*]}"
	exit 1
fi
echo "ALL PASSED"
