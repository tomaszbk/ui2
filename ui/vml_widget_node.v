module ui2

// Generic VML node runtime (design §2.2): the entry points the generic
// compiler lowering emits. A document declares typed props nodes top-down;
// `finish` builds them bottom-up through `P.build` into the retained
// CompiledVmlNode tree, then validates and resolves it.
//
// Deviations from the design signatures, forced by V or by measurements:
// * `vml_child[P, N](mut parent N, ...)` and `vml_repeat[T, N](mut parent N, ...)`
//   take the parent *handle* type N (a `VmlWidgetNode[Q]` or a `VmlSegment`),
//   inferred from the argument, instead of the parent props type Q. V has no
//   overloading and the same call must accept repeater segments.
// * `VmlSegment` is not generic; repeater item builders receive
//   `mut VmlSegment` and pass it as the parent of their roots.
// * `VmlNodeOptions` has no `authored []string` (a literal array allocates on
//   every node build); authored geometry is read from the optional fields
//   x/y/width/height. It gains `identity` (an explicit local identity; the
//   default is `id`, else `__vml_control_<path with _>`), and `slot` is
//   optional (declaration order is the call order).
// * `VmlDocumentConfig.follow_viewport` replaces deriving viewport following
//   from the call shape: the lowering sets it when no explicit frame is given.
// * `vml_guard_child[P, C]()` replaces `vml_guard_children[P]()`: whether a
//   child is an element or a part (Run, Option, MessageBox Button...) depends
//   on both types, so the pair is checked.
// * Refs bind with `r.bind_widget(mut n)!` (`bind(&CompiledVmlNode)` stays for
//   the current lowering until it is removed). A ref's type parameter is the
//   node's props type (`VmlRef[ui2.TextInputProps]`) or a marker type.
// * Repeater items take the host's `child_input` (the compiled lowering offers
//   the host's raw frame) and the host's child placement for a `.normal`
//   host placement, as the compiled lowering does.
// * `prop` effects evaluate synchronously when registered, also inside an
//   effect or batch (keyed items are built inside the list effect), so the
//   first build sees every reactive value exactly once.

// VmlNodeOptions identify a declared node. `path` is the declaration path
// (`0.2.1`); it names nodes without an id.
@[params]
pub struct VmlNodeOptions {
pub:
	id       string
	identity string
	path     string
	key      string
	slot     int = -1
	src      VmlSourceLocation
}

// VmlDocument is one generic document: the document owner and its root node.
@[heap]
pub struct VmlDocument {
pub mut:
	owner &CompiledVmlComponent
mut:
	frame           Rect
	follow_viewport bool
	root            &VmlNodeCore = unsafe { nil }
}

pub fn vml_document(frame Rect, cfg VmlDocumentConfig) !&VmlDocument {
	mut owner := new_vml_document('root', cfg)!
	mut document := &VmlDocument{
		owner:           owner
		frame:           frame
		follow_viewport: cfg.follow_viewport
	}
	owner.widget_document = document
	return document
}

// finish builds the declared tree, validates it and resolves its layout.
pub fn (mut d VmlDocument) finish() !Element {
	mut root := d.root
	if root == unsafe { nil } { return error('VML document has no root element') }
	mut node := root.build_element(d.frame, .normal) or { return root.src.wrap_error(err) }
	if d.follow_viewport {
		node.follow_viewport(!root.authored_width, !root.authored_height)
	}
	element := node.element()
	validate_element_tree(element) or { return root.src.wrap_error(err) }
	mut tree := LayoutTree{}
	tree.replace(element)!
	return tree.resolve(LayoutConstraints{}, measure_layout_text, LayoutEnvironment{})!
}

// VmlStructure is how the runtime reconciles a widget's element.
pub enum VmlStructure {
	// The element's children are its authored children; changes patch it.
	plain
	// The constructor manufactures its children: changes reconcile them.
	generated
	// The constructor reads or transforms its authored children (sources):
	// it is reconciled again when one of them changes.
	sourced
}

// VmlCommonProps is implemented by every props type embedding CommonProps.
pub interface VmlCommonProps {
	common_props() CommonProps
}

// VmlElementProps is implemented by props that build an element.
pub interface VmlElementProps {
	build(ctx VmlBuildContext) !Element
}

interface VmlEventProps {
mut:
	apply_event(event ElementEvent)
}

// Facts the untyped runtime needs about a typed node.
struct VmlFacts {
	element         bool
	part            bool
	container       bool
	structure       VmlStructure
	authored_width  bool
	authored_height bool
	needs_id        bool
	// The props type has its own apply_event: events update the props.
	own_events bool
}

// VmlAnyNode is the typed half of a node, implemented by VmlWidgetNode[P].
interface VmlAnyNode {
	vml_facts() VmlFacts
	vml_type_name() string
	vml_frame(input Rect, placement VmlPlacement) Rect
	vml_child_input(frame Rect, count int) !Rect
	vml_child_placement(placement VmlPlacement) VmlPlacement
	vml_layout_item() VmlLayoutItem
	vml_part(ctx VmlBuildContext) !VmlPart
	vml_has_style() bool
	vml_styled(el Element, mode VmlStyleMode) !Element
mut:
	vml_element(ctx VmlBuildContext, style VmlStyleMode) !Element
	vml_commit() !
}

// How a build applies the node's style. The compiled lowering styles a plain
// element through a style effect over the unstyled constructor defaults
// (`reset`), and a structural rebuild directly (`direct`).
enum VmlStyleMode {
	unstyled
	reset
	direct
}

// Pending change kinds of a built node, coalesced until its commit.
const vml_change_fast = u8(1)
const vml_change_layout = u8(2)
const vml_change_rebuild = u8(4)

// VmlChildList holds declared children and repeaters in declaration order.
// A repeater's position is the number of children declared before it.
struct VmlChildList {
mut:
	children []&VmlNodeCore
	repeats  []VmlRepeatSlot
}

struct VmlRepeatSlot {
	position int
	repeat   VmlRepeater
}

// VmlNodeCore is the untyped half of a node, embedded in VmlWidgetNode[P].
@[heap]
struct VmlNodeCore {
	VmlChildList
mut:
	impl  ?VmlAnyNode
	owner &CompiledVmlComponent = unsafe { nil }
	// parent is the widget that consumes this node: the element parent of an
	// element (also for repeater items), or the owner of a part.
	parent       &VmlNodeCore     = unsafe { nil }
	node         &CompiledVmlNode = unsafe { nil }
	frame_signal &Signal[Rect]    = unsafe { nil }
	id           string
	identity     string
	key          string
	path         string
	src          VmlSourceLocation
	// The input and placement the parent offered at the first build (the
	// document frame for a root before it is built).
	input     Rect
	placement VmlPlacement
	has_input bool
	// Facts recorded when the node is built.
	structure         VmlStructure
	authored_width    bool
	authored_height   bool
	needs_id          bool
	reactive_geometry bool
	// Set when a part has been built into its consumer.
	consumed bool
	pending  u8
	// The element's event entry point is stable across rebuilds; it calls the
	// current build's handler after the node's own update and write-backs.
	dispatcher ElementCallback = unsafe { nil }
	handler    ElementCallback = unsafe { nil }
	// Refs bound to this node (vml_ref.v: bind_widget).
	refs []VmlNodeRef
}

fn (c &VmlNodeCore) typed() VmlAnyNode {
	return c.impl or { panic('ui2: VML node has no typed implementation') }
}

fn (c &VmlNodeCore) ctx_id() string {
	if c.id.len > 0 { return c.id }
	return if c.needs_id { c.identity } else { '' }
}

// The local identity of an element node: its explicit identity, its id, or
// one derived from its declaration path (allocated once, on first use).
fn (mut c VmlNodeCore) local_identity() string {
	if c.identity.len == 0 {
		c.identity = if c.id.len > 0 { c.id } else { vml_control_identity(c.path) }
	}
	return c.identity
}

// vml_control_identity is `__vml_control_` followed by the path with `.`
// replaced by `_`, the identity the compiled lowering gives unnamed nodes.
fn vml_control_identity(path string) string {
	prefix := '__vml_control_'
	length := prefix.len + path.len
	unsafe {
		mut data := malloc_noscan(length + 1)
		vmemcpy(data, prefix.str, prefix.len)
		for i in 0 .. path.len {
			data[prefix.len + i] = if path[i] == `.` { `_` } else { path[i] }
		}
		data[length] = 0
		return data.vstring_with_len(length)
	}
}

// VmlWidgetNode is a declared VML element or part with its typed props.
@[heap]
pub struct VmlWidgetNode[P] {
	VmlNodeCore
pub mut:
	props P
mut:
	binds []fn (P) !
}

// vml_root declares the document root. The owner is the document owner or,
// for a document whose root is a component, that component's owner.
pub fn vml_root[P](mut owner CompiledVmlComponent, props P, o VmlNodeOptions) !&VmlWidgetNode[P] {
	mut document_owner := &owner
	for document_owner.parent != unsafe { nil } {
		document_owner = document_owner.parent
	}
	mut document := document_owner.widget_document
	if document == unsafe { nil } {
		return o.src.wrap_error(error('vml_root requires an owner created by vml_document'))
	}
	if document.root != unsafe { nil } {
		return o.src.wrap_error(error('VML document already has a root element'))
	}
	mut node := vml_new_node(mut owner, props, o, unsafe { nil })!
	node.input = document.frame
	node.has_input = true
	document.root = &node.VmlNodeCore
	return node
}

// vml_child declares a child of a widget node or of a repeater segment.
pub fn vml_child[P, N](mut parent N, mut owner CompiledVmlComponent, props P, o VmlNodeOptions) !&VmlWidgetNode[P] {
	handle := parent.vml_parent()
	mut node := vml_new_node(mut owner, props, o, handle.host)!
	mut list := handle.list
	list.children << &node.VmlNodeCore
	return node
}

fn vml_new_node[P](mut owner CompiledVmlComponent, props P, o VmlNodeOptions, parent &VmlNodeCore) !&VmlWidgetNode[P] {
	owner.require_alive() or { return o.src.wrap_error(err) }
	mut node := &VmlWidgetNode[P]{
		props: props
	}
	node.owner = &owner
	node.parent = parent
	node.id = o.id
	node.identity = o.identity
	node.key = o.key
	node.path = o.path
	node.src = o.src
	node.impl = VmlAnyNode(node)
	$if P is VmlThemed {
		// A theme change rebuilds the widget and reads its layout floor again.
		mut themed := node
		mut revision := owner.theme_revision_signal() or { return o.src.wrap_error(err) }
		owner.scope.effect_now('@theme', fn [mut themed, mut revision] [P]() ! {
			revision.get()!
			if themed.VmlNodeCore.node == unsafe { nil } && !themed.consumed { return }
			themed.VmlNodeCore.changed(vml_change_rebuild | vml_change_layout)
		}) or { return o.src.wrap_error(err) }
	}
	return node
}

// VmlParent is what a parent handle gives vml_child and vml_repeat: the
// widget that lays the children out, and the list they are declared in.
pub struct VmlParent {
	host &VmlNodeCore  = unsafe { nil }
	list &VmlChildList = unsafe { nil }
}

// vml_parent is the parent protocol of vml_child and vml_repeat.
pub fn (mut n VmlWidgetNode[P]) vml_parent() VmlParent {
	return VmlParent{
		host: &n.VmlNodeCore
		list: &n.VmlChildList
	}
}

// node is the retained node, available once the document is built.
pub fn (n &VmlWidgetNode[P]) node() ?&CompiledVmlNode {
	if n.VmlNodeCore.node == unsafe { nil } { return none }
	return n.VmlNodeCore.node
}

// prop registers a reactive property: `set` assigns one field from tracked
// sources. It runs immediately, before the first build; later runs that
// change the props commit the node once per batch.
pub fn (mut n VmlWidgetNode[P]) prop(name string, set fn (mut P) !) ! {
	n.owner.require_alive() or { return n.src.wrap_error(err) }
	if set == unsafe { nil } {
		return n.src.wrap_error(error('VML property `${name}` setter is nil'))
	}
	if name in ['x', 'y', 'width', 'height'] {
		n.reactive_geometry = true
	}
	mut node := &n
	n.owner.scope.effect_now(name, fn [mut node, set] [P]() ! {
		if node.VmlNodeCore.node == unsafe { nil } && !node.consumed {
			set(mut node.props)!
			return
		}
		before := node.props
		set(mut node.props)!
		node.props_changed(before)
	}) or { return n.src.wrap_error(err) }
}

// bind registers a write-back. On an event the node's props update first
// (`apply_event`), then write-backs run, then the element's handlers.
pub fn (mut n VmlWidgetNode[P]) bind(name string, write fn (P) !) ! {
	n.owner.require_alive() or { return n.src.wrap_error(err) }
	if write == unsafe { nil } { return n.src.wrap_error(error('VML binding `${name}` is nil')) }
	n.binds << write
}

// geometry is the node's reactive resolved frame (`id.width` in VML). Before
// the document is built it holds the frame the node will be built with.
pub fn (n &VmlWidgetNode[P]) geometry() !Rect {
	mut core := unsafe { &VmlNodeCore(voidptr(&n.VmlNodeCore)) }
	mut signal := core.geometry_signal()!
	return signal.get()!
}

// geometry_signal creates the frame signal on the first read. That read may
// come from a memo (a component input such as `width: card.width`), which may
// not create signals. The signal belongs to the node's owner and is created
// once, whichever computation reads it first, so it is created outside the
// running computations.
fn (mut c VmlNodeCore) geometry_signal() !&Signal[Rect] {
	if c.frame_signal == unsafe { nil } {
		mut runtime := c.owner.runtime
		running := runtime.stack
		runtime.stack = []&SignalNode{}
		signal := c.owner.geometry(c.local_identity(), c.estimated_frame())
		runtime.stack = running
		c.frame_signal = signal!
	}
	return c.frame_signal
}

// The frame this node is (or will be) built with.
fn (c &VmlNodeCore) estimated_frame() Rect {
	if c.node != unsafe { nil } { return c.node.declaration.frame }
	input, placement := c.estimated_input()
	return c.typed().vml_frame(input, placement)
}

fn (c &VmlNodeCore) estimated_input() (Rect, VmlPlacement) {
	if c.has_input || c.parent == unsafe { nil } { return c.input, c.placement }
	parent := c.parent
	parent_input, parent_placement := parent.estimated_input()
	typed := parent.typed()
	frame := if parent.node != unsafe { nil } {
		parent.node.declaration.frame
	} else {
		typed.vml_frame(parent_input, parent_placement)
	}
	input := typed.vml_child_input(frame, parent.children.len) or { rect(0, 0, frame.width, frame.height) }
	return input, typed.vml_child_placement(parent_placement)
}

// consumer is the nearest built ancestor: the element a part was built into.
fn (c &VmlNodeCore) consumer() &VmlNodeCore {
	mut current := c.parent
	for current != unsafe { nil } && current.node == unsafe { nil } {
		current = current.parent
	}
	return current
}

// vml_defines reports whether P declares the method itself (not through an
// embedded struct).
fn vml_defines[P](name string) bool {
	$for method in P.methods {
		if method.name == name { return true }
	}
	return false
}

// ---------------------------------------------------------------- typed half

fn (n &VmlWidgetNode[P]) vml_type_name() string {
	return P.name.all_after_last('.')
}

fn (n &VmlWidgetNode[P]) vml_facts() VmlFacts {
	mut facts := VmlFacts{
		needs_id:   n.binds.len > 0 || n.refs.len > 0
		own_events: vml_defines[P]('apply_event')
	}
	$if P is VmlElementProps {
		facts = VmlFacts{
			...facts
			element: true
		}
	}
	$if P is VmlPartProps {
		facts = VmlFacts{
			...facts
			part: true
		}
	}
	$if P is VmlContainer {
		facts = VmlFacts{
			...facts
			container: true
		}
	}
	$if P is VmlCommonProps {
		facts = VmlFacts{
			...facts
			structure:       n.props.vml_structure()
			authored_width:  n.props.width != none
			authored_height: n.props.height != none
			needs_id:        facts.needs_id || n.props.control_id_required()
		}
	}
	return facts
}

fn (n &VmlWidgetNode[P]) vml_frame(input Rect, placement VmlPlacement) Rect {
	$if P is VmlCommonProps {
		return n.props.resolve_frame(input, placement)
	} $else {
		return input
	}
}

fn (n &VmlWidgetNode[P]) vml_child_input(frame Rect, count int) !Rect {
	$if P is VmlCommonProps {
		return n.props.child_input(frame, count)!
	} $else {
		return rect(0, 0, frame.width, frame.height)
	}
}

fn (n &VmlWidgetNode[P]) vml_child_placement(placement VmlPlacement) VmlPlacement {
	$if P is VmlCommonProps {
		return n.props.child_placement(placement)
	} $else {
		return placement
	}
}

fn (n &VmlWidgetNode[P]) vml_layout_item() VmlLayoutItem {
	$if P is VmlCommonProps {
		$if P is VmlSizedControl {
			if n.props.height == none {
				mut owner := n.owner
				item := n.props.layout_item()
				height := owner.kit_tokens().metrics(n.props.control_size()).height
				return VmlLayoutItem{
					...item
					min_height: if item.min_height > height { item.min_height } else { height }
				}
			}
		}
		return n.props.layout_item()
	} $else {
		return VmlLayoutItem{}
	}
}

fn (n &VmlWidgetNode[P]) vml_part(ctx VmlBuildContext) !VmlPart {
	$if P is VmlPartProps {
		return n.props.part(ctx)!
	} $else {
		return error('${n.vml_type_name()} is not a VML part')
	}
}

fn (n &VmlWidgetNode[P]) vml_has_style() bool {
	$if P is VmlCommonProps {
		return n.props.style != StylePatch{}
	} $else {
		return false
	}
}

fn (n &VmlWidgetNode[P]) vml_styled(el Element, mode VmlStyleMode) !Element {
	$if P is VmlCommonProps {
		if mode != .unstyled && n.props.style != StylePatch{} {
			base := if mode == .reset {
				Element{
					...el
					box: style_reset_box(el.compiled_metadata, el.box)
				}
			} else {
				el
			}
			return apply_style(base, n.props.style)!
		}
	}
	return el
}

// vml_element builds the declaration: validated, built, projected and
// styled, with the stable event entry point.
fn (mut n VmlWidgetNode[P]) vml_element(ctx VmlBuildContext, style VmlStyleMode) !Element {
	$if P is VmlElementProps {
		// A node with its own state or write-backs routes events through
		// dispatch. The build gets the dispatcher as ctx.dispatch, so the
		// widget's parts can send it the widget's events (VmlEmitter).
		dispatches := n.binds.len > 0 || vml_defines[P]('apply_event')
		if dispatches && n.dispatcher == unsafe { nil } {
			mut node := &n
			n.dispatcher = fn [mut node] [P](event ElementEvent) {
				node.dispatch(event)
			}
		}
		build_ctx := if dispatches {
			VmlBuildContext{
				...ctx
				dispatch: n.dispatcher
			}
		} else {
			ctx
		}
		mut element := n.vml_styled(vml_build_element(n.props, build_ctx)!, style)!
		if dispatches {
			n.handler = element.on_event
			if n.binds.len > 0 || element.on_event != unsafe { nil } {
				element = Element{
					...element
					on_event: n.dispatcher
				}
			}
		}
		if n.reactive_geometry {
			element = element.with_layout_frame(element.layout_input or { element.frame })
		}
		return element
	} $else {
		return error('${n.vml_type_name()} is not a VML element')
	}
}

// dispatch updates the props from the event, runs the write-backs in one
// batch, then the built element's handlers (each its own batch).
fn (mut n VmlWidgetNode[P]) dispatch(event ElementEvent) {
	mut owner := n.owner
	if owner.is_disposed() || owner.is_leaving() { return }
	$if P is VmlEventProps {
		before := n.props
		n.props.apply_event(event)
		// Write-backs run for an event that changed the props (the bound
		// event), like the compiled binding callback on its event kind.
		if n.props != before {
			mut runtime := owner.runtime
			runtime.begin_batch() or { return }
			mut failed := false
			mut message := ''
			n.props_changed(before)
			for write in n.binds {
				write(n.props) or {
					failed = true
					message = err.msg()
					break
				}
			}
			if n.binds.len > 0 {
				owner.invalidate_app() or {
					failed = true
					message = err.msg()
				}
			}
			runtime.finish_batch(failed, message) or {
				eprintln('ui2 compiled VML binding failed: ${err}')
			}
		}
	}
	handler := n.VmlNodeCore.handler
	if handler != unsafe { nil } {
		handler(event)
	}
}

// props_changed classifies a props change and schedules the commit.
fn (mut n VmlWidgetNode[P]) props_changed(before P) {
	if n.props == before { return }
	mut change := vml_change_rebuild
	$if P is VmlCommonProps {
		if P{
			...before
			CommonProps: n.props.CommonProps
		} == n.props {
			change = vml_common_change(before.CommonProps, n.props.CommonProps)
		}
	}
	n.VmlNodeCore.changed(change)
}

// vml_commit applies the pending change kinds to the retained node.
fn (mut n VmlWidgetNode[P]) vml_commit() ! {
	pending := n.pending
	n.pending = 0
	mut node := n.VmlNodeCore.node
	if pending == 0 || node == unsafe { nil } || n.owner.is_disposed() { return }
	if n.structure != .plain {
		// The structural effect's body, run now: it is not tracking the props.
		replacement := n.VmlNodeCore.structural_element()!
		input := node.declaration.layout_input or { node.declaration.frame }
		node.reconcile_structure(Element{ ...replacement, layout_input: input }, true)!
	} else if pending & vml_change_rebuild != 0 || (pending & vml_change_fast != 0
		&& vml_defines[P]('project')) {
		n.VmlNodeCore.rebuild_plain()!
	} else if pending & vml_change_fast != 0 {
		$if P is VmlCommonProps {
			n.props.validate()!
			current := node.source_element()
			node.replace_property(vml_project_fast(current, n.props.CommonProps))!
		}
	}
	if pending & vml_change_layout != 0 {
		n.VmlNodeCore.update_child_layout()!
	}
}

// ---------------------------------------------------------------- untyped half

// changed records a change; parts hand it to their consumer.
fn (mut c VmlNodeCore) changed(change u8) {
	if c.node == unsafe { nil } {
		if c.consumed {
			mut consumer := c.consumer()
			if consumer != unsafe { nil } { consumer.changed(vml_change_rebuild) }
		}
		return
	}
	c.pending |= change
	mut node := c.node
	node.mark_widget_dirty()
}

fn (mut c VmlNodeCore) commit() ! {
	mut typed := c.typed()
	typed.vml_commit()!
}

// build_element builds this element node and its subtree (first build).
fn (mut c VmlNodeCore) build_element(input Rect, placement VmlPlacement) !&CompiledVmlNode {
	mut typed := c.typed()
	facts := typed.vml_facts()
	if !facts.element { return error('${typed.vml_type_name()} is not a VML element') }
	c.input = input
	c.placement = placement
	c.has_input = true
	c.structure = facts.structure
	c.authored_width = facts.authored_width
	c.authored_height = facts.authored_height
	c.needs_id = facts.needs_id
	identity := c.local_identity()
	frame := typed.vml_frame(input, placement)
	element_count := if facts.container { c.children.len } else { 0 }
	child_input := if element_count > 0 {
		typed.vml_child_input(frame, element_count)!
	} else {
		Rect{}
	}
	child_placement := typed.vml_child_placement(placement)
	mut elements := []Element{cap: element_count}
	mut layouts := []VmlLayoutItem{cap: element_count}
	mut nodes := []&CompiledVmlNode{cap: element_count}
	mut parts := []VmlPart{}
	for mut child in c.children {
		child_typed := child.typed()
		child_facts := child_typed.vml_facts()
		if child_facts.element && facts.container {
			mut child_node := child.build_element(child_input, child_placement) or {
				return child.src.wrap_error(err)
			}
			elements << child_node.element()
			layouts << child_typed.vml_layout_item()
			nodes << child_node
		} else if child_facts.part {
			parts << child.build_part() or { return child.src.wrap_error(err) }
		} else {
			return child.src.wrap_error(error('${typed.vml_type_name()} does not accept ${child_typed.vml_type_name()} children'))
		}
	}
	declaration := typed.vml_element(VmlBuildContext{
		id:            c.ctx_id()
		key:           c.key
		frame:         frame
		children:      elements
		child_layouts: layouts
		parts:         parts
		owner:         c.owner
	}, .unstyled)!
	// Children follow their own layout item under a Flex, Grid or Stack.
	for index, mut child_node in nodes {
		if rule := vml_child_rule_for(declaration.layout.kind, layouts[index]) {
			child_node.set_child_rule(rule)!
		}
	}
	inherited := placement in [.normal, .inherited_preferred]
	mut node := c.owner.element(declaration,
		identity:        identity
		authored_width:  c.authored_width
		authored_height: c.authored_height
		inherit_width:   inherited && !c.authored_width
		inherit_height:  inherited && !c.authored_height
	)!
	node.widget = &c
	c.node = node
	c.frame_signal = node.frame_value
	for mut ref in c.refs {
		ref.bind(node)!
	}
	// Styled like the compiled style effect: after the unstyled element is
	// retained, over its constructor defaults.
	if typed.vml_has_style() {
		node.replace_property(typed.vml_styled(node.source_element(), .reset)!)!
	}
	if c.structure != .plain {
		if c.structure == .sourced { node.set_sources(elements)! }
		mut core := &c
		node.structure('@widget', fn [mut core] () !Element {
			return core.structural_element()!
		})!
	}
	if c.repeats.len > 0 { vml_attach_segments(mut node, c.VmlChildList, nodes)! }
	return node
}

// build_part builds a part from its own part children.
fn (mut c VmlNodeCore) build_part() !VmlPart {
	c.consumed = true
	parts := c.collect_parts()!
	return c.typed().vml_part(VmlBuildContext{
		id:    c.id
		key:   c.key
		parts: parts
		owner: c.owner
	})!
}

fn (mut c VmlNodeCore) collect_parts() ![]VmlPart {
	mut parts := []VmlPart{}
	for mut child in c.children {
		if child.node != unsafe { nil } { continue }
		if child.typed().vml_facts().part {
			parts << child.build_part()!
		}
	}
	return parts
}

// structural_element rebuilds a structural widget from its current sources,
// at its resolved frame, like the compiled structural effect.
fn (mut c VmlNodeCore) structural_element() !Element {
	mut node := c.node
	element := node.element()
	children := if c.structure == .sourced { node.child_elements()! } else { []Element{} }
	frame := node.frame()!
	parts := c.collect_parts()!
	mut typed := c.typed()
	return typed.vml_element(VmlBuildContext{
		id:       c.ctx_id()
		key:      element.key
		frame:    frame
		children: children
		parts:    parts
		owner:    c.owner
	}, .direct)!
}

// rebuild_plain rebuilds a plain element at its current frame and children
// and patches the retained declaration.
fn (mut c VmlNodeCore) rebuild_plain() ! {
	mut node := c.node
	current := node.source_element()
	mut typed := c.typed()
	frame := typed.vml_frame(current.layout_input or { current.frame }, .normal)
	mut layouts := []VmlLayoutItem{}
	if current.layout.kind in [.flex, .grid, .stack] {
		visible := node.collect_visible(node.children)
		layouts = []VmlLayoutItem{cap: visible.len}
		for child in visible {
			layouts << child.child_layout.layout_item()
		}
	}
	parts := c.collect_parts()!
	rebuilt := typed.vml_element(VmlBuildContext{
		id:            c.ctx_id()
		key:           current.key
		frame:         frame
		children:      current.children
		child_layouts: layouts
		parts:         parts
		owner:         c.owner
	}, .reset)!
	node.replace_property(Element{
		...rebuilt
		id:  current.id
		key: current.key
	})!
}

// update_child_layout gives the retained node the rule of its current layout
// item under its parent's layout.
fn (mut c VmlNodeCore) update_child_layout() ! {
	mut node := c.node
	mut parent := node.parent
	for parent != unsafe { nil } && parent.is_fragment {
		parent = parent.parent
	}
	if parent == unsafe { nil } { return }
	if rule := vml_child_rule_for(parent.declaration.layout.kind, c.typed().vml_layout_item()) {
		node.set_child_rule(rule)!
	}
}

fn vml_child_rule_for(kind LayoutKind, item VmlLayoutItem) ?VmlChildRule {
	return match kind {
		.flex {
			VmlChildRule{
				flex: item.flex_rule()
			}
		}
		.grid {
			VmlChildRule{
				grid: item.grid_span()
			}
		}
		.stack {
			VmlChildRule{
				stack: item.stack_rule()
			}
		}
		else { none }
	}
}

fn (rule VmlChildRule) layout_item() VmlLayoutItem {
	return VmlLayoutItem{
		flex_basis:   rule.flex.basis
		flex_grow:    rule.flex.grow
		flex_shrink:  rule.flex.shrink
		min_width:    rule.flex.minimum_width
		min_height:   rule.flex.minimum_height
		max_width:    rule.flex.maximum_width
		max_height:   rule.flex.maximum_height
		align_self:   rule.flex.align_self
		column_span:  rule.grid.column_span
		row_span:     rule.grid.row_span
		align_self_x: rule.stack.align_x
		align_self_y: rule.stack.align_y
	}
}

// ---------------------------------------------------------------- change kinds

// vml_common_change classifies a change confined to CommonProps. Fast fields
// are projected onto the retained element without calling build (no build
// reads them); layout item fields only change the child rule.
fn vml_common_change(before CommonProps, after CommonProps) u8 {
	if before.x != after.x || before.y != after.y || before.width != after.width
		|| before.height != after.height || before.style != after.style
		|| before.enabled != after.enabled || before.hidden != after.hidden
		|| before.native != after.native || before.autocorrect != after.autocorrect
		|| before.secure != after.secure || before.keys != after.keys
		|| !vml_same_handlers(before, after) {
		return vml_change_rebuild
	}
	mut change := u8(0)
	if before.VmlLayoutItem != after.VmlLayoutItem { change |= vml_change_layout }
	if vml_fast_fields(before) != vml_fast_fields(after) {
		// A fast field that becomes absent restores the build default.
		if !vml_fast_fields_present(before, after) { return change | vml_change_rebuild }
		change |= vml_change_fast
	}
	return change
}

fn vml_same_handlers(a CommonProps, b CommonProps) bool {
	return a.on_click == b.on_click && a.on_change == b.on_change && a.on_scroll == b.on_scroll
		&& a.on_open == b.on_open && a.on_dismiss == b.on_dismiss
		&& a.on_pointer_down == b.on_pointer_down && a.on_pointer_drag == b.on_pointer_drag
		&& a.on_pointer_up == b.on_pointer_up && a.on_long_press == b.on_long_press
		&& a.on_swipe_left == b.on_swipe_left && a.on_link == b.on_link
		&& a.on_submit == b.on_submit && a.on_key == b.on_key
		&& a.on_pointer_enter == b.on_pointer_enter && a.on_pointer_leave == b.on_pointer_leave
}

// The fields projected verbatim onto the element that no build reads.
struct VmlFastFields {
	button_behavior     ?bool
	clickable           ?bool
	draggable           ?bool
	long_press          ?bool
	swipe_left          ?bool
	rotation            ?f64
	opacity             ?f64
	motion              ?MotionConfig
	translate_x         ?f64
	translate_y         ?f64
	scale_x             ?f64
	scale_y             ?f64
	origin_x            ?f64
	origin_y            ?f64
	cursor              ?string
	tooltip             ?string
	accessibility_role  ?string
	accessibility_label ?string
	accessibility_value ?string
}

fn vml_fast_fields(p CommonProps) VmlFastFields {
	return VmlFastFields{
		button_behavior:     p.button_behavior
		clickable:           p.clickable
		draggable:           p.draggable
		long_press:          p.long_press
		swipe_left:          p.swipe_left
		rotation:            p.rotation
		opacity:             p.opacity
		motion:              p.motion
		translate_x:         p.translate_x
		translate_y:         p.translate_y
		scale_x:             p.scale_x
		scale_y:             p.scale_y
		origin_x:            p.origin_x
		origin_y:            p.origin_y
		cursor:              p.cursor
		tooltip:             p.tooltip
		accessibility_role:  p.accessibility_role
		accessibility_label: p.accessibility_label
		accessibility_value: p.accessibility_value
	}
}

// Every fast field present before is still present after.
fn vml_fast_fields_present(before CommonProps, after CommonProps) bool {
	return (before.button_behavior == none || after.button_behavior != none)
		&& (before.clickable == none || after.clickable != none)
		&& (before.draggable == none || after.draggable != none)
		&& (before.long_press == none || after.long_press != none)
		&& (before.swipe_left == none || after.swipe_left != none)
		&& (before.rotation == none || after.rotation != none)
		&& (before.opacity == none || after.opacity != none)
		&& (before.motion == none || after.motion != none)
		&& (before.translate_x == none || after.translate_x != none)
		&& (before.translate_y == none || after.translate_y != none)
		&& (before.scale_x == none || after.scale_x != none)
		&& (before.scale_y == none || after.scale_y != none)
		&& (before.origin_x == none || after.origin_x != none)
		&& (before.origin_y == none || after.origin_y != none)
		&& (before.cursor == none || after.cursor != none)
		&& (before.tooltip == none || after.tooltip != none)
		&& (before.accessibility_role == none || after.accessibility_role != none)
		&& (before.accessibility_label == none || after.accessibility_label != none)
		&& (before.accessibility_value == none || after.accessibility_value != none)
}

// vml_project_fast projects the fast fields onto a retained element, exactly
// as project_common does for them.
fn vml_project_fast(el Element, p CommonProps) Element {
	return Element{
		...el
		button_behavior:     p.button_behavior or { el.button_behavior }
		clickable:           p.clickable or { el.clickable }
		draggable:           p.draggable or { el.draggable }
		long_press:          p.long_press or { el.long_press }
		swipe_left:          p.swipe_left or { el.swipe_left }
		rotation:            p.rotation or { el.rotation }
		opacity:             p.opacity or { el.opacity }
		motion:              if motion := p.motion { ?MotionConfig(motion) } else { el.motion }
		translate_x:         p.translate_x or { el.translate_x }
		translate_y:         p.translate_y or { el.translate_y }
		scale_x:             p.scale_x or { el.scale_x }
		scale_y:             p.scale_y or { el.scale_y }
		origin_x:            p.origin_x or { el.origin_x }
		origin_y:            p.origin_y or { el.origin_y }
		cursor:              p.cursor or { el.cursor }
		tooltip:             p.tooltip or { el.tooltip }
		accessibility_role:  p.accessibility_role or { el.accessibility_role }
		accessibility_label: p.accessibility_label or { el.accessibility_label }
		accessibility_value: p.accessibility_value or { el.accessibility_value }
	}
}

// ---------------------------------------------------------------- helpers

// vml_assign converts a widget value for a binding write-back to the type of
// the bound target (replaces vml_binding_number). A mismatch is named by the
// widget value: a text binding needs a string target, whatever it is.
pub fn vml_assign[T, V](current T, value V) T {
	_ = current
	$if V is string {
		$if T is string {
			return value
		} $else {
			$compile_error('VML text binding must target a string')
		}
	} $else $if V is DisplayText {
		$if T is string {
			return value.str()
		} $else {
			$compile_error('VML text binding must target a string')
		}
	} $else $if V is bool {
		$if T is bool {
			return value
		} $else {
			$compile_error('VML checked binding must target bool')
		}
	} $else $if V is $int || V is $float {
		$if T is $int || T is $float {
			return T(value)
		} $else {
			$compile_error('VML value binding must target a number')
		}
	} $else $if V is []string {
		$if T is []string {
			return value.clone()
		} $else {
			$compile_error('VML values binding must target a []string')
		}
	} $else {
		$compile_error('VML binding target must be a string, bool, number or []string')
	}
}

// vml_guard_child rejects, at the generated call, a child tag C its parent P
// cannot hold: parts are always accepted, elements need a container parent.
pub fn vml_guard_child[P, C]() {
	$if C is VmlPartProps {
	} $else $if C is VmlElementProps {
		$if P !is VmlContainer {
			$compile_error('this VML element does not accept element children')
		}
	} $else {
		$compile_error('this VML tag cannot be a child')
	}
}

// vml_guard_positioned rejects authored x/y under a parent that does not
// position its children.
pub fn vml_guard_positioned[Q]() {
	$if Q !is VmlPositioner {
		$compile_error('x and y require an Absolute parent')
	}
}
