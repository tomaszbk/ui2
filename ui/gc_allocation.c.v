module ui2

$if gcboehm ? {
	struct C.GC_prof_stats_s {
		bytes_allocd_since_gc  usize
		allocd_bytes_before_gc usize
		gc_no                  usize
	}

	fn C.GC_get_prof_stats(&C.GC_prof_stats_s, usize) usize
}

// GcAllocationSnapshot contains cumulative Boehm allocation and collection
// counters. These count allocation traffic, including memory later reclaimed;
// heap size or RSS cannot detect short-lived allocations in a frame.
pub struct GcAllocationSnapshot {
pub:
	allocated_bytes u64
	collections     u64
}

pub struct GcAllocationDelta {
pub:
	allocated_bytes u64
	collections     u64
}

// gc_allocation_snapshot reads both counters under the collector lock without
// allocating. Allocation acceptance requires a Boehm build: disabled or other
// collectors must not silently report a successful zero-allocation result.
// Use -d no_gc_thread_local_alloc for precise scopes: thread-local Boehm pools
// otherwise report batches of small allocations when their free lists refill.
pub fn gc_allocation_snapshot() !GcAllocationSnapshot {
	$if gcboehm ? {
		mut stats := C.GC_prof_stats_s{}
		C.GC_get_prof_stats(&stats, sizeof(C.GC_prof_stats_s))
		return GcAllocationSnapshot{
			allocated_bytes: u64(stats.allocd_bytes_before_gc) + u64(stats.bytes_allocd_since_gc)
			collections:     u64(stats.gc_no)
		}
	} $else {
		return error('allocation measurement requires the Boehm GC; build with -gc boehm')
	}
}

pub fn (after GcAllocationSnapshot) delta_since(before GcAllocationSnapshot) GcAllocationDelta {
	return GcAllocationDelta{
		allocated_bytes: after.allocated_bytes - before.allocated_bytes
		collections:     after.collections - before.collections
	}
}
