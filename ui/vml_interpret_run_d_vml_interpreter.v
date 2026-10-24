module ui2

import math

// Building and evaluating an interpreted document (design §3.5), compiled only
// with `-d vml_interpreter`. Each lexical scope of the IR becomes a frame at
// run time; a frame holds the scope's values (state signals, computed memos,
// repeater item and index signals, element handles, refs, parameters) and the
// component owner its expressions run under. Nodes are declared through the
// registry, so they are the VmlWidgetNode[P] nodes of compiled VML: a
// property that reads anything reactive is one effect (`prop_value`), a
// constant is set once, events run in `owner.callback` batches and model
// reads subscribe through `watch_app`, exactly like compiled code.

// VmlSession is what the frames of one built document share.
@[heap]
struct VmlSession {
	program   &VmlProgram = unsafe { nil }
	model     &VmlModel   = unsafe { nil }
	callbacks map[string]ElementCallback
	fallback  ?fn (name string) ElementCallback
mut:
	// Hot reload: state values of the previous document, by owner namespace
	// and state name, and the states this document created.
	carry  map[string]VmlValue
	states []VmlStateRecord
}

struct VmlStateRecord {
	key    string
	signal &Signal[VmlValue] = unsafe { nil }
}

// VmlItem is a repeater item. Its equality compares values, so an unchanged
// model array does not update the list (compiled items compare with `==`).
struct VmlItem {
	value VmlValue
}

fn (a VmlItem) == (b VmlItem) bool {
	return vml_value_equal(a.value, b.value)
}

@[heap]
struct VmlFrame {
	run    &VmlSession = unsafe { nil }
	parent &VmlFrame   = unsafe { nil }
	// For a component frame: the frame it was invoked from.
	caller &VmlFrame = unsafe { nil }
mut:
	owner &CompiledVmlComponent = unsafe { nil }
	cells []VmlCell
}

struct VmlCell {
mut:
	signal   &Signal[VmlValue] = unsafe { nil }
	memo     &Memo[VmlValue]   = unsafe { nil }
	item     &Signal[VmlItem]  = unsafe { nil }
	index    &Signal[int]      = unsafe { nil }
	value    VmlValue          = VmlNone{}
	node     ?VmlDynNode
	ref      &VmlDynRef        = unsafe { nil }
	listener fn ([]VmlValue) ! = unsafe { nil }
	setter   fn (VmlValue) !   = unsafe { nil }
}

fn (f &VmlFrame) up(depth int) &VmlFrame {
	mut current := unsafe { f }
	for _ in 0 .. depth {
		current = current.parent
	}
	return current
}

fn (f &VmlFrame) child_frame(owner &CompiledVmlComponent, slots int) &VmlFrame {
	return &VmlFrame{
		run:    f.run
		parent: unsafe { f }
		owner:  unsafe { owner }
		cells:  []VmlCell{len: slots}
	}
}

// --------------------------------------------------------------- equality

// vml_value_same is signal equality: scalars by value (NaNs are equal), and
// compound values always change, like compiled signals of those types.
fn vml_value_same(a VmlValue, b VmlValue) bool {
	match a {
		string {
			if b is string { return a == b }
		}
		i64 {
			if b is i64 { return a == b }
		}
		f64 {
			if b is f64 { return a == b || (a != a && b != b) }
		}
		bool {
			if b is bool { return a == b }
		}
		VmlEnum {
			if b is VmlEnum { return a.name == b.name }
		}
		VmlNone {
			return b is VmlNone
		}
		else {}
	}
	return false
}

// vml_value_equal is V's `==`: compound values compare by contents.
fn vml_value_equal(a VmlValue, b VmlValue) bool {
	match a {
		string {
			if b is string { return a == b }
		}
		i64 {
			if b is i64 { return a == b }
			if b is f64 { return f64(a) == b }
		}
		f64 {
			if b is f64 { return a == b }
			if b is i64 { return a == f64(b) }
		}
		bool {
			if b is bool { return a == b }
		}
		VmlEnum {
			if b is VmlEnum { return a.name == b.name }
			if b is string { return a.name == b }
		}
		[]VmlValue {
			if b is []VmlValue {
				if a.len != b.len { return false }
				for index, item in a {
					if !vml_value_equal(item, b[index]) { return false }
				}
				return true
			}
		}
		VmlObject {
			if b is VmlObject {
				left := a
				right := b
				if left is VmlReflect && right is VmlReflect {
					return left.equals(right)
				}
			}
		}
		StylePatch {
			if b is StylePatch { return a == b }
		}
		VmlCallable {
			if b is VmlCallable { return a.name == b.name && a.run == b.run }
		}
		VmlNone {
			return b is VmlNone
		}
	}
	return false
}

// vml_value_text formats a value as V string interpolation does.
fn vml_value_text(value VmlValue) string {
	return match value {
		string { value }
		i64 { value.str() }
		f64 { value.str() }
		bool { value.str() }
		VmlEnum { value.name }
		[]VmlValue { '[' + value.map(vml_value_repr(it)).join(', ') + ']' }
		VmlObject { vml_object_text(value) }
		StylePatch { 'ui2.StylePatch{...}' }
		VmlCallable { 'fn (ui2.ElementEvent)' }
		VmlNone { 'none' }
	}
}

fn vml_object_text(object VmlObject) string {
	if object is VmlReflect { return object.str() }
	return 'object'
}

// vml_value_repr formats an array element: strings are quoted.
fn vml_value_repr(value VmlValue) string {
	if value is string { return "'" + value + "'" }
	return vml_value_text(value)
}

// vml_coerce converts a value to a declared V type where V converts
// implicitly: an integer stored as a float.
fn vml_coerce(value VmlValue, typ string) VmlValue {
	if value is i64 && typ in ['f64', 'f32'] { return VmlValue(f64(value)) }
	return value
}

// vml_assign_value converts a value for an assignment to `current`'s type,
// as V does for an integer assigned to a float.
fn vml_assign_value(current VmlValue, value VmlValue) VmlValue {
	if current is f64 && value is i64 { return VmlValue(f64(value)) }
	return value
}

// ------------------------------------------------------------- evaluation

fn (f &VmlFrame) read(slot int) !VmlValue {
	cell := f.cells[slot]
	if cell.signal != unsafe { nil } {
		mut signal := cell.signal
		return signal.get()!
	}
	if cell.memo != unsafe { nil } {
		mut memo := cell.memo
		return memo.get()!
	}
	if cell.item != unsafe { nil } {
		mut item := cell.item
		return item.get()!.value
	}
	if cell.index != unsafe { nil } {
		mut index := cell.index
		return VmlValue(i64(index.get()!))
	}
	return cell.value
}

fn (f &VmlFrame) eval(e &VmlIExpr) !VmlValue {
	match e.kind {
		.literal, .enum_name {
			return e.value
		}
		.app_field {
			model := f.run.model
			return model.read(model.data, e.name) or { return e.src.error(err.msg()) }
		}
		.binding {
			return f.up(e.depth).read(e.slot)!
		}
		.member {
			base := f.eval(e.args[0])!
			if base is VmlObject {
				return base.get(e.name) or {
					return e.src.error('${vml_value_description(base)} has no readable field `${e.name}`')
				}
			}
			return e.src.error('`${e.name}`: ${vml_value_description(base)} has no fields')
		}
		.length {
			base := f.eval(e.args[0])!
			return match base {
				string { VmlValue(i64(base.len)) }
				[]VmlValue { VmlValue(i64(base.len)) }
				else { e.src.error('`len`: ${vml_value_description(base)} has no length') }
			}
		}
		.to_str {
			return VmlValue(vml_value_text(f.eval(e.args[0])!))
		}
		.token {
			mut owner := f.owner
			family := e.name.all_before(':')
			name := e.name.all_after(':')
			return match family {
				'color' { VmlValue(i64(owner.color_token(name)!)) }
				'spacing' { VmlValue(owner.spacing_token(name)!) }
				'radius' { VmlValue(owner.radius_token(name)!) }
				else { VmlValue(owner.font_size_token(name)!) }
			}
		}
		.geometry {
			cell := f.up(e.depth).cells[e.slot]
			node := cell.node or { return e.src.error('the element is not declared yet') }
			area := node.geometry()!
			return VmlValue(match e.name {
				'x' { area.x }
				'y' { area.y }
				'width' { area.width }
				else { area.height }
			})
		}
		.not_ {
			value := f.eval(e.args[0])!
			if value is bool { return VmlValue(!value) }
			return e.src.error('`!` requires a bool, not ${vml_value_description(value)}')
		}
		.negate {
			value := f.eval(e.args[0])!
			return match value {
				i64 { VmlValue(-value) }
				f64 { VmlValue(-value) }
				else { e.src.error('`-` requires a number, not ${vml_value_description(value)}') }
			}
		}
		.binary {
			return vml_binary(e.name, f.eval(e.args[0])!, f.eval(e.args[1])!, e.src)!
		}
		.and_, .or_ {
			left := f.eval(e.args[0])!
			if left !is bool {
				return e.src.error('`${if e.kind == .and_ { '&&' } else { '||' }}` requires bools, not ${vml_value_description(left)}')
			}
			if (left as bool) == (e.kind == .or_) { return left }
			right := f.eval(e.args[1])!
			if right !is bool {
				return e.src.error('`${if e.kind == .and_ { '&&' } else { '||' }}` requires bools, not ${vml_value_description(right)}')
			}
			return right
		}
		.conditional {
			condition := f.eval(e.args[0])!
			if condition !is bool {
				return e.src.error('a condition requires a bool, not ${vml_value_description(condition)}')
			}
			return f.eval(if condition as bool { e.args[1] } else { e.args[2] })!
		}
		.array {
			mut items := []VmlValue{cap: e.args.len}
			for arg in e.args {
				items << f.eval(arg)!
			}
			return VmlValue(items)
		}
		.interp {
			mut parts := []string{cap: e.args.len}
			for arg in e.args {
				parts << vml_value_text(f.eval(arg)!)
			}
			return VmlValue(parts.join(''))
		}
		.app_call {
			mut args := []VmlValue{cap: e.args.len}
			for arg in e.args {
				args << f.eval(arg)!
			}
			model := f.run.model
			return model.call(model.data, e.name, args) or { return e.src.error(err.msg()) }
		}
		.fn_call {
			mut args := []VmlValue{cap: e.args.len}
			for arg in e.args {
				args << f.eval(arg)!
			}
			f.call_function(e, args)!
			return VmlValue(VmlNone{})
		}
		.emit {
			mut args := []VmlValue{cap: e.args.len}
			for arg in e.args {
				args << f.eval(arg)!
			}
			listener := f.up(e.depth).cells[e.slot].listener
			if listener != unsafe { nil } { listener(args)! }
			return VmlValue(VmlNone{})
		}
		.ref_call {
			mut args := []VmlValue{cap: e.args.len}
			for arg in e.args {
				args << f.eval(arg)!
			}
			mut ref := f.up(e.depth).cells[e.slot].ref
			return ref.call(e.name, args) or { return e.src.error(err.msg()) }
		}
		.style_call {
			return VmlValue(vml_style_call(e.name, f.eval(e.args[0])!) or {
				return e.src.error(err.msg())
			})
		}
		.motion_call {
			mut args := []VmlValue{cap: e.args.len}
			for arg in e.args {
				args << f.eval(arg)!
			}
			patch := vml_motion_call(e.name, args) or { return e.src.error(err.msg()) }
			return VmlValue(VmlObject(vml_motion_patch_object(patch)))
		}
		.style_state {
			mut patches := []StylePatch{cap: e.args.len}
			for arg in e.args {
				value := f.eval(arg)!
				patches << vml_style_value(value) or { return e.src.error('`${e.name}`: ${err.msg()}') }
			}
			patch := match e.name {
				'hover' { style_hover(patches) or { return e.src.error(err.msg()) } }
				'focus' { style_focus(patches) or { return e.src.error(err.msg()) } }
				'pressed' { style_pressed(patches) or { return e.src.error(err.msg()) } }
				else { style_disabled(patches) or { return e.src.error(err.msg()) } }
			}
			return VmlValue(patch)
		}
		.app_method, .fn_ref, .event_ref, .external {
			return VmlValue(VmlCallable{
				name: e.name
				run:  f.callable(e)
			})
		}
		.assign_app, .assign_state, .assign_input, .block {
			f.exec(e)!
			return VmlValue(VmlNone{})
		}
	}
}

// exec runs a statement.
fn (f &VmlFrame) exec(e &VmlIExpr) ! {
	match e.kind {
		.block {
			for statement in e.args {
				f.exec(statement)!
			}
		}
		.assign_app, .assign_state, .assign_input {
			f.write(e, f.eval(e.args[0])!)!
		}
		else {
			f.eval(e)!
		}
	}
}

// write assigns `value` to an assignment target.
fn (f &VmlFrame) write(target &VmlIExpr, value VmlValue) ! {
	match target.kind {
		.assign_app {
			model := f.run.model
			current := model.read(model.data, target.name) or { VmlValue(VmlNone{}) }
			model.write(model.data, target.name, vml_assign_value(current, value)) or {
				return target.src.error(err.msg())
			}
		}
		.assign_state {
			mut signal := f.up(target.depth).cells[target.slot].signal
			signal.set(vml_assign_value(signal.peek()!, value))!
		}
		.assign_input {
			setter := f.up(target.depth).cells[target.slot].setter
			setter(value)!
		}
		else {
			return target.src.error('not an assignment target')
		}
	}
}

fn (f &VmlFrame) call_function(e &VmlIExpr, args []VmlValue) ! {
	def := e.func
	home := f.up(e.depth)
	mut frame := home.child_frame(home.owner, def.scope.slots)
	for index, parameter in def.params {
		frame.cells[index].value = vml_coerce(args[index], parameter.typ)
	}
	frame.exec(def.body)!
}

// callable is the handler of a reference: an app method, a component
// function or event, or an external callback.
fn (f &VmlFrame) callable(e &VmlIExpr) fn (ElementEvent) ! {
	frame := unsafe { f }
	match e.kind {
		.app_method {
			name := e.name
			return fn [frame, name] (event ElementEvent) ! {
				model := frame.run.model
				model.call_event(model.data, name, event)!
			}
		}
		.fn_ref {
			return fn [frame, e] (event ElementEvent) ! {
				args := if e.func.params.len == 1 {
					[VmlValue(VmlObject(vml_model_object(event)))]
				} else {
					[]VmlValue{}
				}
				frame.call_function(e, args)!
			}
		}
		.event_ref {
			return fn [frame, e] (event ElementEvent) ! {
				listener := frame.up(e.depth).cells[e.slot].listener
				if listener != unsafe { nil } { listener([])! }
			}
		}
		.external {
			callback := frame.external(e.name)
			return fn [callback] (event ElementEvent) ! {
				if callback != unsafe { nil } { callback(event) }
			}
		}
		else {
			return fn [frame, e] (event ElementEvent) ! {
				frame.exec(e)!
			}
		}
	}
}

fn (f &VmlFrame) external(name string) ElementCallback {
	if callback := f.run.callbacks[name] { return callback }
	if fallback := f.run.fallback { return fallback(name) }
	return unsafe { nil }
}

// vml_binary applies a binary operator with V's semantics: integer
// arithmetic stays integral (with integer division), mixing an integer with
// a float gives a float, `+` joins strings, and comparisons need comparable
// operands. `%` of floats truncates them first, as compiled number contexts do.
fn vml_binary(op string, left VmlValue, right VmlValue, src VmlSourceLocation) !VmlValue {
	if op in ['==', '!='] {
		if !vml_comparable(left, right) {
			return src.error('`${op}` cannot compare ${vml_value_description(left)} with ${vml_value_description(right)}')
		}
		equal := vml_value_equal(left, right)
		return VmlValue(if op == '==' { equal } else { !equal })
	}
	if left is string && right is string {
		return match op {
			'+' { VmlValue(left + right) }
			'<' { VmlValue(left < right) }
			'<=' { VmlValue(left <= right) }
			'>' { VmlValue(left > right) }
			'>=' { VmlValue(left >= right) }
			else { src.error('`${op}` is not defined for strings') }
		}
	}
	if left is i64 && right is i64 {
		return match op {
			'+' {
				VmlValue(left + right)
			}
			'-' {
				VmlValue(left - right)
			}
			'*' {
				VmlValue(left * right)
			}
			'/' {
				if right == 0 { return src.error('division by zero') }
				VmlValue(left / right)
			}
			'%' {
				if right == 0 { return src.error('modulo by zero') }
				VmlValue(left % right)
			}
			'<' {
				VmlValue(left < right)
			}
			'<=' {
				VmlValue(left <= right)
			}
			'>' {
				VmlValue(left > right)
			}
			else {
				VmlValue(left >= right)
			}
		}
	}
	a := vml_number(left) or {
		return src.error('`${op}` requires numbers, not ${vml_value_description(left)}')
	}
	b := vml_number(right) or {
		return src.error('`${op}` requires numbers, not ${vml_value_description(right)}')
	}
	return match op {
		'+' {
			VmlValue(a + b)
		}
		'-' {
			VmlValue(a - b)
		}
		'*' {
			VmlValue(a * b)
		}
		'/' {
			VmlValue(a / b)
		}
		'%' {
			if i64(b) == 0 { return src.error('modulo by zero') }
			VmlValue(f64(i64(a) % i64(b)))
		}
		'<' {
			VmlValue(a < b)
		}
		'<=' {
			VmlValue(a <= b)
		}
		'>' {
			VmlValue(a > b)
		}
		else {
			VmlValue(a >= b)
		}
	}
}

fn vml_number(value VmlValue) ?f64 {
	return match value {
		i64 { f64(value) }
		f64 { value }
		else { none }
	}
}

fn vml_is_number(value VmlValue) bool {
	return value is i64 || value is f64
}

fn vml_comparable(left VmlValue, right VmlValue) bool {
	if vml_is_number(left) && vml_is_number(right) { return true }
	return match left {
		string { right is string || right is VmlEnum }
		bool { right is bool }
		VmlEnum { right is VmlEnum || right is string }
		[]VmlValue { right is []VmlValue }
		VmlObject { right is VmlObject }
		StylePatch { right is StylePatch }
		VmlNone { true }
		else { right is VmlNone }
	}
}

// ------------------------------------------------------------------ styles

fn vml_style_value(value VmlValue) !StylePatch {
	return match value {
		StylePatch {
			value
		}
		[]VmlValue {
			mut patches := []StylePatch{cap: value.len}
			for item in value {
				patches << vml_style_value(item)!
			}
			compose_styles(patches)
		}
		else {
			error('expects a style, not ${vml_value_description(value)}')
		}
	}
}

// vml_style_call calls a style helper of ui/style.v with its argument
// converted like the property it sets.
fn vml_style_call(name string, arg VmlValue) !StylePatch {
	s := VmlSetter{
		element: 'style'
		prop:    name
	}
	return match name {
		'background' { style_background(s.color(arg)!) }
		'radius' { style_radius(s.number(arg)!) }
		'transparent' { style_transparent(s.boolean(arg)!) }
		'border_color' { style_border_color(s.color(arg)!) }
		'border_left' { style_border_left(s.number(arg)!) }
		'border_top' { style_border_top(s.number(arg)!) }
		'border_right' { style_border_right(s.number(arg)!) }
		'border_bottom' { style_border_bottom(s.number(arg)!) }
		'border_left_color' { style_border_left_color(s.color(arg)!) }
		'border_top_color' { style_border_top_color(s.color(arg)!) }
		'border_right_color' { style_border_right_color(s.color(arg)!) }
		'border_bottom_color' { style_border_bottom_color(s.color(arg)!) }
		'border_pattern' {
			style_border_pattern(vml_enum_from(unsafe { BorderPattern(0) }, arg, s)!)
		}
		'dash_length' { style_dash_length(s.number(arg)!) }
		'dash_gap' { style_dash_gap(s.number(arg)!) }
		'outline_color' { style_outline_color(s.color(arg)!) }
		'outline_width' { style_outline_width(s.number(arg)!) }
		'outline_offset' { style_outline_offset(s.number(arg)!) }
		'foreground' { style_foreground(s.color(arg)!) }
		'text_background' { style_text_background(s.color(arg)!) }
		'font_size' { style_font_size(s.number(arg)!) }
		'font_family' { style_font_family(s.text(arg)!) }
		'weight' { style_weight(s.integer(arg)!) }
		'letter_spacing' { style_letter_spacing(s.number(arg)!) }
		'line_height' { style_line_height(s.number(arg)!) }
		'line_height_factor' { style_line_height_factor(s.number(arg)!) }
		'baseline_offset' { style_baseline_offset(s.number(arg)!) }
		'tabular_figures' { style_tabular_figures(s.boolean(arg)!) }
		'italic' { style_italic(s.boolean(arg)!) }
		'underline' { style_underline(s.boolean(arg)!) }
		'strikethrough' { style_strikethrough(s.boolean(arg)!) }
		'shadow' { style_shadow(s.boolean(arg)!) }
		'text_outline' { style_text_outline(s.boolean(arg)!) }
		'vertical_align' { style_vertical_align(s.text(arg)!) }
		'link' { style_link(s.text(arg)!) }
		'text_align' { style_text_align(vml_enum_from(unsafe { Align(0) }, arg, s)!) }
		'text_valign' { style_text_valign(vml_enum_from(unsafe { VAlign(0) }, arg, s)!) }
		'head_indent' { style_head_indent(s.number(arg)!) }
		'first_line_indent' { style_first_line_indent(s.number(arg)!) }
		'hyphenation_factor' { style_hyphenation_factor(s.number(arg)!) }
		'lines' { style_lines(s.integer(arg)!) }
		'padding_left' { style_padding_left(s.number(arg)!) }
		'padding_top' { style_padding_top(s.number(arg)!) }
		'padding_right' { style_padding_right(s.number(arg)!) }
		'padding_bottom' { style_padding_bottom(s.number(arg)!) }
		'padding' { style_padding(s.number(arg)!) }
		'border_width' { style_border_width(s.number(arg)!) }
		else { error('unknown style helper `${name}`') }
	}
}

// vml_motion_call calls a motion helper of ui/motion_patch.v with its
// arguments converted to the kinds vml_motion_helpers lists.
fn vml_motion_call(name string, args []VmlValue) !MotionPatch {
	s := VmlSetter{
		element: 'motion'
		prop:    name
	}
	return match name {
		'fade' { motion_fade(s.number(args[0])!) }
		'slide_x' { motion_slide_x(s.number(args[0])!) }
		'slide_y' { motion_slide_y(s.number(args[0])!) }
		'scale' { motion_scale(s.number(args[0])!) }
		'rotate' { motion_rotate(s.number(args[0])!) }
		'duration' { motion_duration(s.number(args[0])!) }
		'enter_duration' { motion_enter_duration(s.number(args[0])!) }
		'exit_duration' { motion_exit_duration(s.number(args[0])!) }
		'transition' { motion_transition(s.number(args[0])!) }
		'spring' { motion_spring(s.number(args[0])!, s.number(args[1])!) }
		'easing' { motion_easing(vml_enum_from(MotionEasing.linear, args[0], s)!) }
		'layout' { motion_layout(vml_enum_from(MotionLayoutMode.none, args[0], s)!) }
		'reduced' { motion_reduced(s.boolean(args[0])!) }
		'enter' { motion_enter(vml_native[MotionStyle](args[0], s)!) }
		'exit' { motion_exit(vml_native[MotionStyle](args[0], s)!) }
		'timeline' { motion_timeline(vml_native[MotionTimeline](args[0], s)!) }
		'target' { motion_target(s.text(args[0])!, vml_native[MotionTimeline](args[1], s)!) }
		else { error('unknown motion helper `${name}`') }
	}
}

// vml_motion_value composes a motion helper's patch, or a list of them (nested
// lists flatten), into a MotionConfig, as compiled VML's `ui2.motion_compose`
// does. Any other value is left for the property to convert.
fn vml_motion_value(value VmlValue) !VmlValue {
	if value !is []VmlValue && vml_motion_patch(value) == none {
		return value
	}
	mut patches := []MotionPatch{}
	vml_motion_patches(value, mut patches)!
	return VmlValue(VmlObject(vml_model_object[MotionConfig](compose_motion(patches))))
}

// vml_motion_patch_object holds a motion helper's patch until a `motion`
// value composes it. Documents cannot read its fields: reflecting them would
// instantiate field readers for its optional enums, which V cannot generate.
fn vml_motion_patch_object(patch MotionPatch) VmlReflect {
	return VmlReflect{
		type_name: typeof[MotionPatch]().name
		type_idx:  typeof[MotionPatch]().idx
		data:      voidptr(&VmlReflectBox[MotionPatch]{
			value: patch
		})
		text:      vml_reflect_text[MotionPatch]
	}
}

fn vml_motion_patch(value VmlValue) ?MotionPatch {
	if value is VmlObject {
		object := value
		if object is VmlReflect {
			return vml_reflected[MotionPatch](object)
		}
	}
	return none
}

fn vml_motion_patches(value VmlValue, mut patches []MotionPatch) ! {
	if value is []VmlValue {
		for item in value {
			vml_motion_patches(item, mut patches)!
		}
		return
	}
	patches << vml_motion_patch(value) or {
		return error('a motion list expects motion helpers, not ${vml_value_description(value)}')
	}
}

// --------------------------------------------------------------------- refs

// VmlDynRef is an interpreted `ref name Type`: bound to the node of its
// control when that node is built, like VmlRef[T].
@[heap]
struct VmlDynRef {
	name  string
	kind  Kind
	owner &CompiledVmlComponent = unsafe { nil }
mut:
	node &CompiledVmlNode = unsafe { nil }
}

fn (mut ref VmlDynRef) bind(node &CompiledVmlNode) ! {
	ref.owner.require_alive()!
	if node.element().kind != ref.kind {
		return error('VML ref `${ref.name}` expects `${ref.kind}`, got `${node.element().kind}`')
	}
	if ref.node != unsafe { nil } && ref.node != node && ref.node.mounted
		&& !ref.node.component.is_disposed() {
		return error('VML ref `${ref.name}` already refers to a mounted control')
	}
	ref.node = unsafe { node }
}

fn (ref &VmlDynRef) available() bool {
	return !ref.owner.is_disposed() && ref.node != unsafe { nil } && ref.node.mounted
		&& !ref.node.component.is_disposed()
}

fn (ref &VmlDynRef) require_node() !&CompiledVmlNode {
	if !ref.available() {
		return error('VML ref `${ref.name}` is unavailable before mount or after unmount')
	}
	return ref.node
}

fn (ref &VmlDynRef) call(method string, args []VmlValue) !VmlValue {
	match method {
		'is_available' {
			return VmlValue(ref.available())
		}
		'id' {
			return VmlValue(ref.require_node()!.element().id)
		}
		'element' {
			return VmlValue(VmlObject(vml_element_object(ref.require_node()!.element())))
		}
		'focus', 'set_text' {
			node := ref.require_node()!
			id := node.element().id
			if id.len == 0 { return error('a VML ref command requires an explicit authored id') }
			if method == 'focus' {
				node.component.dispatch_command(VmlHostCommand{ kind: .focus, id: id })!
			} else {
				content := args[0]
				if content !is string {
					return error('`set_text` requires a string, not ${vml_value_description(content)}')
				}
				node.component.dispatch_command(VmlHostCommand{
					kind: .set_text
					id:   id
					text: content as string
				})!
			}
			return VmlValue(VmlNone{})
		}
		else {
			return error('a ref has no method `${method}`')
		}
	}
}

// ------------------------------------------------------- state and memos

// vml_interp_state is CompiledVmlComponent.state_factory for interpreted
// values, with value equality for scalars. A reload seeds it with the value
// the previous document held for the same owner and name.
fn (f &VmlFrame) state(mut owner CompiledVmlComponent, name string, initialize fn () !VmlValue) !&Signal[VmlValue] {
	owner.require_alive()!
	key := 'state:' + name
	if value := owner.values[key] {
		if owner.value_types[key] != 'VmlValue' {
			return error('VML state `${name}` changed type')
		}
		return unsafe { &Signal[VmlValue](value) }
	}
	carry_key := owner.namespace + '\n' + name
	mut initial := &VmlInitialValue[VmlValue]{
		value: VmlNone{}
	}
	owner.runtime.untracked(fn [mut initial, initialize] () ! {
		initial.value = initialize()!
	})!
	// A state the previous document held survives while its kind is the
	// same: a changed initializer type starts again.
	if carried := f.run.carry[carry_key] {
		if vml_value_same_kind(carried, initial.value) {
			initial.value = carried
		}
	}
	signal := new_signal(mut owner.scope, initial.value, SignalOptions[VmlValue]{
		name:   name
		equals: vml_value_same
	})!
	owner.values[key] = voidptr(signal)
	owner.value_types[key] = 'VmlValue'
	mut session := f.run
	session.states << VmlStateRecord{
		key:    carry_key
		signal: signal
	}
	return signal
}

fn vml_interp_computed(mut owner CompiledVmlComponent, name string, compute fn () !VmlValue) !&Memo[VmlValue] {
	owner.require_alive()!
	key := 'computed:' + name
	if value := owner.values[key] {
		if owner.value_types[key] != 'VmlValue' {
			return error('VML computed `${name}` changed type')
		}
		return unsafe { &Memo[VmlValue](value) }
	}
	memo := new_memo(mut owner.scope, compute, SignalOptions[VmlValue]{
		name:   name
		equals: vml_value_same
	})!
	owner.values[key] = voidptr(memo)
	owner.value_types[key] = 'VmlValue'
	return memo
}

// ------------------------------------------------------------ declaration

// declare declares a node of the IR under `parent` (none for the document
// root). `key` is the key of an enclosing component invocation.
fn (f &VmlFrame) declare(n &VmlINode, parent ?VmlParent, key ?string) !VmlDynNode {
	return match n.kind {
		.element { f.element(n, parent, key)! }
		.component { f.component(n, parent, key)! }
		.repeater { n.src.error('a Repeater must be the child of a container') }
		.slot { n.src.error('a `Slot` must be the child of an element') }
	}
}

// declare_children declares the children of a container under `parent`.
fn (f &VmlFrame) declare_children(nodes []&VmlINode, parent VmlParent) ! {
	for child in nodes {
		match child.kind {
			.repeater { f.repeater(child, parent)! }
			.slot { f.slot(child, parent)! }
			else { f.declare(child, parent, none)! }
		}
	}
}

// slot declares the content an invocation gives a component's `Slot`: in a
// frame of the invocation's caller, under an owner of its own that the
// receiving component owns (CompiledVmlComponent.slot_child).
fn (f &VmlFrame) slot(n &VmlINode, parent VmlParent) ! {
	if n.children.len == 0 {
		return
	}
	mut home := unsafe { f }
	for home.parent != unsafe { nil } {
		home = home.parent
	}
	caller := home.caller
	if caller == unsafe { nil } {
		return n.src.error('`Slot` is only valid inside a component')
	}
	author := caller.owner
	mut host := f.owner
	mut owner := author.slot_child(mut host, n.path) or { return n.src.wrap_error(err) }
	if n.slot_scope.tokens.len > 0 {
		owner.prepare_theme_tokens(n.slot_scope.tokens)!
	}
	frame := caller.child_frame(owner, n.slot_scope.slots)
	frame.declare_children(n.children, parent)!
}

fn (f &VmlFrame) element(n &VmlINode, parent ?VmlParent, inherited ?string) !VmlDynNode {
	mut frame := unsafe { f }
	// An enclosing invocation's key replaces the element's own.
	mut key := inherited or { '' }
	if key.len == 0 && n.key != unsafe { nil } {
		key = vml_value_text(f.eval(n.key)!)
	}
	mut owner := f.owner
	mut node := n.widget.new_node(mut owner, VmlNodeOptions{
		id:   n.id
		key:  key
		path: n.path
		src:  n.src
	}, parent)!
	if n.id_slot >= 0 {
		frame.cells[n.id_slot].node = node
	}
	for p in n.props {
		f.apply_prop(mut node, p)!
	}
	for event in n.events {
		f.apply_event(mut node, event)!
	}
	for b in n.binds {
		f.apply_bind(mut node, b)!
	}
	if n.ref != unsafe { nil } {
		ref := f.up(n.ref.depth).cells[n.ref.slot].ref
		node.bind_ref(ref)!
	}
	f.declare_children(n.children, node.vml_parent())!
	return node
}

fn (f &VmlFrame) apply_event(mut node VmlDynNode, event VmlIEvent) ! {
	node.set_prop(event.name, VmlValue(VmlCallable{
		name: event.name
		run:  f.event_handler(event)
	}))!
}

// apply_bind connects a bindable property to its target: an effect reads the
// target and the control's edits write it.
fn (f &VmlFrame) apply_bind(mut node VmlDynNode, b VmlIBind) ! {
	frame := unsafe { f }
	target := b.target
	write := b.write
	node.prop_value(b.prop, fn [frame, target] () !VmlValue {
		if vml_ir_uses_app(target) {
			frame.owner.watch_app()!
		}
		return frame.eval(target)!
	})!
	node.bind_value(b.prop, fn [frame, target, write] (value VmlValue) ! {
		current := frame.eval(target) or { VmlValue(VmlNone{}) }
		frame.write(write, vml_bound_value(current, value))!
	})!
}

// vml_bound_value converts a control's value for its binding target:
// a number for an integer target is truncated (ui2.vml_assign), a number
// for a string target is formatted.
fn vml_bound_value(current VmlValue, value VmlValue) VmlValue {
	if current is i64 {
		if value is f64 {
			if math.is_finite(value) { return VmlValue(i64(value)) }
		}
	}
	if current is string && value !is string {
		return VmlValue(vml_value_text(value))
	}
	return value
}

fn (f &VmlFrame) apply_prop(mut node VmlDynNode, p VmlIProp) ! {
	if !p.reactive {
		node.set_prop(p.name, f.prop_value(p)!)!
		return
	}
	frame := unsafe { f }
	node.prop_value(p.name, fn [frame, p] () !VmlValue {
		if p.uses_app {
			frame.owner.watch_app()!
		}
		return frame.prop_value(p)!
	})!
}

fn (f &VmlFrame) prop_value(p VmlIProp) !VmlValue {
	value := f.eval(p.expr)!
	if p.style && value is []VmlValue {
		return VmlValue(vml_style_value(value) or { return p.src.error(err.msg()) })
	}
	if p.motion {
		return vml_motion_value(value) or { return p.src.error(err.msg()) }
	}
	return value
}

// event_handler runs an element's handler with `event` bound.
fn (f &VmlFrame) event_handler(event VmlIEvent) fn (ElementEvent) ! {
	frame := unsafe { f }
	handler := event.handler
	slots := event.scope.slots
	if handler.kind in [.app_method, .fn_ref, .event_ref, .external] {
		// The checker resolved the reference from the handler scope, one
		// level below the element's frame.
		return frame.child_frame(frame.owner, slots).callable(handler)
	}
	return fn [frame, handler, slots] (e ElementEvent) ! {
		mut scope := frame.child_frame(frame.owner, slots)
		scope.cells[0].value = VmlValue(VmlObject(vml_model_object(e)))
		scope.exec(handler)!
	}
}

fn (f &VmlFrame) repeater(n &VmlINode, parent VmlParent) ! {
	frame := unsafe { f }
	r := n.repeat
	src := n.src
	mut host := parent
	vml_repeat[VmlItem, VmlParent](mut host, r.name, fn [frame, r, src] () ![]VmlItem {
		if r.model_uses_app {
			frame.owner.watch_app()!
		}
		value := frame.eval(r.model)!
		if value is []VmlValue {
			mut items := []VmlItem{cap: value.len}
			for item in value {
				items << VmlItem{
					value: item
				}
			}
			return items
		}
		return src.error('a Repeater model must be an array, not ${vml_value_description(value)}')
	}, fn [frame, r, src] (item VmlItem) string {
		mut scope := frame.child_frame(frame.owner, r.key_scope.slots)
		scope.cells[0].value = item.value
		value := scope.eval(r.key) or {
			eprintln(src.wrap_error(err).msg())
			return ''
		}
		return vml_value_text(value)
	}, fn [frame, r] (mut item_owner CompiledVmlComponent, mut segment VmlSegment, item &Signal[VmlItem]) ! {
		if r.item_scope.tokens.len > 0 {
			item_owner.prepare_theme_tokens(r.item_scope.tokens)!
		}
		mut scope := frame.child_frame(item_owner, r.item_scope.slots)
		scope.cells[r.item_slot].item = unsafe { item }
		scope.cells[r.index_slot].index = item_owner.state('@index', 0)!
		scope.declare_children(r.children, segment.vml_parent())!
	}, src)!
}

fn (f &VmlFrame) component(n &VmlINode, parent ?VmlParent, inherited ?string) !VmlDynNode {
	comp := n.comp
	mut caller := unsafe { f }
	mut parent_owner := f.owner
	mut owner := parent_owner.child(comp.owner_name) or { return n.src.wrap_error(err) }
	if comp.scope.tokens.len > 0 {
		owner.prepare_theme_tokens(comp.scope.tokens)!
	}
	mut frame := &VmlFrame{
		run:    f.run
		caller: caller
		owner:  owner
		cells:  []VmlCell{len: comp.scope.slots}
	}
	component_frame := frame
	for input in comp.inputs {
		match input.kind {
			.event {
				frame.cells[input.slot].listener = caller.listener(input)
			}
			.argument, .bound {
				expr := input.expr
				uses_app := input.uses_app
				typ := input.typ
				mut memo := vml_interp_computed(mut owner, '@input:' + input.name, fn [caller, expr, uses_app, typ] () !VmlValue {
					if uses_app {
						caller.owner.watch_app()!
					}
					return vml_coerce(caller.eval(expr)!, typ)
				})!
				mut state := frame.state(mut owner, input.name, fn [mut memo] () !VmlValue {
					return memo.get()!
				})!
				owner.scope.effect('@input:' + input.name, fn [mut memo, mut state] () ! {
					state.set(memo.get()!)!
				})!
				frame.cells[input.slot].signal = state
				if input.kind == .bound {
					write := input.write
					frame.cells[input.slot].setter = fn [caller, write, mut state] (value VmlValue) ! {
						caller.write(write, value)!
						state.set(vml_assign_value(state.peek()!, value))!
					}
				}
			}
			.default_value {
				expr := input.expr
				typ := input.typ
				frame.cells[input.slot].signal = frame.state(mut owner, input.name, fn [component_frame, expr, typ] () !VmlValue {
					return vml_coerce(component_frame.eval(expr)!, typ)
				})!
			}
		}
	}
	for ref in comp.refs {
		frame.cells[ref.slot].ref = &VmlDynRef{
			name:  ref.name
			kind:  ref.kind
			owner: owner
		}
	}
	for data in comp.data {
		expr := data.expr
		if data.computed {
			uses_app := data.uses_app
			frame.cells[data.slot].memo = vml_interp_computed(mut owner, data.name, fn [component_frame, expr, uses_app] () !VmlValue {
				if uses_app {
					component_frame.owner.watch_app()!
				}
				return component_frame.eval(expr)!
			})!
		} else {
			frame.cells[data.slot].signal = frame.state(mut owner, data.name, fn [component_frame, expr] () !VmlValue {
				return component_frame.eval(expr)!
			})!
		}
	}
	if comp.mount != unsafe { nil } {
		action := comp.mount
		owner.on_mount('mount', fn [component_frame, action] () ! {
			component_frame.exec(action)!
		})!
	}
	if comp.unmount != unsafe { nil } {
		action := comp.unmount
		owner.on_unmount('unmount', fn [component_frame, action] () {
			component_frame.exec(action) or { eprintln('ui2 VML unmount failed: ${err}') }
		})!
	}
	if comp.cleanup != unsafe { nil } {
		action := comp.cleanup
		owner.on_cleanup('cleanup', fn [component_frame, action] () {
			component_frame.exec(action) or { eprintln('ui2 VML cleanup failed: ${err}') }
		})!
	}
	// The invocation's own key replaces an enclosing invocation's.
	mut key := inherited
	if comp.key != unsafe { nil } {
		key = vml_value_text(f.eval(comp.key)!)
	}
	mut root := frame.declare(comp.root, parent, key)!
	for p in comp.forward {
		f.apply_prop(mut root, p)!
	}
	for event in comp.events {
		f.apply_event(mut root, event)!
	}
	for b in comp.binds {
		f.apply_bind(mut root, b)!
	}
	if comp.ref != unsafe { nil } {
		ref := f.up(comp.ref.depth).cells[comp.ref.slot].ref
		root.bind_ref(ref)!
	}
	if n.id_slot >= 0 {
		caller.cells[n.id_slot].node = root
	}
	return root
}

// listener is a component event's listener: the caller's handler with the
// payload bound, or nothing.
fn (f &VmlFrame) listener(input VmlIInput) fn ([]VmlValue) ! {
	frame := unsafe { f }
	handler := input.handler
	if handler == unsafe { nil } {
		return fn (args []VmlValue) ! {}
	}
	params := input.params
	slots := input.scope.slots
	match handler.kind {
		.app_method {
			name := handler.name
			return fn [frame, name, params] (args []VmlValue) ! {
				model := frame.run.model
				method := model.schema.methods[name] or { VmlModelMethod{} }
				payload := if method.params.len == 0 { []VmlValue{} } else { args }
				_ = params
				model.call(model.data, name, payload)!
			}
		}
		.fn_ref {
			// References resolve from the listener scope, one level below
			// the caller's frame.
			scope := frame.child_frame(frame.owner, slots)
			return fn [scope, handler] (args []VmlValue) ! {
				payload := if handler.func.params.len == 0 { []VmlValue{} } else { args }
				scope.call_function(handler, payload)!
			}
		}
		.event_ref {
			scope := frame.child_frame(frame.owner, slots)
			return fn [scope, handler] (args []VmlValue) ! {
				listener := scope.up(handler.depth).cells[handler.slot].listener
				if listener != unsafe { nil } { listener(args)! }
			}
		}
		.external {
			callback := frame.external(handler.name)
			return fn [callback] (args []VmlValue) ! {
				if callback != unsafe { nil } { callback(ElementEvent{}) }
			}
		}
		else {
			return fn [frame, handler, params, slots] (args []VmlValue) ! {
				mut scope := frame.child_frame(frame.owner, slots)
				for index, parameter in params {
					if index < args.len {
						scope.cells[index].value = vml_coerce(args[index], parameter.typ)
					}
				}
				scope.exec(handler)!
			}
		}
	}
}

// vml_build declares a program's document and builds it.
fn vml_build(run &VmlSession, frame Rect, config VmlDocumentConfig) !Element {
	mut d := vml_document(frame, config)!
	mut owner := d.owner
	program := run.program
	if program.scope.tokens.len > 0 {
		owner.prepare_theme_tokens(program.scope.tokens) or {
			d.owner.dispose() or {}
			return err
		}
	}
	mut root := &VmlFrame{
		run:   run
		owner: owner
		cells: []VmlCell{len: program.scope.slots}
	}
	root.declare(program.root, none, none) or {
		d.owner.dispose() or {}
		return err
	}
	return d.finish() or {
		d.owner.dispose() or {}
		return err
	}
}

@[heap]
struct VmlElementBox {
	element Element
}

// vml_element_object exposes the resolved element of a ref: its identity,
// content, state and frame. Elements are not reflected as a whole; they hold
// the retained runtime.
fn vml_element_object(element Element) VmlReflect {
	return VmlReflect{
		type_name: 'ui2.Element'
		type_idx:  typeof[Element]().idx
		data:      voidptr(&VmlElementBox{
			element: element
		})
		read:      vml_element_read
	}
}

fn vml_element_read(data voidptr, name string) ?VmlValue {
	el := unsafe { &VmlElementBox(data) }.element
	return match name {
		'id' { VmlValue(el.id) }
		'key' { VmlValue(el.key) }
		'kind' { VmlValue(VmlEnum{ name: el.kind.str() }) }
		'text' { VmlValue(el.text) }
		'placeholder' { VmlValue(el.placeholder) }
		'checked' { VmlValue(el.checked) }
		'value' { VmlValue(el.value) }
		'hidden' { VmlValue(el.hidden) }
		'enabled' { VmlValue(el.enabled) }
		'frame' { VmlValue(VmlObject(vml_reflect(el.frame))) }
		else { none }
	}
}
