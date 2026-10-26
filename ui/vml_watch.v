module ui2

// Watches, unwrapped options and optional inputs of compiled and interpreted VML.

@[heap]
struct VmlWatchState[T] {
mut:
	started bool
	last    T
}

// watch runs `action(old, now)` each time the value `read` returns changes
// (by `==`): `watch old, now := value { ... }` in a component. The first
// value is recorded without running the action. `read` is tracked like any
// effect; the action runs untracked, as one UI action.
pub fn (mut component CompiledVmlComponent) watch[T](name string, read fn () !T, action fn (T, T) !) ! {
	component.watch_by[T](name, read, action, fn [T](a T, b T) bool {
		return a == b
	})!
}

// watch_by is watch with an equality of its own.
pub fn (mut component CompiledVmlComponent) watch_by[T](name string, read fn () !T, action fn (T, T) !, equals fn (T, T) bool) ! {
	component.require_alive()!
	if read == unsafe { nil } || action == unsafe { nil } {
		return error('compiled VML watch `${name}` requires read and action callbacks')
	}
	mut state := &VmlWatchState[T]{}
	owner := &component
	component.scope.effect('@watch:' + name, fn [owner, mut state, read, action, equals] [T]() ! {
		now := read()!
		if !state.started {
			state.started = true
			state.last = now
			return
		}
		if equals(state.last, now) { return }
		old := state.last
		state.last = now
		if owner.is_disposed() || owner.is_leaving() { return }
		mut runtime := owner.runtime
		runtime.untracked(fn [owner, action, old, now] [T]() ! {
			mut actions := owner.runtime
			actions.batch(fn [owner, action, old, now] [T]() ! {
				action(old, now)!
				owner.invalidate_app()!
			})!
		})!
	})!
}

// vml_unwrapped is the value of `if name := option` while its branch shows:
// it starts as the option's value, follows it, and keeps its last value when
// the option becomes none (the branch is leaving then).
pub fn vml_unwrapped[T](mut owner CompiledVmlComponent, initial ?T, read fn () ?T) !&Signal[T] {
	first := initial or { return error('VML `if name := value` read none') }
	mut signal := owner.state[T]('@unwrapped', first)!
	owner.scope.effect('@unwrapped', fn [read, mut signal] [T]() ! {
		if value := read() {
			signal.set(value)!
		}
	})!
	return signal
}

// VmlOption is a component input of an optional type `?T`: V keeps no
// signals or results of options, so the input holds this instead and VML
// reads it back as `?T`.
pub struct VmlOption[T] {
pub:
	value T
	some  bool
}

// vml_option stores an optional value as a VmlOption.
pub fn vml_option[T](value ?T) VmlOption[T] {
	if v := value {
		return VmlOption[T]{
			value: v
			some:  true
		}
	}
	return VmlOption[T]{}
}

// option is the stored optional value.
pub fn (o VmlOption[T]) option() ?T {
	if o.some {
		return o.value
	}
	return none
}
