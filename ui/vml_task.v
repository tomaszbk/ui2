module ui2

import sync

// Workers carry this cancellation handle rather than reading a UI-thread scope.
// Cancellation prevents delivery; application side effects already performed by
// the worker remain the worker's responsibility.
@[heap]
pub struct VmlTask {
	owner &CompiledVmlComponent
mut:
	mutex     &sync.Mutex = sync.new_mutex()
	cancelled bool
}

pub fn (mut component CompiledVmlComponent) task(name string) !&VmlTask {
	component.require_alive()!
	key := 'task:' + name
	if value := component.values[key] { return unsafe { &VmlTask(value) } }
	mut task := &VmlTask{ owner: &component }
	component.on_cleanup(key, fn [mut task] () { task.cancel() })!
	component.values[key] = voidptr(task)
	return task
}

pub fn (mut task VmlTask) cancel() {
	task.mutex.lock()
	task.cancelled = true
	task.mutex.unlock()
}

pub fn (task &VmlTask) is_cancelled() bool {
	task.mutex.lock()
	cancelled := task.cancelled
	task.mutex.unlock()
	return cancelled
}

pub fn (task &VmlTask) post(dispatcher UiDispatcher, action fn () !) bool {
	if task.is_cancelled() || action == unsafe { nil } { return false }
	return dispatcher.post(fn [task, action] () {
		if task.is_cancelled() || task.owner.is_disposed() { return }
		task.owner.runtime.batch(action) or { eprintln('ui2 compiled VML task failed: ${err}') }
	})
}
