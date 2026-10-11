// vtest vflags: -d no_gc_thread_local_alloc
module ui2

fn test_gc_allocation_snapshot_has_no_measurement_allocations() {
	$if gcboehm ? {
		before := gc_allocation_snapshot()!
		mut after := before
		for _ in 0 .. 100 {
			after = gc_allocation_snapshot()!
		}
		delta := after.delta_since(before)
		assert delta.allocated_bytes == 0
		assert delta.collections == 0
	} $else {
		if _ := gc_allocation_snapshot() {
			assert false, 'unsupported collectors must not report zero allocations'
		}
	}
}

fn test_gc_allocation_snapshot_counts_reclaimed_allocation_and_collections() {
	$if gcboehm ? {
		before := gc_allocation_snapshot()!
		mut data := []u8{len: 8192}
		data[0] = 73
		gc_collect()
		after := gc_allocation_snapshot()!
		delta := after.delta_since(before)
		assert data[0] == 73
		assert delta.allocated_bytes >= 8192
		assert delta.collections >= 1
	}
}

fn test_gc_allocation_precise_sampling_detects_each_small_allocation_after_warmup() {
	$if gcboehm ?&& no_gc_thread_local_alloc ? {
		mut buffers := [][]u8{cap: 256}
		// Warm this size class first. A thread-local slab refill can make the
		// first tiny allocation visible while hiding every subsequent one.
		for _ in 0 .. 128 {
			buffers << []u8{len: 16}
		}
		for i in 0 .. 20 {
			before := gc_allocation_snapshot()!
			mut data := []u8{len: 16}
			data[0] = u8(i)
			delta := gc_allocation_snapshot()!.delta_since(before)
			assert data[0] == u8(i)
			assert delta.allocated_bytes >= 16
			buffers << data
		}
		assert buffers.len == 148
	}
}
