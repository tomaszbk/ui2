// vtest vflags: -gc boehm -d no_gc_thread_local_alloc
module main

import ui2

// The twenty-key calculator previously allocated over 9 MB per build. Keep a
// GC-backed bound on the complete first construction, including its effects,
// scopes and retained projections, rather than measuring only warm reads.
// Linux with `-gc boehm -d no_gc_thread_local_alloc` measures about 2.0 MB;
// the budget leaves roughly twice that.
fn test_compiled_calculator_first_build_allocation_is_bounded() ! {
	$if gcboehm ? {
		mut app := benchmark_model(default_rows)
		before := ui2.gc_allocation_snapshot()!
		root := build_compiled(mut app, ui2.rect(0, 0, 800, 600))
		delta := ui2.gc_allocation_snapshot()!.delta_since(before)
		assert delta.allocated_bytes <= 4096 * 1024
		assert root.compiled_node != unsafe { nil }
		assert consume_and_dispose(root) == 1
	}
}

// This wider Repeater reproduces the original gigabyte first-build workload.
// Each child change once re-projected every sibling up to the root; projections
// now settle once per batch. Linux measures about 28 MB for the complete
// construction and disposal with the GC on; the budget leaves roughly twice that.
fn test_compiled_three_hundred_key_first_build_allocation_is_bounded() ! {
	$if gcboehm ? {
		mut app := benchmark_model(75)
		before := ui2.gc_allocation_snapshot()!
		root := build_compiled(mut app, ui2.rect(0, 0, 800, 600))
		assert root.children[0].children[0].children[0].children.len == 301
		assert consume_and_dispose(root) == 1
		delta := ui2.gc_allocation_snapshot()!.delta_since(before)
		assert delta.allocated_bytes <= 56 * 1024 * 1024
	}
}

// generic.v builds form.vml through the generic node runtime, in the shape the
// generic lowering emits. It must build the same document as `$vml`.
fn test_generic_lowering_builds_the_compiled_document() {
	mut app := benchmark_model(default_rows)
	frame := ui2.rect(0, 0, 800, 600)
	compiled := build_compiled(mut app, frame)
	generic := build_generic(mut app, frame)
	assert_same_tree(compiled, generic)
	mut compiled_root := compiled.compiled_node
	mut generic_root := generic.compiled_node
	app.display = '0'
	app.keys = benchmark_model(2).keys.reverse()
	compiled_root.component.invalidate_app() or { panic(err) }
	generic_root.component.invalidate_app() or { panic(err) }
	assert_same_tree(compiled_root.element(), generic_root.element())
	assert consume_and_dispose(compiled_root.element()) == 1
	assert consume_and_dispose(generic_root.element()) == 1
}

fn assert_same_tree(a ui2.Element, b ui2.Element) {
	assert a.kind == b.kind
	assert a.id == b.id
	assert a.key == b.key
	assert a.frame == b.frame
	assert a.text == b.text
	assert a.box == b.box
	assert a.text_style == b.text_style
	assert a.children.len == b.children.len
	for i, child in a.children {
		assert_same_tree(child, b.children[i])
	}
}

// The generic runtime allocates less than the compiled lowering. Linux
// measures about 1.3 MB for its twenty-key first build and about 17 MB for
// the three-hundred-key construction and disposal; the budgets leave roughly
// twice that.
fn test_generic_calculator_first_build_allocation_is_bounded() ! {
	$if gcboehm ? {
		mut app := benchmark_model(default_rows)
		before := ui2.gc_allocation_snapshot()!
		root := build_generic(mut app, ui2.rect(0, 0, 800, 600))
		delta := ui2.gc_allocation_snapshot()!.delta_since(before)
		assert delta.allocated_bytes <= 2560 * 1024
		assert consume_and_dispose(root) == 1
	}
}

fn test_generic_three_hundred_key_first_build_allocation_is_bounded() ! {
	$if gcboehm ? {
		mut app := benchmark_model(75)
		before := ui2.gc_allocation_snapshot()!
		root := build_generic(mut app, ui2.rect(0, 0, 800, 600))
		assert root.children[0].children[0].children[0].children.len == 301
		assert consume_and_dispose(root) == 1
		delta := ui2.gc_allocation_snapshot()!.delta_since(before)
		assert delta.allocated_bytes <= 34 * 1024 * 1024
	}
}
