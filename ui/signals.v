module ui2

// A runtime belongs to one thread. It has no renderer dependency or internal
// locks; workers must deliver changes to its owner (for UI, via UiDispatcher).
@[params]
pub struct SignalRuntimeConfig {
pub:
	max_runs_per_effect int = 100
	max_runs_per_flush  int = 10000
	max_memo_depth      int = 256
}

pub struct SignalStats {
pub mut:
	signals       int
	memos         int
	effects       int
	scopes        int
	subscriptions int
	cleanups      int
	pending       int
}

@[heap]
pub struct SignalRuntime {
	config SignalRuntimeConfig
mut:
	roots            []&SignalScope
	queue            []&SignalNode
	current          &SignalNode = unsafe { nil }
	stack            []&SignalNode
	untracked_depth  int
	batch_depth      int
	execution_depth  int
	flushing         bool
	closed           bool
	closing          bool
	comparison_depth int
	next_id          int
	flush_serial     u64
	invalidation     u64
	counts           SignalStats
	// Reused traversal and wave buffers keep steady-state notification free of
	// temporary arrays. Each is owned by exactly one non-reentrant operation.
	invalidation_work []&SignalNode
	queue_spare       []&SignalNode
	run_serial        u64
	// A consumer that coalesces its own derived state (compiled VML child
	// projections) settles it at a flush boundary, before effects observe it.
	settle         fn () ! = unsafe { nil }
	settle_pending bool
}

enum SignalNodeKind {
	source
	memo
	effect
}

struct SignalDependency {
	node    &SignalNode
	version u64
mut:
	// Index of the observer's entry in node.subscribers.
	slot int
}

// A released subscription leaves an empty slot, so the remaining subscribers
// keep their registration order (invalidation order is observable) while
// unsubscription stays O(1). Slots are compacted once most are empty.
struct SignalSubscriber {
mut:
	node       &SignalNode = unsafe { nil }
	dependency int // index of this edge in node.dependencies
}

@[heap]
struct SignalNode {
	id   int
	name string
	kind SignalNodeKind
mut:
	runtime      &SignalRuntime
	scope        &SignalScope
	alive        bool = true
	initialized  bool
	stale        bool = true
	running      bool
	queued       bool
	version      u64
	marked       u64
	flush_serial u64
	flush_runs   int
	dependencies []SignalDependency
	subscribers  []SignalSubscriber
	released     int // empty subscriber slots
	cleanups     []fn ()
	run          fn () ! = unsafe { nil }
	// Lifetime success is separate from cache validity, which retry/errors reset.
	has_succeeded bool
	scope_slot    int // index in scope.nodes
	// The last observer run that tracked this source. While that run has not
	// been interleaved with a nested run, a matching stamp proves the edge
	// exists and a mismatch proves it does not, without scanning dependencies.
	track_observer &SignalNode = unsafe { nil }
	track_serial   u64
	run_serial     u64
	interleaved    bool
}

// Scopes own nodes and child scopes. Disposal releases graph edges and owned cleanup
// captures; storage is reclaimed by the normal GC, never manually freed.
@[heap]
pub struct SignalScope {
mut:
	runtime  &SignalRuntime
	parent   &SignalScope = unsafe { nil }
	alive    bool         = true
	// Disposed members leave nil slots (compacted lazily), so removal is O(1)
	// and teardown keeps reverse creation order.
	nodes          []&SignalNode
	released_nodes int
	children       []&SignalScope
	released_children int
	parent_slot    int
	cleanups []fn ()
}

@[heap]
pub struct SignalEffect {
mut:
	node &SignalNode
}

pub fn new_signal_runtime(config SignalRuntimeConfig) &SignalRuntime {
	return &SignalRuntime{
		config: SignalRuntimeConfig{
			max_runs_per_effect: if config.max_runs_per_effect > 0 {
				config.max_runs_per_effect
			} else {
				100
			}
			max_runs_per_flush:  if config.max_runs_per_flush > 0 {
				config.max_runs_per_flush
			} else {
				10000
			}
			max_memo_depth:      if config.max_memo_depth > 0 { config.max_memo_depth } else { 256 }
		}
	}
}

pub fn (runtime &SignalRuntime) stats() SignalStats {
	return SignalStats{
		signals:       runtime.counts.signals
		memos:         runtime.counts.memos
		effects:       runtime.counts.effects
		scopes:        runtime.counts.scopes
		subscriptions: runtime.counts.subscriptions
		cleanups:      runtime.counts.cleanups
		pending:       runtime.counts.pending
	}
}

pub fn (runtime &SignalRuntime) is_disposed() bool { return runtime.closed }

pub fn (scope &SignalScope) is_disposed() bool { return !scope.alive }

fn (runtime &SignalRuntime) require_open() ! {
	if runtime.closed { return error('signals: runtime is disposed') }
}

fn (runtime &SignalRuntime) require_action() ! {
	runtime.require_open()!
	if runtime.comparison_depth > 0 {
		return error('signals: equality callbacks must be pure (reads only)')
	}
	for node in runtime.stack {
		if node.kind == .memo {
			return error('signals: memo `${node.name}` must be pure (reads only)')
		}
	}
}

fn (runtime &SignalRuntime) require_create() ! {
	runtime.require_action()!
	if runtime.closing { return error('signals: runtime is disposing') }
}

pub fn (mut runtime SignalRuntime) scope() !&SignalScope {
	runtime.require_create()!
	mut scope := &SignalScope{ runtime: &runtime }
	runtime.roots << scope
	runtime.counts.scopes++
	return scope
}

pub fn (mut scope SignalScope) child() !&SignalScope {
	scope.require_alive()!
	scope.runtime.require_create()!
	child := &SignalScope{ runtime: scope.runtime, parent: &scope, parent_slot: scope.children.len }
	scope.children << child
	scope.runtime.counts.scopes++
	return child
}

fn (scope &SignalScope) require_alive() ! {
	scope.runtime.require_open()!
	if !scope.alive { return error('signals: scope is disposed') }
}

fn (mut scope SignalScope) new_node(kind SignalNodeKind, name string) !&SignalNode {
	scope.require_alive()!
	scope.runtime.require_create()!
	scope.runtime.next_id++
	node := &SignalNode{
		id:      scope.runtime.next_id
		name:    if name.len > 0 { name } else { '${kind}#${scope.runtime.next_id}' }
		kind:    kind
		runtime: scope.runtime
		scope:   &scope
		scope_slot: scope.nodes.len
	}
	scope.nodes << node
	match kind {
		.source { scope.runtime.counts.signals++ }
		.memo { scope.runtime.counts.memos++ }
		.effect { scope.runtime.counts.effects++ }
	}
	return node
}

// Scope teardown first closes the scope and disposes its children. Cleanup runs
// untracked while this scope's state and memos are still readable, before its
// own nodes are disposed. New work and callbacks are blocked by the closed scope.
pub fn (mut scope SignalScope) on_cleanup(cleanup fn ()) ! {
	scope.require_alive()!
	scope.runtime.require_action()!
	if cleanup == unsafe { nil } { return error('signals: cleanup callback is nil') }
	scope.cleanups << cleanup
	scope.runtime.counts.cleanups++
}

// Register cleanup for this effect invocation. It runs untracked, before the
// next invocation or on disposal, in reverse registration order, exactly once.
pub fn (mut runtime SignalRuntime) on_effect_cleanup(cleanup fn ()) ! {
	if cleanup == unsafe { nil } { return error('signals: cleanup callback is nil') }
	mut node := runtime.current
	if node == unsafe { nil } || node.kind != .effect || !node.running {
		return error('signals: cleanup requires a running effect')
	}
	if !node.alive {
		runtime.untracked_depth++
		cleanup()
		runtime.untracked_depth--
		return
	}
	runtime.require_create()!
	node.cleanups << cleanup
	runtime.counts.cleanups++
}

// Effects run immediately outside a batch, or at its outer boundary. Callback
// errors are returned to the triggering caller, after other queued effects run.
pub fn (mut scope SignalScope) effect(name string, run fn () !) !&SignalEffect {
	if run == unsafe { nil } { return error('signals: effect callback is nil') }
	mut node := scope.new_node(.effect, name)!
	node.run = run
	scope.runtime.enqueue(mut node)
	scope.runtime.flush_if_ready()!
	return &SignalEffect{ node: node }
}

// effect_now creates an effect and runs it synchronously, also inside a batch,
// a flush or another effect, so its first values are available to the caller
// right away. Later runs follow the ordinary effect schedule. A failing first
// run disposes the effect and returns the error.
fn (mut scope SignalScope) effect_now(name string, run fn () !) ! {
	if run == unsafe { nil } { return error('signals: effect callback is nil') }
	mut node := scope.new_node(.effect, name)!
	node.run = run
	node.refresh() or {
		node.dispose_node()
		return err
	}
}

pub fn (mut effect SignalEffect) retry() ! {
	effect.node.require_alive()!
	effect.node.runtime.require_action()!
	effect.node.initialized = false
	effect.node.stale = true
	effect.node.runtime.enqueue(mut effect.node)
	effect.node.runtime.flush_if_ready()!
}

pub fn (effect &SignalEffect) is_disposed() bool { return !effect.node.alive }

pub fn (mut effect SignalEffect) dispose() ! {
	if !effect.node.alive { return }
	effect.node.runtime.require_action()!
	effect.node.dispose_node()
	effect.node.runtime.flush_if_ready()!
}

fn (mut runtime SignalRuntime) values_equal[T](equals fn (T, T) bool, left T, right T) bool {
	runtime.comparison_depth++
	runtime.untracked_depth++
	defer {
		runtime.untracked_depth--
		runtime.comparison_depth--
	}
	return equals(left, right)
}

// Source writes commit immediately. Effects wait for the outermost batch,
// including on an error; a batch is notification coalescing, not rollback.
pub fn (mut runtime SignalRuntime) batch(action fn () !) ! {
	runtime.require_action()!
	if action == unsafe { nil } { return error('signals: batch callback is nil') }
	runtime.begin_batch()!
	mut action_error := ''
	mut action_failed := false
	action() or {
		action_error = err.msg()
		action_failed = true
	}
	runtime.finish_batch(action_failed, action_error)!
}

// Internal synchronous publishers can enter a batch without constructing a
// temporary closure. They share the same error/flush contract as public batch.
fn (mut runtime SignalRuntime) begin_batch() ! {
	runtime.require_action()!
	runtime.batch_depth++
}

fn (mut runtime SignalRuntime) finish_batch(action_failed bool, action_error string) ! {
	runtime.batch_depth--
	mut flush_error := ''
	runtime.flush_if_ready() or { flush_error = err.msg() }
	if action_failed {
		return error(action_error + if flush_error != '' { '; ' + flush_error } else { '' })
	}
	if flush_error != '' { return error(flush_error) }
}

// Suppress reads made directly by action. A memo evaluated by action still
// tracks its own dependencies, so an untracked pull never breaks its cache.
pub fn (mut runtime SignalRuntime) untracked(action fn () !) ! {
	runtime.require_open()!
	if action == unsafe { nil } { return error('signals: untracked callback is nil') }
	runtime.untracked_depth++
	defer { runtime.untracked_depth-- }
	action()!
}

fn (node &SignalNode) require_alive() ! {
	node.runtime.require_open()!
	if !node.alive { return error('signals: `${node.name}` is disposed') }
}

fn (mut runtime SignalRuntime) track(mut source SignalNode) {
	mut observer := runtime.current
	if runtime.untracked_depth > 0 || observer == unsafe { nil } || !observer.alive { return }
	if source.track_observer == observer && source.track_serial == observer.run_serial { return }
	if observer.interleaved {
		for dependency in observer.dependencies {
			if dependency.node == &source { return }
		}
	}
	source.track_observer = observer
	source.track_serial = observer.run_serial
	observer.dependencies << SignalDependency{ node: &source, version: source.version, slot: source.subscribers.len }
	source.subscribers << SignalSubscriber{ node: observer, dependency: observer.dependencies.len - 1 }
	runtime.counts.subscriptions++
}

fn (mut source SignalNode) release_subscriber(slot int) {
	source.subscribers[slot] = SignalSubscriber{}
	source.released++
	if source.released == source.subscribers.len {
		source.subscribers.clear()
		source.released = 0
	} else if source.released >= 16 && source.released * 2 > source.subscribers.len {
		source.compact_subscribers()
	}
}

fn (mut source SignalNode) compact_subscribers() {
	mut write := 0
	for read in 0 .. source.subscribers.len {
		entry := source.subscribers[read]
		if entry.node == unsafe { nil } { continue }
		if write != read {
			source.subscribers[write] = entry
			mut observer := entry.node
			observer.dependencies[entry.dependency].slot = write
		}
		write++
	}
	source.subscribers.trim(write)
	source.released = 0
}

fn (mut node SignalNode) detach_dependencies() {
	for dependency in node.dependencies {
		mut source := dependency.node
		source.release_subscriber(dependency.slot)
		node.runtime.counts.subscriptions--
	}
	node.dependencies.clear()
}

fn (mut runtime SignalRuntime) enqueue(mut node SignalNode) {
	if node.alive && !node.queued {
		node.queued = true
		runtime.counts.pending++
		runtime.queue << &node
	}
}

// Mark the entire downstream graph before executing any callback. Invalidation
// is iterative and visits each node once, including diamonds and feedback.
fn (mut runtime SignalRuntime) invalidate(source &SignalNode) {
	runtime.invalidation++
	runtime.invalidation_work.clear()
	for entry in source.subscribers {
		if entry.node != unsafe { nil } { runtime.invalidation_work << entry.node }
	}
	for runtime.invalidation_work.len > 0 {
		mut node := runtime.invalidation_work.pop()
		if !node.alive || node.marked == runtime.invalidation { continue }
		node.marked = runtime.invalidation
		node.stale = true
		if node.kind == .effect { runtime.enqueue(mut node) }
		for entry in node.subscribers {
			if entry.node != unsafe { nil } { runtime.invalidation_work << entry.node }
		}
	}
}

fn (mut node SignalNode) dependencies_changed() !bool {
	for dependency in node.dependencies {
		mut source := dependency.node
		source.require_alive()!
		if source.kind == .memo {
			// An observer may handle a failed pull with `or { fallback }`.
			// Give its callback that opportunity instead of throwing while
			// validating the previous dependency versions.
			source.refresh() or { return true }
		}
		if source.version != dependency.version { return true }
	}
	return false
}

fn (mut node SignalNode) run_cleanups() {
	cleanups := node.cleanups.clone()
	node.cleanups.delete_many(0, node.cleanups.len)
	node.runtime.counts.cleanups -= cleanups.len
	// Prevent nested flushes and accidental subscriptions from cleanup reads.
	node.runtime.execution_depth++
	node.runtime.untracked_depth++
	for i := cleanups.len - 1; i >= 0; i-- { cleanups[i]() }
	node.runtime.untracked_depth--
	node.runtime.execution_depth--
}

fn (runtime &SignalRuntime) trace(next &SignalNode) string {
	mut names := []string{}
	for node in runtime.stack { names << node.name }
	names << next.name
	return names.join(' -> ')
}

fn (mut node SignalNode) refresh() ! {
	node.require_alive()!
	if node.running { return error('signals: dependency cycle: ${node.runtime.trace(&node)}') }
	if !node.stale { return }
	if node.runtime.stack.len >= node.runtime.config.max_memo_depth {
		return error('signals: evaluation depth exceeded: ${node.runtime.trace(&node)}')
	}
	// Include dependency validation in the cycle guard: stale memo cycles can
	// otherwise recurse before entering the compute callback.
	node.running = true
	node.runtime.stack << &node
	defer {
		node.running = false
		node.runtime.stack.delete_last()
	}
	if node.initialized && !node.dependencies_changed()! {
		node.stale = false
		return
	}
	node.detach_dependencies()
	node.run_cleanups()
	if !node.alive { return }
	mut previous := node.runtime.current
	previous_untracked := node.runtime.untracked_depth
	if previous != unsafe { nil } { previous.interleaved = true }
	node.runtime.run_serial++
	node.run_serial = node.runtime.run_serial
	node.interleaved = false
	node.runtime.current = &node
	node.runtime.untracked_depth = 0
	node.runtime.execution_depth++
	defer {
		node.runtime.current = previous
		node.runtime.untracked_depth = previous_untracked
		node.runtime.execution_depth--
	}
	node.stale = false
	node.run() or {
		node.stale = true
		node.initialized = false
		return error('signals: `${node.name}`: ${err.msg()}')
	}
	if node.alive {
		node.initialized = true
		node.has_succeeded = true
	}
}

fn (mut runtime SignalRuntime) flush_if_ready() ! {
	if runtime.batch_depth == 0 && runtime.execution_depth == 0 && !runtime.flushing && !runtime.closed {
		runtime.flush()!
	}
}

// Drain detached waves; writes during a callback queue another wave rather than
// recurse. A feedback offender is disposed, and unrelated effects still run.
// Deferred consumer state settles before each wave, so the effects it notifies
// run in the next wave exactly as if it had been updated eagerly.
pub fn (mut runtime SignalRuntime) flush() ! {
	runtime.require_action()!
	if runtime.batch_depth > 0 || runtime.execution_depth > 0 || runtime.flushing { return }
	runtime.flushing = true
	runtime.flush_serial++
	defer { runtime.flushing = false }
	mut first_error := ''
	mut runs := 0
	for !runtime.closed {
		if runtime.settle_pending {
			runtime.settle_pending = false
			if runtime.settle != unsafe { nil } {
				runtime.settle() or {
					if first_error == '' { first_error = err.msg() }
				}
			}
			continue
		}
		if runtime.queue.len == 0 { break }
		// Swap the two queue buffers: callbacks append the next wave to the
		// other one, and neither is reallocated once it has grown.
		mut wave := unsafe { runtime.queue }
		runtime.queue = unsafe { runtime.queue_spare }
		runtime.queue.clear()
		for mut node in wave {
			if node.queued { runtime.counts.pending-- }
			node.queued = false
			if !node.alive { continue }
			if node.flush_serial != runtime.flush_serial {
				node.flush_serial = runtime.flush_serial
				node.flush_runs = 0
			}
			node.flush_runs++
			runs++
			if node.flush_runs > runtime.config.max_runs_per_effect || runs > runtime.config.max_runs_per_flush {
				if first_error == '' {
					first_error = 'signals: feedback limit exceeded in effect `${node.name}` (node ${node.id})'
				}
				node.dispose_node()
				continue
			}
			node.refresh() or {
				if first_error == '' { first_error = err.msg() }
				// Initial failure belongs to this node, even when creation was
				// deferred. Dispose inside the flush so cleanup writes join later
				// waves under the same budget. Successful nodes survive other
				// nodes' errors and their own later failures, including retry().
				if !node.has_succeeded { node.dispose_node() }
			}
		}
		wave.clear()
		runtime.queue_spare = unsafe { wave }
	}
	if first_error != '' { return error(first_error) }
}

fn (mut node SignalNode) dispose_node() {
	if !node.alive { return }
	node.alive = false
	if node.queued { node.runtime.counts.pending-- }
	node.queued = false
	node.detach_dependencies()
	// A surviving consumer will report a disposed dependency on its next pull.
	node.runtime.invalidate(&node)
	for entry in node.subscribers {
		if entry.node == unsafe { nil } { continue }
		mut subscriber := entry.node
		index := entry.dependency
		subscriber.dependencies.delete(index)
		// Later edges shift down; their sources address them by index.
		for j in index .. subscriber.dependencies.len {
			dependency := subscriber.dependencies[j]
			mut source := dependency.node
			source.subscribers[dependency.slot].dependency = j
		}
		subscriber.initialized = false
		node.runtime.counts.subscriptions--
	}
	node.subscribers.clear()
	node.released = 0
	node.run_cleanups()
	node.run = unsafe { nil }
	match node.kind {
		.source { node.runtime.counts.signals-- }
		.memo { node.runtime.counts.memos-- }
		.effect { node.runtime.counts.effects-- }
	}
	// A scope being disposed releases its whole member list at once.
	if node.scope.alive { node.scope.release_node(node.scope_slot) }
}

fn (mut scope SignalScope) release_node(slot int) {
	scope.nodes[slot] = unsafe { nil }
	scope.released_nodes++
	if scope.released_nodes == scope.nodes.len {
		scope.nodes.clear()
		scope.released_nodes = 0
	} else if scope.released_nodes >= 16 && scope.released_nodes * 2 > scope.nodes.len {
		mut write := 0
		for read in 0 .. scope.nodes.len {
			mut member := scope.nodes[read]
			if member == unsafe { nil } { continue }
			scope.nodes[write] = member
			member.scope_slot = write
			write++
		}
		scope.nodes.trim(write)
		scope.released_nodes = 0
	}
}

fn (mut scope SignalScope) release_child(slot int) {
	scope.children[slot] = unsafe { nil }
	scope.released_children++
	if scope.released_children == scope.children.len {
		scope.children.clear()
		scope.released_children = 0
	} else if scope.released_children >= 16 && scope.released_children * 2 > scope.children.len {
		mut write := 0
		for read in 0 .. scope.children.len {
			mut child := scope.children[read]
			if child == unsafe { nil } { continue }
			scope.children[write] = child
			child.parent_slot = write
			write++
		}
		scope.children.trim(write)
		scope.released_children = 0
	}
}

pub fn (mut scope SignalScope) dispose() ! {
	if !scope.alive { return }
	scope.runtime.require_action()!
	scope.runtime.execution_depth++
	scope.dispose_scope()
	scope.runtime.execution_depth--
	scope.runtime.flush_if_ready()!
}

fn (mut scope SignalScope) dispose_scope() {
	if !scope.alive { return }
	scope.alive = false
	// Members of a closed scope do not unlink themselves, so these lists stay
	// stable while they are torn down and are released together afterwards.
	for i := scope.children.len - 1; i >= 0; i-- {
		mut child := scope.children[i]
		if child != unsafe { nil } { child.dispose_scope() }
	}
	scope.children.clear()
	scope.released_children = 0
	cleanups := scope.cleanups.clone()
	scope.cleanups.delete_many(0, scope.cleanups.len)
	scope.runtime.counts.cleanups -= cleanups.len
	scope.runtime.untracked_depth++
	for i := cleanups.len - 1; i >= 0; i-- { cleanups[i]() }
	scope.runtime.untracked_depth--
	for i := scope.nodes.len - 1; i >= 0; i-- {
		mut node := scope.nodes[i]
		if node != unsafe { nil } { node.dispose_node() }
	}
	scope.nodes.clear()
	scope.released_nodes = 0
	scope.runtime.counts.scopes--
	if scope.parent != unsafe { nil } {
		if scope.parent.alive { scope.parent.release_child(scope.parent_slot) }
	} else {
		for i, root in scope.runtime.roots {
			if root == &scope {
				scope.runtime.roots.delete(i)
				break
			}
		}
	}
}

pub fn (mut runtime SignalRuntime) dispose() ! {
	if runtime.closed { return }
	runtime.require_action()!
	if runtime.closing { return }
	runtime.closing = true
	runtime.execution_depth++
	for mut scope in runtime.roots.clone() { scope.dispose_scope() }
	runtime.execution_depth--
	runtime.queue.delete_many(0, runtime.queue.len)
	runtime.closed = true
	runtime.closing = false
}
