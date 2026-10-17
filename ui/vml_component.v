module ui2

// A component owns one signal scope. Child names are canonical declaration paths
// or escaped list keys supplied by the compiler, never presentation ids.
@[heap]
pub struct CompiledVmlComponent {
pub:
	runtime            &SignalRuntime
	scope              &SignalScope
	namespace          string
	identity_namespace string
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
	leaving         bool
	publish      fn (string, Element) = compiled_vml_publish
	command_handler fn (VmlHostCommand) ! = compiled_vml_host_command
	app_revision &Signal[u64]
	theme Theme
	theme_colors map[string]&Signal[u32]
	theme_numbers map[string]&Signal[f64]
	theme_spacing map[string]&Signal[f64]
	theme_radii map[string]&Signal[f64]
	theme_font_sizes map[string]&Signal[f64]
	// Shared by every component of a document, like its signal runtime.
	projections &VmlProjections
}

@[heap]
pub struct CompiledVmlNode {
pub:
	component &CompiledVmlComponent
mut:
	declaration       Element
	local_id          string
	authored_id       string
	authored_width    bool
	authored_height   bool
	inherit_width     bool
	inherit_height    bool
	is_fragment       bool
	relative_key      string
	fragment_keys_prefix string
	fragment_keys_ready bool
	presentation      &VmlPresentation = unsafe { nil }
	source_snapshot   &VmlSourceSnapshot = unsafe { nil }
	parent            &CompiledVmlNode = unsafe { nil }
	children          []&CompiledVmlNode
	children_revision &Signal[u64]
	source_children   []&CompiledVmlNode
	source_owners     []&CompiledVmlNode
	has_sources       bool
	effects           map[string]&SignalEffect
	mounted           bool

	frame_value      &Signal[Rect] = unsafe { nil }
	viewport_width   bool
	viewport_height  bool
	segments         []VmlChildSegment
	segments_current bool
	child_layout     VmlChildRule
	child_layout_set bool

	// Private identity, computed once for the owner lifetime.
	identity_value string
	// Hex form of identity_value used in layout paths, computed on first use.
	identity_hex string
	// Deferred projection state (see vml_projection.v).
	projection_dirty  bool
	descendant_dirty  bool
	projection_queued bool
	revision_pending  bool
	visible_buffer    []&CompiledVmlNode
	// Per-call marks for set_children identity checks: (caller, serial).
	check_serial   u64
	attach_owner   voidptr
	attach_serial  u64
	ancestor_owner voidptr
	ancestor_serial u64
}

pub fn new_vml_component(name string) !&CompiledVmlComponent {
	return new_vml_owner(name, 'vml:' + vml_identity_segment(name), Theme{})
}

// A document preserves application-facing ids. Reusable components below it
// have their own namespace, so two instances cannot collide.
@[params]
pub struct VmlDocumentConfig {
pub:
	theme ?Theme
}

pub fn new_vml_document(name string, config VmlDocumentConfig) !&CompiledVmlComponent {
	return new_vml_owner(name, '', config.theme or { vml_initial_theme() })
}

fn new_vml_owner(name string, namespace string, theme Theme) !&CompiledVmlComponent {
	theme.validate()!
	mut runtime := new_signal_runtime()
	mut scope := runtime.scope()!
	revision := new_signal(mut scope, u64(0), name: '@app')!
	projections := new_vml_projections(mut runtime)
	mut owner := &CompiledVmlComponent{
		runtime:            runtime
		projections:        projections
		scope:              scope
		name:               name
		namespace:          namespace
		identity_namespace: next_vml_owner_id()
		app_revision:       revision
		theme: Theme{ colors: theme.colors.clone(), spacing: theme.spacing.clone(), radii: theme.radii.clone(), font_sizes: theme.font_sizes.clone() }
	}
	return owner
}

pub fn (component &CompiledVmlComponent) is_disposed() bool {
	return component.disposed || component.scope.is_disposed()
}

fn (component &CompiledVmlComponent) is_leaving() bool {
	return component.leaving || (component.parent != unsafe { nil } && component.parent.is_leaving())
}

fn (component &CompiledVmlComponent) require_alive() ! {
	if component.is_disposed() { return error('compiled VML component is disposed') }
}

// Embedded compiled documents can publish through their host's retained UI
// runtime. Existing descendants and subsequently created scopes use this relay.
pub fn (mut component CompiledVmlComponent) set_publisher(publish fn (string, Element)) ! {
	component.require_alive()!
	if publish == unsafe { nil } { return error('compiled VML publisher is nil') }
	component.publish = publish
	for _, mut child in component.children {
		if !child.is_disposed() { child.set_publisher(publish)! }
	}
}

pub fn (mut component CompiledVmlComponent) child(name string) !&CompiledVmlComponent {
	component.require_alive()!
	if name.len == 0 { return error('compiled VML child requires a declaration identity') }
	if existing := component.children[name] {
		if !existing.is_disposed() { return existing }
	}
	scope := component.scope.child()!
	// Length-prefixed segments keep nested names unambiguous without
	// re-encoding the already-encoded parent namespace at every level.
	segment := vml_identity_segment(name)
	mut child := &CompiledVmlComponent{
		runtime:            component.runtime
		projections:        component.projections
		scope:              scope
		namespace:          if component.namespace.len == 0 {
			'vml:' + segment
		} else {
			component.namespace + '/' + segment
		}
		identity_namespace: component.identity_namespace + '/' + segment
		parent:             &component
		name:               name
		publish:            component.publish
		command_handler:    component.command_handler
		app_revision:       component.app_revision
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

pub fn (mut component CompiledVmlComponent) element(declaration Element, config VmlNodeConfig) !&CompiledVmlNode {
	return component.owned_element(declaration, config, false)
}

fn (mut component CompiledVmlComponent) owned_element(declaration Element, config VmlNodeConfig, fragment bool) !&CompiledVmlNode {
	component.require_alive()!
	local_id := if config.identity.len > 0 { config.identity } else { declaration.id }
	if local_id.len == 0 {
		return error('compiled VML element requires a local declaration identity')
	}
	if mut node := component.nodes[local_id] {
		if node.authored_id != declaration.id || node.declaration.kind != declaration.kind || node.is_fragment != fragment {
			return error('compiled VML local identity changed its authored id or kind')
		}
		if !node.mounted && (node.declaration.frame != declaration.frame
			|| node.declaration.layout_input != declaration.layout_input
			|| node.declaration.layout != declaration.layout
			|| node.declaration.content_size != declaration.content_size) {
			// Preferred-size passes and allocated-size passes share one instance.
			// Only authored geometry follows the latter; effects retain values.
			node.declaration = Element{
				...node.declaration
				frame:        declaration.frame
				layout_input: declaration.layout_input
				layout:       declaration.layout
				content_size: declaration.content_size
			}
			node.source_snapshot = unsafe { nil }
			node.propagate()
		}
		return node
	}
	mut node := &CompiledVmlNode{
		component:         &component
		local_id:          local_id
		authored_id:       declaration.id
		authored_width:    config.authored_width
		authored_height:   config.authored_height
		inherit_width:     config.inherit_width
		inherit_height:    config.inherit_height
		is_fragment:       fragment
		relative_key:      declaration.key
		identity_value:    '/compiled:' + component.identity_namespace + '/' + vml_identity_segment(local_id)
		fragment_keys_ready: true
		children_revision: new_signal(mut component.scope, u64(0),
			name: '@children:' + local_id
		)!
		declaration:       Element{
			...declaration
			compiled_source: unsafe { nil }
			id:       component.control_id(declaration.id)
			children: []
		}
		frame_value:       component.geometry(local_id, declaration.frame)!
	}
	node.declaration = node.update_motion(node.declaration)!
	component.nodes[local_id] = node
	node.set_element_children(declaration.children)!
	return node
}

pub fn (mut node CompiledVmlNode) set_element_children(declarations []Element) ! {
	mut children := []&CompiledVmlNode{cap: declarations.len}
	for index, child in declarations {
		if child.compiled_node != unsafe { nil } {
			mut projected := child.compiled_node
			projected.set_presentation(child, &node)!
			children << child.compiled_node
		} else {
			// Composite control APIs manufacture headers/backdrops and other
			// internal controls. Retain them with the same ownership as authored
			// declarations, without adding a second widget implementation.
			children << node.component.element(child,
				identity: node.internal_identity(child, index)
			)!
		}

		mut owned_child := children.last()
		if !owned_child.child_layout_set {
			owned_child.inherit_child_layout(node.declaration.layout, index)
		}
	}
	node.set_children(children)!
}

pub fn (node &CompiledVmlNode) element() Element {
	element := vml_present(node.constructor_source_element(), node.presentation)
	if node.component.is_leaving() {
		return Element{ ...element, presence_exiting: true, enabled: false }
	}
	return element
}

pub fn (node &CompiledVmlNode) child_elements() ![]Element {
	node.component.require_alive()!
	node.children_revision.get()!
	if node.has_sources { return node.source_children.map(it.constructor_source_element()) }
	node.ensure_projection()
	return node.declaration.children.clone()
}

pub fn (mut node CompiledVmlNode) set_sources(elements []Element) ! {
	node.component.require_alive()!
	mut children := []&CompiledVmlNode{cap: elements.len}
	for element in elements {
		if element.compiled_node == unsafe { nil } {
			return error('compiled widget sources require retained declarations')
		}
		children << element.compiled_node
	}
	node.component.on_cleanup('sources:' + node.local_id, fn [mut node] () { node.detach_sources() })!
	if node.has_sources && node.source_children == children { return }
	for mut old in node.source_children {
		if old !in children { old.source_owners = old.source_owners.filter(it != &node) }
	}
	node.has_sources = true
	node.source_children = children
	for mut child in children {
		if &node !in child.source_owners { child.source_owners << &node }
	}
	node.children_revision.set(node.children_revision.peek()! + 1)!
}

fn (mut node CompiledVmlNode) detach_sources() {
	for mut child in node.source_children {
		child.source_owners = child.source_owners.filter(it != &node)
	}
	node.source_children.clear()
}

// Composite config effects call the existing control constructor again and
// reconcile only its generated subtree. Authored child handles remain retained.
pub fn (mut node CompiledVmlNode) structure(name string, update fn () !Element) ! {
	node.component.require_alive()!
	key := 'structure:' + name
	if key in node.effects { return }
	if update == unsafe { nil } { return error('compiled VML structural effect is nil') }
	effect := node.component.scope.effect('${node.declaration.id}.${key}', fn [mut node, update] () ! {
		replacement := update()!
		node.component.runtime.untracked(fn [mut node, replacement] () ! {
			// A widget rebuild uses its allocated frame to place helper controls.
			// Keep the authored input for the next measure pass; otherwise Flex
			// shrink would repeatedly shrink the last allocation as its new basis.
			input := node.declaration.layout_input or { node.declaration.frame }
			node.reconcile_structure(Element{ ...replacement, layout_input: input }, true)!
		})!
	})!
	node.effects[key] = effect
}

fn (mut node CompiledVmlNode) reconcile_structure(replacement Element, publish bool) ! {
	node.component.require_alive()!
	if replacement.kind != node.declaration.kind {
		return error('compiled VML structural effect must preserve element kind')
	}
	if replacement.id !in [node.authored_id, node.declaration.id] {
		return error('compiled VML structural effect must preserve id')
	}
	before := node.element()
	source_before := node.source_element()
	was_mounted := node.mounted
	node.mounted = false
	defer { if !node.component.is_disposed() { node.mounted = was_mounted } }
	mut children := []&CompiledVmlNode{cap: replacement.children.len}
	for index, element in replacement.children {
		if element.compiled_node != unsafe { nil } {
			mut child := element.compiled_node
			child.set_presentation(element, &node)!
			children << child
		} else {
			mut child := node.component.element(Element{ ...element, children: [] },
				identity: node.internal_identity(element, index)
			)!
			child.reconcile_structure(element, false)!
			children << child
		}
	}
	node.declaration = node.update_motion(Element{
		...replacement
		compiled_source: unsafe { nil }
		id:            node.declaration.id
		key:           node.declaration.key
		compiled_node: &node
		children:      node.declaration.children
	})!
	node.source_snapshot = unsafe { nil }
	if node.component.is_disposed() { return }
	node.set_children(children)!
	changed := !vml_declaration_equal(before, node.element())
	if changed || !vml_declaration_equal(source_before, node.source_element()) { node.propagate() }
	if was_mounted { node.prepare_motion_mount()! }
	node.mark_mounted(was_mounted)
	if was_mounted {
		for mut child in node.children {
			if child.component.has_mounted_nodes() { child.component.mount()! }
		}
	}
	if publish && was_mounted && changed {
		node.publish_structure()
	}
}

// Property effects are registered once, even if measurement asks for the same
// declaration again. Reading signals in update establishes the dependencies.
pub fn (mut node CompiledVmlNode) effect(property string, update fn (Element) !Element) ! {
	node.component.require_alive()!
	if property in node.effects { return }
	if update == unsafe { nil } { return error('compiled VML property effect is nil') }
	effect := node.component.scope.effect('${node.declaration.id}.${property}', fn [mut node, update] () ! {
		replacement := update(node.source_element())!
		node.replace_property(replacement)!
	})!
	node.effects[property] = effect
}

pub fn (mut node CompiledVmlNode) patch(update fn (Element) Element) ! {
	if update == unsafe { nil } { return error('compiled VML property patch is nil') }
	node.replace_property(update(node.source_element()))!
}

fn (mut node CompiledVmlNode) replace_property(replacement Element) ! {
	node.component.require_alive()!
	node.ensure_projection()
	if replacement.id != node.declaration.id || replacement.kind != node.declaration.kind
		|| replacement.key != node.declaration.key {
		return error('compiled VML property patch must preserve element identity and kind')
	}
	if !vml_same_elements(replacement.children, node.declaration.children) {
		return error('compiled VML property patch cannot replace children')
	}
	if vml_declaration_equal(replacement, node.source_element()) { return }
	// Children, id and key are unchanged and were validated when attached,
	// so only this element's own properties need checking.
	validate_element_properties(replacement, 'root')!
	node.declaration = node.update_motion(Element{ ...replacement, compiled_node: node, compiled_source: unsafe { nil } })!
	node.source_snapshot = unsafe { nil }
	if node.component.is_disposed() { return }
	node.propagate()
	if node.mounted { node.publish_structure() }
}

fn (mut node CompiledVmlNode) notify_sources() {
	for mut owner in node.source_owners {
		if owner.component.is_disposed() { continue }
		previous := owner.children_revision.peek() or { continue }
		owner.children_revision.set(previous + 1) or { eprintln('ui2 compiled VML source update failed: ${err}') }
	}
}

// This only changes structure. Existing node owners and their signal scopes
// survive a reorder, so backend key/id identity keeps edits, focus and scroll.
pub fn (mut node CompiledVmlNode) set_children(children []&CompiledVmlNode) ! {
	node.component.require_alive()!
	node.check_children(children)!
	prefix := node.fragment_prefix()
	if node.children == children {
		// Re-submitting the retained children (segment refreshes, child rule
		// writes) compares the current projection in place before copying it.
		current := node.declaration.children
		if vml_projection_matches(children, prefix, current) {
			_, layout_changed := node.child_layout_spec(node.collect_visible(children), current)!
			if !layout_changed {
				node.projection_dirty = false
				return
			}
		}
	}
	elements := vml_project_children(children, prefix, unsafe { nil }, [])
	layout, _ := node.child_layout_spec(node.collect_visible(children), elements)!
	candidate := Element{ ...node.declaration, children: elements, layout: layout, compiled_node: node }
	validate_element_tree(candidate)!
	if node.is_fragment { node.validate_fragment_children(children)! }
	for mut old in node.children {
		if old !in children {
			old.parent = unsafe { nil }
			old.clear_presentation()
			old.mark_mounted(false)
		}
	}
	if node.children != children { node.segments_current = false }
	node.children = children.clone()
	for mut child in node.children { child.parent = &node }
	for mut child in node.children { child.refresh_fragment_keys() }
	node.declaration = candidate
	node.projection_dirty = false
	node.revision_pending = false
	node.source_snapshot = unsafe { nil }
	if !node.has_sources { node.children_revision.set(node.children_revision.peek()! + 1)! }
	node.propagate()
	if node.mounted {
		for mut child in node.children {
			child.prepare_motion_mount()!
			child.mark_mounted(true)
		}
		node.mount_visible_owners()!
		node.publish_structure()
	}
}

// Identity checks mark this node's ancestors and the candidate children with
// a stamp unique to this call, instead of building a set per call.
fn (mut node CompiledVmlNode) check_children(children []&CompiledVmlNode) ! {
	node.check_serial++
	owner := voidptr(&node)
	serial := node.check_serial
	mut ancestor := &node
	for ancestor != unsafe { nil } {
		ancestor.ancestor_owner = owner
		ancestor.ancestor_serial = serial
		ancestor = ancestor.parent
	}
	for child in children {
		child.component.require_alive()!
		mut candidate := unsafe { &CompiledVmlNode(voidptr(child)) }
		if candidate.attach_owner == owner && candidate.attach_serial == serial {
			return error('compiled VML child declaration cannot appear more than once')
		}
		candidate.attach_owner = owner
		candidate.attach_serial = serial
		if voidptr(child) == voidptr(&node) { return error('compiled VML element cannot contain itself') }
		if child.ancestor_owner == owner && child.ancestor_serial == serial {
			return error('compiled VML element cannot contain an ancestor')
		}
		if child.parent != unsafe { nil } && voidptr(child.parent) != voidptr(&node) {
			return error('compiled VML element already belongs to another parent')
		}
	}
}

fn (mut node CompiledVmlNode) mark_mounted(mounted bool) {
	node.mounted = mounted
	for mut child in node.children { child.mark_mounted(mounted) }
}

pub fn (mut node CompiledVmlNode) mount() ! {
	node.component.require_alive()!
	node.prepare_motion_mount()!
	node.mark_mounted(true)
	node.mount_visible_owners()!
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
	if component.mounted || !component.has_mounted_nodes() { return }
	component.mounted = true
	for name in component.mount_order { component.runtime.untracked(component.mount_hooks[name])! }
	for _, mut child in component.children {
		if child.has_mounted_nodes() { child.mount()! }
	}
}

fn (component &CompiledVmlComponent) has_mounted_nodes() bool {
	if component.is_disposed() { return false }
	for _, node in component.nodes { if node.mounted && !node.is_fragment { return true } }
	for _, child in component.children { if child.has_mounted_nodes() { return true } }
	return false
}

pub fn (mut component CompiledVmlComponent) dispose() ! {
	if component.is_disposed() { return }
	component.scope.dispose()!
	component.disposed = true
	for _, mut node in component.nodes {
		node.mark_mounted(false)
		node.source_snapshot = unsafe { nil }
		node.clear_presentation()
	}
	component.values.clear()
	component.nodes.clear()
	component.mount_hooks.clear()
	component.children.clear()
	if component.parent != unsafe { nil } { component.parent.children.delete(component.name) }
	if component.parent == unsafe { nil } {
		component.runtime.dispose()!
		mut projections := component.projections
		projections.clear()
	}
}

// Every UI action is one batch. Stale backend callbacks and delayed tasks do
// nothing after their owning component has been removed.
pub fn (component &CompiledVmlComponent) callback(action fn (ElementEvent) !) ElementCallback {
	return fn [component, action] (event ElementEvent) {
		if component.is_disposed() || component.is_leaving() || action == unsafe { nil } { return }
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
