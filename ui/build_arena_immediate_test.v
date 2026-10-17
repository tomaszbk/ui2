// vtest vflags: -gc boehm -d no_gc_thread_local_alloc
@[has_globals]
module ui2

$if (android || ios || linux || macos || windows) && !ui2_headless ?&& !ui2_document_library ? {
	import arena
}

fn test_build_validation_reuses_arena_and_owns_escaping_diagnostics() ! {
	$if (android || ios || linux || macos || windows) && !ui2_headless ?&& !ui2_document_library ? {
		mut w := &Window{}
		defer { w.build_arena.allocator.free() }
		root := view('root', rect(0, 0, 100, 100), BoxStyle{}, [
			label('child', 'Retained text', rect(0, 0, 40, 20), TextStyle{}),
		])
		w.validate_custom_build(root)!
		capacity := w.build_arena.allocator.capacity()
		assert capacity > 0
		before := gc_allocation_snapshot()!
		for _ in 0 .. 32 { w.validate_custom_build(root)! }
		delta := gc_allocation_snapshot()!.delta_since(before)
		assert delta.allocated_bytes == 0
		assert delta.collections == 0
		assert w.build_arena.allocator.capacity() == capacity
		assert w.build_arena.allocator.used() == 0
		assert !arena.active()
		duplicate := view('root', rect(0, 0, 100, 100), BoxStyle{}, [root.children[0],
			root.children[0]])
		mut diagnostic := ''
		w.validate_custom_build(duplicate) or { diagnostic = err.msg() }
		assert diagnostic.contains('child')
		assert !w.build_arena.allocator.owns(diagnostic.str)
		// Subsequent validation can reuse/reset every arena byte without losing
		// the public diagnostic or any authored data supplied by the builder.
		w.validate_custom_build(root)!
		assert diagnostic.contains('child')
		assert root.children[0].text == 'Retained text'
		assert !arena.active()
	}
}
