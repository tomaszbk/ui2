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
}

enum SignalNodeKind {
	source
	memo
	effect
}

struct SignalDependency {
	node    &SignalNode
	version u64
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
	subscribers  []&SignalNode
	cleanups     []fn ()
	run          fn () ! = unsafe { nil }
	// Lifetime success is separate from cache validity, which retry/errors reset.
	has_succeeded bool
}

// Scopes own nodes and child scopes. Disposal releases graph edges and owned cleanup
// captures; storage is reclaimed by the normal GC, never manually freed.
@[heap]
pub struct SignalScope {
mut:
	runtime  &SignalRuntime
	parent   &SignalScope = unsafe { nil }
	alive    bool         = true
	nodes    []&SignalNode
	children []&SignalScope
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
	child := &SignalScope{ runtime: scope.runtime, parent: &scope }
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
	}
	scope.nodes << node
	match kind {
		.source { scope.runtime.counts.signals++ }
		.memo { scope.runtime.counts.memos++ }
		.effect { scope.runtime.counts.effects++ }
	}
	return node
}

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
	runtime.batch_depth++
	mut action_error := ''
	mut action_failed := false
	action() or {
		action_error = err.msg()
		action_failed = true
	}
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
	for dependency in observer.dependencies {
		if dependency.node == &source { return }
	}
	observer.dependencies << SignalDependency{ node: &source, version: source.version }
	source.subscribers << observer
	runtime.counts.subscriptions++
}

fn (mut node SignalNode) detach_dependencies() {
	for dependency in node.dependencies {
		mut source := dependency.node
		for i, subscriber in source.subscribers {
			if subscriber == &node {
				source.subscribers.delete(i)
				node.runtime.counts.subscriptions--
				break
			}
		}
	}
	node.dependencies.delete_many(0, node.dependencies.len)
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
	mut work := source.subscribers.clone()
	for work.len > 0 {
		mut node := work.pop()
		if !node.alive || node.marked == runtime.invalidation { continue }
		node.marked = runtime.invalidation
		node.stale = true
		if node.kind == .effect { runtime.enqueue(mut node) }
		work << node.subscribers
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
	previous := node.runtime.current
	previous_untracked := node.runtime.untracked_depth
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
pub fn (mut runtime SignalRuntime) flush() ! {
	runtime.require_action()!
	if runtime.batch_depth > 0 || runtime.execution_depth > 0 || runtime.flushing { return }
	runtime.flushing = true
	runtime.flush_serial++
	defer { runtime.flushing = false }
	mut first_error := ''
	mut runs := 0
	for runtime.queue.len > 0 && !runtime.closed {
		mut wave := runtime.queue.clone()
		runtime.queue.delete_many(0, runtime.queue.len)
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
	for mut subscriber in node.subscribers.clone() {
		for i, dependency in subscriber.dependencies {
			if dependency.node == &node {
				subscriber.dependencies.delete(i)
				subscriber.initialized = false
				node.runtime.counts.subscriptions--
				break
			}
		}
	}
	node.subscribers.delete_many(0, node.subscribers.len)
	node.run_cleanups()
	node.run = unsafe { nil }
	match node.kind {
		.source { node.runtime.counts.signals-- }
		.memo { node.runtime.counts.memos-- }
		.effect { node.runtime.counts.effects-- }
	}
	for i, owned in node.scope.nodes {
		if owned == &node {
			node.scope.nodes.delete(i)
			break
		}
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
	children := scope.children.clone()
	for i := children.len - 1; i >= 0; i-- {
		mut child := children[i]
		child.dispose_scope()
	}
	nodes := scope.nodes.clone()
	for i := nodes.len - 1; i >= 0; i-- {
		mut node := nodes[i]
		node.dispose_node()
	}
	cleanups := scope.cleanups.clone()
	scope.cleanups.delete_many(0, scope.cleanups.len)
	scope.runtime.counts.cleanups -= cleanups.len
	scope.runtime.untracked_depth++
	for i := cleanups.len - 1; i >= 0; i-- { cleanups[i]() }
	scope.runtime.untracked_depth--
	scope.runtime.counts.scopes--
	if scope.parent != unsafe { nil } {
		for i, child in scope.parent.children {
			if child == &scope {
				scope.parent.children.delete(i)
				break
			}
		}
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
