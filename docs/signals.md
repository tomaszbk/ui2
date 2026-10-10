# Signals core

`Signal[T]`, `Memo[T]` and effects form a typed, window-independent reactive
graph. Use the normal GC. Every graph has an explicit `SignalRuntime` and
lifetime scopes; no global tracking state, timer or renderer is required.

```v
import ui2

mut runtime := ui2.new_signal_runtime()
mut scope := runtime.scope()!
defer { runtime.dispose() or { eprintln(err) } }

mut count := ui2.new_signal(mut scope, 1, name: 'count')!
mut doubled := ui2.new_memo(mut scope, fn [mut count] () !int {
    return count.get()! * 2
}, name: 'doubled')!

scope.effect('print', fn [mut doubled] () ! {
    println(doubled.get()!)
})! // prints 2

runtime.batch(fn [mut count, mut doubled] () ! {
    count.set(2)!
    assert doubled.get()! == 4
    count.set(3)!
})! // prints 6 once
```

## API

| Operation | Contract |
| --- | --- |
| `new_signal(mut scope, initial, name: 'x') !&Signal[T]` | Own a typed source in this scope. |
| `signal.get() !T` | Read and subscribe the currently evaluating memo/effect. |
| `signal.peek() !T` | Read without subscribing. |
| `signal.set(value) !bool` | Commit a changed value, invalidate and flush when allowed; return false for equal writes. |
| `new_memo(mut scope, compute, name: 'x') !&Memo[T]` | Own a lazy computed value. `compute` is `fn () !T` and must be pure. |
| `memo.get() !T` / `memo.peek() !T` | Pull an up-to-date cached value, with/without subscribing the caller. |
| `scope.effect(name, callback) !&SignalEffect` | Own an integration effect (`fn () !`). Initial execution waits for an enclosing batch, otherwise runs synchronously. |
| `runtime.batch(action) !` | Defer effects until the outermost batch exits. |
| `runtime.untracked(action) !` | Suppress subscriptions from direct reads in action (`fn () !`). |
| `runtime.on_effect_cleanup(fn () { ... }) !` | Register cleanup for the current effect invocation. |
| `runtime.scope() !&SignalScope` / `scope.child() !&SignalScope` | Create an independently disposable lifetime or a child owned by its parent. |
| `scope.on_cleanup(fn () { ... }) !` | Register lifetime cleanup. |
| `effect.dispose() !` / `scope.dispose() !` / `runtime.dispose() !` | Idempotently release owned effects, subscriptions and cleanup resources. |
| `effect.retry() !` | Explicitly rerun a surviving effect after a callback error. |
| `effect.is_disposed() bool` / `scope.is_disposed() bool` / `runtime.is_disposed() bool` | Observe whether its lifetime ended. |
| `runtime.flush() !` | Drain queued effects when outside an action/batch/flush; normally automatic. |
| `runtime.stats() SignalStats` | Snapshot active sources, memos, effects, scopes, edges, cleanup callbacks and pending effects. |

Specify `SignalOptions[T].equals` for an application-specific pure comparator
(`fn (T, T) bool`). The same options apply to sources and memos. Names appear
in diagnostics; absent names get a kind and runtime-local node number.

## Equality and observable writes

The default policy has no hidden recursive model comparison:

| Value | Equal when |
| --- | --- |
| Booleans, integers, enums, strings | V value equality holds. Strings compare their contents. |
| `f32` / `f64` | V numeric equality holds, or both are NaN. Positive/negative zero are equal; equal infinities are equal. |
| Pointers, including pointers to objects | Pointer identity matches. Mutating the pointed-to object does not notify. |
| Arrays, fixed arrays, maps, structs, interfaces, sum/optional values and other compounds | Never by default: every setter call counts as a change. |

An equal write keeps the old stored value and does not invalidate dependents.
A memo whose refreshed result is equal keeps its old value/version; consumers
that read only that memo skip their callback. Equality callbacks execute
untracked and cannot write/create/dispose graph resources. Opt into a specific
comparison only when its cost and meaning suit the application.

Reads and writes follow V's value/reference semantics, without deep copying or
watching mutations through aliases. Treat reactive values as immutable snapshots:
for collections, build a replacement (for example using `.clone()`) and call
`set`; for mutable objects, use explicit signals for observable fields. Normal
assignments such as `app.count++` on an ordinary `int` do **not** notify signals.
Compiled VML lowers `state` writes to signal setters and batches handlers;
application fields used by VML are refreshed after actions or an explicit
`ui2.request_refresh()`. See [compiled components](vml-components.md).

## Transactions and dependency tracking

Writes commit immediately. Later reads in the same batch see them, including
dirty memos. Nested batches flush once at the outer boundary. A batch is not
rollback: if action returns an error, its committed writes still flush before
the error returns. If action and flush both fail, the returned message contains
both failures.

Invalidation first marks the entire downstream graph, then effects pull the
memos they need. Pulling checks upstream versions and refreshes dirty values
before returning them. A diamond therefore exposes a coherent result, and
unused memos never evaluate. Dependencies are recorded afresh on each callback;
branches no longer read lose their subscriptions. Reading an untracked memo
still refreshes and tracks **its own** dependencies, while the caller does not
subscribe to it. Graphs are separate tracking domains; reactive dependencies
must share one runtime.

Effects run synchronously in detached scheduling waves. A write or a newly
created effect inside a callback queues subsequent work; it never recursively
invokes another effect. Do not depend on sibling effect ordering. Derive values
with memos rather than effects that maintain another copy of state. There is
no geometry/post-mount effect phase here: these callbacks are integration
effects, without a promise that layout or painting has finished.

## Lifetime, errors and ownership

Scopes dispose child scopes first, then nodes in reverse creation order, then
their own cleanups. Cleanup callbacks run once in reverse registration order,
untracked and outside locks. Effect cleanups run before the next invocation or
on disposal, including failed invocations. Register captured values/resources
in the callback rather than trying to read already disposed sources during
teardown. Disposing an effect/scope during its own callback immediately removes
its edges; subsequent reads do not resurrect the observer, queued disposed
effects are skipped, and newly registered invocation cleanup runs immediately.

Dispose short-lived observers before their sources. Surviving consumers of a
disposed source receive a diagnostic when pulled/executed. Disposed source/memo
reads and new resources in closed scopes/runtimes return errors. The runtime
holds active scopes strongly: GC is not a replacement for explicit teardown.
`stats()` returns to its baseline after teardown; these are active graph
resources, not reserved allocator bytes or measured GC collections.

Memo cycles include the evaluation path in an error. Writes and resource
creation/disposal inside a memo are rejected. Reentrant effect feedback is
bounded by `SignalRuntimeConfig` (100 scheduling attempts per effect, 10,000 per flush,
256 nested evaluations by default); an offender is disposed with a named
diagnostic, while remaining queued effects drain within the total budget.
Effects exceeding the total budget are also disposed. Limits are configurable for
large graphs. Recursive memo evaluation has a depth diagnostic as well.

Callbacks may return V `Result` errors. Tracking, batch and flush context is
restored on these errors; other queued effects still run. A failed initial
effect is disposed, while a later failed effect can recover on a dependency
change or via `retry()`. Failed memos remain dirty and retry on pull. Source
writes remain committed if their effect flush fails. Observers can handle memo
errors with `or { fallback }` and remain subscribed for recovery; dependency
validation does not bypass their error handler. Cleanup callbacks are
infallible `fn ()`; handle failures of external cleanup operations there. V
panics/process termination are not recoverable callback errors.

Every runtime and all its handles belong to a single owner thread. There are
no internal locks and no worker mutation API. A UI worker should post a batched
action through `UiDispatcher` to that thread, checking `scope.is_disposed()` there before
accessing its sources. Different runtimes can be owned by different threads
when their state and callbacks are independent.

## UI integration example

Run `v run examples/signals` or `v -d ui2_custom_rendering run examples/signals`.
The batch button makes three writes but records one coherent observation;
toggling the bonus removes/adds that branch's dependency. The editable Spanish
text retains the same id/declaration across updates, so existing renderer
contracts preserve local edits, selection, focus and composition.

The example's effect requests a declarative refresh. Compiled VML uses this
same signal graph to own component scopes, lower state and computed declarations,
batch actions, patch retained properties and reconcile repeaters by key. See
[compiled VML components](vml-components.md). The signal graph is independently
testable with no window or clock; performance requires separate measurements.
