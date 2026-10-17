module ui2

import math

// VML interpreter registry (design §3.1), compiled only with
// `-d vml_interpreter`. Every builtin tag is one line in
// `vml_builtin_widgets`; descriptors and dynamic setters come from the props
// types by comptime reflection, so interpreted nodes are the same
// VmlWidgetNode[P] nodes the generic lowering declares.
//
// Deviations from the design signatures:
// * `VmlWidgetType.new_node` takes the parent as `?VmlParent`, the handle
//   `vml_parent()` returns (so a repeater segment can be a parent too), and
//   returns the interface value `VmlDynNode` rather than `&VmlDynNode`.
// * `VmlDynNode.bind` is `bind_value`: V has no overloading, and the typed
//   `bind(name, fn (P) !)` of VmlWidgetNode[P] keeps its name.
// * `VmlDynNode` adds `prop_value(name, eval)`, the dynamic `prop`: an effect
//   evaluates the expression and sets the field, so reactive geometry and the
//   per-batch commit behave as on the compiled path, while `set_prop` sets a
//   value once. It also adds `get_prop` (inspectors, write-backs) and
//   `vml_parent`, the parent protocol of vml_child.
// * `VmlPropInfo` adds `type_name` and `optional` (an unset optional field
//   keeps the constructor default); `VmlWidgetType` adds `type_name`.
// * `VmlValueKind` is defined here: number, integer, color, boolean, string,
//   display_text, enumeration, style, callback, object, other.
// * `VmlObject.get` returns an option. `VmlReflect` is not generic: with a
//   generic implementor (`VmlReflect[T]`) V generates C that does not compile
//   for `==` on VmlValue and prints it as an unknown interface value, so
//   `vml_reflect(value)` erases the type and `vml_reflected[T](r)` recovers it. A struct-typed field takes a
//   VmlReflect holding a value of its type. Optional struct fields convert
//   only for the types ui2 props use (?MotionConfig, ?OverlayConfig,
//   ?OverlayPoint): V cannot name the payload type of a generic option.
// * `VmlCallable` is a handler, `run(event)`, which `set_prop` wraps with
//   `owner.callback` (one batch plus `invalidate_app`, like compiled handlers).
// * Bindable fields are the fields `apply_event` writes for a change event,
//   found by applying one to the default props.
// * `vml_register` returns an error for an empty or builtin tag.

// VmlValue is an interpreted value.
pub type VmlValue = string
	| i64
	| f64
	| bool
	| VmlEnum
	| []VmlValue
	| VmlObject
	| VmlCallable
	| StylePatch
	| VmlNone

// VmlNone is an absent value: an unset option, or the result of a void call.
// Assigned to an optional property it unsets the property.
pub struct VmlNone {}

// VmlEnum is a bare name (`align: right`).
pub struct VmlEnum {
pub:
	name string
}

// VmlObject is a value with named fields (a model value).
pub interface VmlObject {
	get(name string) ?VmlValue
}

// VmlReflect holds a typed V value as a VmlObject (`vml_reflect(value)`). A
// struct-typed property takes the held value when its type matches.
pub struct VmlReflect {
pub:
	type_name string
mut:
	type_idx int
	data     voidptr
	read     fn (data voidptr, name string) ?VmlValue = unsafe { nil }
	// The held value's text (its type, `Type{...}`), and (for model values)
	// value equality with another holder of the same type.
	text fn (data voidptr) string              = unsafe { nil }
	same fn (data voidptr, other voidptr) bool = unsafe { nil }
}

@[heap]
struct VmlReflectBox[T] {
	value T
}

pub fn vml_reflect[T](value T) VmlReflect {
	return VmlReflect{
		type_name: typeof[T]().name
		type_idx:  typeof[T]().idx
		data:      voidptr(&VmlReflectBox[T]{
			value: value
		})
		read:      vml_reflect_read[T]
		text:      vml_reflect_text[T]
	}
}

// vml_reflect_text names the held value's type. V's own formatting of
// arbitrary structs is not generated here: it is large, and documents print
// fields rather than whole structs.
fn vml_reflect_text[T](_ voidptr) string {
	return typeof[T]().name.all_after_last('.') + '{...}'
}

// str is the held value's text: its type name, as `Type{...}`.
pub fn (r VmlReflect) str() string {
	if r.text == unsafe { nil } || r.data == unsafe { nil } { return r.type_name }
	return r.text(r.data)
}

// equals reports whether both hold equal values of the same type.
pub fn (r VmlReflect) equals(other VmlReflect) bool {
	if r.type_idx != other.type_idx { return false }
	if r.data == other.data { return true }
	if r.same == unsafe { nil } || r.data == unsafe { nil } || other.data == unsafe { nil } {
		return false
	}
	return r.same(r.data, other.data)
}

fn vml_reflect_read[T](data voidptr, name string) ?VmlValue {
	boxed := unsafe { &VmlReflectBox[T](data) }
	return vml_field_value(boxed.value, name)
}

pub fn (r VmlReflect) get(name string) ?VmlValue {
	if r.read == unsafe { nil } { return none }
	return r.read(r.data, name)
}

// vml_reflected is the held value when it has type T.
pub fn vml_reflected[T](r VmlReflect) ?T {
	if r.data == unsafe { nil } || r.type_idx != typeof[T]().idx { return none }
	boxed := unsafe { &VmlReflectBox[T](r.data) }
	return boxed.value
}

// VmlCallable is an interpreted event handler.
pub struct VmlCallable {
pub:
	name string
	run  fn (event ElementEvent) ! = unsafe { nil }
}

// VmlValueKind is the kind of value a property takes.
pub enum VmlValueKind {
	number       // f64: a number
	integer      // int: an integral number
	color        // u32: `#RRGGBB` or an integer
	boolean      // bool
	string       // string
	display_text // DisplayText: a string or a number
	enumeration  // an enum: one of `enum_values`
	style        // StylePatch: a style or an array of styles
	callback     // ElementCallback: a VmlCallable
	object       // a struct: a VmlReflect holding that struct
	other        // not settable by the interpreter
}

// VmlPropInfo describes one property of a widget.
pub struct VmlPropInfo {
pub:
	name        string
	kind        VmlValueKind
	type_name   string
	enum_values []string
	optional    bool
	is_event    bool
	bindable    bool
}

// VmlWidgetType describes a widget tag and creates its nodes.
pub struct VmlWidgetType {
pub:
	name      string
	type_name string
	props     []VmlPropInfo
	new_node  fn (mut owner CompiledVmlComponent, o VmlNodeOptions, parent ?VmlParent) !VmlDynNode = unsafe { nil }
}

pub fn (t VmlWidgetType) prop(name string) ?VmlPropInfo {
	for info in t.props {
		if info.name == name { return info }
	}
	return none
}

// VmlDynNode is a node driven by property names, implemented by
// VmlWidgetNode[P].
pub interface VmlDynNode {
	geometry() !Rect
	get_prop(name string) !VmlValue
mut:
	set_prop(name string, value VmlValue) !
	prop_value(name string, eval fn () !VmlValue) !
	on(event string, cb ElementCallback) !
	bind_value(name string, write fn (VmlValue) !) !
	bind_ref(ref VmlNodeRef) !
	vml_parent() VmlParent
}

// vml_parent lets a parent handle itself be the parent of vml_child.
pub fn (p VmlParent) vml_parent() VmlParent {
	return p
}

// vml_widget describes props type P: its properties (embedded structs
// included) and a constructor for its nodes.
pub fn vml_widget[P]() VmlWidgetType {
	$if P is VmlElementProps {
	} $else $if P is VmlPartProps {
	} $else {
		$compile_error('vml_widget requires a props type with `build` or `part`')
	}
	bindable := vml_bindable_fields[P]()
	mut props := []VmlPropInfo{}
	vml_collect_props(P{}, bindable, mut props)
	return VmlWidgetType{
		name:      vml_element_name(P.name)
		type_name: P.name
		props:     props
		new_node:  vml_new_dyn_node[P]
	}
}

fn vml_new_dyn_node[P](mut owner CompiledVmlComponent, o VmlNodeOptions, parent ?VmlParent) !VmlDynNode {
	if handle := parent {
		// A fresh value: V does not resolve methods on the unwrapped option
		// inside a generic call.
		mut host := VmlParent{
			host: handle.host
			list: handle.list
		}
		return vml_child(mut host, mut owner, P{}, o)!
	}
	return vml_root(mut owner, P{}, o)!
}

// The builtin tags.
const vml_builtin_widgets = {
	'Screen':        vml_widget[ScreenProps]()
	'View':          vml_widget[ViewProps]()
	'Absolute':      vml_widget[AbsoluteProps]()
	'Flex':          vml_widget[FlexProps]()
	'Row':           vml_widget[RowProps]()
	'Column':        vml_widget[ColumnProps]()
	'Grid':          vml_widget[GridProps]()
	'Stack':         vml_widget[StackProps]()
	'Scroll':        vml_widget[ScrollProps]()
	'ScaledContent': vml_widget[ScaledContentProps]()
	'Label':         vml_widget[LabelProps]()
	'Run':           vml_widget[RunProps]()
	'TextInput':     vml_widget[TextInputProps]()
	'TextArea':      vml_widget[TextAreaProps]()
	'Image':         vml_widget[ImageProps]()
	'Button':        vml_widget[ButtonProps]()
	'Checkbox':      vml_widget[CheckboxProps]()
	'Dropdown':      vml_widget[DropdownProps]()
	'Option':        vml_widget[OptionProps]()
	'ProgressBar':   vml_widget[ProgressBarProps]()
	'Slider':        vml_widget[SliderProps]()
	'Switch':        vml_widget[SwitchProps]()
	'Spinner':       vml_widget[SpinnerProps]()
	'MessageBox':    vml_widget[MessageBoxProps]()
	'ToggleButton':  vml_widget[ToggleButtonProps]()
	'Accordion':     vml_widget[AccordionProps]()
	'AccordionItem': vml_widget[AccordionItemProps]()
	'TabbedPanel':   vml_widget[TabbedPanelProps]()
	'Tab':           vml_widget[TabProps]()
	'Carousel':      vml_widget[CarouselProps]()
	'CarouselSlide': vml_widget[CarouselSlideProps]()
	'ScreenManager': vml_widget[ScreenManagerProps]()
	'ManagedScreen': vml_widget[ManagedScreenProps]()
	'ScreenView':    vml_widget[ScreenViewProps]()
	'TreeView':      vml_widget[TreeViewProps]()
	'TreeNode':      vml_widget[TreeNodeProps]()
	'MenuItem':      vml_widget[MenuItemProps]()
	'MenuSeparator': vml_widget[MenuSeparatorProps]()
	'Menu':          vml_widget[MenuProps]()
	'MenuBar':       vml_widget[MenuBarProps]()
	'Dialog':        vml_widget[DialogProps]()
	'Popover':       vml_widget[PopoverProps]()
	'MenuOverlay':   vml_widget[MenuOverlayProps]()
	'ContextMenu':   vml_widget[ContextMenuProps]()
	'Tooltip':       vml_widget[TooltipProps]()
}

@[heap]
struct VmlWidgetRegistry {
mut:
	types map[string]VmlWidgetType
}

const vml_widget_registry = &VmlWidgetRegistry{}

// vml_register adds a third-party widget tag (by convention a dotted tag,
// `module.Widget`).
pub fn vml_register(tag string, t VmlWidgetType) ! {
	if tag.len == 0 { return error('VML widget tag is empty') }
	if tag in vml_builtin_widgets { return error('`${tag}` is a builtin VML element') }
	if t.new_node == unsafe { nil } { return error('VML widget `${tag}` has no constructor') }
	mut registry := unsafe { vml_widget_registry }
	registry.types[tag] = t
}

// vml_widget_type looks a tag up: registered widgets, then builtins.
pub fn vml_widget_type(tag string) ?VmlWidgetType {
	registry := unsafe { vml_widget_registry }
	if tag in registry.types { return registry.types[tag] }
	return vml_builtin_widgets[tag] or { return none }
}

// vml_widget_tags lists the builtin and registered tags, sorted.
pub fn vml_widget_tags() []string {
	registry := unsafe { vml_widget_registry }
	mut tags := vml_builtin_widgets.keys()
	tags << registry.types.keys()
	tags.sort()
	return tags
}

// vml_dyn_node declares a node of `tag`: the document root without a parent.
pub fn vml_dyn_node(tag string, mut owner CompiledVmlComponent, o VmlNodeOptions, parent ?VmlParent) !VmlDynNode {
	t := vml_widget_type(tag) or {
		return o.src.wrap_error(error('unknown VML element `${tag}`'))
	}
	return t.new_node(mut owner, o, parent)!
}

// vml_element_name is the tag of a props type: `ui2.SliderProps` is `Slider`.
fn vml_element_name(type_name string) string {
	name := type_name.all_after_last('.')
	return if name.len > 5 && name.ends_with('Props') { name[..name.len - 5] } else { name }
}

// ------------------------------------------------------------ dynamic nodes

// set_prop converts and assigns one property. On a built node the change
// commits like a prop effect.
pub fn (mut n VmlWidgetNode[P]) set_prop(name string, value VmlValue) ! {
	n.owner.require_alive() or { return n.src.wrap_error(err) }
	before := n.props
	found := vml_set_field(mut n.props, name, value, n.setter(name)) or {
		return n.src.wrap_error(err)
	}
	if !found { return n.src.wrap_error(n.unknown(name)) }
	n.dyn_changed(before)
}

// prop_value registers a reactive property: `eval` runs in an effect and its
// value is converted into the field.
pub fn (mut n VmlWidgetNode[P]) prop_value(name string, eval fn () !VmlValue) ! {
	if !vml_has_field(n.props, name) { return n.src.wrap_error(n.unknown(name)) }
	if eval == unsafe { nil } {
		return n.src.wrap_error(error('VML property `${name}` expression is nil'))
	}
	setter := n.setter(name)
	n.prop(name, fn [name, eval, setter] [P](mut p P) ! {
		vml_set_field(mut p, name, eval()!, setter)!
	})!
}

// get_prop reads one property.
pub fn (n &VmlWidgetNode[P]) get_prop(name string) !VmlValue {
	if value := vml_field_value(n.props, name) { return value }
	if vml_has_field(n.props, name) {
		return error('property `${name}` of `${vml_element_name(P.name)}` is not set')
	}
	return n.unknown(name)
}

// on sets an event handler: `click` or `on_click`.
pub fn (mut n VmlWidgetNode[P]) on(event string, cb ElementCallback) ! {
	n.owner.require_alive() or { return n.src.wrap_error(err) }
	field := if event.starts_with('on_') { event } else { 'on_' + event }
	before := n.props
	if !vml_set_handler(mut n.props, field, cb) {
		return n.src.wrap_error(error('`${vml_element_name(P.name)}` has no event `${event}`'))
	}
	n.dyn_changed(before)
}

// bind_value registers a write-back of a bindable property.
pub fn (mut n VmlWidgetNode[P]) bind_value(name string, write fn (VmlValue) !) ! {
	if name !in vml_bindable_fields[P]() {
		if !vml_has_field(n.props, name) { return n.src.wrap_error(n.unknown(name)) }
		return n.src.wrap_error(error('property `${name}` of `${vml_element_name(P.name)}` is not bindable'))
	}
	if write == unsafe { nil } { return n.src.wrap_error(error('VML binding `${name}` is nil')) }
	// Captured under another name: inside a generic closure V types a
	// captured `write` as a different function.
	sink := write
	n.bind(name, fn [name, sink] [P](p P) ! {
		sink(vml_field_value(p, name) or { return error('VML binding `${name}` has no value') })!
	})!
}

// bind_ref binds a ref (vml_ref.v) to the node when it is built, or now when
// it already is.
pub fn (mut n VmlWidgetNode[P]) bind_ref(ref VmlNodeRef) ! {
	n.owner.require_alive() or { return n.src.wrap_error(err) }
	n.refs << ref
	if retained := n.node() {
		mut bound := ref
		bound.bind(retained) or { return n.src.wrap_error(err) }
	}
}

fn (n &VmlWidgetNode[P]) setter(name string) VmlSetter {
	return VmlSetter{
		element: vml_element_name(P.name)
		prop:    name
		owner:   n.owner
	}
}

fn (n &VmlWidgetNode[P]) unknown(name string) IError {
	return error('`${vml_element_name(P.name)}` has no property `${name}`')
}

fn (mut n VmlWidgetNode[P]) dyn_changed(before P) {
	if n.VmlNodeCore.node == unsafe { nil } && !n.consumed { return }
	n.props_changed(before)
}

// ------------------------------------------------------------- descriptors

fn vml_collect_props[T](value T, bindable []string, mut out []VmlPropInfo) {
	// Own fields first: they shadow fields of embedded structs.
	$for field in T.fields {
		$if field.is_embed {
		} $else {
			mut kind := VmlValueKind.other
			mut optional := false
			mut enum_values := []string{}
			$if field.typ is f64 {
				kind = .number
			} $else $if field.typ is ?f64 {
				kind = .number
				optional = true
			} $else $if field.typ is int {
				kind = .integer
			} $else $if field.typ is ?int {
				kind = .integer
				optional = true
			} $else $if field.typ is u32 {
				kind = .color
			} $else $if field.typ is ?u32 {
				kind = .color
				optional = true
			} $else $if field.typ is bool {
				kind = .boolean
			} $else $if field.typ is ?bool {
				kind = .boolean
				optional = true
			} $else $if field.typ is string {
				kind = .string
			} $else $if field.typ is ?string {
				kind = .string
				optional = true
			} $else $if field.typ is DisplayText {
				kind = .display_text
			} $else $if field.typ is ?DisplayText {
				kind = .display_text
				optional = true
			} $else $if field.typ is StylePatch {
				kind = .style
			} $else $if field.typ is ElementCallback {
				kind = .callback
			} $else $if field.typ is ?MotionConfig {
				kind = .object
				optional = true
			} $else $if field.typ is ?OverlayConfig {
				kind = .object
				optional = true
			} $else $if field.typ is ?OverlayPoint {
				kind = .object
				optional = true
			} $else $if field.is_enum {
				kind = .enumeration
				enum_values = vml_enum_names(value.$(field.name))
			} $else $if field.is_struct {
				kind = .object
			}
			out << VmlPropInfo{
				name:        field.name
				kind:        kind
				type_name:   typeof(value.$(field.name)).name
				enum_values: enum_values
				optional:    optional
				is_event:    kind == .callback
				bindable:    field.name in bindable
			}
		}
	}
	$for field in T.fields {
		$if field.is_embed {
			mut embedded := []VmlPropInfo{}
			vml_collect_props(value.$(field.name), bindable, mut embedded)
			for info in embedded {
				if !out.any(it.name == info.name) { out << info }
			}
		}
	}
}

fn vml_enum_names[E](value E) []string {
	_ = value
	mut names := []string{}
	$for item in E.values {
		names << item.name
	}
	return names
}

fn vml_enum_name[E](value E) string {
	$for item in E.values {
		if item.value == value { return item.name }
	}
	return int(value).str()
}

// The fields `apply_event` writes for a change event.
fn vml_bindable_fields[P]() []string {
	mut names := []string{}
	$if P is VmlEventProps {
		before := P{}
		mut probe := P{}
		probe.apply_event(ElementEvent{
			kind:    .change
			text:    '\u0001'
			value:   0.123456789
			checked: true
		})
		$for field in P.fields {
			$if field.typ is string {
				if probe.$(field.name) != before.$(field.name) { names << field.name }
			} $else $if field.typ is DisplayText {
				if probe.$(field.name) != before.$(field.name) { names << field.name }
			} $else $if field.typ is f64 {
				if probe.$(field.name) != before.$(field.name) { names << field.name }
			} $else $if field.typ is bool {
				if probe.$(field.name) != before.$(field.name) { names << field.name }
			}
		}
	}
	return names
}

fn vml_has_field[T](value T, name string) bool {
	$for field in T.fields {
		$if field.is_embed {
			if vml_has_field(value.$(field.name), name) { return true }
		} $else {
			if field.name == name { return true }
		}
	}
	return false
}

// ------------------------------------------------------------- conversions

// VmlSetter converts values for one property of one element.
struct VmlSetter {
	element string
	prop    string
	owner   &CompiledVmlComponent = unsafe { nil }
}

fn (s VmlSetter) mismatch(expected string, value VmlValue) IError {
	return error('property `${s.prop}` of `${s.element}` expects ${expected}, not ${vml_value_description(value)}')
}

fn vml_value_description(value VmlValue) string {
	return match value {
		string { 'the string "${value}"' }
		i64 { 'the integer ${value}' }
		f64 { 'the number ${value}' }
		bool { 'the bool ${value}' }
		VmlEnum { 'the name `${value.name}`' }
		[]VmlValue { 'an array' }
		VmlObject { 'an object' }
		VmlCallable { 'a callable' }
		StylePatch { 'a style' }
		VmlNone { 'none' }
	}
}

fn (s VmlSetter) number(value VmlValue) !f64 {
	return match value {
		i64 { f64(value) }
		f64 { value }
		else { s.mismatch('a number', value) }
	}
}

fn (s VmlSetter) integer(value VmlValue) !int {
	whole := match value {
		i64 {
			value
		}
		f64 {
			if !math.is_finite(value) || value != math.trunc(value) {
				return error('property `${s.prop}` of `${s.element}` expects an integral number, not ${value}')
			}
			i64(value)
		}
		else {
			return s.mismatch('an integer', value)
		}
	}
	if whole < i64(min_i32) || whole > i64(max_i32) {
		return error('property `${s.prop}` of `${s.element}` expects an integer that fits in int, not ${whole}')
	}
	return int(whole)
}

fn (s VmlSetter) color(value VmlValue) !u32 {
	match value {
		string {
			if value.len == 7 && value[0] == `#` && value[1..].bytes().all(it.is_hex_digit()) {
				return u32(('0x' + value[1..]).u64())
			}
		}
		i64 {
			if value >= 0 && value <= i64(max_u32) { return u32(value) }
		}
		f64 {
			if math.is_finite(value) && value == math.trunc(value) && value >= 0
				&& value <= f64(max_u32) {
				return u32(value)
			}
		}
		else {}
	}
	return s.mismatch('a color (#RRGGBB or an integer from 0 to 0xFFFFFFFF)', value)
}

fn (s VmlSetter) boolean(value VmlValue) !bool {
	return match value {
		bool { value }
		else { s.mismatch('a bool', value) }
	}
}

fn (s VmlSetter) text(value VmlValue) !string {
	return match value {
		string { value }
		else { s.mismatch('a string', value) }
	}
}

fn (s VmlSetter) display(value VmlValue) !DisplayText {
	return match value {
		string { DisplayText(value) }
		i64 { DisplayText(value) }
		f64 { DisplayText(value) }
		else { s.mismatch('a string or a number', value) }
	}
}

fn (s VmlSetter) style(value VmlValue) !StylePatch {
	match value {
		StylePatch {
			return value
		}
		[]VmlValue {
			mut patches := []StylePatch{cap: value.len}
			for item in value {
				if item is StylePatch {
					patches << item
				} else {
					return s.mismatch('a style or an array of styles', item)
				}
			}
			return compose_styles(patches)
		}
		else {
			return s.mismatch('a style', value)
		}
	}
}

fn (s VmlSetter) callback(value VmlValue) !ElementCallback {
	if value is VmlCallable {
		if value.run != unsafe { nil } {
			mut owner := s.owner
			return owner.callback(value.run)
		}
	}
	return s.mismatch('a callable', value)
}

fn vml_enum_from[E](current E, value VmlValue, s VmlSetter) !E {
	name := match value {
		VmlEnum { value.name }
		string { value }
		else { return s.mismatch('one of ${vml_enum_names(current).join(', ')}', value) }
	}
	$for item in E.values {
		if item.name == name { return item.value }
	}
	return error('property `${s.prop}` of `${s.element}` has no value `${name}`; valid values: ${vml_enum_names(current).join(', ')}')
}

fn vml_native[F](value VmlValue, s VmlSetter) !F {
	if value is VmlObject {
		object := value
		if object is VmlReflect {
			if held := vml_reflected[F](object) { return held }
		}
	}
	return s.mismatch('a ${vml_element_name(typeof[F]().name)} value', value)
}

fn vml_native_like[F](current F, value VmlValue, s VmlSetter) !F {
	_ = current
	return vml_native[F](value, s)!
}

fn vml_set_field[T](mut target T, name string, value VmlValue, s VmlSetter) !bool {
	$for field in T.fields {
		$if field.is_embed {
		} $else {
			if field.name == name {
				$if field.is_option {
					if value is VmlNone {
						target.$(field.name) = none
						return true
					}
				}
				$if field.typ is f64 {
					target.$(field.name) = s.number(value)!
				} $else $if field.typ is ?f64 {
					target.$(field.name) = s.number(value)!
				} $else $if field.typ is int {
					target.$(field.name) = s.integer(value)!
				} $else $if field.typ is ?int {
					target.$(field.name) = s.integer(value)!
				} $else $if field.typ is u32 {
					target.$(field.name) = s.color(value)!
				} $else $if field.typ is ?u32 {
					target.$(field.name) = s.color(value)!
				} $else $if field.typ is bool {
					target.$(field.name) = s.boolean(value)!
				} $else $if field.typ is ?bool {
					target.$(field.name) = s.boolean(value)!
				} $else $if field.typ is string {
					target.$(field.name) = s.text(value)!
				} $else $if field.typ is ?string {
					target.$(field.name) = s.text(value)!
				} $else $if field.typ is DisplayText {
					target.$(field.name) = s.display(value)!
				} $else $if field.typ is ?DisplayText {
					target.$(field.name) = s.display(value)!
				} $else $if field.typ is StylePatch {
					target.$(field.name) = s.style(value)!
				} $else $if field.typ is ElementCallback {
					target.$(field.name) = s.callback(value)!
				} $else $if field.typ is ?MotionConfig {
					target.$(field.name) = vml_native[MotionConfig](value, s)!
				} $else $if field.typ is ?OverlayConfig {
					target.$(field.name) = vml_native[OverlayConfig](value, s)!
				} $else $if field.typ is ?OverlayPoint {
					target.$(field.name) = vml_native[OverlayPoint](value, s)!
				} $else $if field.is_enum {
					target.$(field.name) = vml_enum_from(target.$(field.name), value, s)!
				} $else $if field.is_struct {
					target.$(field.name) = vml_native_like(target.$(field.name), value, s)!
				} $else {
					return error('property `${s.prop}` of `${s.element}` cannot be set by the interpreter')
				}
				return true
			}
		}
	}
	$for field in T.fields {
		$if field.is_embed {
			mut embedded := target.$(field.name)
			if vml_set_field(mut embedded, name, value, s)! {
				target.$(field.name) = embedded
				return true
			}
		}
	}
	return false
}

fn vml_set_handler[T](mut target T, name string, cb ElementCallback) bool {
	$for field in T.fields {
		$if field.is_embed {
		} $else {
			$if field.typ is ElementCallback {
				if field.name == name {
					target.$(field.name) = cb
					return true
				}
			}
		}
	}
	$for field in T.fields {
		$if field.is_embed {
			mut embedded := target.$(field.name)
			if vml_set_handler(mut embedded, name, cb) {
				target.$(field.name) = embedded
				return true
			}
		}
	}
	return false
}

// vml_field_value reads a field as a VmlValue; none when the field is
// unknown, unset or has no interpreted representation.
fn vml_field_value[T](value T, name string) ?VmlValue {
	$for field in T.fields {
		$if field.is_embed {
		} $else {
			if field.name == name {
				$if field.typ is f64 {
					return VmlValue(value.$(field.name))
				} $else $if field.typ is ?f64 {
					if v := value.$(field.name) { return VmlValue(v) }
				} $else $if field.typ is int {
					return VmlValue(i64(value.$(field.name)))
				} $else $if field.typ is ?int {
					if v := value.$(field.name) { return VmlValue(i64(v)) }
				} $else $if field.typ is i64 {
					return VmlValue(value.$(field.name))
				} $else $if field.typ is u32 {
					return VmlValue(i64(value.$(field.name)))
				} $else $if field.typ is ?u32 {
					if v := value.$(field.name) { return VmlValue(i64(v)) }
				} $else $if field.typ is bool {
					return VmlValue(value.$(field.name))
				} $else $if field.typ is ?bool {
					if v := value.$(field.name) { return VmlValue(v) }
				} $else $if field.typ is string {
					return VmlValue(value.$(field.name))
				} $else $if field.typ is ?string {
					if v := value.$(field.name) { return VmlValue(v) }
				} $else $if field.typ is DisplayText {
					return vml_display_value(value.$(field.name))
				} $else $if field.typ is ?DisplayText {
					if v := value.$(field.name) { return vml_display_value(v) }
				} $else $if field.typ is StylePatch {
					return VmlValue(value.$(field.name))
				} $else $if field.typ is ElementCallback {
					cb := value.$(field.name)
					if cb != unsafe { nil } {
						return VmlValue(VmlCallable{
							name: field.name
							run:  fn [cb] (event ElementEvent) ! {
								cb(event)
							}
						})
					}
				} $else $if field.typ is ?MotionConfig {
					if v := value.$(field.name) { return vml_reflect_value[MotionConfig](v) }
				} $else $if field.typ is ?OverlayConfig {
					if v := value.$(field.name) { return vml_reflect_value[OverlayConfig](v) }
				} $else $if field.typ is ?OverlayPoint {
					if v := value.$(field.name) { return vml_reflect_value[OverlayPoint](v) }
				} $else $if field.is_enum {
					return VmlValue(VmlEnum{
						name: vml_enum_name(value.$(field.name))
					})
				} $else $if field.is_struct {
					return vml_reflect_value(value.$(field.name))
				}
				return none
			}
		}
	}
	$for field in T.fields {
		$if field.is_embed {
			if v := vml_field_value(value.$(field.name), name) { return v }
		}
	}
	return none
}

fn vml_display_value(text DisplayText) VmlValue {
	return match text {
		string { VmlValue(text) }
		int { VmlValue(i64(text)) }
		i64 { VmlValue(text) }
		f64 { VmlValue(text) }
	}
}

fn vml_reflect_value[F](value F) VmlValue {
	return VmlValue(VmlObject(vml_reflect(value)))
}
