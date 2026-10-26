module ui2

import ui2.vml

// The VML interpreter's loader (design §3.3), compiled only with
// `-d vml_interpreter`. Its reading of a document is the shared VML IR
// (ui2.vml, ir.v), the same resolution the generator prints as V: which name
// every identifier denotes, scopes, identity paths and declaration order. The
// loader checks what the IR leaves to a consumer that knows the widgets and
// the model (element tags and properties against the registry, `app` paths,
// methods and writes against the model's schema, style and motion helpers),
// turns literals into values and instantiates every component invocation as
// the runtime builds it, with its slots filled by the invocation's content.
// Anything outside the interpreter's expression subset is an error here,
// before anything runs.

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
	index       // args[0][args[1]]
	or_else     // args[0] or { args[1] }
	// Handler references: a callable value.
	app_method // name: `on_x: app.method`
	fn_ref     // depth, slot: `on_x: local_fn`
	event_ref  // depth, slot: `on_x: component_event`
	external   // name: a callback from VmlInterpretConfig.callbacks
	// Statements; `op` is the assignment operator.
	assign_app   // name op args[0]
	assign_state // depth, slot op args[0]
	assign_input // depth, slot op args[0] (a bindable input)
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
	op    string
	src   VmlSourceLocation
}

// VmlScope is what a frame of one lexical scope of the IR needs: its number
// of slots and, for scopes with an owner of their own (document, component,
// item, slot), the theme tokens their expressions read, which are prepared
// before any memo can read them.
@[heap]
struct VmlScope {
	slots  int
	tokens []string
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
	repeater // a `for`
	cond     // an `if`
	slot     // a component's `Slot`: the invocation's content, in `slot_scope`
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

// VmlIWatch is a component `watch`: `body` runs in a frame of `scope`
// (slot 0: the old value, slot 1: the new one) when `expr` changes.
struct VmlIWatch {
	expr     &VmlIExpr = unsafe { nil }
	body     &VmlIExpr = unsafe { nil }
	scope    &VmlScope = unsafe { nil }
	uses_app bool
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
	watches []VmlIWatch
	mount   &VmlIExpr = unsafe { nil }
	unmount &VmlIExpr = unsafe { nil }
	cleanup &VmlIExpr = unsafe { nil }
	root    &VmlINode = unsafe { nil }
	// The invocation's key and ref, and the properties, events and bindings
	// the component does not declare, which configure its root: all in the
	// caller's scope. The instance id is exported to the caller's frame.
	key     &VmlIExpr = unsafe { nil }
	forward []VmlIProp
	events  []VmlIEvent
	binds   []VmlIBind
	ref     &VmlIExpr = unsafe { nil }
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

// VmlIBranch is one branch of an `if`: its condition (nil for `else`), the
// slot of the unwrapped value of `if name := option` (-1 for none) and its
// children, in a frame of `scope` with an owner of its own.
@[heap]
struct VmlIBranch {
	cond      &VmlIExpr = unsafe { nil }
	scope     &VmlScope = unsafe { nil }
	bind_slot int       = -1
mut:
	children []&VmlINode
}

@[heap]
struct VmlICond {
	name          string
	cond_uses_app bool
mut:
	branches []&VmlIBranch
}

@[heap]
struct VmlINode {
	kind VmlINodeKind
	tag  string
	path string
	src  VmlSourceLocation
	// A slot: the scope its content is resolved in (a child of the scope the
	// invocation was written in), with an owner of its own.
	slot_scope &VmlScope = unsafe { nil }
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
	cond     &VmlICond      = unsafe { nil }
}

// VmlProgram is a loaded document: its IR and the scope of its root.
@[heap]
pub struct VmlProgram {
pub:
	path string
mut:
	root  &VmlINode = unsafe { nil }
	scope &VmlScope = unsafe { nil }
	// The refs of the document's own element ids.
	refs  []VmlIRef
	menus bool
	// External callback names the document uses.
	externals []string
	// Every file of the document (the root and its imports), for watching.
	files []string
}

// ---------------------------------------------------------------- language

const vml_geometry_props = ['x', 'y', 'width', 'height']

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
		'View', 'Button', 'Dialog', 'Popover', 'MenuOverlay', 'ContextMenu', 'Tooltip' { .view }
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

fn vml_src(source string, line int, column int) VmlSourceLocation {
	return VmlSourceLocation{
		source: source
		line:   line
		column: column
	}
}

fn (src VmlSourceLocation) error(message string) IError {
	if src.source.len > 0 {
		return error('${src.source}:${src.line}:${src.column}: ${message}')
	}
	if src.line > 0 { return error('${message} at line ${src.line}, column ${src.column}') }
	return error(message)
}

fn vml_event_type() &VmlModelType {
	mut seen := map[string]&VmlModelType{}
	return vml_model_type(ElementEvent{}, mut seen)
}

// ------------------------------------------------------------------ loader

struct VmlLoader {
	model     &VmlModel = unsafe { nil }
	callbacks map[string]ElementCallback
	lenient   bool // unknown external callbacks are allowed (previews)
	program   &vml.Program = unsafe { nil }
mut:
	scopes    map[int]&VmlScope
	functions map[int]&VmlIFunction
	externals []string
	// Static types of scope values by binding (`scope:slot`): repeater items.
	types map[string]&VmlModelType
}

// VmlSlotFill is the content one invocation gives the slots of its component;
// `parent` fills the slots of the component the invocation is written in.
struct VmlSlotFill {
	inv    &vml.IInvocation = unsafe { nil }
	parent ?&VmlSlotFill
}

// vml_check checks a resolved document against a model and the registry.
fn vml_check(program &vml.Program, model &VmlModel, callbacks map[string]ElementCallback, lenient bool) !&VmlProgram {
	mut c := VmlLoader{
		model:     model
		callbacks: callbacks
		lenient:   lenient
		program:   program
	}
	mut out := &VmlProgram{
		path:  program.path
		scope: c.scope(program.scope)
		menus: program.menus
		files: program.files.clone()
	}
	for reference in program.refs {
		out.refs << c.ref_decl(reference, vml_ir_src(program.root.src))!
	}
	out.root = c.node(program.root, '', none)!
	out.externals = c.externals
	return out
}

fn vml_ir_src(l vml.Location) VmlSourceLocation {
	return vml_src(l.path, l.line, l.column)
}

fn vml_binding_key(b vml.Binding) string {
	return '${b.scope_id}:${b.slot}'
}

// vml_instance_path is the document path of a node whose IR path is relative
// to the component instance at `base` (empty for document paths).
fn vml_instance_path(base string, path string) string {
	return if base.len == 0 { path } else { '${base}.${path}' }
}

fn (mut c VmlLoader) scope(s &vml.Scope) &VmlScope {
	if existing := c.scopes[s.id] {
		return existing
	}
	scope := &VmlScope{
		slots:  s.slots()
		tokens: s.tokens.clone()
	}
	c.scopes[s.id] = scope
	return scope
}

// -------------------------------------------------------------------- nodes

// node instantiates a node whose path is relative to the component instance
// at `base`; `fill` is the content of the slots of that component.
fn (mut c VmlLoader) node(n &vml.INode, base string, fill ?&VmlSlotFill) !&VmlINode {
	return match n.kind {
		.element { c.element(n, base, fill)! }
		.component { c.invocation(n, base, fill)! }
		.slot { c.slot(n, base, fill)! }
		.repeater, .cond { vml_ir_src(n.src).error('`if` and `for` must be children of a container') }
	}
}

fn (mut c VmlLoader) children(nodes []&vml.INode, base string, fill ?&VmlSlotFill) ![]&VmlINode {
	mut out := []&VmlINode{cap: nodes.len}
	for child in nodes {
		out << match child.kind {
			.repeater { c.repeater(child, base, fill)! }
			.cond { c.cond(child, base, fill)! }
			else { c.node(child, base, fill)! }
		}
	}
	return out
}

// cond checks an `if` chain: each branch's condition and children, and the
// type of the value `if name := option` unwraps.
fn (mut c VmlLoader) cond(n &vml.INode, base string, fill ?&VmlSlotFill) !&VmlINode {
	mut cond := &VmlICond{
		name:          n.cond.name
		cond_uses_app: n.cond.cond_uses_app
	}
	for b in n.cond.branches {
		mut condition := &VmlIExpr(unsafe { nil })
		if !isnil(b.cond) {
			condition = c.expr(b.cond, false)!
			if b.bind_slot >= 0 && condition.typ != unsafe { nil } {
				if condition.typ.kind !in [.optional, .dynamic] {
					return vml_ir_src(b.src).error('`if name := value` unwraps an option, not ${condition.typ.describe()}')
				}
				c.types['${b.scope.id}:${b.bind_slot}'] = condition.typ.elem
			}
		}
		mut branch := &VmlIBranch{
			cond:      condition
			scope:     c.scope(b.scope)
			bind_slot: b.bind_slot
		}
		branch.children = c.children(b.children, base, fill)!
		cond.branches << branch
	}
	return &VmlINode{
		kind: .cond
		tag:  'if'
		path: vml_instance_path(base, n.path)
		src:  vml_ir_src(n.src)
		cond: cond
	}
}

fn (mut c VmlLoader) element(n &vml.INode, base string, fill ?&VmlSlotFill) !&VmlINode {
	src := vml_ir_src(n.src)
	widget := vml_widget_type(n.tag) or {
		return src.error('unknown VML element `${n.tag}`; the interpreter knows ${vml_widget_tags().join(', ')}')
	}
	mut node := &VmlINode{
		kind:    .element
		tag:     n.tag
		path:    vml_instance_path(base, n.path)
		src:     src
		widget:  widget
		id:      n.id
		id_slot: n.id_slot
	}
	if !isnil(n.key) {
		node.key = c.expr(n.key, true)!
	}
	mut geometry := []vml.IProp{}
	mut others := []vml.IProp{}
	for p in n.props {
		if p.name in vml_geometry_props {
			geometry << p
		} else {
			others << p
		}
	}
	for p in vml_order_geometry(geometry, n.id) {
		node.props << c.prop(n.tag, widget, p)!
	}
	for p in others {
		node.props << c.prop(n.tag, widget, p)!
	}
	if n.binds.len > 1 {
		return vml_ir_src(n.binds[1].src).error('an element takes one binding')
	}
	for b in n.binds {
		node.binds << c.bind(n.tag, widget, b)!
	}
	for event in n.events {
		node.events << c.event(n.tag, widget, event)!
	}
	if !isnil(n.ref) {
		node.ref = c.ref_target(n.tag, n.ref)!
	}
	node.children = c.children(n.children, base, fill)!
	return node
}

// slot fills a component's `Slot` with the content of the invocation, which
// is resolved in a scope of the invocation's caller; a slot the invocation
// does not fill stays empty.
fn (mut c VmlLoader) slot(n &vml.INode, base string, fill ?&VmlSlotFill) !&VmlINode {
	src := vml_ir_src(n.src)
	f := fill or { return src.error('`Slot` is only valid inside a component') }
	nodes := f.inv.slots[n.tag] or { []&vml.INode{} }
	mut node := &VmlINode{
		kind:       .slot
		tag:        n.tag
		path:       vml_instance_path(base, n.path)
		src:        src
		slot_scope: if scope := f.inv.slot_scopes[n.tag] { c.scope(scope) } else { &VmlScope{} }
	}
	// The content is the caller's: the slots it places are the caller's.
	node.children = c.children(nodes, base, f.parent)!
	return node
}

// vml_order_geometry orders geometry properties so that one reading another
// property of its own element comes after it; a cycle keeps source order.
fn vml_order_geometry(properties []vml.IProp, node_id string) []vml.IProp {
	mut remaining := properties.clone()
	if node_id.len == 0 || remaining.len < 2 {
		return remaining
	}
	mut ordered := []vml.IProp{cap: remaining.len}
	for remaining.len > 0 {
		mut deferred := []vml.IProp{cap: remaining.len}
		for p in remaining {
			if remaining.any(it.name != p.name && vml_reads_geometry(p.expr, node_id, it.name)) {
				deferred << p
			} else {
				ordered << p
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

fn vml_reads_geometry(e &vml.IExpr, id string, field string) bool {
	if e.kind == .geometry && e.binding.name == id && e.name == field {
		return true
	}
	return e.args.any(vml_reads_geometry(it, id, field))
}

fn (mut c VmlLoader) prop(tag string, widget VmlWidgetType, p vml.IProp) !VmlIProp {
	src := vml_ir_src(p.src)
	info := widget.prop(p.name) or {
		if p.name == 'model' {
			return src.error('`model` is a Repeater property')
		}
		return src.error('`${tag}` has no property `${p.name}`')
	}
	if info.is_event {
		return src.error('`${p.name}` of `${tag}` is an event')
	}
	if info.kind == .other {
		return src.error('property `${p.name}` of `${tag}` cannot be set by the interpreter; use compiled VML')
	}
	// A bare name is an enum value only where the property takes one.
	if p.expr.kind == .enum_name && info.kind != .enumeration {
		return src.error('unknown name `${p.expr.name}`')
	}
	style := info.kind == .style
	motion := p.name == 'motion'
	expr := if style {
		c.style_value(tag, p.expr, false)!
	} else if motion {
		c.motion_value(p.expr)!
	} else {
		c.expr(p.expr, true)!
	}
	return VmlIProp{
		name:     p.name
		expr:     expr
		reactive: vml_ir_reactive(expr)
		uses_app: vml_ir_uses_app(expr)
		style:    style
		motion:   motion
		src:      src
	}
}

fn (mut c VmlLoader) bind(tag string, widget VmlWidgetType, b vml.IBind) !VmlIBind {
	src := vml_ir_src(b.src)
	info := widget.prop(b.prop) or { return src.error('`${tag}` has no property `${b.prop}`') }
	if !info.bindable {
		return src.error('property `${b.prop}` of `${tag}` is not bindable')
	}
	return VmlIBind{
		prop:   b.prop
		target: c.expr(b.target, false)!
		write:  c.write_target(b.write)!
	}
}

fn (mut c VmlLoader) event(tag string, widget VmlWidgetType, e vml.IEvent) !VmlIEvent {
	src := vml_ir_src(e.src)
	info := widget.prop(e.name) or { return src.error('`${tag}` has no event `${e.name}`') }
	if !info.is_event {
		return src.error('`${e.name}` of `${tag}` is not an event')
	}
	handler := c.handler(e.handler, [])!
	return VmlIEvent{
		name:     e.name
		handler:  handler
		scope:    c.scope(e.scope)
		uses_app: vml_ir_uses_app(handler)
	}
}

// ref_decl checks the ref of an element id: the control it names must
// support ref commands.
fn (mut c VmlLoader) ref_decl(reference vml.IRef, src VmlSourceLocation) !VmlIRef {
	kind := vml_ref_kind_of(reference.tag) or {
		return src.error('`${reference.name}` names a ${reference.tag}, which has no ref methods')
	}
	return VmlIRef{
		name: reference.name
		slot: reference.slot
		kind: kind
		tag:  reference.tag
	}
}

fn (mut c VmlLoader) ref_target(tag string, x &vml.IExpr) !&VmlIExpr {
	src := vml_ir_src(x.src)
	kind := vml_ref_kind_of(tag) or { return src.error('`${tag}` cannot be the target of a ref') }
	want := vml_ref_kind_of(x.binding.ref_tag) or {
		return src.error('`${x.binding.name}` names a ${x.binding.ref_tag}, which has no ref methods')
	}
	if kind != want {
		return src.error('ref `${x.binding.name}` requires ${want}; received ${tag}')
	}
	return &VmlIExpr{
		kind:  .binding
		depth: x.depth
		slot:  x.binding.slot
		src:   src
	}
}

// ---------------------------------------------------------------- repeaters

fn (mut c VmlLoader) repeater(n &vml.INode, base string, fill ?&VmlSlotFill) !&VmlINode {
	r := n.repeat
	model := c.expr(r.model, false)!
	mut item_type := &VmlModelType(unsafe { nil })
	if model.typ != unsafe { nil } {
		if model.typ.kind != .array && model.typ.kind != .dynamic {
			return vml_ir_src(r.model_src).error('a `for` iterates an array, not ${model.typ.describe()}')
		}
		item_type = model.typ.elem
	}
	c.types['${r.key_scope.id}:0'] = item_type
	c.types['${r.item_scope.id}:${r.item_slot}'] = item_type
	mut repeat := &VmlIRepeater{
		name:           r.name
		model:          model
		model_uses_app: vml_ir_uses_app(model)
		key:            c.expr(r.key, false)!
		key_scope:      c.scope(r.key_scope)
		item_scope:     c.scope(r.item_scope)
		item_slot:      r.item_slot
		index_slot:     r.index_slot
	}
	repeat.children = c.children(r.children, base, fill)!
	return &VmlINode{
		kind:   .repeater
		tag:    'for'
		path:   vml_instance_path(base, n.path)
		src:    vml_ir_src(n.src)
		repeat: repeat
	}
}

// --------------------------------------------------------------- components

// invocation instantiates a component: the definition's scope and members,
// the invocation's arguments, handlers and root configuration in the caller,
// and the definition's root with the invocation's slot content.
fn (mut c VmlLoader) invocation(n &vml.INode, base string, fill ?&VmlSlotFill) !&VmlINode {
	src := vml_ir_src(n.src)
	inv := n.invoke
	def := c.program.components[inv.def_key] or {
		return src.error('unknown component `${n.tag}`')
	}
	path := vml_instance_path(base, n.path)
	mut comp := &VmlIComponent{
		name:       def.name
		owner_name: path
		scope:      c.scope(def.scope)
	}
	// The resolver supplies one argument per declared input, in order.
	for index, decl in def.inputs {
		arg := inv.args[index]
		match arg.kind {
			.event {
				comp.inputs << VmlIInput{
					name:    decl.name
					typ:     decl.typ
					kind:    .event
					slot:    decl.slot
					handler: if isnil(arg.handler) {
						&VmlIExpr(unsafe { nil })
					} else {
						c.handler(arg.handler, decl.params)!
					}
					scope:   c.scope(arg.scope)
					params:  decl.params
				}
			}
			.bound {
				expr := c.expr(arg.expr, false)!
				comp.inputs << VmlIInput{
					name:     decl.name
					typ:      decl.typ
					kind:     .bound
					slot:     decl.slot
					expr:     expr
					uses_app: vml_ir_uses_app(expr)
					write:    c.write_target(arg.write)!
				}
			}
			.argument, .default_value {
				value := if arg.kind == .argument { arg.expr } else { decl.default_value }
				expr := c.input_value(decl.typ, value, n.tag)!
				comp.inputs << VmlIInput{
					name:     decl.name
					typ:      decl.typ
					kind:     if arg.kind == .argument {
						VmlInputKind.argument
					} else {
						VmlInputKind.default_value
					}
					slot:     decl.slot
					expr:     expr
					uses_app: vml_ir_uses_app(expr)
				}
			}
		}
	}
	for reference in def.refs {
		comp.refs << c.ref_decl(reference, src)!
	}
	for data in def.data {
		expr := c.expr(data.expr, true)!
		comp.data << VmlIData{
			name:     data.name
			slot:     data.slot
			computed: data.computed
			expr:     expr
			uses_app: vml_ir_uses_app(expr)
		}
	}
	for fun in def.functions {
		c.function(fun)!
	}
	for watch in def.watches {
		expr := c.expr(watch.expr, false)!
		body := c.action(watch.body)!
		comp.watches << VmlIWatch{
			expr:     expr
			body:     body
			scope:    c.scope(watch.scope)
			uses_app: vml_ir_uses_app(expr) || vml_ir_uses_app(body)
		}
	}
	if !isnil(def.mount) {
		comp.mount = c.action(def.mount)!
	}
	if !isnil(def.unmount) {
		comp.unmount = c.action(def.unmount)!
	}
	if !isnil(def.cleanup) {
		comp.cleanup = c.action(def.cleanup)!
	}
	if !isnil(inv.key) {
		comp.key = c.expr(inv.key, true)!
	}
	root_tag := c.root_tag(def)
	root_widget := vml_widget_type(root_tag) or { VmlWidgetType{} }
	for p in inv.forwarded {
		comp.forward << c.prop(root_tag, root_widget, p)!
	}
	for e in inv.forwarded_events {
		comp.events << c.event(root_tag, root_widget, e)!
	}
	for b in inv.forwarded_binds {
		comp.binds << c.bind(root_tag, root_widget, b)!
	}
	if !isnil(inv.ref) {
		comp.ref = c.ref_target(root_tag, inv.ref)!
	}
	comp.root = c.node(def.root, path, &VmlSlotFill{
		inv:    inv
		parent: fill
	})!
	if comp.root.kind == .slot {
		return src.error('the root of component `${def.name}` is a `Slot`; wrap it in an element')
	}
	return &VmlINode{
		kind:    .component
		tag:     n.tag
		path:    path
		src:     src
		id:      n.id
		id_slot: n.id_slot
		comp:    comp
	}
}

// root_tag is the tag of the element a definition's root declares, through
// components whose root is another component.
fn (c &VmlLoader) root_tag(def &vml.IComponentDef) string {
	if def.root.kind == .component {
		inner := c.program.components[def.root.invoke.def_key] or { return '' }
		return c.root_tag(inner)
	}
	return def.root.tag
}

fn (mut c VmlLoader) input_value(typ string, x &vml.IExpr, tag string) !&VmlIExpr {
	if typ == 'ui2.StylePatch' {
		return c.style_value(tag, x, false)
	}
	if typ.trim_left('?') == 'ui2.MotionConfig' {
		return c.motion_value(x)
	}
	return c.expr(x, true)
}

fn (mut c VmlLoader) function(fun &vml.IFunction) !&VmlIFunction {
	if existing := c.functions[fun.scope.id] {
		return existing
	}
	mut def := &VmlIFunction{
		name:   fun.name
		params: fun.params
		scope:  c.scope(fun.scope)
	}
	c.functions[fun.scope.id] = def
	def.body = c.action(fun.body)!
	return def
}

// ------------------------------------------------------- styles and motion

// style_value checks a style value: lists, conditionals, helper calls with
// one argument, one level of interaction states, and model values.
fn (mut c VmlLoader) style_value(tag string, x &vml.IExpr, state bool) !&VmlIExpr {
	src := vml_ir_src(x.src)
	match x.kind {
		.array {
			mut items := []&VmlIExpr{cap: x.args.len}
			for arg in x.args {
				items << c.style_value(tag, arg, state)!
			}
			return &VmlIExpr{
				kind: .array
				args: items
				src:  src
			}
		}
		.conditional {
			return &VmlIExpr{
				kind: .conditional
				args: [c.expr(x.args[0], false)!, c.style_value(tag, x.args[1], state)!,
					c.style_value(tag, x.args[2], state)!]
				src:  src
			}
		}
		.helper {
			if x.name in vml_state_styles {
				if tag == 'Run' {
					return src.error('Run styles support text properties')
				}
				if state {
					return src.error('interaction styles cannot nest interaction states')
				}
				if x.args.len != 1 || x.args[0].kind != .array {
					return src.error('`${x.name}` requires one style list')
				}
				mut entries := []&VmlIExpr{cap: x.args[0].args.len}
				for entry in x.args[0].args {
					entries << c.style_value(tag, entry, true)!
				}
				return &VmlIExpr{
					kind: .style_state
					name: x.name
					args: entries
					src:  src
				}
			}
			if x.name !in vml_style_helpers {
				return src.error('unknown style helper `${x.name}`')
			}
			if x.args.len != 1 {
				return src.error('`${x.name}` requires exactly one argument')
			}
			if state && x.name !in vml_box_style_helpers {
				return src.error('interaction styles support box properties and foreground')
			}
			return &VmlIExpr{
				kind: .style_call
				name: x.name
				args: [c.expr(x.args[0], true)!]
				src:  src
			}
		}
		.app_field, .member, .binding, .app_call {
			return c.expr(x, false)
		}
		else {
			return src.error('style requires a list, typed style value or conditional style')
		}
	}
}

// motion_value checks a motion value: a motion helper call, a list of them,
// a conditional, or a model value.
fn (mut c VmlLoader) motion_value(x &vml.IExpr) !&VmlIExpr {
	src := vml_ir_src(x.src)
	match x.kind {
		.array {
			mut items := []&VmlIExpr{cap: x.args.len}
			for arg in x.args {
				items << c.motion_value(arg)!
			}
			return &VmlIExpr{
				kind: .array
				args: items
				src:  src
			}
		}
		.conditional {
			return &VmlIExpr{
				kind: .conditional
				args: [c.expr(x.args[0], false)!, c.motion_value(x.args[1])!,
					c.motion_value(x.args[2])!]
				src:  src
			}
		}
		.helper {
			if x.name in vml_compiled_motion_helpers {
				return src.error('the motion helper `${x.name}` takes a V callback or handle; use compiled VML')
			}
			kinds := vml_motion_helpers[x.name] or {
				return src.error('unknown motion helper `${x.name}`')
			}
			if x.args.len != kinds.len {
				return src.error('`${x.name}` takes ${kinds.len} argument(s), not ${x.args.len}')
			}
			mut args := []&VmlIExpr{cap: x.args.len}
			for arg in x.args {
				args << c.expr(arg, true)!
			}
			return &VmlIExpr{
				kind: .motion_call
				name: x.name
				args: args
				src:  src
			}
		}
		.app_field, .member, .binding, .app_call {
			return c.expr(x, false)
		}
		else {
			return src.error('motion requires a motion helper, a list of them, a typed motion value or a conditional')
		}
	}
}

// -------------------------------------------------------------- expressions

// expr checks an expression. `enums` allows a bare name that names nothing
// in scope, which is an enum value (`align: center`).
fn (mut c VmlLoader) expr(x &vml.IExpr, enums bool) !&VmlIExpr {
	src := vml_ir_src(x.src)
	match x.kind {
		.literal {
			return match x.literal {
				.string {
					&VmlIExpr{
						kind:  .literal
						value: VmlValue(x.value)
						typ:   &VmlModelType{
							name: 'string'
							kind: .text
						}
						src:   src
					}
				}
				.bool {
					&VmlIExpr{
						kind:  .literal
						value: VmlValue(x.value == 'true')
						typ:   &VmlModelType{
							name: 'bool'
							kind: .boolean
						}
						src:   src
					}
				}
				.float {
					&VmlIExpr{
						kind:  .literal
						value: VmlValue(x.value.f64())
						typ:   &VmlModelType{
							name: 'f64'
							kind: .number
						}
						src:   src
					}
				}
				.int {
					&VmlIExpr{
						kind:  .literal
						value: VmlValue(x.value.i64())
						typ:   &VmlModelType{
							name: 'int'
							kind: .integer
						}
						src:   src
					}
				}
			}
		}
		.color {
			if x.name.len != 7 {
				return src.error('invalid color `${x.name}`; colors are #RRGGBB')
			}
			return &VmlIExpr{
				kind:  .literal
				value: VmlValue(x.name)
				src:   src
			}
		}
		.enum_name {
			if !enums {
				return src.error('unknown name `${x.name}`')
			}
			return &VmlIExpr{
				kind:  .enum_name
				value: VmlValue(VmlEnum{
					name: x.name
				})
				src:   src
			}
		}
		.app_field {
			field := c.model.schema.fields[x.name] or {
				return src.error('the model ${c.model.type_name} has no field `${x.name}`')
			}
			if !field.is_pub {
				return src.error('field `${x.name}` of ${c.model.type_name} is not public')
			}
			return &VmlIExpr{
				kind: .app_field
				name: x.name
				typ:  field.typ
				src:  src
			}
		}
		.binding {
			b := x.binding
			match b.kind {
				.func, .event { return src.error('`${b.name}` is a function; call it') }
				.ref { return src.error('`${b.name}` is a ref; call one of its methods') }
				else {}
			}
			mut typ := c.types[vml_binding_key(b)] or { &VmlModelType(unsafe { nil }) }
			if b.kind == .param && b.typ in ['ui2.ElementEvent', 'ElementEvent'] {
				typ = vml_event_type()
			}
			return &VmlIExpr{
				kind:  .binding
				depth: x.depth
				slot:  b.slot
				typ:   typ
				src:   src
			}
		}
		.member {
			return c.member(c.expr(x.args[0], false)!, x.name, src)
		}
		.length {
			base := c.expr(x.args[0], false)!
			if base.typ != unsafe { nil } && base.typ.kind !in [.text, .array, .dynamic] {
				return c.member(base, 'len', src)
			}
			return &VmlIExpr{
				kind: .length
				args: [base]
				typ:  &VmlModelType{
					name: 'int'
					kind: .integer
				}
				src:  src
			}
		}
		.to_str {
			return &VmlIExpr{
				kind: .to_str
				args: [c.expr(x.args[0], false)!]
				typ:  &VmlModelType{
					name: 'string'
					kind: .text
				}
				src:  src
			}
		}
		.token {
			return &VmlIExpr{
				kind: .token
				name: x.name
				src:  src
			}
		}
		.geometry {
			return &VmlIExpr{
				kind:  .geometry
				name:  x.name
				depth: x.depth
				slot:  x.binding.slot
				typ:   &VmlModelType{
					name: 'f64'
					kind: .number
				}
				src:   src
			}
		}
		.external {
			return src.error('unknown name `${x.name.all_before('.')}`')
		}
		.not_, .negate {
			operand := c.expr(x.args[0], false)!
			return &VmlIExpr{
				kind: if x.kind == .not_ { VmlIKind.not_ } else { VmlIKind.negate }
				args: [operand]
				typ:  operand.typ
				src:  src
			}
		}
		.binary, .and_, .or_ {
			if x.kind == .binary && x.name !in ['+', '-', '*', '/', '%', '==', '!=', '<', '<=',
				'>', '>='] {
				return src.error('unsupported operator `${x.name}`')
			}
			return &VmlIExpr{
				kind: match x.kind {
					.and_ { VmlIKind.and_ }
					.or_ { VmlIKind.or_ }
					else { VmlIKind.binary }
				}
				name: x.name
				args: [c.expr(x.args[0], true)!, c.expr(x.args[1], true)!]
				src:  src
			}
		}
		.conditional {
			return &VmlIExpr{
				kind: .conditional
				args: [c.expr(x.args[0], false)!, c.expr(x.args[1], enums)!, c.expr(x.args[2],
					enums)!]
				src:  src
			}
		}
		.array, .interp {
			mut items := []&VmlIExpr{cap: x.args.len}
			for arg in x.args {
				items << c.expr(arg, x.kind == .array && enums)!
			}
			return &VmlIExpr{
				kind: if x.kind == .array { VmlIKind.array } else { VmlIKind.interp }
				args: items
				src:  src
			}
		}
		.app_call {
			mut args := []&VmlIExpr{cap: x.args.len}
			for arg in x.args {
				args << c.expr(arg, true)!
			}
			if method := c.model.schema.methods[x.name] {
				if !method.supported {
					return src.error('`app.${x.name}` has a signature the interpreter cannot call (parameters: ${method.params.join(', ')}); it calls methods taking nothing, one int, i64, f64, string, bool or ui2.ElementEvent, or two of int, f64, string and bool')
				}
				if method.params.len != args.len {
					return src.error('`app.${x.name}` takes ${method.params.len} argument(s), not ${args.len}')
				}
			} else if c.model.type_name != 'sample' {
				return src.error('the model ${c.model.type_name} has no method `${x.name}`')
			}
			return &VmlIExpr{
				kind: .app_call
				name: x.name
				args: args
				src:  src
			}
		}
		.fn_call, .emit {
			mut args := []&VmlIExpr{cap: x.args.len}
			for arg in x.args {
				args << c.expr(arg, true)!
			}
			return &VmlIExpr{
				kind:  if x.kind == .fn_call { VmlIKind.fn_call } else { VmlIKind.emit }
				depth: x.depth
				slot:  x.binding.slot
				args:  args
				func:  if x.kind == .fn_call {
					c.function(x.binding.func)!
				} else {
					&VmlIFunction(unsafe { nil })
				}
				src:   src
			}
		}
		.ref_call {
			kind := vml_ref_kind_of(x.binding.ref_tag) or { Kind.view }
			if x.name == 'focus' && kind in [.label, .image, .scroll] {
				return src.error('a ${kind} ref does not support focus')
			}
			if x.name == 'set_text' && kind !in [.text_field, .text_area] {
				return src.error('only TextInput and TextArea refs support set_text')
			}
			mut args := []&VmlIExpr{cap: x.args.len}
			for arg in x.args {
				args << c.expr(arg, false)!
			}
			return &VmlIExpr{
				kind:  .ref_call
				name:  x.name
				depth: x.depth
				slot:  x.binding.slot
				args:  args
				src:   src
			}
		}
		.module_call, .helper {
			if !x.name.contains('.') {
				return src.error('unknown function `${x.name}`')
			}
			return src.error('the interpreter does not support the call `${x.name}(...)`; it calls app methods, component functions and events, ref methods, style helpers and `.str()`; use compiled VML for other V calls')
		}
		.method_call {
			if x.name.len == 0 {
				return src.error('the interpreter does not call function values; use compiled VML for `fn` inputs')
			}
			return src.error('the interpreter does not call `.${x.name}(...)` on values; it calls app methods, component functions and events, ref methods, style helpers and `.str()`; use compiled VML for other V calls')
		}
		.index {
			base := c.expr(x.args[0], false)!
			index := c.expr(x.args[1], false)!
			mut elem := &VmlModelType(unsafe { nil })
			if base.typ != unsafe { nil } {
				match base.typ.kind {
					.array, .text { elem = base.typ.elem }
					.dynamic {}
					.unsupported { return src.error('the interpreter cannot index ${base.typ.describe()}; use compiled VML') }
					else { return src.error('${base.typ.describe()} cannot be indexed') }
				}
			}
			return &VmlIExpr{
				kind: .index
				args: [base, index]
				typ:  elem
				src:  src
			}
		}
		.or_else {
			left := c.expr(x.args[0], false)!
			return &VmlIExpr{
				kind: .or_else
				args: [left, c.expr(x.args[1], enums)!]
				typ:  if left.typ != unsafe { nil } && left.typ.kind == .optional {
					left.typ.elem
				} else {
					left.typ
				}
				src:  src
			}
		}
		.app_method, .fn_ref, .event_ref, .module_fn {
			return c.handler(x, [])
		}
		.assign_app, .assign_binding, .assign_place, .block {
			return c.action(x)
		}
	}
}

// member reads `.name`, checked against the static type when it is known.
fn (mut c VmlLoader) member(base &VmlIExpr, name string, src VmlSourceLocation) !&VmlIExpr {
	typ := base.typ
	mut field_type := &VmlModelType(unsafe { nil })
	if typ != unsafe { nil } {
		match typ.kind {
			.object {
				field := typ.fields[name] or { return src.error('${typ.name} has no field `${name}`') }
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
	return &VmlIExpr{
		kind: .member
		name: name
		args: [base]
		typ:  field_type
		src:  src
	}
}

// ---------------------------------------------------------------- handlers

// handler checks an event handler: a reference (`app.save`, a component
// function or event, an external callback) or an action. `payload` are the
// parameters of the component event it handles.
fn (mut c VmlLoader) handler(h &vml.IExpr, payload []vml.Parameter) !&VmlIExpr {
	src := vml_ir_src(h.src)
	match h.kind {
		.app_method {
			if method := c.model.schema.methods[h.name] {
				ok := method.params.len == 0
					|| (method.params.len == 1 && method.params[0] == 'ElementEvent')
					|| (payload.len > 0 && method.params == payload.map(it.typ))
				if !ok {
					return src.error('callback `app.${h.name}` requires fn () or fn (ui2.ElementEvent)')
				}
			} else if c.model.type_name != 'sample' {
				return src.error('the model ${c.model.type_name} has no method `${h.name}`')
			}
			return &VmlIExpr{
				kind: .app_method
				name: h.name
				src:  src
			}
		}
		.fn_ref {
			params := h.binding.params
			if params.len > 1 || (params.len == 1
				&& params[0].typ !in ['ui2.ElementEvent', 'ElementEvent']
				&& payload.map(it.typ) != params.map(it.typ)) {
				return src.error('callback `${h.binding.name}` requires fn () or fn (ui2.ElementEvent)')
			}
			return &VmlIExpr{
				kind:  .fn_ref
				depth: h.depth
				slot:  h.binding.slot
				func:  c.function(h.binding.func)!
				src:   src
			}
		}
		.event_ref {
			if h.binding.params.len > 0 && payload.map(it.typ) != h.binding.params.map(it.typ) {
				return src.error('event `${h.binding.name}` has a payload and cannot be a callback')
			}
			return &VmlIExpr{
				kind:  .event_ref
				depth: h.depth
				slot:  h.binding.slot
				src:   src
			}
		}
		.module_fn {
			if h.name !in c.callbacks && !c.lenient {
				return src.error('unknown callback `${h.name}`; pass it in VmlInterpretConfig.callbacks')
			}
			if h.name !in c.externals {
				c.externals << h.name
			}
			return &VmlIExpr{
				kind: .external
				name: h.name
				src:  src
			}
		}
		.external {
			return src.error('`${h.name}` is not callable')
		}
		else {
			return c.action(h)
		}
	}
}

// action checks a statement: an assignment, a call or a block.
fn (mut c VmlLoader) action(x &vml.IExpr) !&VmlIExpr {
	match x.kind {
		.block {
			mut statements := []&VmlIExpr{cap: x.args.len}
			for statement in x.args {
				statements << c.action(statement)!
			}
			return &VmlIExpr{
				kind: .block
				args: statements
				src:  vml_ir_src(x.src)
			}
		}
		.assign_app, .assign_binding, .assign_place {
			target := c.write_target(x)!
			return &VmlIExpr{
				...target
				args: [c.expr(x.args.last(), true)!]
			}
		}
		else {
			return c.expr(x, true)
		}
	}
}

// write_target checks a writable target: a public mutable `app` field, a
// state or a bindable input.
fn (mut c VmlLoader) write_target(x &vml.IExpr) !&VmlIExpr {
	src := vml_ir_src(x.src)
	match x.kind {
		.assign_app {
			field := c.model.schema.fields[x.name] or {
				if c.model.type_name == 'sample' {
					return &VmlIExpr{
						kind: .assign_app
						name: x.name
						op:   x.op
						src:  src
					}
				}
				return src.error('the model ${c.model.type_name} has no field `${x.name}`')
			}
			if !field.is_pub || !field.is_mut {
				return src.error('VML target `app.${x.name}` must be public and mutable')
			}
			return &VmlIExpr{
				kind: .assign_app
				name: x.name
				typ:  field.typ
				op:   x.op
				src:  src
			}
		}
		.assign_binding {
			return &VmlIExpr{
				kind:  if x.binding.kind == .state {
					VmlIKind.assign_state
				} else {
					VmlIKind.assign_input
				}
				depth: x.depth
				slot:  x.binding.slot
				op:    x.op
				src:   src
			}
		}
		.assign_place {
			return src.error('the interpreter writes `app.field`, state and bound inputs; use compiled VML to write a field or an element of one')
		}
		else {
			return src.error('VML target is read-only or unknown; use state or an explicit bind connection')
		}
	}
}

// ------------------------------------------------------------ static facts

// vml_ir_reactive reports whether an expression reads anything that can
// change: the model, a scope value, an element's geometry or a theme token.
fn vml_ir_reactive(e &VmlIExpr) bool {
	if e.kind in [.app_field, .binding, .geometry, .token, .app_call, .fn_call, .ref_call] {
		return true
	}
	return e.args.any(vml_ir_reactive(it))
}

fn vml_ir_uses_app(e &VmlIExpr) bool {
	if e.kind in [.app_field, .app_call, .app_method, .assign_app] {
		return true
	}
	return e.args.any(vml_ir_uses_app(it))
}
