module ui2

@[heap]
struct SignalErrorLifecycleFixture {
mut:
	values  []int
	words   []string
	cleaned int
	fail    bool
	failed  &SignalEffect = unsafe { nil }
	sibling &SignalEffect = unsafe { nil }
}

fn test_signals_deferred_initial_failure_disposes_its_resources_once() ! {
	mut runtime := new_signal_runtime()
	mut scope := runtime.scope()!
	mut source := new_signal(mut scope, 0)!
	mut fixture := &SignalErrorLifecycleFixture{}
	baseline := runtime.stats()
	mut reported := false
	runtime.batch(fn [mut runtime, mut scope, mut source, mut fixture] () ! {
		fixture.failed = scope.effect('deferred failure', fn [mut runtime, mut source, mut fixture] () ! {
			fixture.values << source.get()!
			runtime.on_effect_cleanup(fn [mut fixture] () { fixture.words << 'first' })!
			runtime.on_effect_cleanup(fn [mut fixture] () { fixture.words << 'second' })!
			return error('initial failure')
		})!
		assert fixture.values.len == 0 && !fixture.failed.is_disposed()
		return error('batch action failed')
	}) or {
		reported = true
		assert err.msg().contains('batch action failed') && err.msg().contains('initial failure')
	}
	assert reported
	assert fixture.values == [0]
	assert fixture.words == ['second', 'first']
	assert fixture.failed.is_disposed()
	assert runtime.stats() == baseline
	fixture.failed.dispose()!
	source.set(1)!
	assert fixture.values == [0] && fixture.words == ['second', 'first']
	scope.dispose()!
	assert runtime.stats() == SignalStats{}
}

fn test_signals_initial_failure_created_by_callback_does_not_retain_resources() ! {
	mut runtime := new_signal_runtime()
	mut scope := runtime.scope()!
	mut source := new_signal(mut scope, 0)!
	mut fixture := &SignalErrorLifecycleFixture{}
	scope.effect('creator', fn [mut runtime, mut scope, mut source, mut fixture] () ! {
		value := source.get()!
		fixture.values << value
		if value == 1 {
			fixture.failed = scope.effect('callback child', fn [mut runtime, mut source, mut fixture] () ! {
				source.get()!
				runtime.on_effect_cleanup(fn [mut fixture] () { fixture.cleaned++ })!
				return error('child initial failure')
			})!
			assert fixture.cleaned == 0
		}
	})!
	baseline := runtime.stats()
	mut reported := false
	source.set(1) or {
		reported = true
		assert err.msg().contains('child initial failure')
	}
	assert reported
	assert fixture.failed.is_disposed() && fixture.cleaned == 1
	assert runtime.stats() == baseline
	source.set(2)!
	assert fixture.values == [0, 1, 2]
	scope.dispose()!
	assert fixture.cleaned == 1 && runtime.stats() == SignalStats{}
}

fn test_signals_successful_new_outer_and_queued_sibling_survive_child_failure() ! {
	mut runtime := new_signal_runtime()
	mut scope := runtime.scope()!
	mut source := new_signal(mut scope, 0)!
	mut fixture := &SignalErrorLifecycleFixture{}
	mut reported := false
	scope.effect('successful outer', fn [mut runtime, mut scope, mut source, mut fixture] () ! {
		value := source.get()!
		fixture.values << value
		if value == 0 {
			fixture.failed = scope.effect('failed child', fn [mut runtime, mut source, mut fixture] () ! {
				source.get()!
				runtime.on_effect_cleanup(fn [mut fixture] () { fixture.cleaned++ })!
				return error('child failure')
			})!
			fixture.sibling = scope.effect('successful sibling', fn [mut source, mut fixture] () ! {
				fixture.words << '${source.get()!}'
			})!
			assert fixture.words.len == 0
		}
	}) or {
		reported = true
		assert err.msg().contains('child failure')
	}
	assert reported
	assert fixture.failed.is_disposed() && !fixture.sibling.is_disposed()
	assert fixture.cleaned == 1
	assert runtime.stats() == SignalStats{ signals: 1, scopes: 1, effects: 2, subscriptions: 2 }
	source.set(1)!
	assert fixture.values == [0, 1] && fixture.words == ['0', '1']
	scope.dispose()!
	assert fixture.cleaned == 1 && runtime.stats() == SignalStats{}
}

fn test_signals_initial_failure_cleanup_drains_observers_and_preserves_original_error() ! {
	mut runtime := new_signal_runtime()
	mut scope := runtime.scope()!
	mut source := new_signal(mut scope, 0)!
	mut fixture := &SignalErrorLifecycleFixture{}
	scope.effect('observer', fn [mut source, mut fixture] () ! {
		value := source.get()!
		fixture.values << value
		if value == 1 { return error('observer also failed') }
	})!
	baseline := runtime.stats()
	mut reported := false
	scope.effect('initial writer', fn [mut runtime, mut source, mut fixture] () ! {
		runtime.on_effect_cleanup(fn [mut runtime, mut source, mut fixture] () {
			fixture.cleaned++
			source.set(1) or { panic(err) }
			// The observer must run in a subsequent wave, outside this cleanup.
			assert fixture.values == [0]
			mut rejected := false
			runtime.on_effect_cleanup(fn [mut fixture] () { fixture.cleaned++ }) or {
				rejected = true
				assert err.msg().contains('cleanup requires a running effect')
			}
			assert rejected
		})!
		return error('original initial failure')
	}) or {
		reported = true
		assert err.msg() == 'signals: `initial writer`: original initial failure'
		assert fixture.values == [0, 1] && runtime.stats().pending == 0
	}
	assert reported && fixture.cleaned == 1
	assert source.peek()! == 1 && runtime.stats() == baseline
	source.set(2)!
	assert fixture.values == [0, 1, 2]
	scope.dispose()!
	assert fixture.cleaned == 1 && runtime.stats() == SignalStats{}
}

fn test_signals_successful_effect_keeps_resources_after_repeated_failed_retry() ! {
	mut runtime := new_signal_runtime()
	mut scope := runtime.scope()!
	mut source := new_signal(mut scope, 0)!
	mut fixture := &SignalErrorLifecycleFixture{}
	mut effect := scope.effect('retry survivor', fn [mut runtime, mut source, mut fixture] () ! {
		fixture.values << source.get()!
		runtime.on_effect_cleanup(fn [mut fixture] () { fixture.cleaned++ })!
		if fixture.fail { return error('retry failure') }
	})!
	baseline := runtime.stats()
	fixture.fail = true
	for attempt in 1 .. 3 {
		mut reported := false
		effect.retry() or {
			reported = true
			assert err.msg().contains('retry failure')
		}
		assert reported && !effect.is_disposed()
		assert fixture.cleaned == attempt && runtime.stats() == baseline
	}
	fixture.fail = false
	source.set(1)!
	assert fixture.values == [0, 0, 0, 1] && fixture.cleaned == 3
	assert runtime.stats() == baseline
	effect.dispose()!
	assert fixture.cleaned == 4
	scope.dispose()!
	assert fixture.cleaned == 4 && runtime.stats() == SignalStats{}
}

fn test_signals_successful_first_invocation_survives_later_failure_in_same_flush() ! {
	mut runtime := new_signal_runtime()
	mut scope := runtime.scope()!
	mut source := new_signal(mut scope, 0)!
	mut fixture := &SignalErrorLifecycleFixture{}
	mut reported := false
	scope.effect('first succeeded', fn [mut runtime, mut source, mut fixture] () ! {
		value := source.get()!
		fixture.values << value
		runtime.on_effect_cleanup(fn [mut fixture] () { fixture.cleaned++ })!
		if value == 0 { source.set(1)! }
		if value == 1 { return error('later invocation failed') }
	}) or {
		reported = true
		assert err.msg().contains('later invocation failed')
	}
	assert reported && fixture.values == [0, 1] && fixture.cleaned == 1
	assert runtime.stats() == SignalStats{ signals: 1, scopes: 1, effects: 1, subscriptions: 1, cleanups: 1 }
	source.set(2)!
	assert fixture.values == [0, 1, 2] && fixture.cleaned == 2
	scope.dispose()!
	assert fixture.cleaned == 3 && runtime.stats() == SignalStats{}
}

fn test_signals_scope_disposed_by_failed_initial_callback_is_not_resurrected() ! {
	mut runtime := new_signal_runtime()
	mut parent := runtime.scope()!
	mut source := new_signal(mut parent, 0)!
	mut fixture := &SignalErrorLifecycleFixture{}
	parent.effect('surviving observer', fn [mut source, mut fixture] () ! {
		fixture.values << source.get()!
	})!
	baseline := runtime.stats()
	mut child := parent.child()!
	mut reported := false
	runtime.batch(fn [mut runtime, mut child, mut source, mut fixture] () ! {
		fixture.failed = child.effect('dispose then fail', fn [mut runtime, mut child, mut source, mut fixture] () ! {
			source.get()!
			runtime.on_effect_cleanup(fn [mut source, mut fixture] () {
				fixture.cleaned++
				source.set(1) or { panic(err) }
			})!
			child.dispose()!
			source.get()! // A read after disposal must not reattach this observer.
			runtime.on_effect_cleanup(fn [mut fixture] () { fixture.cleaned++ })!
			mut rejected := false
			child.effect('resurrection', fn () ! {}) or {
				rejected = true
				assert err.msg().contains('scope is disposed')
			}
			assert rejected
			return error('failure after disposal')
		})!
	}) or {
		reported = true
		assert err.msg().contains('failure after disposal')
	}
	assert reported && child.is_disposed() && fixture.failed.is_disposed()
	assert fixture.cleaned == 2 && fixture.values == [0, 1]
	assert runtime.stats() == baseline
	source.set(2)!
	assert fixture.values == [0, 1, 2] && fixture.cleaned == 2
	parent.dispose()!
	assert runtime.stats() == SignalStats{}
}

fn test_signals_initial_failure_cleanup_feedback_uses_same_bounded_flush() ! {
	mut runtime := new_signal_runtime(max_runs_per_effect: 20, max_runs_per_flush: 4)
	mut scope := runtime.scope()!
	mut source := new_signal(mut scope, 0)!
	mut fixture := &SignalErrorLifecycleFixture{}
	mut feedback := scope.effect('cleanup feedback', fn [mut source, mut fixture] () ! {
		value := source.get()!
		fixture.values << value
		if value > 0 { source.set(value + 1)! }
	})!
	mut reported := false
	scope.effect('initial failure', fn [mut runtime, mut source, mut fixture] () ! {
		runtime.on_effect_cleanup(fn [mut source, mut fixture] () {
			fixture.cleaned++
			source.set(1) or { panic(err) }
		})!
		return error('first error')
	}) or {
		reported = true
		assert err.msg() == 'signals: `initial failure`: first error'
	}
	assert reported && feedback.is_disposed() && fixture.cleaned == 1
	// The failed initial invocation consumes one of the four flush attempts.
	assert fixture.values == [0, 1, 2, 3]
	assert source.peek()! == 4
	assert runtime.stats() == SignalStats{ signals: 1, scopes: 1 }
	scope.dispose()!
	assert fixture.cleaned == 1 && runtime.stats() == SignalStats{}
}
