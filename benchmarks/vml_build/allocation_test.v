// vtest vflags: -gc boehm -d no_gc_thread_local_alloc
module main

import ui2

// The twenty-key calculator previously allocated over 9 MB per build. Keep a
// GC-backed bound on the complete first construction, including its effects,
// scopes and retained projections, rather than measuring only warm reads.
// Linux with `-gc boehm -d no_gc_thread_local_alloc` measures about 2.3 MB;
// the budget leaves roughly twice that.
fn test_compiled_calculator_first_build_allocation_is_bounded() ! {
	$if gcboehm ? {
		mut app := benchmark_model(default_rows)
		before := ui2.gc_allocation_snapshot()!
		root := build_compiled(mut app, ui2.rect(0, 0, 800, 600))
		delta := ui2.gc_allocation_snapshot()!.delta_since(before)
		assert delta.allocated_bytes <= 4608 * 1024
		assert root.compiled_node != unsafe { nil }
		assert consume_and_dispose(root) == 1
	}
}

// This wider Repeater reproduces the original gigabyte first-build workload.
// Each child change once re-projected every sibling up to the root; projections
// now settle once per batch. Linux measures about 31 MB for the complete
// construction and disposal with the GC on; the budget leaves roughly twice that.
fn test_compiled_three_hundred_key_first_build_allocation_is_bounded() ! {
	$if gcboehm ? {
		mut app := benchmark_model(75)
		before := ui2.gc_allocation_snapshot()!
		root := build_compiled(mut app, ui2.rect(0, 0, 800, 600))
		assert root.children[0].children[0].children[0].children.len == 301
		assert consume_and_dispose(root) == 1
		delta := ui2.gc_allocation_snapshot()!.delta_since(before)
		assert delta.allocated_bytes <= 64 * 1024 * 1024
	}
}
