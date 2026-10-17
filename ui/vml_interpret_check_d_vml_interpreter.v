module ui2

import vml

// The VML interpreter's loader (design §3.3), compiled only with
// `-d vml_interpreter`. It resolves a parsed document once into an IR in which
// every name is a slot of a lexical scope, so a build only evaluates. The
// walk follows the compiled lowering: declaration paths, the order in which
// ids become visible (an id is visible in its own properties, its subtree and
// everything declared after it in the same component; repeaters see every
// static sibling), component scopes, slot content resolved where it was
// written, and repeater items. Anything outside the expression subset, an
// unknown name or element, a model path the model type does not have, or a
// method outside the signature table is an error here, before anything runs.

// ------------------------------------------------------------------ the IR

enum VmlIKind {
	literal     // value
	enum_name   // value: a VmlEnum
	app_field   // name: a top-level model field
	binding     // depth, slot: a scope value (state, item, input, ...)
	member      // args[0].name
	length      // args[0].len
	to_str      // args[0].str()
	token       // name: `color:x`, `spacing:x`, `radius:x` or `font_size:x`
	geometry    // depth, slot: an element; name: x, y, width or height
	not_        // !args[0]
	negate      // -args[0]
	binary      // args[0] name args[1]
	and_        // args[0] && args[1]
	or_         // args[0] || args[1]
	conditional // args[0] ? args[1] : args[2]
	array       // [args]
	interp      // the concatenation of args (text parts are literals)
	app_call    // name(args) on the model
	fn_call     // depth, slot: a component function; args
	emit        // depth, slot: a component event; args
	ref_call    // depth, slot: a ref; name: its method; args
	style_call  // name: a style helper; args[0]
	motion_call // name: a motion helper; args
	style_state // name: hover, focus, pressed or disabled; args: patches
	// Handler references: a callable value.
	app_method // name: `on_x: app.method`
	fn_ref     // depth, slot: `on_x: local_fn`
	event_ref  // depth, slot: `on_x: component_event`
	external   // name: a callback from VmlInterpretConfig.callbacks
	// Statements.
	assign_app   // name = args[0]
	assign_state // depth, slot = args[0]
	assign_input // depth, slot = args[0] (a bindable input)
	block        // args, in order
}

@[heap]
struct VmlIExpr {
	kind  VmlIKind
	name  string
	value VmlValue = VmlNone{}
	depth int
	slot  int = -1
	args  []&VmlIExpr
	typ   &VmlModelType = unsafe { nil }
	func  &VmlIFunction = unsafe { nil }
	src   VmlSourceLocation
}

enum VmlScopeKind {
	document
	component
	item
	key
	slot
	function
	listener
	handler
}

enum VmlBindKind {
	state
	computed
	input
	item
	index
	func
	event
	ref
	id
	param
}

struct VmlBinding {
	kind     VmlBindKind
	slot     int
	writable bool
	params   []vml.Parameter
	func     &VmlIFunction = unsafe { nil }
	ref_kind Kind
	typ      &VmlModelType = unsafe { nil }
}

// VmlScope is one lexical scope. Scopes that own a component owner at run
// time (document, component, item, slot) also collect the theme tokens their
// expressions read, which are prepared before any memo can read them.
@[heap]
struct VmlScope {
	kind   VmlScopeKind
	parent &VmlScope = unsafe { nil }
	// The scope a component was invoked from: its slot content resolves there.
	caller &VmlScope = unsafe { nil }
mut:
	names  map[string]VmlBinding
	slots  int
	tokens []string
}

fn (mut s VmlScope) add(name string, binding VmlBinding) VmlBinding {
	bound := VmlBinding{
		...binding
		slot: s.slots
	}
	s.names[name] = bound
	s.slots++
	return bound
}

// owner_scope is the nearest scope with its own component owner.
fn (s &VmlScope) owner_scope() &VmlScope {
	mut current := unsafe { s }
	for current.kind in [.key, .function, .listener, .handler] && current.parent != unsafe { nil } {
		current = current.parent
	}
	return current
}

fn (s &VmlScope) lookup(name string) ?(VmlBinding, int) {
	mut current := unsafe { s }
	mut depth := 0
	for current != unsafe { nil } {
		if binding := current.names[name] { return binding, depth }
		current = current.parent
		depth++
	}
	return none
}

@[heap]
struct VmlIFunction {
	name   string
	params []vml.Parameter
	scope  &VmlScope = unsafe { nil }
mut:
	body &VmlIExpr = unsafe { nil }
}

enum VmlINodeKind {
	element
	component
	repeater
}

struct VmlIProp {
	name     string
	expr     &VmlIExpr = unsafe { nil }
	reactive bool
	uses_app bool
	// A style property: lists and nested style names compose into one patch.
	style bool
	// A motion property: helper patches and lists of them compose into one
	// MotionConfig.
	motion bool
	src    VmlSourceLocation
}

struct VmlIEvent {
	name     string
	handler  &VmlIExpr = unsafe { nil }
	scope    &VmlScope = unsafe { nil } // the handler scope (`event`)
	uses_app bool
}

struct VmlIBind {
	prop   string
	target &VmlIExpr = unsafe { nil } // the bound value, read
	write  &VmlIExpr = unsafe { nil } // its assignment; args[0] is filled at run time
}

enum VmlInputKind {
	event
	argument
	bound
	default_value
}

struct VmlIInput {
	name     string
	typ      string
	kind     VmlInputKind
	slot     int
	expr     &VmlIExpr = unsafe { nil } // value: caller scope (argument, bound) or component scope
	uses_app bool
	// event: the handler in the listener scope, or nil for no handler
	handler &VmlIExpr = unsafe { nil }
	scope   &VmlScope = unsafe { nil }
	params  []vml.Parameter
	// bound: the caller's target, written before the input's own state
	write &VmlIExpr = unsafe { nil }
}

struct VmlIData {
	name     string
	slot     int
	computed bool
	expr     &VmlIExpr = unsafe { nil }
	uses_app bool
}

struct VmlIRef {
	name string
	slot int
	kind Kind
	tag  string
}

@[heap]
struct VmlIComponent {
	name       string
	owner_name string
	scope      &VmlScope = unsafe { nil }
mut:
	inputs  []VmlIInput
	refs    []VmlIRef
	data    []VmlIData
	mount   &VmlIExpr = unsafe { nil }
	unmount &VmlIExpr = unsafe { nil }
	cleanup &VmlIExpr = unsafe { nil }
	root    &VmlINode = unsafe { nil }
	// The invocation's key, child layout properties and ref, in the caller's
	// scope; the instance id is exported to the caller's frame.
	key    &VmlIExpr = unsafe { nil }
	layout []VmlIProp
	ref    &VmlIExpr = unsafe { nil }
}

@[heap]
struct VmlIRepeater {
	name           string
	model          &VmlIExpr = unsafe { nil }
	model_uses_app bool
	key            &VmlIExpr = unsafe { nil }
	key_scope      &VmlScope = unsafe { nil }
	item_scope     &VmlScope = unsafe { nil }
	item_slot      int
	index_slot     int
mut:
	children []&VmlINode
}

@[heap]
struct VmlINode {
	kind VmlINodeKind
	tag  string
	path string
	src  VmlSourceLocation
	// Slot content: built with its own owner in a scope of the author's.
	slot_scope       &VmlScope = unsafe { nil }
	slot_from_caller bool
mut:
	widget VmlWidgetType
	id     string
	// The id's slot in the frame the node is declared in (-1: no id).
	id_slot  int       = -1
	key      &VmlIExpr = unsafe { nil }
	props    []VmlIProp
	events   []VmlIEvent
	binds    []VmlIBind
	ref      &VmlIExpr = unsafe { nil }
	children []&VmlINode
	comp     &VmlIComponent = unsafe { nil }
	repeat   &VmlIRepeater  = unsafe { nil }
}

// VmlProgram is a loaded document: its IR and the scope of its root.
@[heap]
pub struct VmlProgram {
pub:
	path string
mut:
	root  &VmlINode = unsafe { nil }
	scope &VmlScope = unsafe { nil }
	menus bool
	// External callback names the document uses.
	externals []string
	// Every file of the document (the root and its imports), for watching.
	files []string
}

// ---------------------------------------------------------------- language

const vml_reserved_roots = ['app', 'color', 'spacing', 'radius', 'typography']

const vml_geometry_props = ['x', 'y', 'width', 'height']

const vml_layout_tags = ['Flex', 'Row', 'Column', 'Grid']

const vml_part_tags = ['Keyframe', 'MenuItem', 'Option', 'Run', 'Timeline']

// Child layout properties an invocation passes to its component's root.
const vml_child_layout_props = ['flex_grow', 'flex_shrink', 'flex_basis', 'min_width', 'max_width',
	'min_height', 'max_height', 'align_self', 'column_span', 'row_span', 'align_self_x', 'align_self_y']

const vml_state_styles = ['hover', 'focus', 'pressed', 'disabled']

// The style helpers of ui/style.v and the kind of their argument.
const vml_style_helpers = {
	'background':          VmlValueKind.color
	'radius':              .number
	'transparent':         .boolean
	'border_color':        .color
	'border_left':         .number
	'border_top':          .number
	'border_right':        .number
	'border_bottom':       .number
	'border_left_color':   .color
	'border_top_color':    .color
	'border_right_color':  .color
	'border_bottom_color': .color
	'border_pattern':      .enumeration
	'dash_length':         .number
	'dash_gap':            .number
	'outline_color':       .color
	'outline_width':       .number
	'outline_offset':      .number
	'foreground':          .color
	'text_background':     .color
	'font_size':           .number
	'font_family':         .string
	'weight':              .integer
	'letter_spacing':      .number
	'line_height':         .number
	'line_height_factor':  .number
	'baseline_offset':     .number
	'tabular_figures':     .boolean
	'italic':              .boolean
	'underline':           .boolean
	'strikethrough':       .boolean
	'shadow':              .boolean
	'text_outline':        .boolean
	'vertical_align':      .string
	'link':                .string
	'text_align':          .enumeration
	'text_valign':         .enumeration
	'head_indent':         .number
	'first_line_indent':   .number
	'hyphenation_factor':  .number
	'lines':               .integer
	'padding_left':        .number
	'padding_top':         .number
	'padding_right':       .number
	'padding_bottom':      .number
	'padding':             .number
	'border_width':        .number
}

// Box properties (and foreground) are the ones interaction styles accept.
const vml_box_style_helpers = ['background', 'radius', 'transparent', 'border_color', 'border_left',
	'border_top', 'border_right', 'border_bottom', 'border_left_color', 'border_top_color',
	'border_right_color', 'border_bottom_color', 'border_pattern', 'dash_length', 'dash_gap',
	'outline_color', 'outline_width', 'outline_offset', 'padding_left', 'padding_top', 'padding_right',
	'padding_bottom', 'padding', 'border_width', 'foreground']

// The motion helpers of ui/motion_patch.v and the kinds of their arguments.
// A `motion` value composes the patches they return, as compiled VML's
// `ui2.motion_compose` does. enter and exit take a MotionStyle, timeline and
// target a MotionTimeline: model values.
const vml_motion_helpers = {
	'fade':           [VmlValueKind.number]
	'slide_x':        [VmlValueKind.number]
	'slide_y':        [VmlValueKind.number]
	'scale':          [VmlValueKind.number]
	'rotate':         [VmlValueKind.number]
	'duration':       [VmlValueKind.number]
	'enter_duration': [VmlValueKind.number]
	'exit_duration':  [VmlValueKind.number]
	'transition':     [VmlValueKind.number]
	'spring':         [VmlValueKind.number, .number]
	'easing':         [VmlValueKind.enumeration]
	'layout':         [VmlValueKind.enumeration]
	'reduced':        [VmlValueKind.boolean]
	'enter':          [VmlValueKind.object]
	'exit':           [VmlValueKind.object]
	'timeline':       [VmlValueKind.object]
	'target':         [VmlValueKind.string, .object]
}

// The motion helpers that take a V callback or handle, which a document
// cannot write.
const vml_compiled_motion_helpers = ['on', 'handle', 'clock']

// The control kind a `ref name Type` declaration names.
fn vml_ref_kind_of(tag string) ?Kind {
	return match tag {
		'Button' { .button }
		'View', 'Dialog', 'Popover', 'MenuOverlay', 'ContextMenu', 'Tooltip' { .view }
		'Label' { .label }
		'Image' { .image }
		'TextInput' { .text_field }
		'TextArea' { .text_area }
		'Scroll' { .scroll }
		'Checkbox' { .checkbox }
		'Dropdown' { .dropdown }
		'Slider' { .slider }
		'Switch' { .switch_control }
		'ToggleButton' { .toggle_button }
		else { none }
	}
}

fn vml_var(path string) string {
	return path.replace('.', '_').replace('-', '_')
}

fn vml_src(source string, line int, column int) VmlSourceLocation {
	return VmlSourceLocation{
		source: source
		line:   line
		column: column
	}
}

fn vml_expr_src(e &vml.Expr) VmlSourceLocation {
	return vml_src(e.source, e.line, e.column)
}

fn vml_node_src(n &vml.Node) VmlSourceLocation {
	return vml_src(n.source, n.line, n.column)
}

fn (src VmlSourceLocation) error(message string) IError {
	if src.source.len > 0 {
		return error('${src.source}:${src.line}:${src.column}: ${message}')
	}
	if src.line > 0 { return error('${message} at line ${src.line}, column ${src.column}') }
	return error(message)
}

fn vml_is_event(name string) bool {
	return name.starts_with('on_')
}

// ----------------------------------------------------------------- checker

struct VmlChecker {
	model     &VmlModel = unsafe { nil }
	callbacks map[string]ElementCallback
	lenient   bool // unknown external callbacks are allowed (previews)
mut:
	externals []string
}

// vml_check resolves a parsed document against a model.
fn vml_check(root &vml.Node, model &VmlModel, callbacks map[string]ElementCallback, lenient bool) !&VmlProgram {
	mut c := VmlChecker{
		model:     model
		callbacks: callbacks
		lenient:   lenient
	}
	mut scope := &VmlScope{
		kind: .document
	}
	mut program := &VmlProgram{
		path:  root.source
		scope: scope
		menus: root.tag in ['Menu', 'MenuBar']
	}
	if root.tag == vml.component_tag && root.children.len == 0 {
		return vml_node_src(root).error('component `${root.component_name}` has no root element')
	}
	program.root = c.node(root, '0', mut scope, false)!
	program.externals = c.externals
	return program
}

// node resolves an element, a component invocation or slot content at `path`
// in `scope`, adding the ids it declares to `scope`.
fn (mut c VmlChecker) node(n &vml.Node, path string, mut scope VmlScope, keyed bool) !&VmlINode {
	if n.caller_content {
		// Written by the component's caller: resolve where it was written, with
		// an owner of its own (CompiledVmlComponent.slot_child).
		from_caller := scope.kind == .component && scope.caller != unsafe { nil }
		lexical := if from_caller { scope.caller } else { &scope }
		mut slot_scope := &VmlScope{
			kind:   .slot
			parent: lexical
		}
		content := &vml.Node{
			...n
			caller_content: false
		}
		mut inner := c.node(content, path, mut slot_scope, keyed)!
		return &VmlINode{
			...inner
			slot_scope:       slot_scope
			slot_from_caller: from_caller
		}
	}
	if n.tag == vml.component_tag {
		return c.component(n, path, mut scope, keyed)
	}
	if n.tag == 'Repeater' {
		return vml_node_src(n).error('a Repeater must be the child of a container')
	}
	if n.tag == 'Slot' {
		return vml_node_src(n).error('`Slot` is only valid inside a component')
	}
	return c.element(n, path, mut scope, keyed)
}

// element resolves an element. `keyed` is set for the root of a component
// whose invocation has a key: that key replaces the root's own.
fn (mut c VmlChecker) element(n &vml.Node, path string, mut scope VmlScope, keyed bool) !&VmlINode {
	src := vml_node_src(n)
	widget := vml_widget_type(n.tag) or {
		return src.error('unknown VML element `${n.tag}`; the interpreter knows ${vml_widget_tags().join(', ')}')
	}
	mut node := &VmlINode{
		kind:   .element
		tag:    n.tag
		path:   path
		src:    src
		widget: widget
		id:     n.id
	}
	if n.id.len > 0 {
		if n.id in vml_reserved_roots {
			return src.error('element id `${n.id}` collides with the reserved name `${n.id}`')
		}
		node.id_slot = scope.add(n.id, VmlBinding{
			kind: .id
		}).slot
	}
	c.collect_tokens(n, mut scope)
	mut geometry := []vml.Property{}
	mut others := []vml.Property{}
	for property in n.properties {
		if property.name in vml_geometry_props {
			geometry << property
		} else {
			others << property
		}
	}
	for property in vml_order_properties(geometry, n.id) {
		node.props << c.prop(n, widget, property, scope)!
	}
	mut bindings := 0
	for property in others {
		if property.name == 'id' { continue }
		if property.name == 'key' {
			if !keyed {
				node.key = c.expr(property.expr, scope, true)!
			}
			continue
		}
		if property.name == 'ref' {
			node.ref = c.ref_target(n, property, scope)!
			continue
		}
		if property.name.starts_with('bind.') {
			bindings++
			if bindings > 1 {
				return vml_property_src(n, property).error('an element takes one binding')
			}
			node.binds << c.bind(n, widget, property, scope)!
			continue
		}
		if vml_is_event(property.name) {
			node.events << c.event(n, widget, property, scope)!
			continue
		}
		node.props << c.prop(n, widget, property, scope)!
	}
	// Children in the order the compiled lowering visits them: static children
	// first (an id declared by one is visible to the next), then repeaters,
	// which see every static sibling. Declaration order is kept for building.
	layout := n.tag in vml_layout_tags
	mut resolved := []&VmlINode{len: n.children.len, init: unsafe { nil }}
	mut visible := 0
	mut repeaters := []int{}
	for index, child in n.children {
		part := child.tag in vml_part_tags
		child_path := if layout && !part { '${path}.${visible}' } else { '${path}.${index}' }
		if !part { visible++ }
		if child.tag == 'Repeater' {
			repeaters << index
			continue
		}
		resolved[index] = c.node(child, child_path, mut scope, false)!
	}
	for index in repeaters {
		resolved[index] = c.repeater(n.children[index], '${vml_var(path)}.${index}', mut scope)!
	}
	node.children = resolved
	return node
}

fn vml_property_src(n &vml.Node, property vml.Property) VmlSourceLocation {
	return vml_src(if property.expr.source.len > 0 { property.expr.source } else { n.source },
		property.line, property.column)
}

// vml_order_properties orders geometry properties so that one reading
// another property of its own element comes after it, like the compiled
// lowering; a cycle keeps source order.
fn vml_order_properties(properties []vml.Property, node_id string) []vml.Property {
	mut remaining := properties.clone()
	if node_id.len == 0 || remaining.len < 2 { return remaining }
	mut ordered := []vml.Property{cap: remaining.len}
	for remaining.len > 0 {
		mut deferred := []vml.Property{cap: remaining.len}
		for property in remaining {
			mut pending := false
			for candidate in remaining {
				if candidate.name != property.name
					&& vml.expr_uses_path(property.expr, '${node_id}.${candidate.name}') {
					pending = true
					break
				}
			}
			if pending {
				deferred << property
			} else {
				ordered << property
			}
		}
		if deferred.len == remaining.len {
			ordered << deferred
			break
		}
		remaining = deferred.clone()
	}
	return ordered
}

fn (mut c VmlChecker) prop(n &vml.Node, widget VmlWidgetType, property vml.Property, scope &VmlScope) !VmlIProp {
	src := vml_property_src(n, property)
	info := widget.prop(property.name) or {
		if property.name == 'model' {
			return src.error('`model` is a Repeater property')
		}
		return src.error('`${n.tag}` has no property `${property.name}`')
	}
	if info.is_event {
		return src.error('`${property.name}` of `${n.tag}` is an event')
	}
	if info.kind == .other {
		return src.error('property `${property.name}` of `${n.tag}` cannot be set by the interpreter; use compiled VML')
	}
	if property.name == 'style' {
		c.check_style(n, property.expr, false)!
	}
	if property.name == 'motion' {
		c.check_motion(property.expr)!
	}
	// A bare name is an enum value only where the property takes one.
	if property.expr.kind == .path && !property.expr.value.contains('.')
		&& !property.expr.value.starts_with('#') && info.kind != .enumeration {
		_, _ := scope.lookup(property.expr.value) or {
			return src.error('unknown name `${property.expr.value}`')
		}
	}
	expr := c.expr(property.expr, scope, true)!
	return VmlIProp{
		name:     property.name
		expr:     expr
		reactive: vml_ir_reactive(expr)
		uses_app: vml_ir_uses_app(expr)
		style:    info.kind == .style
		motion:   property.name == 'motion'
		src:      src
	}
}

fn (mut c VmlChecker) bind(n &vml.Node, widget VmlWidgetType, property vml.Property, scope &VmlScope) !VmlIBind {
	src := vml_property_src(n, property)
	name := property.name.all_after('bind.')
	info := widget.prop(name) or { return src.error('`${n.tag}` has no property `${name}`') }
	if !info.bindable {
		return src.error('property `${name}` of `${n.tag}` is not bindable')
	}
	if property.expr.kind != .path {
		return src.error('a binding target must be `app.field` or a writable name')
	}
	target := c.expr(property.expr, scope, false)!
	write := c.assignment_target(property.expr, scope, src)!
	return VmlIBind{
		prop:   name
		target: target
		write:  write
	}
}

fn (mut c VmlChecker) event(n &vml.Node, widget VmlWidgetType, property vml.Property, scope &VmlScope) !VmlIEvent {
	src := vml_property_src(n, property)
	info := widget.prop(property.name) or {
		return src.error('`${n.tag}` has no event `${property.name}`')
	}
	if !info.is_event {
		return src.error('`${property.name}` of `${n.tag}` is not an event')
	}
	mut handler_scope := &VmlScope{
		kind:   .handler
		parent: scope
	}
	handler_scope.add('event', VmlBinding{
		kind: .param
		typ:  vml_event_type()
	})
	handler := c.handler(property.expr, mut handler_scope, [])!
	return VmlIEvent{
		name:     property.name
		handler:  handler
		scope:    handler_scope
		uses_app: vml_ir_uses_app(handler)
	}
}

fn vml_event_type() &VmlModelType {
	mut seen := map[string]&VmlModelType{}
	return vml_model_type(ElementEvent{}, mut seen)
}

fn (mut c VmlChecker) ref_target(n &vml.Node, property vml.Property, scope &VmlScope) !&VmlIExpr {
	src := vml_property_src(n, property)
	if property.expr.kind != .path || property.expr.value.contains('.') {
		return src.error('`ref` takes the name of a `ref` declaration')
	}
	binding, depth := scope.lookup(property.expr.value) or {
		return src.error('unknown ref `${property.expr.value}`')
	}
	if binding.kind != .ref {
		return src.error('`${property.expr.value}` is not a ref')
	}
	mut control := unsafe { n }
	for control.tag == vml.component_tag && control.children.len > 0 {
		control = control.children[0]
	}
	kind := vml_ref_kind_of(control.tag) or {
		return src.error('`${control.tag}` cannot be the target of a ref')
	}
	if kind != binding.ref_kind {
		return src.error('ref `${property.expr.value}` requires ${binding.ref_kind}; received ${control.tag}')
	}
	return &VmlIExpr{
		kind:  .binding
		depth: depth
		slot:  binding.slot
		src:   src
	}
}

// collect_tokens records the theme tokens an element's properties read in the
// scope that owns their component owner.
fn (mut c VmlChecker) collect_tokens(n &vml.Node, mut scope VmlScope) {
	mut names := []string{}
	for property in n.properties {
		vml_expr_tokens(property.expr, mut names)
	}
	vml_add_tokens(scope, names)
}

fn vml_add_tokens(scope &VmlScope, names []string) {
	mut owner := scope.owner_scope()
	for name in names {
		if name !in owner.tokens { owner.tokens << name }
	}
}

fn vml_expr_tokens(e &vml.Expr, mut names []string) {
	if e.kind == .path {
		for pair in [['color', 'color'], ['spacing', 'spacing'], ['radius', 'radius'],
			['typography', 'font_size']] {
			if e.value.starts_with(pair[0] + '.') {
				name := pair[1] + ':' + e.value.all_after(pair[0] + '.')
				if name !in names { names << name }
			}
		}
	}
	if !isnil(e.left) { vml_expr_tokens(e.left, mut names) }
	if !isnil(e.right) { vml_expr_tokens(e.right, mut names) }
	if !isnil(e.third) { vml_expr_tokens(e.third, mut names) }
	for arg in e.args { vml_expr_tokens(arg, mut names) }
	for part in e.parts {
		if !isnil(part.expr) { vml_expr_tokens(part.expr, mut names) }
	}
}

// --------------------------------------------------------------- repeaters

fn (mut c VmlChecker) repeater(n &vml.Node, path string, mut scope VmlScope) !&VmlINode {
	src := vml_node_src(n)
	model_property := vml.find_property(n, 'model') or {
		return src.error('a Repeater requires `model`')
	}
	key_property := vml.find_property(n, 'key') or {
		return src.error('a Repeater requires `key`')
	}
	for property in n.properties {
		if property.name !in ['model', 'key'] {
			return vml_property_src(n, property).error('a Repeater takes only `model` and `key`, not `${property.name}`')
		}
	}
	model := c.expr(model_property.expr, scope, false)!
	mut item_type := &VmlModelType(unsafe { nil })
	if model.typ != unsafe { nil } {
		if model.typ.kind != .array && model.typ.kind != .dynamic {
			return vml_property_src(n, model_property).error('a Repeater model must be an array, not ${model.typ.describe()}')
		}
		item_type = model.typ.elem
	}
	mut key_scope := &VmlScope{
		kind:   .key
		parent: &scope
	}
	key_scope.add('item', VmlBinding{
		kind: .item
		typ:  item_type
	})
	key := c.expr(key_property.expr, key_scope, false)!
	mut item_scope := &VmlScope{
		kind:   .item
		parent: &scope
	}
	item_slot := item_scope.add('item', VmlBinding{
		kind: .item
		typ:  item_type
	}).slot
	index_slot := item_scope.add('index', VmlBinding{
		kind: .index
	}).slot
	mut repeat := &VmlIRepeater{
		name:           vml_var(path)
		model:          model
		model_uses_app: vml_ir_uses_app(model)
		key:            key
		key_scope:      key_scope
		item_scope:     item_scope
		item_slot:      item_slot
		index_slot:     index_slot
	}
	// Items hold the element children in order (a nested repeater sees the
	// ids declared before it); parts are not items, as in compiled VML.
	mut resolved := []&VmlINode{}
	for child in n.children {
		if child.tag in vml_part_tags { continue }
		child_path := '${path}.${resolved.len}'
		if child.tag == 'Repeater' {
			resolved << c.repeater(child, child_path, mut item_scope)!
		} else {
			resolved << c.node(child, child_path, mut item_scope, false)!
		}
	}
	repeat.children = resolved
	return &VmlINode{
		kind:   .repeater
		tag:    'Repeater'
		path:   path
		src:    src
		repeat: repeat
	}
}

// -------------------------------------------------------------- components

fn (mut c VmlChecker) component(n &vml.Node, path string, mut caller VmlScope, keyed bool) !&VmlINode {
	src := vml_node_src(n)
	if n.children.len == 0 {
		return src.error('component `${n.component_name}` has no root element')
	}
	for property in n.properties {
		if property.name in ['id', 'key', 'ref'] || property.name in vml_child_layout_props {
			continue
		}
		name := property.name.all_after('bind.')
		if vml_is_event(property.name) {
			if !n.inputs.any(it.typ == 'event' && it.name == property.name.all_after('on_')) {
				return vml_property_src(n, property).error('unknown component event `${property.name}` on ${n.component_name}')
			}
		} else if !n.inputs.any(it.typ !in ['event', 'slot'] && it.name == name) {
			return vml_property_src(n, property).error('unknown component input `${property.name}` on ${n.component_name}')
		}
	}
	mut scope := &VmlScope{
		kind:   .component
		caller: &caller
	}
	mut comp := &VmlIComponent{
		name:       n.component_name
		owner_name: path
		scope:      scope
	}
	// The invocation's own properties and their tokens live in the caller.
	mut caller_tokens := []string{}
	for property in n.properties {
		vml_expr_tokens(property.expr, mut caller_tokens)
	}
	vml_add_tokens(caller, caller_tokens)
	mut own_tokens := []string{}
	for input in n.inputs {
		if !isnil(input.default_value) { vml_expr_tokens(input.default_value, mut own_tokens) }
	}
	for data in n.data {
		vml_expr_tokens(data.expr, mut own_tokens)
	}
	for function in n.functions {
		for statement in function.body {
			vml_expr_tokens(statement, mut own_tokens)
		}
	}
	vml_add_tokens(scope, own_tokens)
	for input in n.inputs {
		isrc := vml_src(n.source, input.line, input.column)
		if input.typ == 'slot' { continue }
		if input.typ == 'event' {
			mut listener := &VmlScope{
				kind:   .listener
				parent: &caller
			}
			for parameter in input.parameters {
				listener.add(parameter.name, VmlBinding{
					kind: .param
				})
			}
			mut handler := &VmlIExpr(unsafe { nil })
			if property := vml.find_property(n, 'on_' + input.name) {
				handler = c.handler(property.expr, mut listener, input.parameters)!
			}
			slot := scope.add(input.name, VmlBinding{
				kind:   .event
				params: input.parameters
			}).slot
			comp.inputs << VmlIInput{
				name:    input.name
				typ:     input.typ
				kind:    .event
				slot:    slot
				handler: handler
				scope:   listener
				params:  input.parameters
			}
			continue
		}
		argument := vml.find_property(n, input.name)
		binding := vml.find_property(n, 'bind.' + input.name)
		if argument != none && binding != none {
			return isrc.error('component input `${input.name}` cannot have both a value and a bind connection')
		}
		if property := binding {
			if !input.bindable {
				return vml_property_src(n, property).error('input `${input.name}` is not declared bindable')
			}
			if property.expr.kind != .path {
				return vml_property_src(n, property).error('a binding target must be `app.field` or a writable name')
			}
			expr := c.expr(property.expr, caller, false)!
			write := c.assignment_target(property.expr, caller, vml_property_src(n, property))!
			slot := scope.add(input.name, VmlBinding{
				kind:     .input
				writable: true
			}).slot
			comp.inputs << VmlIInput{
				name:     input.name
				typ:      input.typ
				kind:     .bound
				slot:     slot
				expr:     expr
				uses_app: vml_ir_uses_app(expr)
				write:    write
			}
		} else if property := argument {
			expr := if input.typ == 'ui2.StylePatch' {
				c.check_style(n, property.expr, false)!
				c.expr(property.expr, caller, true)!
			} else {
				if input.typ.trim_left('?') == 'ui2.MotionConfig' {
					c.check_motion(property.expr)!
				}
				c.expr(property.expr, caller, true)!
			}
			slot := scope.add(input.name, VmlBinding{
				kind: .input
			}).slot
			comp.inputs << VmlIInput{
				name:     input.name
				typ:      input.typ
				kind:     .argument
				slot:     slot
				expr:     expr
				uses_app: vml_ir_uses_app(expr)
			}
		} else {
			if isnil(input.default_value) {
				return src.error('required component input `${input.name}` of ${n.component_name} is missing')
			}
			expr := c.expr(input.default_value, scope, true)!
			slot := scope.add(input.name, VmlBinding{
				kind: .input
			}).slot
			comp.inputs << VmlIInput{
				name:     input.name
				typ:      input.typ
				kind:     .default_value
				slot:     slot
				expr:     expr
				uses_app: vml_ir_uses_app(expr)
			}
		}
	}
	for reference in n.refs {
		kind := vml_ref_kind_of(reference.typ) or {
			return src.error('`ref ${reference.name} ${reference.typ}`: ${reference.typ} cannot be the target of a ref')
		}
		slot := scope.add(reference.name, VmlBinding{
			kind:     .ref
			ref_kind: kind
		}).slot
		comp.refs << VmlIRef{
			name: reference.name
			slot: slot
			kind: kind
			tag:  reference.typ
		}
	}
	for data in n.data {
		expr := c.expr(data.expr, scope, true)!
		slot := scope.add(data.name, VmlBinding{
			kind:     if data.computed { VmlBindKind.computed } else { VmlBindKind.state }
			writable: !data.computed
		}).slot
		comp.data << VmlIData{
			name:     data.name
			slot:     slot
			computed: data.computed
			expr:     expr
			uses_app: vml_ir_uses_app(expr)
		}
	}
	for function in n.functions {
		mut fn_scope := &VmlScope{
			kind:   .function
			parent: scope
		}
		for parameter in function.parameters {
			fn_scope.add(parameter.name, VmlBinding{
				kind: .param
			})
		}
		mut def := &VmlIFunction{
			name:   function.name
			params: function.parameters
			scope:  fn_scope
		}
		def.body = c.action(&vml.Expr{
			kind:   .block
			args:   function.body
			source: n.source
		}, fn_scope)!
		scope.add(function.name, VmlBinding{
			kind:   .func
			params: function.parameters
			func:   def
		})
	}
	if n.mount.len > 0 {
		comp.mount = c.action(&vml.Expr{ kind: .block, args: n.mount, source: n.source }, scope)!
	}
	if n.unmount.len > 0 {
		comp.unmount = c.action(&vml.Expr{ kind: .block, args: n.unmount, source: n.source },
			scope)!
	}
	if n.cleanup.len > 0 {
		comp.cleanup = c.action(&vml.Expr{ kind: .block, args: n.cleanup, source: n.source },
			scope)!
	}
	// Invocation key, child layout and ref (caller scope).
	if property := vml.find_property(n, 'key') {
		if !keyed {
			comp.key = c.expr(property.expr, caller, true)!
		}
	}
	for property in n.properties {
		if property.name in vml_child_layout_props {
			expr := c.expr(property.expr, caller, true)!
			comp.layout << VmlIProp{
				name:     property.name
				expr:     expr
				reactive: vml_ir_reactive(expr)
				uses_app: vml_ir_uses_app(expr)
				src:      vml_property_src(n, property)
			}
		}
	}
	if property := vml.find_property(n, 'ref') {
		comp.ref = c.ref_target(n, property, caller)!
	}
	// The root keeps its own key only when the invocation has none.
	root_keyed := keyed || comp.key != unsafe { nil }
	comp.root = c.node(n.children[0], path + '.root', mut scope, root_keyed)!
	mut node := &VmlINode{
		kind: .component
		tag:  n.component_name
		path: path
		src:  src
		id:   n.id
		comp: comp
	}
	if n.id.len > 0 {
		node.id_slot = caller.add(n.id, VmlBinding{
			kind: .id
		}).slot
	}
	return node
}

// ------------------------------------------------------------- expressions

// expr resolves an expression. `enums` allows a bare unknown name, which is
// an enum value (`align: center`).
fn (mut c VmlChecker) expr(e &vml.Expr, scope &VmlScope, enums bool) !&VmlIExpr {
	src := vml_expr_src(e)
	match e.kind {
		.literal {
			return &VmlIExpr{
				kind:  .literal
				value: vml_literal(e) or { return src.error('invalid literal `${e.value}`') }
				typ:   vml_literal_type(e)
				src:   src
			}
		}
		.path {
			return c.path(e, scope, enums)
		}
		.call {
			return c.call(e, scope)
		}
		.unary {
			operand := c.expr(e.left, scope, false)!
			return &VmlIExpr{
				kind: if e.value == '!' { VmlIKind.not_ } else { VmlIKind.negate }
				args: [operand]
				typ:  operand.typ
				src:  src
			}
		}
		.binary {
			left := c.expr(e.left, scope, true)!
			right := c.expr(e.right, scope, true)!
			kind := match e.value {
				'&&' { VmlIKind.and_ }
				'||' { VmlIKind.or_ }
				else { VmlIKind.binary }
			}
			if kind == .binary && e.value !in ['+', '-', '*', '/', '%', '==', '!=', '<', '<=',
				'>', '>='] {
				return src.error('unsupported operator `${e.value}`')
			}
			return &VmlIExpr{
				kind: kind
				name: e.value
				args: [left, right]
				src:  src
			}
		}
		.conditional {
			return &VmlIExpr{
				kind: .conditional
				args: [c.expr(e.left, scope, false)!, c.expr(e.right, scope, enums)!,
					c.expr(e.third, scope, enums)!]
				src:  src
			}
		}
		.array {
			mut items := []&VmlIExpr{cap: e.args.len}
			for arg in e.args {
				items << c.expr(arg, scope, enums)!
			}
			return &VmlIExpr{
				kind: .array
				args: items
				src:  src
			}
		}
		.interpolation {
			mut parts := []&VmlIExpr{cap: e.parts.len}
			for part in e.parts {
				if isnil(part.expr) {
					parts << &VmlIExpr{
						kind:  .literal
						value: VmlValue(part.text)
					}
				} else {
					parts << c.expr(part.expr, scope, false)!
				}
			}
			return &VmlIExpr{
				kind: .interp
				args: parts
				src:  src
			}
		}
		.assignment {
			return src.error('an assignment is only valid in an event handler')
		}
		.block {
			return src.error('a `{ ... }` block is only valid in an event handler')
		}
	}
}

fn vml_literal(e &vml.Expr) ?VmlValue {
	if e.quoted { return VmlValue(e.value) }
	if e.value == 'true' { return VmlValue(true) }
	if e.value == 'false' { return VmlValue(false) }
	if e.value.contains('.') {
		if e.value.count('.') > 1 { return none }
		return VmlValue(e.value.f64())
	}
	if e.value.len == 0 || !e.value.bytes().all(it.is_digit()) { return none }
	return VmlValue(e.value.i64())
}

fn vml_literal_type(e &vml.Expr) &VmlModelType {
	if e.quoted {
		return &VmlModelType{
			name: 'string'
			kind: .text
		}
	}
	if e.value in ['true', 'false'] {
		return &VmlModelType{
			name: 'bool'
			kind: .boolean
		}
	}
	if e.value.contains('.') {
		return &VmlModelType{
			name: 'f64'
			kind: .number
		}
	}
	return &VmlModelType{
		name: 'int'
		kind: .integer
	}
}

fn vml_token_name(value string) ?string {
	for pair in [['color', 'color'], ['spacing', 'spacing'], ['radius', 'radius'],
		['typography', 'font_size']] {
		if value.starts_with(pair[0] + '.') {
			name := value.all_after(pair[0] + '.')
			if name.len == 0 || name.contains('.') { return none }
			return pair[1] + ':' + name
		}
	}
	return none
}

fn (mut c VmlChecker) path(e &vml.Expr, scope &VmlScope, enums bool) !&VmlIExpr {
	src := vml_expr_src(e)
	value := e.value
	if value.starts_with('.') && value.len > 1 && !value[1..].contains('.') {
		return &VmlIExpr{
			kind:  .enum_name
			value: VmlValue(VmlEnum{
				name: value[1..]
			})
			src:   src
		}
	}
	if value.starts_with('#') {
		if value.len == 7 && value[1..].bytes().all(it.is_hex_digit()) {
			return &VmlIExpr{
				kind:  .literal
				value: VmlValue(value)
				src:   src
			}
		}
		return src.error('invalid color `${value}`; colors are #RRGGBB')
	}
	parts := value.split('.')
	if parts.any(it.len == 0) { return src.error('invalid name `${value}`') }
	root := parts[0]
	if root in ['color', 'spacing', 'radius', 'typography'] {
		token := vml_token_name(value) or {
			return src.error('`${value}` is not a theme token; write `${root}.name`')
		}
		vml_add_tokens(scope, [token])
		return &VmlIExpr{
			kind: .token
			name: token
			src:  src
		}
	}
	if root == 'app' {
		if parts.len == 1 {
			return src.error('`app` is not a value; read one of its fields')
		}
		field := c.model.schema.fields[parts[1]] or {
			return src.error('the model ${c.model.type_name} has no field `${parts[1]}`')
		}
		if !field.is_pub {
			return src.error('field `${parts[1]}` of ${c.model.type_name} is not public')
		}
		base := &VmlIExpr{
			kind: .app_field
			name: parts[1]
			typ:  field.typ
			src:  src
		}
		return c.members(base, parts[2..], src)
	}
	if binding, depth := scope.lookup(root) {
		match binding.kind {
			.id {
				if parts.len == 2 && parts[1] in vml_geometry_props {
					return &VmlIExpr{
						kind:  .geometry
						name:  parts[1]
						depth: depth
						slot:  binding.slot
						typ:   &VmlModelType{
							name: 'f64'
							kind: .number
						}
						src:   src
					}
				}
				return src.error('`${value}`: an element id exposes only x, y, width and height')
			}
			.func, .event {
				return src.error('`${root}` is a function; call it')
			}
			.ref {
				return src.error('`${root}` is a ref; call one of its methods')
			}
			else {
				base := &VmlIExpr{
					kind:  .binding
					depth: depth
					slot:  binding.slot
					typ:   binding.typ
					src:   src
				}
				return c.members(base, parts[1..], src)
			}
		}
	}
	if parts.len == 1 && enums {
		return &VmlIExpr{
			kind:  .enum_name
			value: VmlValue(VmlEnum{
				name: value
			})
			src:   src
		}
	}
	return src.error('unknown name `${root}`')
}

// members applies `.field` and `.len` reads, checking them against the
// static type when it is known.
fn (mut c VmlChecker) members(base &VmlIExpr, names []string, src VmlSourceLocation) !&VmlIExpr {
	mut current := unsafe { base }
	for name in names {
		typ := current.typ
		if name == 'len' && (typ == unsafe { nil } || typ.kind in [.text, .array, .dynamic]) {
			current = &VmlIExpr{
				kind: .length
				args: [current]
				typ:  &VmlModelType{
					name: 'int'
					kind: .integer
				}
				src:  src
			}
			continue
		}
		mut field_type := &VmlModelType(unsafe { nil })
		if typ != unsafe { nil } {
			match typ.kind {
				.object {
					field := typ.fields[name] or {
						return src.error('${typ.name} has no field `${name}`')
					}
					if !field.is_pub {
						return src.error('field `${name}` of ${typ.name} is not public')
					}
					field_type = field.typ
				}
				.optional {
					if typ.elem != unsafe { nil } && typ.elem.kind == .object {
						return src.error('`${name}` reads the option ${typ.name}; options are values, not objects')
					}
				}
				.dynamic {}
				else {
					return src.error('${typ.describe()} has no field `${name}`')
				}
			}
		}
		current = &VmlIExpr{
			kind: .member
			name: name
			args: [current]
			typ:  field_type
			src:  src
		}
	}
	return current
}

fn (mut c VmlChecker) call(e &vml.Expr, scope &VmlScope) !&VmlIExpr {
	src := vml_expr_src(e)
	value := e.value
	mut args := []&VmlIExpr{cap: e.args.len}
	parts := value.split('.')
	if parts.len == 2 && parts[0] == 'app' {
		for arg in e.args {
			args << c.expr(arg, scope, true)!
		}
		name := parts[1]
		method := c.model.schema.methods[name] or {
			if c.model.schema.kind == .object && c.model.type_name == 'sample' {
				return &VmlIExpr{
					kind: .app_call
					name: name
					args: args
					src:  src
				}
			}
			return src.error('the model ${c.model.type_name} has no method `${name}`')
		}
		if !method.supported {
			return src.error('`app.${name}` has a signature the interpreter cannot call (parameters: ${method.params.join(', ')}); it calls methods taking nothing, one int, i64, f64, string, bool or ui2.ElementEvent, or two of int, f64, string and bool')
		}
		if method.params.len != args.len {
			return src.error('`app.${name}` takes ${method.params.len} argument(s), not ${args.len}')
		}
		return &VmlIExpr{
			kind: .app_call
			name: name
			args: args
			src:  src
		}
	}
	if parts.len >= 2 && parts.last() == 'str' && e.args.len == 0 {
		base := c.path(&vml.Expr{
			...e
			kind:  .path
			value: parts[..parts.len - 1].join('.')
		}, scope, false)!
		return &VmlIExpr{
			kind: .to_str
			args: [base]
			typ:  &VmlModelType{
				name: 'string'
				kind: .text
			}
			src:  src
		}
	}
	if parts.len == 2 {
		if binding, depth := scope.lookup(parts[0]) {
			if binding.kind == .ref {
				for arg in e.args {
					args << c.expr(arg, scope, false)!
				}
				method := parts[1]
				arity := match method {
					'is_available', 'focus', 'id', 'element' { 0 }
					'set_text' { 1 }
					else {
						return src.error('a ref has no method `${method}`; refs have is_available, focus, set_text, id and element')
					}
				}
				if args.len != arity {
					return src.error('`${value}` takes ${arity} argument(s), not ${args.len}')
				}
				if method == 'focus' && binding.ref_kind in [.label, .image, .scroll] {
					return src.error('a ${binding.ref_kind} ref does not support focus')
				}
				if method == 'set_text' && binding.ref_kind !in [.text_field, .text_area] {
					return src.error('only TextInput and TextArea refs support set_text')
				}
				return &VmlIExpr{
					kind:  .ref_call
					name:  method
					depth: depth
					slot:  binding.slot
					args:  args
					src:   src
				}
			}
		}
	}
	if parts.len == 1 {
		if binding, depth := scope.lookup(value) {
			for arg in e.args {
				args << c.expr(arg, scope, true)!
			}
			match binding.kind {
				.func {
					if args.len != binding.params.len {
						return src.error('`${value}` takes ${binding.params.len} argument(s), not ${args.len}')
					}
					return &VmlIExpr{
						kind:  .fn_call
						depth: depth
						slot:  binding.slot
						args:  args
						func:  binding.func
						src:   src
					}
				}
				.event {
					if args.len != binding.params.len {
						return src.error('event `${value}` takes ${binding.params.len} payload value(s), not ${args.len}')
					}
					return &VmlIExpr{
						kind:  .emit
						depth: depth
						slot:  binding.slot
						args:  args
						src:   src
					}
				}
				else {
					return src.error('`${value}` is not a function')
				}
			}
		}
		if value in vml_state_styles {
			if e.args.len != 1 || e.args[0].kind != .array {
				return src.error('`${value}` requires one style list')
			}
			for arg in e.args[0].args {
				args << c.expr(arg, scope, true)!
			}
			return &VmlIExpr{
				kind: .style_state
				name: value
				args: args
				src:  src
			}
		}
		if value in vml_style_helpers {
			if e.args.len != 1 {
				return src.error('`${value}` requires exactly one argument')
			}
			return &VmlIExpr{
				kind: .style_call
				name: value
				args: [c.expr(e.args[0], scope, true)!]
				src:  src
			}
		}
		if kinds := vml_motion_helpers[value] {
			if e.args.len != kinds.len {
				return src.error('`${value}` takes ${kinds.len} argument(s), not ${e.args.len}')
			}
			for arg in e.args {
				args << c.expr(arg, scope, true)!
			}
			return &VmlIExpr{
				kind: .motion_call
				name: value
				args: args
				src:  src
			}
		}
		if value in vml_compiled_motion_helpers {
			return src.error('the motion helper `${value}` takes a V callback or handle; use compiled VML')
		}
		return src.error('unknown function `${value}`')
	}
	return src.error('the interpreter does not support the call `${value}(...)`; it calls app methods, component functions and events, ref methods, style helpers and `.str()`; use compiled VML for other V calls')
}

// check_style validates a style value: lists, conditionals, helper calls with
// one argument, and one level of interaction states.
fn (mut c VmlChecker) check_style(n &vml.Node, e &vml.Expr, state bool) ! {
	src := vml_expr_src(e)
	match e.kind {
		.array {
			for arg in e.args {
				c.check_style(n, arg, state)!
			}
		}
		.conditional {
			c.check_style(n, e.right, state)!
			c.check_style(n, e.third, state)!
		}
		.path {}
		.call {
			if e.value.contains('.') { return }
			if e.value in vml_state_styles {
				if n.tag == 'Run' { return src.error('Run styles support text properties') }
				if state { return src.error('interaction styles cannot nest interaction states') }
				if e.args.len != 1 || e.args[0].kind != .array {
					return src.error('`${e.value}` requires one style list')
				}
				c.check_style(n, e.args[0], true)!
				return
			}
			if e.value !in vml_style_helpers {
				return src.error('unknown style helper `${e.value}`')
			}
			if e.args.len != 1 { return src.error('`${e.value}` requires exactly one argument') }
			if state && e.value !in vml_box_style_helpers {
				return src.error('interaction styles support box properties and foreground')
			}
		}
		else {
			return src.error('style requires a list, typed style value or conditional style')
		}
	}
}

// check_motion validates a motion value: a motion helper call, a list of
// them, a conditional, or a model value.
fn (mut c VmlChecker) check_motion(e &vml.Expr) ! {
	src := vml_expr_src(e)
	match e.kind {
		.array {
			for arg in e.args {
				c.check_motion(arg)!
			}
		}
		.conditional {
			c.check_motion(e.right)!
			c.check_motion(e.third)!
		}
		.path {}
		.call {
			if e.value.contains('.') { return }
			if e.value !in vml_motion_helpers && e.value !in vml_compiled_motion_helpers {
				return src.error('unknown motion helper `${e.value}`')
			}
		}
		else {
			return src.error('motion requires a motion helper, a list of them, a typed motion value or a conditional')
		}
	}
}

// ---------------------------------------------------------------- handlers

// handler resolves an event handler: a reference (`app.save`, a component
// function or event, an external callback) or an action. `payload` are the
// parameters of a component event it handles.
fn (mut c VmlChecker) handler(e &vml.Expr, mut scope VmlScope, payload []vml.Parameter) !&VmlIExpr {
	src := vml_expr_src(e)
	if e.kind != .path { return c.action(e, scope) }
	value := e.value
	parts := value.split('.')
	if parts.len == 2 && parts[0] == 'app' {
		name := parts[1]
		method := c.model.schema.methods[name] or {
			if c.model.type_name == 'sample' {
				return &VmlIExpr{
					kind: .app_method
					name: name
					src:  src
				}
			}
			return src.error('the model ${c.model.type_name} has no method `${name}`')
		}
		ok := method.params.len == 0 || (method.params.len == 1 && method.params[0] == 'ElementEvent')
			|| (payload.len > 0 && method.params == payload.map(it.typ))
		if !ok {
			return src.error('callback `app.${name}` requires fn () or fn (ui2.ElementEvent)')
		}
		return &VmlIExpr{
			kind: .app_method
			name: name
			src:  src
		}
	}
	if parts.len == 1 {
		if binding, depth := scope.lookup(value) {
			match binding.kind {
				.func {
					if binding.params.len > 1 || (binding.params.len == 1
						&& binding.params[0].typ !in ['ui2.ElementEvent', 'ElementEvent']
						&& payload.map(it.typ) != binding.params.map(it.typ)) {
						return src.error('callback `${value}` requires fn () or fn (ui2.ElementEvent)')
					}
					return &VmlIExpr{
						kind:  .fn_ref
						depth: depth
						slot:  binding.slot
						func:  binding.func
						src:   src
					}
				}
				.event {
					if binding.params.len > 0 && payload.map(it.typ) != binding.params.map(it.typ) {
						return src.error('event `${value}` has a payload and cannot be a callback')
					}
					return &VmlIExpr{
						kind:  .event_ref
						depth: depth
						slot:  binding.slot
						src:   src
					}
				}
				else {
					return src.error('`${value}` is not callable')
				}
			}
		}
		if value !in c.callbacks && !c.lenient {
			return src.error('unknown callback `${value}`; pass it in VmlInterpretConfig.callbacks')
		}
		if value !in c.externals { c.externals << value }
		return &VmlIExpr{
			kind: .external
			name: value
			src:  src
		}
	}
	return src.error('`${value}` is not callable')
}

// action resolves a statement: an assignment, a call or a block.
fn (mut c VmlChecker) action(e &vml.Expr, scope &VmlScope) !&VmlIExpr {
	src := vml_expr_src(e)
	match e.kind {
		.block {
			mut statements := []&VmlIExpr{cap: e.args.len}
			for statement in e.args {
				statements << c.action(statement, scope)!
			}
			return &VmlIExpr{
				kind: .block
				args: statements
				src:  src
			}
		}
		.assignment {
			mut target := c.assignment_target(e.left, scope, src)!
			value := c.expr(e.right, scope, true)!
			return &VmlIExpr{
				...target
				args: [value]
			}
		}
		else {
			return c.expr(e, scope, true)
		}
	}
}

// assignment_target resolves a writable target: `app.field` (public and
// mutable), a component state or a bindable component input.
fn (mut c VmlChecker) assignment_target(e &vml.Expr, scope &VmlScope, src VmlSourceLocation) !&VmlIExpr {
	if e.kind != .path {
		return src.error('assignment target must be a name')
	}
	value := e.value
	parts := value.split('.')
	if parts.len == 2 && parts[0] == 'app' {
		field := c.model.schema.fields[parts[1]] or {
			if c.model.type_name == 'sample' {
				return &VmlIExpr{
					kind: .assign_app
					name: parts[1]
					src:  src
				}
			}
			return src.error('the model ${c.model.type_name} has no field `${parts[1]}`')
		}
		if !field.is_pub || !field.is_mut {
			return src.error('VML target `${value}` must be public and mutable')
		}
		return &VmlIExpr{
			kind: .assign_app
			name: parts[1]
			typ:  field.typ
			src:  src
		}
	}
	if parts.len == 1 {
		if binding, depth := scope.lookup(value) {
			if binding.kind == .state {
				return &VmlIExpr{
					kind:  .assign_state
					depth: depth
					slot:  binding.slot
					src:   src
				}
			}
			if binding.kind == .input && binding.writable {
				return &VmlIExpr{
					kind:  .assign_input
					depth: depth
					slot:  binding.slot
					src:   src
				}
			}
		}
	}
	return src.error('VML target `${value}` is read-only or unknown; use state or an explicit bind connection')
}

// ------------------------------------------------------------ static facts

// vml_ir_reactive reports whether an expression reads anything that can
// change: the model, a scope value, an element's geometry or a theme token.
fn vml_ir_reactive(e &VmlIExpr) bool {
	if e.kind in [.app_field, .binding, .geometry, .token, .app_call, .fn_call, .ref_call] {
		return true
	}
	for arg in e.args {
		if vml_ir_reactive(arg) { return true }
	}
	return false
}

fn vml_ir_uses_app(e &VmlIExpr) bool {
	if e.kind in [.app_field, .app_call, .app_method, .assign_app] { return true }
	for arg in e.args {
		if vml_ir_uses_app(arg) { return true }
	}
	return false
}
