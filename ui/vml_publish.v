module ui2

// host_window is the window that mounted the component's document, or nil
// while no window has mounted it.
fn (component &CompiledVmlComponent) host_window() &Window {
	mut owner := unsafe { component }
	for owner.parent != unsafe { nil } {
		owner = owner.parent
	}
	return owner.window
}

// publish_element applies a compiled document's update: through the host's
// publisher when one is attached, otherwise in the window that mounted the
// document, where the custom renderer patches its retained layout and the
// other backends refresh the element or reconcile the cached document
// snapshot (backend.v). A document no window has mounted has nothing to update.
fn (component &CompiledVmlComponent) publish_element(id string, element Element) {
	if component.publish != unsafe { nil } {
		component.publish(id, element)
		return
	}
	if backend_needs_host {
		panic('compiled VML document library updates require an attached host publisher')
	}
	mut w := component.host_window()
	if w != unsafe { nil } {
		w.refresh_compiled_element(id, element.compiled_node, element)
	}
}
