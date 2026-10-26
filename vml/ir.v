module vml

// The VML intermediate representation. `resolve` turns a parsed document into
// this resolved form once; the generator (`generate`) prints it as V and the
// ui2 interpreter evaluates it, so both consumers share one reading of the
// language: which name every identifier denotes, which scope owns it, the
// identity path of every node, the order of declarations and which values are
// reactive. The IR knows no widget and no model type: tags stay names, model
// paths stay names, and literals keep their source text. Consumers that know
// the widgets and the model (V's type checker for generated code, the
// interpreter's registry and model schema) check those.

// ScopeKind is what opened a lexical scope.
pub enum ScopeKind {
	document  // the document root: its refs
	component // a component instance: inputs, refs, state, functions
	item      // one `for` item: its item and index names
	key       // a `for` key expression: the item name
	branch    // one branch of an `if`: the unwrapped value of `if name := option`
	slot      // slot content, resolved in its author's scope
	function  // a component function: its parameters
	listener  // a component event handler in the caller: the payload names
	handler   // an element event handler: `event`
	watch     // a `watch` body: its old and new values
}

// BindingKind is what a name in a scope denotes.
pub enum BindingKind {
	state    // `state name := value`: writable
	computed // `computed name := value`
	input    // a component input; writable when bound
	item     // a `for` item or the unwrapped value of `if name := option`: read-only
	index    // the `for` index
	func     // a component function
	event    // a component event (callable to emit)
	ref      // the ref of an element id whose methods are called (`name.focus()`)
	id       // an element id (its geometry)
	param    // a function, listener, handler or watch parameter
}

pub struct Binding {
pub:
	kind     BindingKind
	name     string
	slot     int
	scope_id int
	writable bool
	// func: its declaration; event: its payload; param: its declared type.
	params []Parameter
	func   &IFunction = unsafe { nil }
	typ    string
	// ref: the tag of the element it refers to.
	ref_tag string
}

// Scope is one lexical scope. Scopes that own a component owner at run time
// (document, component, item, slot) collect the theme tokens the expressions
// evaluated under that owner read; they are prepared before any memo reads
// them.
@[heap]
pub struct Scope {
pub:
	id     int
	kind   ScopeKind
	parent &Scope = unsafe { nil }
	// A component scope: the scope its invocation was written in, where its
	// slot content resolves.
	caller &Scope = unsafe { nil }
pub mut:
	names  map[string]Binding
	order  []string
	tokens []string
}

pub fn (s &Scope) slots() int {
	return s.order.len
}

// lookup finds `name` in this scope or an enclosing one; depth counts the
// scopes walked up.
pub fn (s &Scope) lookup(name string) ?(Binding, int) {
	mut current := unsafe { s }
	mut depth := 0
	for current != unsafe { nil } {
		if binding := current.names[name] {
			return binding, depth
		}
		current = current.parent
		depth++
	}
	return none
}

// lookup_value finds a bare name that denotes a value or a function: element
// ids are not values (only `id.x/y/width/height` read them), so a bare name
// equal to an id is an enum value or a helper of that name.
pub fn (s &Scope) lookup_value(name string) ?(Binding, int) {
	mut current := unsafe { s }
	mut depth := 0
	for current != unsafe { nil } {
		if binding := current.names[name] {
			if binding.kind != .id {
				return binding, depth
			}
		}
		current = current.parent
		depth++
	}
	return none
}

// owner_scope is the nearest scope with its own component owner.
pub fn (s &Scope) owner_scope() &Scope {
	mut current := unsafe { s }
	for current.kind in [.key, .function, .listener, .handler, .watch] && current.parent != unsafe { nil } {
		current = current.parent
	}
	return current
}

// LiteralKind is the type of a literal as written.
pub enum LiteralKind {
	string
	int
	float
	bool
}

// IKind is the kind of a resolved expression or statement.
pub enum IKind {
	literal     // text in `literal`: `"a"`, `12`, `1.5`, `true`
	color       // name: `#RRGGBB` or `#RRGGBBAA`
	enum_name   // name: a bare enum value
	app_field   // name: a top-level model field
	binding     // binding: a scope value (state, computed, input, item, index, param)
	member      // args[0].name
	length      // args[0].len
	to_str      // args[0].str()
	token       // name: `color:x`, `spacing:x`, `radius:x` or `font_size:x`
	geometry    // binding: an element id; name: x, y, width or height
	external    // name: a dotted path that names no VML value, kept for V
	not_        // !args[0]
	negate      // -args[0]
	binary      // args[0] name args[1]
	and_        // args[0] && args[1]
	or_         // args[0] || args[1]
	conditional // args[0] ? args[1] : args[2]
	array       // [args]
	interp      // the concatenation of args; text parts are string literals
	app_call    // name(args) on the model
	fn_call     // binding: a component function; args
	emit        // binding: a component event; args
	ref_call    // binding: a ref; name: its method; args
	module_call // name(args): a function of the module the code lives in
	helper      // name(args): a helper of the value's namespace (`font_size(18)`)
	index       // args[0][args[1]]
	method_call // args[0].name(args[1..]); without a name, the call of the function value args[0]
	or_else     // args[0] or { args[1] }
	// Handler references: a callable value.
	app_method // name: `on_x: app.method`
	fn_ref     // binding: `on_x: local_fn`
	event_ref  // binding: `on_x: component_event`
	module_fn  // name: a function of the module, or an external callback
	// Statements. `op` is the assignment operator: `=`, `+=`, `-=`, `*=`,
	// `/=`, `%=` or `<<`.
	assign_app     // app.name op args[0]
	assign_binding // binding op args[0]: a state or a bindable input
	assign_place   // place op args[1]; args[0] is the place, a field or index path
	block          // args, in order
}

@[heap]
pub struct IExpr {
pub:
	kind    IKind
	name    string
	literal LiteralKind
	// The literal's value: the string contents (unescaped) or the number or
	// bool as written.
	value   string
	binding Binding
	// depth counts the scopes from the use to the binding's scope.
	depth int
	args  []&IExpr
	// helper: the call ends in `!` (a helper taking a list of entries).
	fallible bool
	op       string
	src      Location
}

// IProp is a property of an element (or forwarded to a component's root).
pub struct IProp {
pub:
	name string
	expr &IExpr = unsafe { nil }
	// The value is built by the helper namespace of the property (a list, a
	// helper call or a conditional with one): `style: [font_size(18)]`.
	helper bool
	// The value reads something that can change after the build: the model,
	// a scope value, element geometry or a theme token.
	reactive bool
	uses_app bool
	src      Location
}

// IEvent is an `on_*` property: its handler runs in a handler scope where
// `event` is the element event.
pub struct IEvent {
pub:
	name     string
	handler  &IExpr = unsafe { nil }
	scope    &Scope = unsafe { nil }
	uses_app bool
	src      Location
}

// IBind is a `bind.name: target` connection.
pub struct IBind {
pub:
	prop   string
	target &IExpr = unsafe { nil } // the value read
	write  &IExpr = unsafe { nil } // the assignment; args is the written value at run time
	src    Location
}

// InputKind is how an invocation supplies a component input.
pub enum InputKind {
	event         // handled by the caller (or not at all)
	argument      // a value written by the caller
	bound         // a `bind.name:` connection to a writable caller target
	default_value // not supplied: the declared default, in the component's scope
}

// IInputDecl is an input a component declares in its signature.
pub struct IInputDecl {
pub:
	name     string
	typ      string
	slot     int
	event    bool
	bindable bool
	// The declared default, resolved in the component's scope, or nil.
	default_value &IExpr = unsafe { nil }
	default_helper bool
	params         []Parameter
	src            Location
}

// IArg is how one invocation supplies one declared input.
pub struct IArg {
pub:
	name     string
	typ      string
	kind     InputKind
	// argument, bound: in the caller's scope.
	expr     &IExpr = unsafe { nil }
	helper   bool
	uses_app bool
	// event: the handler in its listener scope, or nil for none.
	handler &IExpr = unsafe { nil }
	scope   &Scope = unsafe { nil }
	params  []Parameter
	// bound: the caller's target assignment.
	write &IExpr = unsafe { nil }
	src   Location
}

pub struct IData {
pub:
	name     string
	slot     int
	computed bool
	expr     &IExpr = unsafe { nil }
	uses_app bool
	src      Location
}

// IRef is the ref of an element id whose methods the document calls.
pub struct IRef {
pub:
	name    string
	slot    int
	tag     string
	methods []IRefMethod
}

// IRefMethod is the first call of one ref method, where V checks the target
// supports it.
pub struct IRefMethod {
pub:
	name string
	src  Location
}

// IWatch is a component `watch`: `body` runs in `scope`, whose slot 0 is the
// old value and slot 1 the new one, each time the value of `expr` changes.
pub struct IWatch {
pub:
	expr     &IExpr = unsafe { nil }
	body     &IExpr = unsafe { nil }
	scope    &Scope = unsafe { nil }
	old      string
	now      string
	uses_app bool
	src      Location
}

@[heap]
pub struct IFunction {
pub:
	name   string
	params []Parameter
	scope  &Scope = unsafe { nil }
pub mut:
	body &IExpr = unsafe { nil }
}

// IComponentDef is a component definition, resolved once for every
// invocation. Its nodes' paths are relative to an instance (they start with
// `root`), and `slots` lists where its `Slot`s are.
@[heap]
pub struct IComponentDef {
pub:
	key    string
	name   string
	source string
	scope  &Scope = unsafe { nil }
pub mut:
	inputs    []IInputDecl
	refs      []IRef
	data      []IData
	functions []&IFunction
	watches   []IWatch
	mount     &IExpr = unsafe { nil }
	unmount   &IExpr = unsafe { nil }
	cleanup   &IExpr = unsafe { nil }
	root      &INode = unsafe { nil }
	// Slot name to the instance-relative path of its `Slot`.
	slots    map[string]string
	uses_app bool
	src      Location
}

// IInvocation is one use of a component, resolved in the caller's scope.
@[heap]
pub struct IInvocation {
pub:
	def_key string
	caller  &Scope = unsafe { nil }
pub mut:
	args []IArg
	// Slot content by slot name, resolved in a slot scope of the caller. Its
	// paths are relative to the instance: the slot's path, then the index.
	slots       map[string][]&INode
	slot_scopes map[string]&Scope
	// The invocation's key and ref.
	key &IExpr = unsafe { nil }
	ref &IExpr = unsafe { nil }
	// Invocation properties the component does not declare: they configure its
	// root and are evaluated in the caller's scope.
	forwarded        []IProp
	forwarded_events []IEvent
	forwarded_binds  []IBind
}

@[heap]
pub struct IRepeater {
pub:
	// The suffix the repeater's names use.
	name           string
	model          &IExpr = unsafe { nil }
	model_uses_app bool
	key            &IExpr = unsafe { nil }
	key_scope      &Scope = unsafe { nil }
	item_scope     &Scope = unsafe { nil }
	item_slot      int
	index_slot     int
	src            Location
	model_src      Location
	key_src        Location
pub mut:
	children []&INode
}

// IBranch is one branch of an `if`: its condition (nil for `else`) and
// children, in a scope with an owner of its own. `bind_slot` is the slot of
// the unwrapped value of `if name := option` (-1 for none).
@[heap]
pub struct IBranch {
pub:
	cond      &IExpr = unsafe { nil }
	scope     &Scope = unsafe { nil }
	bind_slot int    = -1
	src       Location
pub mut:
	children []&INode
}

// ICond is an `if` chain. It is a keyed list of at most one item, the index
// of the branch whose condition holds: a change of branch removes the old
// branch's nodes (with their exit motion) and builds the new one's.
@[heap]
pub struct ICond {
pub:
	name          string
	cond_uses_app bool
pub mut:
	branches []&IBranch
}

pub enum INodeKind {
	element
	component // an invocation: `invoke` and the definition it names
	repeater  // a `for`
	cond      // an `if`
	slot      // a `Slot` of a component definition: `tag` is the slot's name
}

@[heap]
pub struct INode {
pub:
	kind INodeKind
	tag  string
	// The identity path of the node in its document.
	path string
	src  Location
	// The path is relative to a component instance (`root...`) or, for slot
	// content, to the instance it fills.
	relative bool
pub mut:
	id         string
	id_slot    int = -1
	id_binding Binding
	key      &IExpr = unsafe { nil }
	key_src  Location
	props    []IProp
	events   []IEvent
	binds    []IBind
	ref      &IExpr = unsafe { nil }
	children []&INode
	invoke   &IInvocation = unsafe { nil }
	repeat   &IRepeater   = unsafe { nil }
	cond     &ICond       = unsafe { nil }
}

// Program is a resolved document: its root node and the scope it opens.
@[heap]
pub struct Program {
pub:
	path string
pub mut:
	root  &INode = unsafe { nil }
	scope &Scope = unsafe { nil }
	// The component definitions the document uses, by key.
	components map[string]&IComponentDef
	// The refs of the document's own element ids.
	refs []IRef
	// The root is a menu document (`Menu` or `MenuBar`).
	menus bool
	// Functions of the module that the document's handlers name or call.
	module_functions []string
	// The module functions handlers name as callbacks (`on_click: save`).
	module_callbacks []string
	// Every file of the document: the root and its imports.
	files []string
	// The document reads `app`.
	uses_app bool
}
