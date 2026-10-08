module ui2

@[params]
pub struct SignalOptions[T] {
pub:
	name   string
	equals fn (T, T) bool = unsafe { nil }
}

@[heap]
pub struct Signal[T] {
	equals fn (T, T) bool = unsafe { nil }
mut:
	node  &SignalNode
	value T
}

@[heap]
pub struct Memo[T] {
	equals fn (T, T) bool = unsafe { nil }
mut:
	node  &SignalNode
	value T
}

// Scalar value equality; all NaNs compare equal and signed zeros compare equal.
// Pointers compare identity. Arrays, maps, structs and other compound values
// always count as changed: there is no implicit recursive comparison.
fn signal_default_equals[T](left T, right T) bool {
	$if T is $pointer {
		return voidptr(left) == voidptr(right)
	} $else $if T is $float {
		return left == right || (left != left && right != right)
	} $else $if T is $int || T is bool || T is string || T is $enum {
		return left == right
	} $else {
		return false
	}
}

pub fn new_signal[T](mut scope SignalScope, value T, options SignalOptions[T]) !&Signal[T] {
	mut node := scope.new_node(.source, options.name)!
	node.stale = false
	node.initialized = true
	return &Signal[T]{
		node:   node
		value:  value
		equals: if options.equals == unsafe { nil } {
			signal_default_equals[T]
		} else {
			options.equals
		}
	}
}

pub fn (mut signal Signal[T]) get() !T {
	signal.node.require_alive()!
	signal.node.runtime.track(mut signal.node)
	return signal.value
}

pub fn (signal &Signal[T]) peek() !T {
	signal.node.require_alive()!
	return signal.value
}

// Returns whether equality changed. A flush error does not roll back the write.
pub fn (mut signal Signal[T]) set(value T) !bool {
	signal.node.require_alive()!
	signal.node.runtime.require_action()!
	equal := signal.node.runtime.values_equal[T](signal.equals, signal.value, value)
	if equal { return false }
	signal.value = value
	signal.node.version++
	signal.node.runtime.invalidate(signal.node)
	signal.node.runtime.flush_if_ready()!
	return true
}

pub fn new_memo[T](mut scope SignalScope, compute fn () !T, options SignalOptions[T]) !&Memo[T] {
	if compute == unsafe { nil } { return error('signals: memo callback is nil') }
	mut node := scope.new_node(.memo, options.name)!
	mut memo := &Memo[T]{
		node:   node
		equals: if options.equals == unsafe { nil } {
			signal_default_equals[T]
		} else {
			options.equals
		}
	}
	node.run = fn [mut memo, compute] [T]() ! {
		value := compute()!
		memo.node.require_alive()!
		if !memo.node.initialized || !memo.node.runtime.values_equal[T](memo.equals, memo.value, value) {
			memo.value = value
			memo.node.version++
		}
	}
	return memo
}

pub fn (mut memo Memo[T]) get() !T {
	memo.node.refresh() or {
		if memo.node.alive { memo.node.runtime.track(mut memo.node) }
		return err
	}
	memo.node.runtime.track(mut memo.node)
	return memo.value
}

pub fn (mut memo Memo[T]) peek() !T {
	memo.node.refresh()!
	return memo.value
}
