module ui2

// The backend applies a compiled document's update: the custom renderer patches
// its retained layout, the other backends refresh the element or reconcile the
// cached document snapshot (backend.v).
fn compiled_vml_publish(id string, element Element) {
	if backend_needs_host {
		panic('compiled VML document library updates require an attached host publisher')
	}
	refresh_compiled_element(id, element.compiled_node, element)
}

// The compiled controller returns its retained document whole. Effects that
// run while it produces that declaration are already part of it.
fn compiled_vml_begin_snapshot() {
	begin_compiled_snapshot()
}

fn compiled_vml_end_snapshot() {
	end_compiled_snapshot()
}
