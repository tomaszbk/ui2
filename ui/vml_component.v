module ui2

// A component owns one signal scope. Child names are canonical declaration paths
// or escaped list keys supplied by the compiler, never presentation ids.
@[heap]
pub struct CompiledVmlComponent {
pub:
	runtime   &SignalRuntime
	scope     &SignalScope
	namespace string
mut:
	parent       &CompiledVmlComponent = unsafe { nil }
	name         string
	children     map[string]&CompiledVmlComponent
	nodes        map[string]&CompiledVmlNode
	values       map[string]voidptr
	value_types  map[string]string
	mount_hooks  map[string]fn () !
	mount_order  []string
	cleanup_keys map[string]bool
	mounted      bool
	disposed     bool
	publish      fn (string, Element) = refresh_element
	app_revision &Signal[u64]
}

@[heap]
pub struct CompiledVmlNode {
pub:
	component &CompiledVmlComponent
mut:
	declaration Element
	local_id    string
	parent      &CompiledVmlNode = unsafe { nil }
	children    []&CompiledVmlNode
	effects     map[string]&SignalEffect
	mounted     bool
}

pub fn new_vml_component(name string) !&CompiledVmlComponent {
	return new_vml_owner(name, 'vml:' + name.bytes().hex())
}

// A document preserves application-facing ids. Reusable components below it
// have their own namespace, so two instances cannot collide.
pub fn new_vml_document(name string) !&CompiledVmlComponent {
	return new_vml_owner(name, '')
}

fn new_vml_owner(name string, namespace string) !&CompiledVmlComponent {
	mut runtime := new_signal_runtime()
	mut scope := runtime.scope()!
	revision := new_signal(mut scope, u64(0), name: '@app')!
	return &CompiledVmlComponent{
		runtime:      runtime
		scope:        scope
		name:         name
		namespace:    namespace
		app_revision: revision
	}
}

pub fn (component &CompiledVmlComponent) is_disposed() bool {
	return component.disposed || component.scope.is_disposed()
}

fn (component &CompiledVmlComponent) require_alive() ! {
	if component.is_disposed() { return error('compiled VML component is disposed') }
}

pub fn (mut component CompiledVmlComponent) child(name string) !&CompiledVmlComponent {
	component.require_alive()!
	if name.len == 0 { return error('compiled VML child requires a declaration identity') }
	if existing := component.children[name] {
		if !existing.is_disposed() { return existing }
	}
	scope := component.scope.child()!
	child := &CompiledVmlComponent{
		runtime:      component.runtime
		scope:        scope
		namespace:    if component.namespace.len == 0 {
			'vml:' + name.bytes().hex()
		} else {
			component.namespace + '/' + name.bytes().hex()
		}
		parent:       &component
		name:         name
		publish:      component.publish
		app_revision: component.app_revision
	}
	component.children[name] = child
	return child
}

// Slot expressions keep their author's lexical captures, but the receiving
// component owns the mounted content's effects, resources and descendants.
pub fn (author &CompiledVmlComponent) slot_child(mut host CompiledVmlComponent, name string) !&CompiledVmlComponent {
	author.require_alive()!
	host.require_alive()!
	if author.runtime != host.runtime {
		return error('compiled VML slot owners must share a runtime')
	}
	return host.child('slot:' + author.namespace + ':' + name)
}

// Values are retained by the component, with the concrete type checked before
// recovering a pointer. State is created once; computed remains a lazy memo.
pub fn (mut component CompiledVmlComponent) state[T](name string, initial T) !&Signal[T] {
	component.require_alive()!
	key := 'state:' + name
	if value := component.values[key] {
		if component.value_types[key] != T.name {
			return error('compiled VML state `${name}` changed type')
		}
		return unsafe { &Signal[T](value) }
	}
	value := new_signal(mut component.scope, initial, name: name)!
	component.values[key] = voidptr(value)
	component.value_types[key] = T.name
	return value
}

struct VmlInitialValue[T] {
mut:
	value T
}

// The compiler uses a factory rather than an eager argument, so preferred-size
// passes cannot repeat initialization or its application side effects.
pub fn (mut component CompiledVmlComponent) state_factory[T](name string, initialize fn () !T) !&Signal[T] {
	component.require_alive()!
	key := 'state:' + name
	if value := component.values[key] {
		if component.value_types[key] != T.name {
			return error('compiled VML state `${name}` changed type')
		}
		return unsafe { &Signal[T](value) }
	}
	if initialize == unsafe { nil } { return error('compiled VML state initializer is nil') }
	mut initial := &VmlInitialValue[T]{}
	component.runtime.untracked(fn [mut initial, initialize] [T]() ! {
		initial.value = initialize()!
	})!
	return component.state(name, initial.value)!
}

pub fn (mut component CompiledVmlComponent) computed[T](name string, compute fn () !T) !&Memo[T] {
	component.require_alive()!
	key := 'computed:' + name
	if value := component.values[key] {
		if component.value_types[key] != T.name {
			return error('compiled VML computed `${name}` changed type')
		}
		return unsafe { &Memo[T](value) }
	}
	value := new_memo(mut component.scope, compute, name: name)!
	component.values[key] = voidptr(value)
	component.value_types[key] = T.name
	return value
}

pub fn (mut component CompiledVmlComponent) element(declaration Element) !&CompiledVmlNode {
	component.require_alive()!
	if declaration.id.len == 0 {
		return error('compiled VML element requires a local declaration identity')
	}
	if mut node := component.nodes[declaration.id] {
		if !node.mounted {
			// Preferred-size passes and allocated-size passes share one instance.
			// Only authored geometry follows the latter; effects retain values.
			node.declaration = Element{
				...node.declaration
				frame:        declaration.frame
				layout_input: declaration.layout_input
				layout:       declaration.layout
				content_size: declaration.content_size
			}
			node.propagate()
		}
		return node
	}
	mut node := &CompiledVmlNode{
		component:   &component
		local_id:    declaration.id
		declaration: Element{ ...declaration, id: if component.namespace.len == 0 {
			declaration.id
		} else {
			component.namespace + ':' + declaration.id.bytes().hex()
		}, children: [] }
	}
	component.nodes[declaration.id] = node
	node.set_element_children(declaration.children)!
	return node
}

pub fn (mut node CompiledVmlNode) set_element_children(declarations []Element) ! {
	mut children := []&CompiledVmlNode{}
	for index, child in declarations {
		if child.compiled_node != unsafe { nil } {
			children << child.compiled_node
		} else {
			// Composite control APIs manufacture headers/backdrops and other
			// internal controls. Retain them with the same ownership as authored
			// declarations, without adding a second widget implementation.
			local_id := if child.id.len > 0 {
				child.id
			} else {
				node.local_id + '/internal:' + index.str()
			}
			children << node.component.element(Element{ ...child, id: local_id })!
		}
	}
	node.set_children(children)!
}

pub fn (node &CompiledVmlNode) element() Element {
	return Element{ ...node.declaration, compiled_node: node }
}

// Property effects are registered once, even if measurement asks for the same
// declaration again. Reading signals in update establishes the dependencies.
pub fn (mut node CompiledVmlNode) effect(property string, update fn (Element) !Element) ! {
	node.component.require_alive()!
	if property in node.effects { return }
	if update == unsafe { nil } { return error('compiled VML property effect is nil') }
	effect := node.component.scope.effect('${node.declaration.id}.${property}', fn [mut node, update] () ! {
		replacement := update(node.element())!
		node.replace_property(replacement)!
	})!
	node.effects[property] = effect
}

pub fn (mut node CompiledVmlNode) patch(update fn (Element) Element) ! {
	if update == unsafe { nil } { return error('compiled VML property patch is nil') }
	node.replace_property(update(node.element()))!
}

fn (mut node CompiledVmlNode) replace_property(replacement Element) ! {
	node.component.require_alive()!
	if replacement.id != node.declaration.id || replacement.kind != node.declaration.kind
		|| replacement.key != node.declaration.key {
		return error('compiled VML property patch must preserve element identity and kind')
	}
	if replacement.children != node.declaration.children {
		return error('compiled VML property patch cannot replace children')
	}
	if replacement == node.element() { return }
	validate_element_tree(replacement)!
	node.declaration = Element{ ...replacement, compiled_node: node }
	node.propagate()
	if node.mounted { node.component.publish(node.declaration.id, node.element()) }
}

fn (mut node CompiledVmlNode) propagate() {
	if node.parent == unsafe { nil } { return }
	mut parent := node.parent
	mut children := parent.declaration.children.clone()
	for index, child in parent.children {
		if child == &node {
			children[index] = node.element()
			break
		}
	}
	parent.declaration = Element{ ...parent.declaration, children: children }
	parent.propagate()
}

// This only changes structure. Existing node owners and their signal scopes
// survive a reorder, so backend key/id identity keeps edits, focus and scroll.
pub fn (mut node CompiledVmlNode) set_children(children []&CompiledVmlNode) ! {
	node.component.require_alive()!
	mut elements := []Element{cap: children.len}
	for child in children {
		child.component.require_alive()!
		if child == &node { return error('compiled VML element cannot contain itself') }
		mut ancestor := &node
		for ancestor.parent != unsafe { nil } {
			ancestor = ancestor.parent
			if ancestor == child { return error('compiled VML element cannot contain an ancestor') }
		}
		if child.parent != unsafe { nil } && child.parent != &node {
			return error('compiled VML element already belongs to another parent')
		}
		elements << child.element()
	}
	candidate := Element{ ...node.declaration, children: elements, compiled_node: node }
	validate_element_tree(candidate)!
	if node.children == children { return }
	for mut old in node.children {
		if old !in children {
			old.parent = unsafe { nil }
			old.mark_mounted(false)
		}
	}
	node.children = children.clone()
	for mut child in node.children { child.parent = &node }
	node.declaration = candidate
	node.propagate()
	if node.mounted {
		for mut child in node.children {
			child.mark_mounted(true)
			child.component.mount()!
		}
		node.component.publish(node.declaration.id, node.element())
	}
}

fn (mut node CompiledVmlNode) mark_mounted(mounted bool) {
	node.mounted = mounted
	for mut child in node.children { child.mark_mounted(mounted) }
}

pub fn (mut node CompiledVmlNode) mount() ! {
	node.component.require_alive()!
	node.mark_mounted(true)
	node.component.mount()!
}

pub fn (mut component CompiledVmlComponent) on_mount(name string, action fn () !) ! {
	component.require_alive()!
	if action == unsafe { nil } { return error('compiled VML mount callback is nil') }
	if name in component.mount_hooks { return }
	component.mount_hooks[name] = action
	component.mount_order << name
	if component.mounted { component.runtime.untracked(action)! }
}

pub fn (mut component CompiledVmlComponent) on_cleanup(name string, cleanup fn ()) ! {
	component.require_alive()!
	if name in component.cleanup_keys { return }
	component.scope.on_cleanup(cleanup)!
	component.cleanup_keys[name] = true
}

pub fn (mut component CompiledVmlComponent) on_unmount(name string, action fn ()) ! {
	if action == unsafe { nil } { return error('compiled VML unmount callback is nil') }
	component.on_cleanup('unmount:' + name, fn [component, action] () {
		if component.mounted { action() }
	})!
}

pub fn (mut component CompiledVmlComponent) mount() ! {
	component.require_alive()!
	if component.mounted { return }
	component.mounted = true
	for name in component.mount_order { component.runtime.untracked(component.mount_hooks[name])! }
	for _, mut child in component.children {
		if child.has_mounted_nodes() { child.mount()! }
	}
}

fn (component &CompiledVmlComponent) has_mounted_nodes() bool {
	if component.is_disposed() { return false }
	for _, node in component.nodes { if node.mounted { return true } }
	for _, child in component.children { if child.has_mounted_nodes() { return true } }
	return false
}

pub fn (mut component CompiledVmlComponent) dispose() ! {
	if component.is_disposed() { return }
	component.scope.dispose()!
	component.disposed = true
	for _, mut node in component.nodes { node.mark_mounted(false) }
	component.values.clear()
	component.nodes.clear()
	component.mount_hooks.clear()
	component.children.clear()
	if component.parent != unsafe { nil } { component.parent.children.delete(component.name) }
	if component.parent == unsafe { nil } { component.runtime.dispose()! }
}

// Every UI action is one batch. Stale backend callbacks and delayed tasks do
// nothing after their owning component has been removed.
pub fn (component &CompiledVmlComponent) callback(action fn (ElementEvent) !) ElementCallback {
	return fn [component, action] (event ElementEvent) {
		if component.is_disposed() || action == unsafe { nil } { return }
		component.runtime.batch(fn [component, action, event] () ! {
			action(event) or {
				component.invalidate_app()!
				return err
			}
			component.invalidate_app()!
		}) or {
			eprintln('ui2 compiled VML action failed: ${err}')
		}
	}
}

// External V service/model data is invalidated explicitly. Only effects that
// read watch_app subscribe; local signal effects remain independent of it.
pub fn (component &CompiledVmlComponent) watch_app() ! {
	component.require_alive()!
	component.app_revision.get()!
}

pub fn (component &CompiledVmlComponent) invalidate_app() ! {
	if component.is_disposed() { return }
	component.app_revision.set(component.app_revision.peek()! + 1)!
}
