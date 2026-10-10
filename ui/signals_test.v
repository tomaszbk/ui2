module ui2

import math

@[heap]
struct SignalsFixture {
mut:
	values []int
	words  []string
	a      int
	b      int
	c      int
}

fn test_signals_lazy_diamond_push_pull_and_equality_cutoff() ! {
	mut runtime := new_signal_runtime()
	mut scope := runtime.scope()!
	mut source := new_signal(mut scope, 1, name: 'source')!
	mut counts := &SignalsFixture{}
	mut left := new_memo(mut scope, fn [mut source, mut counts] () !int {
		counts.a++
		return source.get()! * 2
	},
		name: 'left'
	)!
	mut right := new_memo(mut scope, fn [mut source, mut counts] () !int {
		counts.b++
		return source.get()! * 3
	},
		name: 'right'
	)!
	mut total := new_memo(mut scope, fn [mut left, mut right, mut counts] () !int {
		counts.c++
		return left.get()! + right.get()!
	},
		name: 'total'
	)!
	assert counts.a == 0 && counts.b == 0 && counts.c == 0
	assert source.set(2)!
	assert counts.a == 0
	scope.effect('observe diamond', fn [mut total, mut counts] () ! {
		counts.values << total.get()!
	})!
	assert counts.values == [10]
	assert total.get()! == 10
	assert counts.c == 1
	assert source.set(3)!
	assert counts.values == [10, 15]
	assert counts.a == 2 && counts.b == 2 && counts.c == 2
	assert !source.set(3)!
	assert counts.values == [10, 15]
	mut parity := new_memo(mut scope, fn [mut source] () !int { return source.get()! % 2 })!
	scope.effect('parity', fn [mut parity, mut counts] () ! { counts.words << '${parity.get()!}' })!
	assert source.set(5)!
	assert counts.words == ['1']
	assert counts.values == [10, 15, 25]
	scope.dispose()!
	assert runtime.stats() == SignalStats{}
}

fn test_signals_nested_batches_read_own_writes_and_dirty_memo() ! {
	mut runtime := new_signal_runtime()
	mut scope := runtime.scope()!
	mut a := new_signal(mut scope, 1)!
	mut b := new_signal(mut scope, 10)!
	mut sum := new_memo(mut scope, fn [mut a, mut b] () !int { return a.get()! + b.get()! })!
	mut fixture := &SignalsFixture{}
	scope.effect('sum', fn [mut sum, mut fixture] () ! { fixture.values << sum.get()! })!
	runtime.batch(fn [mut runtime, mut a, mut b, mut sum, fixture] () ! {
		a.set(2)!
		assert a.get()! == 2
		assert sum.get()! == 12
		runtime.batch(fn [mut b, mut sum, fixture] () ! {
			b.set(20)!
			assert sum.get()! == 22
			assert fixture.values == [11]
		})!
		a.set(3)!
		assert sum.get()! == 23
		assert fixture.values == [11]
	})!
	assert fixture.values == [11, 23]
	runtime.dispose()!
	assert runtime.stats() == SignalStats{}
}

fn test_signals_dynamic_dependencies_and_untracked_memo_preserve_cache() ! {
	mut runtime := new_signal_runtime()
	mut scope := runtime.scope()!
	mut choose_a := new_signal(mut scope, true)!
	mut a := new_signal(mut scope, 2)!
	mut b := new_signal(mut scope, 7)!
	mut incidental := new_signal(mut scope, 0)!
	mut branch := new_memo(mut scope, fn [mut choose_a, mut a, mut b] () !int {
		return if choose_a.get()! { a.get()! } else { b.get()! }
	})!
	mut doubled := new_memo(mut scope, fn [mut incidental] () !int { return incidental.get()! * 2 })!
	mut fixture := &SignalsFixture{}
	scope.effect('branch', fn [mut runtime, mut branch, mut incidental, mut doubled, mut fixture] () ! {
		fixture.values << branch.get()!
		incidental.peek()!
		runtime.untracked(fn [mut doubled] () ! { doubled.get()! })!
	})!
	assert runtime.stats().subscriptions == 4 // branch: 2; effect: 1; doubled: 1
	a.set(3)!
	choose_a.set(false)!
	a.set(99)!
	incidental.set(4)!
	assert fixture.values == [2, 3, 7]
	assert doubled.get()! == 8
	b.set(8)!
	assert fixture.values == [2, 3, 7, 8]
	scope.dispose()!
	assert runtime.stats() == SignalStats{}
}

fn test_signals_effect_cleanup_scope_tree_and_repeated_teardown() ! {
	mut runtime := new_signal_runtime()
	assert !runtime.is_disposed()
	for _ in 0 .. 20 {
		mut scope := runtime.scope()!
		mut child := scope.child()!
		assert !scope.is_disposed() && !child.is_disposed()
		mut source := new_signal(mut scope, 0)!
		mut fixture := &SignalsFixture{}
		scope.on_cleanup(fn [mut fixture] () { fixture.words << 'scope' })!
		child.on_cleanup(fn [mut fixture] () { fixture.words << 'child' })!
		mut effect := child.effect('resource', fn [mut runtime, mut source, mut fixture] () ! {
			value := source.get()!
			fixture.values << value
			runtime.on_effect_cleanup(fn [value, mut fixture] () { fixture.words << '${value}' })!
		})!
		assert runtime.stats().cleanups == 3
		source.set(1)!
		assert fixture.words == ['0']
		scope.dispose()!
		assert scope.is_disposed() && child.is_disposed()
		assert effect.is_disposed()
		assert fixture.words == ['0', 'child', '1', 'scope']
		scope.dispose()!
		effect.dispose()!
		assert runtime.stats() == SignalStats{}
	}
}

fn test_signals_cleanup_is_untracked_and_may_write_without_nested_flush() ! {
	mut runtime := new_signal_runtime()
	mut scope := runtime.scope()!
	mut source := new_signal(mut scope, 0)!
	mut incidental := new_signal(mut scope, 0)!
	mut fixture := &SignalsFixture{}
	mut effect := scope.effect('cleanup writer', fn [mut runtime, mut source, mut incidental, mut fixture] () ! {
		fixture.values << source.get()!
		runtime.on_effect_cleanup(fn [mut incidental, mut fixture] () {
			incidental.get() or { panic(err) }
			incidental.set(incidental.peek() or { panic(err) } + 1) or { panic(err) }
			fixture.a++
		})!
	})!
	source.set(1)!
	assert fixture.values == [0, 1]
	incidental.set(10)!
	assert fixture.values == [0, 1]
	effect.dispose()!
	assert incidental.get()! == 11
	assert fixture.a == 2
	scope.dispose()!
}

fn test_signals_disposal_during_callback_and_pending_effect_is_safe() ! {
	mut runtime := new_signal_runtime()
	mut parent := runtime.scope()!
	mut child := parent.child()!
	mut source := new_signal(mut parent, 0)!
	mut fixture := &SignalsFixture{}
	// Invalidation visits subscribers in reverse registration order: disposer is
	// scheduled before pending. Both are owned by the scope it disposes.
	child.effect('pending', fn [mut source, mut fixture] () ! { fixture.values << source.get()! })!
	child.effect('dispose self', fn [mut runtime, mut source, mut child, mut fixture] () ! {
		value := source.get()!
		runtime.on_effect_cleanup(fn [mut fixture] () { fixture.a++ })!
		if value > 0 {
			child.dispose()!
			// Reads after disposal must not reattach this dead observer.
			source.get()!
			runtime.on_effect_cleanup(fn [mut fixture] () { fixture.b++ })!
		}
	})!
	source.set(1)!
	assert fixture.values == [0]
	assert fixture.a == 2 && fixture.b == 1
	assert runtime.stats().effects == 0
	assert runtime.stats().subscriptions == 0
	parent.dispose()!
	assert runtime.stats() == SignalStats{}
}

fn test_signals_reentrant_writes_new_effects_and_feedback_are_bounded() ! {
	mut runtime := new_signal_runtime(max_runs_per_effect: 4)
	mut scope := runtime.scope()!
	mut source := new_signal(mut scope, 0)!
	mut fixture := &SignalsFixture{}
	scope.effect('finite feedback', fn [mut source, mut fixture] () ! {
		value := source.get()!
		fixture.values << value
		if value < 2 { source.set(value + 1)! }
	})!
	assert fixture.values == [0, 1, 2]
	mut feedback := scope.effect('unbounded feedback', fn [mut source] () ! {
		value := source.get()!
		if value > 10 { source.set(value + 1)! }
	})!
	source.set(11) or {
		assert err.msg().contains('feedback limit')
		assert err.msg().contains('unbounded feedback')
		assert feedback.is_disposed()
		assert source.peek()! == 15
		source.set(3)!
		assert fixture.values.last() == 3
		scope.dispose()!
		assert runtime.stats() == SignalStats{}
		return
	}
	assert false, 'feedback must diagnose, never hang'
}

@[heap]
struct SignalCycleFixture {
mut:
	left  &Memo[int] = unsafe { nil }
	right &Memo[int] = unsafe { nil }
}

fn test_signals_memo_cycle_error_restores_context_and_can_recover() ! {
	mut runtime := new_signal_runtime()
	mut scope := runtime.scope()!
	mut cyclic := new_signal(mut scope, true)!
	mut refs := &SignalCycleFixture{}
	refs.left = new_memo(mut scope, fn [mut cyclic, mut refs] () !int {
		return if cyclic.get()! { refs.right.get()! } else { 42 }
	},
		name: 'left'
	)!
	refs.right = new_memo(mut scope, fn [mut refs] () !int { return refs.left.get()! },
		name: 'right'
	)!
	refs.left.get() or {
		assert err.msg().contains('left -> right -> left')
		assert runtime.current == unsafe { nil }
		assert runtime.stack.len == 0
		cyclic.set(false)!
		assert refs.left.get()! == 42
		assert refs.right.get()! == 42
		scope.dispose()!
		assert runtime.stats() == SignalStats{}
		return
	}
	assert false
}

fn test_signals_callback_errors_batch_errors_and_recovery() ! {
	mut runtime := new_signal_runtime()
	mut scope := runtime.scope()!
	mut source := new_signal(mut scope, 0)!
	mut fixture := &SignalsFixture{}
	mut memo := new_memo(mut scope, fn [mut source] () !int {
		value := source.get()!
		if value == 1 { return error('unavailable') }
		return value * 10
	})!
	mut effect := scope.effect('recoverable', fn [mut memo, mut fixture] () ! {
		fixture.values << memo.get()!
	})!
	scope.effect('independent', fn [mut source, mut fixture] () ! {
		fixture.words << '${source.get()!}'
	})!
	source.set(1) or { assert err.msg().contains('unavailable') }
	assert runtime.current == unsafe { nil }
	assert runtime.stack.len == 0
	assert runtime.execution_depth == 0 && !runtime.flushing
	assert fixture.words == ['0', '1']
	source.set(2)!
	assert fixture.values == [0, 20]
	effect.retry()!
	assert fixture.values == [0, 20, 20]
	runtime.batch(fn [mut runtime, mut source] () ! {
		runtime.untracked(fn [mut source] () ! {
			source.get()!
			return error('action error')
		})!
	}) or { assert err.msg().contains('action error') }
	assert runtime.batch_depth == 0 && runtime.untracked_depth == 0
	runtime.batch(fn [mut source] () ! {
		source.set(3)!
		return error('after write')
	}) or {
		assert err.msg().contains('after write')
	}
	assert fixture.values == [0, 20, 20, 30]
	scope.dispose()!
}

fn test_signals_equality_scalar_nan_pointer_and_compound_policy() ! {
	mut runtime := new_signal_runtime()
	mut scope := runtime.scope()!
	mut scalar := new_signal(mut scope, 'español')!
	assert !scalar.set('español')!
	assert scalar.set('niño')!
	mut floating := new_signal(mut scope, f64(0))!
	assert !floating.set(-f64(0))!
	assert floating.set(math.nan())!
	assert !floating.set(math.nan())!
	assert floating.set(math.inf(1))!
	assert !floating.set(math.inf(1))!
	mut array := new_signal(mut scope, [1, 2])!
	assert array.set([1, 2])!
	mut object := new_signal(mut scope, SignalStats{ signals: 1 })!
	assert object.set(SignalStats{ signals: 1 })!
	mut map_signal := new_signal(mut scope, {
		'a': 1
	})!
	assert map_signal.set({
		'a': 1
	})!
	a := &SignalsFixture{}
	b := &SignalsFixture{}
	mut pointer := new_signal(mut scope, a)!
	assert !pointer.set(a)!
	assert pointer.set(b)!
	mut custom := new_signal(mut scope, [1, 2],
		equals: fn (a []int, b []int) bool { return a.len == b.len }
	)!
	assert !custom.set([3, 4])!
	assert custom.peek()! == [1, 2] // equal writes do not replace the value
	assert custom.set([3])!
	scope.dispose()!
}

fn test_signals_memos_reject_writes_and_restore_tracking() ! {
	mut runtime := new_signal_runtime()
	mut scope := runtime.scope()!
	mut source := new_signal(mut scope, 0)!
	mut bad := new_memo(mut scope, fn [mut source] () !int {
		source.set(1)!
		return 1
	},
		name: 'impure'
	)!
	bad.get() or { assert err.msg().contains('must be pure') }
	assert source.peek()! == 0
	assert runtime.stack.len == 0 && runtime.current == unsafe { nil }
	mut fixture := &SignalsFixture{}
	scope.effect('after error', fn [mut source, mut fixture] () ! {
		fixture.values << source.get()!
	})!
	source.set(1)!
	assert fixture.values == [0, 1]
	scope.dispose()!
}

fn test_signals_effects_created_and_disposed_in_batch_or_callback() ! {
	mut runtime := new_signal_runtime()
	mut scope := runtime.scope()!
	mut source := new_signal(mut scope, 0)!
	mut fixture := &SignalsFixture{}
	runtime.batch(fn [mut scope, mut source, mut fixture] () ! {
		mut cancelled := scope.effect('cancelled initial', fn [mut fixture] () ! { fixture.a++ })!
		cancelled.dispose()!
		scope.effect('creator', fn [mut scope, mut source, mut fixture] () ! {
			value := source.get()!
			fixture.values << value
			if value == 1 {
				scope.effect('created inside callback', fn [mut source, mut fixture] () ! {
					fixture.words << '${source.get()!}'
				})!
				assert fixture.words.len == 0
			}
		})!
		assert fixture.a == 0 && fixture.values.len == 0
	})!
	assert fixture.values == [0]
	source.set(1)!
	assert fixture.values == [0, 1]
	assert fixture.words == ['1']
	source.set(2)!
	assert fixture.words == ['1', '2']
	assert fixture.a == 0
	scope.dispose()!
	assert runtime.stats() == SignalStats{}
}

fn test_signals_direct_effect_dynamic_dependencies_untracked_error_and_isolation() ! {
	mut runtime := new_signal_runtime()
	mut other := new_signal_runtime()
	mut scope := runtime.scope()!
	mut other_scope := other.scope()!
	mut choose := new_signal(mut scope, true)!
	mut a := new_signal(mut scope, 1)!
	mut b := new_signal(mut scope, 9)!
	mut unrelated := new_signal(mut other_scope, 100)!
	mut fixture := &SignalsFixture{}
	scope.effect('dynamic effect', fn [mut runtime, mut choose, mut a, mut b, mut unrelated, mut fixture] () ! {
		fixture.values << if choose.get()! { a.get()! } else { b.get()! }
		// A read in another runtime belongs to a separate tracking domain.
		unrelated.get()!
		runtime.untracked(fn [mut b] () ! {
			b.get()!
			return error('ignored read')
		}) or {}
		assert runtime.untracked_depth == 0
	})!
	assert runtime.stats().subscriptions == 2
	choose.set(false)!
	a.set(2)!
	unrelated.set(200)!
	assert fixture.values == [1, 9]
	b.set(10)!
	assert fixture.values == [1, 9, 10]
	assert other.stats().subscriptions == 0
	runtime.dispose()!
	other.dispose()!
	assert runtime.stats() == SignalStats{}
}

fn test_signals_failed_new_dependency_recovers_and_initial_error_cleans_resources() ! {
	mut runtime := new_signal_runtime()
	mut scope := runtime.scope()!
	mut switch := new_signal(mut scope, false)!
	mut source := new_signal(mut scope, 0)!
	mut fixture := &SignalsFixture{}
	mut memo := new_memo(mut scope, fn [mut source] () !int {
		value := source.get()!
		if value == 0 { return error('not ready') }
		return value
	})!
	scope.effect('new failing branch', fn [mut switch, mut memo, mut fixture] () ! {
		if switch.get()! { fixture.values << memo.get()! }
	})!
	switch.set(true) or { assert err.msg().contains('not ready') }
	source.set(7)!
	assert fixture.values == [7]
	baseline := runtime.stats()
	scope.effect('initial failure', fn [mut runtime, mut fixture] () ! {
		runtime.on_effect_cleanup(fn [mut fixture] () { fixture.a++ })!
		return error('initial failure')
	}) or { assert err.msg().contains('initial failure') }
	assert fixture.a == 1
	assert runtime.stats() == baseline
	scope.dispose()!
	assert runtime.stats() == SignalStats{}
}

fn test_signals_depth_limit_and_total_feedback_budget_restore_context() ! {
	mut runtime := new_signal_runtime(max_memo_depth: 2, max_runs_per_flush: 3)
	mut scope := runtime.scope()!
	mut a := new_memo(mut scope, fn () !int { return 1 }, name: 'a')!
	mut b := new_memo(mut scope, fn [mut a] () !int { return a.get()! + 1 }, name: 'b')!
	mut c := new_memo(mut scope, fn [mut b] () !int { return b.get()! + 1 }, name: 'c')!
	c.get() or { assert err.msg().contains('evaluation depth exceeded: c -> b -> a') }
	assert runtime.stack.len == 0 && runtime.current == unsafe { nil }
	assert b.get()! == 2
	assert c.get()! == 3 // cached ancestors avoid exceeding depth
	mut fixture := &SignalsFixture{}
	runtime.batch(fn [mut scope, mut fixture] () ! {
		for i in 0 .. 5 {
			scope.effect('budget-${i}', fn [mut fixture] () ! { fixture.a++ })!
		}
	}) or { assert err.msg().contains('feedback limit') }
	assert fixture.a == 3
	assert runtime.stats().effects == 3
	assert runtime.stats().pending == 0
	scope.dispose()!
	assert runtime.stats() == SignalStats{}
}

fn test_signals_runtime_disposal_inside_effect_and_late_cleanup() ! {
	mut runtime := new_signal_runtime()
	mut scope := runtime.scope()!
	mut source := new_signal(mut scope, 0)!
	mut fixture := &SignalsFixture{}
	mut effect := scope.effect('shutdown', fn [mut runtime, mut source, mut fixture] () ! {
		if source.get()! > 0 {
			runtime.dispose()!
			runtime.on_effect_cleanup(fn [mut fixture] () { fixture.a++ })!
		}
	})!
	source.set(1)!
	assert effect.is_disposed()
	assert runtime.is_disposed() && scope.is_disposed()
	assert fixture.a == 1
	assert runtime.stats() == SignalStats{}
	effect.dispose()!
	scope.dispose()!
	runtime.dispose()!
}

fn test_signals_disposed_source_diagnoses_surviving_consumer() ! {
	mut runtime := new_signal_runtime()
	mut sources := runtime.scope()!
	mut observers := runtime.scope()!
	mut source := new_signal(mut sources, 0, name: 'short lived')!
	mut fixture := &SignalsFixture{}
	observers.effect('survivor', fn [mut source, mut fixture] () ! {
		fixture.values << source.get()!
	})!
	sources.dispose() or { assert err.msg().contains('short lived` is disposed') }
	assert runtime.current == unsafe { nil } && runtime.stack.len == 0
	assert runtime.stats().subscriptions == 0
	source.get() or { assert err.msg().contains('disposed') }
	observers.dispose()!
	assert runtime.stats() == SignalStats{}
}

fn test_signals_custom_equality_is_untracked_and_cannot_write() ! {
	mut runtime := new_signal_runtime()
	mut scope := runtime.scope()!
	mut incidental := new_signal(mut scope, 0)!
	mut value := new_signal(mut scope, 0,
		equals: fn [mut incidental] (a int, b int) bool {
			incidental.get() or { panic(err) }
			incidental.set(1) or { assert err.msg().contains('equality callbacks must be pure') }
			return a == b
		}
	)!
	mut trigger := new_signal(mut scope, 0)!
	mut fixture := &SignalsFixture{}
	scope.effect('comparator writer', fn [mut trigger, mut value, mut fixture] () ! {
		value.set(trigger.get()!)!
		fixture.a++
	})!
	assert incidental.peek()! == 0
	assert runtime.stats().subscriptions == 1
	incidental.set(2)!
	assert fixture.a == 1
	trigger.set(1)!
	assert fixture.a == 2
	assert value.peek()! == 1
	scope.dispose()!
}

fn test_signals_wide_diamond_and_own_batch_reference_results() ! {
	mut runtime := new_signal_runtime()
	mut scope := runtime.scope()!
	mut x := new_signal(mut scope, 0)!
	mut branches := []&Memo[int]{}
	for factor in 1 .. 33 {
		branches << new_memo(mut scope, fn [mut x, factor] () !int { return x.get()! * factor })!
	}
	mut fixture := &SignalsFixture{}
	scope.effect('wide diamond', fn [mut x, mut branches, mut fixture] () ! {
		value := x.get()!
		mut sum := 0
		for mut branch in branches { sum += branch.get()! }
		assert sum == value * 528 // independently calculated 1+...+32
		fixture.values << sum
	})!
	for iteration in 1 .. 30 {
		runtime.batch(fn [mut x, mut branches, iteration] () ! {
			x.set(iteration * 2 - 1)!
			assert branches[0].get()! == iteration * 2 - 1
			x.set(iteration * 2)!
		})!
	}
	assert fixture.values.len == 30
	assert fixture.values.last() == 58 * 528
	scope.dispose()!
	assert runtime.stats() == SignalStats{}
}

fn test_signals_normal_gc_keeps_callbacks_and_scope_ownership_alive() ! {
	mut runtime := new_signal_runtime()
	mut scope := runtime.scope()!
	mut source := new_signal(mut scope, 1)!
	mut fixture := &SignalsFixture{}
	mut memo := new_memo(mut scope, fn [mut source] () !int { return source.get()! * 7 })!
	// Drop the effect handle: the owning scope still retains the effect.
	scope.effect('GC ownership', fn [mut memo, mut fixture] () ! { fixture.values << memo.get()! })!
	for i in 2 .. 12 {
		gc_collect()
		source.set(i)!
		assert fixture.values.last() == i * 7
	}
	assert fixture.values.len == 11
	scope.dispose()!
	gc_collect()
	assert runtime.stats() == SignalStats{}
}

fn test_signals_scalar_enum_f32_fixed_array_and_memo_custom_equality() ! {
	mut runtime := new_signal_runtime()
	mut scope := runtime.scope()!
	mut enumeration := new_signal(mut scope, SignalNodeKind.source)!
	assert !enumeration.set(.source)!
	assert enumeration.set(.memo)!
	mut floating := new_signal(mut scope, f32(math.nan()))!
	assert !floating.set(f32(math.nan()))!
	assert floating.set(f32(1))!
	mut fixed := new_signal(mut scope, [1, 2]!)!
	assert fixed.set([1, 2]!)!
	mut input := new_signal(mut scope, 1)!
	mut fixture := &SignalsFixture{}
	mut memo := new_memo(mut scope, fn [mut input] () ![]int { return [input.get()!] },
		equals: fn (a []int, b []int) bool { return a[0] % 2 == b[0] % 2 }
	)!
	scope.effect('custom memo', fn [mut memo, mut fixture] () ! { fixture.values << memo.get()![0] })!
	input.set(3)!
	assert fixture.values == [1]
	assert memo.get()! == [1]
	input.set(4)!
	assert fixture.values == [1, 4]
	scope.dispose()!
}

fn test_signals_batch_reports_empty_error_and_both_action_and_effect_failure() ! {
	mut runtime := new_signal_runtime()
	mut scope := runtime.scope()!
	mut source := new_signal(mut scope, 0)!
	scope.effect('failure', fn [mut source] () ! {
		if source.get()! == 1 { return error('effect failure') }
	})!
	mut reported := false
	runtime.batch(fn () ! { return error('') }) or { reported = true }
	assert reported
	runtime.batch(fn [mut source] () ! {
		source.set(1)!
		return error('action failure')
	}) or {
		assert err.msg().contains('action failure') && err.msg().contains('effect failure')
	}
	assert source.peek()! == 1
	assert runtime.batch_depth == 0 && runtime.execution_depth == 0 && runtime.stack.len == 0
	source.set(2)!
	scope.dispose()!
	assert runtime.stats() == SignalStats{}
}

fn test_signals_handled_memo_errors_stay_reactive_without_forcing_effect_errors() ! {
	mut runtime := new_signal_runtime()
	mut scope := runtime.scope()!
	mut source := new_signal(mut scope, 0)!
	mut memo := new_memo(mut scope, fn [mut source] () !int {
		value := source.get()!
		if value < 2 { return error('not ready') }
		return value
	})!
	mut fixture := &SignalsFixture{}
	scope.effect('fallback consumer', fn [mut memo, mut fixture] () ! {
		fixture.values << memo.get() or { -1 }
	})!
	source.set(1)! // validation must not bypass the callback's error handler
	assert fixture.values == [-1, -1]
	source.set(2)!
	assert fixture.values == [-1, -1, 2]
	scope.dispose()!
	assert runtime.stats() == SignalStats{}
}
