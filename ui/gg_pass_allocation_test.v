// vtest vflags: -gc boehm -d no_gc_thread_local_alloc -d ui2_custom_rendering
@[has_globals]
module ui2

$if macos && ui2_custom_rendering ? && !ui2_embedder ? && !ui2_headless ? {
	import gg

	struct GgPassAllocationAcceptance {
	mut:
		context  &gg.Context = unsafe { nil }
		delta    GcAllocationDelta
		measured bool
	}

	fn gg_pass_allocation_frame(mut probe GgPassAllocationAcceptance) {
		// The real Sokol window owns and initializes the default rendering
		// context; exercise the ordinary gg-backed pass submission directly.
		for _ in 0 .. 8 {
			probe.context.begin()
			probe.context.draw_rect_filled(2, 2, 12, 12, gg.blue)
			probe.context.end()
		}
		before := gc_allocation_snapshot() or { panic(err) }
		for _ in 0 .. 100 {
			probe.context.begin()
			probe.context.draw_rect_filled(2, 2, 12, 12, gg.blue)
			probe.context.end()
		}
		probe.delta = (gc_allocation_snapshot() or { panic(err) }).delta_since(before)
		probe.measured = true
		probe.context.quit()
	}
}

fn test_real_gg_pass_submission_allocates_nothing_after_warmup() {
	$if macos && ui2_custom_rendering ? && !ui2_embedder ? && !ui2_headless ? {
		mut probe := &GgPassAllocationAcceptance{}
		probe.context = gg.new_context(
			width:        64
			height:       64
			window_title: 'gg pass allocation acceptance'
			frame_fn:     gg_pass_allocation_frame
			user_data:    probe
		)
		probe.context.run()
		assert probe.measured
		assert probe.delta.allocated_bytes == 0
		assert probe.delta.collections == 0
	}
}
