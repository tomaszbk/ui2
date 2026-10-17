// vtest vflags: -gc boehm -d no_gc_thread_local_alloc -d ui2_embedder
@[has_globals]
module ui2

$if macos && ui2_embedder ?&& !ui2_headless ? {
	import gg
	import os
	import sokol.gfx
	import time

	const allocation_fixture_labels = 300

	fn allocation_fixture_environment() gfx.Environment {
		return gfx.Environment{
			defaults: gfx.EnvironmentDefaults{ color_format: .bgra8, depth_format: .@none, sample_count: 1 }
			metal:    gfx.MetalEnvironment{ device: C.ui2_embedder_metal_device() }
		}
	}

	fn allocation_fixture_report(name string, delta GcAllocationDelta, frames int, elapsed time.Duration) {
		println('${name}: frames=${frames} bytes=${delta.allocated_bytes} bytes/frame=${f64(delta.allocated_bytes) / frames:.1f} collections=${delta.collections} us/frame=${f64(elapsed) / f64(time.microsecond) / frames:.1f}')
	}
}

// Measure the actual hidden Metal window, retained layout, input, text shaping,
// clipping and GPU submission. Warm both alternating values/hover positions
// before sampling so the acceptance does not count mount or cache population.
fn test_flat_retained_idle_hover_and_counter_tick_allocation_budgets() ! {
	run_retained_allocation_fixture(false)!
}

fn test_grouped_retained_idle_hover_and_counter_tick_allocation_budgets() ! {
	run_retained_allocation_fixture(true)!
}

fn run_retained_allocation_fixture(grouped bool) ! {
	$if macos && ui2_embedder ?&& !ui2_headless ? {
		mut ctx := new_surface_draw_context(gg.Config{ width: 1000, height: 700 }, allocation_fixture_environment())!
		window := C.ui2_embedder_create(&C.ui2_embedder_config{ title: c'Allocation acceptance', width: 1000, height: 700, visible: false }, &C.ui2_embedder_callbacks{}, unsafe { nil })
		assert window != unsafe { nil }
		mut component := new_vml_component('allocation acceptance')!
		defer {
			component.dispose() or { panic(err) }
			C.ui2_embedder_close(window)
			ctx.destroy()
		}
		mut w := &Window{ ctx: ctx, native_window: window, has_root: true }
		mount_watch := time.new_stopwatch()
		before_mount := gc_allocation_snapshot()!
		mut root := component.element(Element{ ...screen(0xffffff, []), id: 'root', frame: rect(0, 0, 1000, 700) })!
		mut counter := component.element(label('counter', 'tick A', rect(8, 8, 300, 24), TextStyle{}))!
		mut value := component.state('counter text', 'tick A')!
		counter.effect('text', fn [mut value] (element Element) !Element {
			return Element{ ...element, text: value.get()! }
		})!
		mut children := []&CompiledVmlNode{cap: allocation_fixture_labels + 2}
		children << counter
		children << component.element(Element{
			...button('hover', 'Hover', rect(400, 4, 100, 28), BoxStyle{ bg: 0xabcdef }, TextStyle{})
			interaction_style: InteractionStyle{ hover: BoxStylePatch{ bg: 0xcdefab } }
		})!
		mut static_children := []&CompiledVmlNode{cap: allocation_fixture_labels}
		for i in 0 .. allocation_fixture_labels {
			static_children << component.element(label('item-${i}', 'Item ${i} value ${(i * 7) % 97}',
				rect(8 + (i % 6) * 160, 40 + (i / 6) * 13, 150, 12), TextStyle{}))!
		}
		last_label_id := static_children[static_children.len - 1].element().id
		if grouped {
			mut static_group := component.element(view('static', rect(0, 0, 1000, 700), BoxStyle{ transparent: true }, []))!
			static_group.set_children(static_children)!
			children << static_group
		} else {
			children << static_children
		}
		root.set_children(children)!
		w.declared_root = root.element()
		root.mount()!
		on_frame(mut w)
		assert ctx.text.shape_builds >= u64(allocation_fixture_labels + 2)
		mount_delta := gc_allocation_snapshot()!.delta_since(before_mount)
		mount_elapsed := mount_watch.elapsed()
		// Alternate bounded strings and points; neither workload constructs its
		// own arrays or formats strings inside the measured scope.
		inside := gg.Event{ typ: .mouse_move, mouse_x: 450, mouse_y: 15 }
		outside := gg.Event{ typ: .mouse_move, mouse_x: 900, mouse_y: 15 }
		for i in 0 .. 8 {
			value.set(if i % 2 == 0 { 'tick B' } else { 'tick A' })!
			on_event(if i % 2 == 0 { &inside } else { &outside }, mut w)
			on_frame(mut w)
		}
		assert w.hit_test(450, 15).id == children[1].element().id
		iterations := if os.getenv('UI2_ALLOCATION_FRAMES').int() > 0 {
			os.getenv('UI2_ALLOCATION_FRAMES').int()
		} else {
			120
		}
		// Keep snapshots and the stopwatch on the stack; report after sampling.
		idle_stats := w.scheduler.stats()
		mut watch := time.new_stopwatch()
		idle_before := gc_allocation_snapshot()!
		for _ in 0 .. iterations { on_frame(mut w) }
		idle_delta := gc_allocation_snapshot()!.delta_since(idle_before)
		idle_elapsed := watch.elapsed()
		assert w.scheduler.stats().draws == idle_stats.draws
		watch.restart()
		hover_before := gc_allocation_snapshot()!
		for i in 0 .. iterations {
			on_event(if i % 2 == 0 { &inside } else { &outside }, mut w)
			on_frame(mut w)
		}
		hover_delta := gc_allocation_snapshot()!.delta_since(hover_before)
		hover_elapsed := watch.elapsed()
		hover_stats := w.scheduler.stats()
		assert hover_stats.draws == idle_stats.draws + u64(iterations)
		assert hover_stats.builds == idle_stats.builds
		watch.restart()
		tick_before := gc_allocation_snapshot()!
		mut tick_last := tick_before
		mut tick_peak_bytes := u64(0)
		for i in 0 .. iterations {
			value.set(if i % 2 == 0 { 'tick B' } else { 'tick A' })!
			on_frame(mut w)
			tick_now := gc_allocation_snapshot()!
			tick_bytes := tick_now.delta_since(tick_last).allocated_bytes
			if tick_bytes > tick_peak_bytes { tick_peak_bytes = tick_bytes }
			tick_last = tick_now
		}
		tick_delta := gc_allocation_snapshot()!.delta_since(tick_before)
		tick_elapsed := watch.elapsed()
		tick_stats := w.scheduler.stats()
		assert tick_stats.draws == hover_stats.draws + u64(iterations)
		assert tick_stats.builds == hover_stats.builds
		assert w.navigation.node(last_label_id) != none
		assert w.hit_test(450, 15).id == children[1].element().id
		name := if grouped { 'grouped' } else { 'flat' }
		allocation_fixture_report('${name}/mount', mount_delta, 1, mount_elapsed)
		allocation_fixture_report('${name}/idle', idle_delta, iterations, idle_elapsed)
		allocation_fixture_report('${name}/hover', hover_delta, iterations, hover_elapsed)
		allocation_fixture_report('${name}/tick', tick_delta, iterations, tick_elapsed)
		println('${name}/tick peak bytes/frame=${tick_peak_bytes}')
		if os.getenv('UI2_ALLOCATION_BASELINE') == '1' { return }
		assert idle_delta.allocated_bytes == 0
		assert idle_delta.collections == 0
		assert hover_delta.allocated_bytes == 0
		assert hover_delta.collections == 0
		// Flat snapshots copy the changed ancestor's direct Element array. The
		// bound covers three authored/resolved/compiled ancestor projections,
		// while a retained static subtree has a fixed 128 KiB action budget.
		tick_budget := if grouped { u64(128 * 1024) } else { u64(6 * 1024 * 1024) }
		assert tick_delta.allocated_bytes <= u64(iterations) * tick_budget
		assert tick_peak_bytes <= tick_budget
		assert tick_delta.collections <= u64(iterations / 8 + 1)
	}
}
