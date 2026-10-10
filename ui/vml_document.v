module ui2

// A document can return an imported component's node directly. Closing that
// visual root releases its implicit document scope as well as all descendants.
// Component.dispose keeps its narrower scope for keyed removal and slots.
pub fn (node &CompiledVmlNode) dispose_document() ! {
	mut owner := node.component
	for owner.parent != unsafe { nil } {
		owner = owner.parent
	}
	owner.dispose()!
}
