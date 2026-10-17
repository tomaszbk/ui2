module ui2

import math

// Model access by reflection for the VML interpreter (design §3.4), compiled
// only with `-d vml_interpreter`. Reads are lazy: `app.x` reads one field of
// the live model when an effect runs, and a struct value becomes a VmlReflect
// whose fields are read on demand. The loader validates every model path,
// write and call against VmlModelType, the schema built once per load from the
// model's type. Only public fields are readable and only `pub mut` top-level
// fields are writable, as compiled VML's guards require; methods are called
// through the signature table of vml_model_call.

// VmlTypeKind classifies a model type for load-time validation.
enum VmlTypeKind {
	dynamic     // known only when the value is read (method results)
	text        // string
	integer     // any integer type
	number      // f32 or f64
	boolean     // bool
	enumeration // an enum
	array       // a dynamic array; `elem` is its element type
	object      // a struct with readable fields
	style       // ui2.StylePatch
	callback    // a function value
	optional    // an option; `elem` is its payload type when known
	unsupported // maps, interfaces, sum types, fixed arrays, voidptr
}

// VmlModelType is the schema of one model type.
@[heap]
struct VmlModelType {
	name string
mut:
	kind        VmlTypeKind
	elem        &VmlModelType = unsafe { nil }
	fields      map[string]VmlModelField
	methods     map[string]VmlModelMethod
	enum_values []string
}

struct VmlModelField {
	name   string
	typ    &VmlModelType = unsafe { nil }
	is_pub bool
	is_mut bool
}

struct VmlModelMethod {
	name      string
	params    []string
	void      bool
	supported bool
}

fn (t &VmlModelType) describe() string {
	return match t.kind {
		.dynamic { 'a value' }
		.text { 'a string' }
		.integer { 'an integer (${t.name})' }
		.number { 'a number (${t.name})' }
		.boolean { 'a bool' }
		.enumeration { 'the enum ${t.name}' }
		.array { 'the array ${t.name}' }
		.object { 'the struct ${t.name}' }
		.style { 'a style' }
		.callback { 'a function' }
		.optional { 'the option ${t.name}' }
		.unsupported { 'the type ${t.name}, which VML cannot read' }
	}
}

// VmlModel is the interpreter's handle on the application model: a typed
// model (`vml_model(&app)`) or a sample object (`vml_sample_model`).
@[heap]
pub struct VmlModel {
pub:
	type_name string
mut:
	data       voidptr
	schema     &VmlModelType = unsafe { nil }
	read       fn (data voidptr, name string) !VmlValue                  = unsafe { nil }
	write      fn (data voidptr, name string, value VmlValue) !          = unsafe { nil }
	call       fn (data voidptr, name string, args []VmlValue) !VmlValue = unsafe { nil }
	call_event fn (data voidptr, name string, event ElementEvent) !      = unsafe { nil }
}

// vml_model wraps a live typed model. Its schema is computed once per type.
pub fn vml_model[T](model &T) &VmlModel {
	return &VmlModel{
		type_name:  typeof[T]().name
		data:       voidptr(model)
		schema:     vml_model_schema[T](model)
		read:       vml_model_read_root[T]
		write:      vml_model_write_root[T]
		call:       vml_model_call_root[T]
		call_event: vml_model_call_event_root[T]
	}
}

@[heap]
struct VmlSchemaCache {
mut:
	types map[string]&VmlModelType
}

const vml_schema_cache = &VmlSchemaCache{}

fn vml_model_schema[T](model &T) &VmlModelType {
	mut cache := unsafe { vml_schema_cache }
	name := typeof[T]().name
	if cached := cache.types[name] {
		if cached.kind != .dynamic { return cached }
	}
	mut seen := map[string]&VmlModelType{}
	mut schema := vml_model_type(*model, mut seen)
	$if T is $struct {
		schema.methods = vml_model_methods[T]()
	}
	cache.types[name] = schema
	return schema
}

// vml_model_type builds the schema of T from a value of T (V cannot pass a
// field's type as a generic argument, so recursion goes through values).
fn vml_model_type[T](value T, mut seen map[string]&VmlModelType) &VmlModelType {
	name := typeof[T]().name
	if existing := seen[name] { return existing }
	mut t := &VmlModelType{
		name: name
	}
	seen[name] = t
	$if T is string {
		t.kind = .text
	} $else $if T is bool {
		t.kind = .boolean
	} $else $if T is $int {
		t.kind = .integer
	} $else $if T is $float {
		t.kind = .number
	} $else $if T is $enum {
		t.kind = .enumeration
		t.enum_values = vml_enum_names(value)
	} $else $if T is StylePatch {
		t.kind = .style
	} $else $if T is $array_fixed {
		t.kind = .unsupported
	} $else $if T is $array {
		t.kind = .array
		t.elem = vml_model_elem_type(value, mut seen)
	} $else $if T is voidptr {
		t.kind = .unsupported
	} $else $if T is $pointer {
		return vml_model_pointer_type(value, mut seen)
	} $else $if T is $option {
		t.kind = .optional
	} $else $if T is $function {
		t.kind = .callback
	} $else $if T is $interface {
		t.kind = .unsupported
	} $else $if T is $sumtype {
		t.kind = .unsupported
	} $else $if T is $map {
		t.kind = .unsupported
	} $else $if T is $struct {
		t.kind = .object
		$for field in T.fields {
			// Only public fields are reflected (the rule compiled VML enforces),
			// which also keeps a model's private machinery out of the build.
			$if field.is_pub {
				mut field_type := &VmlModelType(unsafe { nil })
				$if field.is_option {
					field_type = vml_model_option_type(value.$(field.name), mut seen)
				} $else {
					field_type = vml_model_type(value.$(field.name), mut seen)
				}
				t.fields[field.name] = VmlModelField{
					name:   field.name
					typ:    field_type
					is_pub: true
					is_mut: field.is_mut
				}
			} $else {
				t.fields[field.name] = VmlModelField{
					name: field.name
					typ:  &VmlModelType{
						name: 'private'
						kind: .unsupported
					}
				}
			}
		}
	} $else {
		t.kind = .unsupported
	}
	return t
}

fn vml_model_elem_type[E](_ []E, mut seen map[string]&VmlModelType) &VmlModelType {
	$if E is $interface || E is $sumtype || E is voidptr {
		return &VmlModelType{
			name: typeof[E]().name
			kind: .unsupported
		}
	} $else {
		probe := []E{len: 1}
		return vml_model_type(probe[0], mut seen)
	}
}

fn vml_model_pointer_type[E](_ &E, mut seen map[string]&VmlModelType) &VmlModelType {
	$if E is $interface || E is $sumtype || E is voidptr || E is $pointer {
		return &VmlModelType{
			name: typeof[E]().name
			kind: .unsupported
		}
	} $else {
		probe := []E{len: 1}
		return vml_model_type(probe[0], mut seen)
	}
}

// The payload types of the options VML reads; V cannot name the payload of a
// generic option.
fn vml_model_option_type[O](value O, mut seen map[string]&VmlModelType) &VmlModelType {
	name := typeof[O]().name
	if existing := seen[name] { return existing }
	mut t := &VmlModelType{
		name: name
		kind: .optional
	}
	seen[name] = t
	$if O is ?int || O is ?i64 || O is ?u32 {
		t.elem = &VmlModelType{
			name: name.trim_left('?')
			kind: .integer
		}
	} $else $if O is ?f64 {
		t.elem = &VmlModelType{
			name: 'f64'
			kind: .number
		}
	} $else $if O is ?string {
		t.elem = &VmlModelType{
			name: 'string'
			kind: .text
		}
	} $else $if O is ?bool {
		t.elem = &VmlModelType{
			name: 'bool'
			kind: .boolean
		}
	} $else $if O is ?OverlayPoint {
		t.elem = vml_model_type(OverlayPoint{}, mut seen)
	} $else $if O is ?MotionConfig {
		t.elem = vml_model_type(MotionConfig{}, mut seen)
	} $else $if O is ?OverlayConfig {
		t.elem = vml_model_type(OverlayConfig{}, mut seen)
	}
	_ = value
	return t
}

// ------------------------------------------------------------------- reads

fn vml_model_read_root[T](data voidptr, name string) !VmlValue {
	model := unsafe { &T(data) }
	return vml_model_field(model, name)
}

// vml_model_field reads a public field of a struct.
fn vml_model_field[T](value &T, name string) !VmlValue {
	$if T is $struct {
		$for field in T.fields {
			if field.name == name {
				$if field.is_pub {
					$if field.is_option {
						return vml_model_option(value.$(field.name))
					} $else {
						return vml_model_value(value.$(field.name))!
					}
				} $else {
					return error('field `${name}` of ${typeof[T]().name} is not public')
				}
			}
		}
	}
	return error('${typeof[T]().name} has no field `${name}`')
}

// vml_model_value converts a model value to a VmlValue. Structs stay lazy.
fn vml_model_value[T](value T) !VmlValue {
	$if T is string {
		return VmlValue(value)
	} $else $if T is bool {
		return VmlValue(value)
	} $else $if T is $int {
		return VmlValue(i64(value))
	} $else $if T is $float {
		return VmlValue(f64(value))
	} $else $if T is $enum {
		return VmlValue(VmlEnum{
			name: vml_enum_name(value)
		})
	} $else $if T is StylePatch {
		return VmlValue(value)
	} $else $if T is ElementCallback {
		return vml_callback_value(value)
	} $else $if T is $function {
		return error('VML cannot read the function ${typeof[T]().name}')
	} $else $if T is $array_fixed {
		return error('VML cannot read the fixed array ${typeof[T]().name}')
	} $else $if T is $array {
		return vml_model_array(value)!
	} $else $if T is voidptr {
		return error('VML cannot read a voidptr')
	} $else $if T is $pointer {
		if value == unsafe { nil } { return error('the reference ${typeof[T]().name} is nil') }
		return vml_model_deref(value)!
	} $else $if T is $interface {
		return error('VML cannot read the interface ${typeof[T]().name}')
	} $else $if T is $sumtype {
		return error('VML cannot read the sum type ${typeof[T]().name}')
	} $else $if T is $map {
		return error('VML cannot read the map ${typeof[T]().name}')
	} $else $if T is $struct {
		return VmlValue(VmlObject(vml_model_object(value)))
	} $else {
		return error('VML cannot read ${typeof[T]().name}')
	}
}

fn vml_model_deref[E](value &E) !VmlValue {
	$if E is $interface || E is $sumtype || E is voidptr || E is $pointer {
		return error('VML cannot read ${typeof[E]().name}')
	} $else $if E is $struct {
		// A reference stays a reference: the object reads the live value.
		return VmlValue(VmlObject(vml_model_ref_object(value)))
	} $else {
		return vml_model_value(*value)!
	}
}

fn vml_model_array[E](values []E) !VmlValue {
	mut out := []VmlValue{cap: values.len}
	for item in values {
		out << vml_model_value(item)!
	}
	return VmlValue(out)
}

fn vml_model_option[O](value O) !VmlValue {
	$if O is ?int {
		if v := value { return VmlValue(i64(v)) }
	} $else $if O is ?i64 {
		if v := value { return VmlValue(v) }
	} $else $if O is ?u32 {
		if v := value { return VmlValue(i64(v)) }
	} $else $if O is ?f64 {
		if v := value { return VmlValue(v) }
	} $else $if O is ?string {
		if v := value { return VmlValue(v) }
	} $else $if O is ?bool {
		if v := value { return VmlValue(v) }
	} $else $if O is ?OverlayPoint {
		// The payload type is named: inferred from `v`, it would be the option.
		if v := value { return VmlValue(VmlObject(vml_model_object[OverlayPoint](v))) }
	} $else $if O is ?MotionConfig {
		if v := value { return VmlValue(VmlObject(vml_model_object[MotionConfig](v))) }
	} $else $if O is ?OverlayConfig {
		if v := value { return VmlValue(VmlObject(vml_model_object[OverlayConfig](v))) }
	} $else {
		return error('VML cannot read the option ${typeof[O]().name}')
	}
	return VmlValue(VmlNone{})
}

// vml_model_object holds a copy of a struct value: an array element or a
// nested struct read from the model.
fn vml_model_object[T](value T) VmlReflect {
	return VmlReflect{
		type_name: typeof[T]().name
		type_idx:  typeof[T]().idx
		data:      voidptr(&VmlReflectBox[T]{
			value: value
		})
		read:      vml_model_read_boxed[T]
		text:      vml_reflect_text[T]
		same:      vml_model_same[T]
	}
}

// vml_model_ref_object reads a struct through a model reference, so it
// sees the referenced value as it is when read.
fn vml_model_ref_object[T](value &T) VmlReflect {
	return VmlReflect{
		type_name: typeof[T]().name
		type_idx:  typeof[T]().idx
		data:      voidptr(&VmlReflectRef[T]{
			value: unsafe { value }
		})
		read:      vml_model_read_ref[T]
		text:      vml_reflect_text[T]
		same:      vml_model_same_ref[T]
	}
}

@[heap]
struct VmlReflectRef[T] {
	value &T = unsafe { nil }
}

fn vml_model_read_ref[T](data voidptr, name string) ?VmlValue {
	boxed := unsafe { &VmlReflectRef[T](data) }
	return vml_model_field(boxed.value, name) or { return none }
}

fn vml_model_same_ref[T](data voidptr, other voidptr) bool {
	a := unsafe { &VmlReflectRef[T](data) }
	b := unsafe { &VmlReflectRef[T](other) }
	return a.value == b.value || *a.value == *b.value
}

// vml_model_same compares two model values as V's `==` does, which is how
// compiled keyed lists compare their items.
fn vml_model_same[T](data voidptr, other voidptr) bool {
	a := unsafe { &VmlReflectBox[T](data) }
	b := unsafe { &VmlReflectBox[T](other) }
	return a.value == b.value
}

fn vml_model_read_boxed[T](data voidptr, name string) ?VmlValue {
	boxed := unsafe { &VmlReflectBox[T](data) }
	return vml_model_field(&boxed.value, name) or { return none }
}

// ------------------------------------------------------------------ writes

fn vml_model_write_root[T](data voidptr, name string, value VmlValue) ! {
	mut model := unsafe { &T(data) }
	$if T is $struct {
		$for field in T.fields {
			if field.name == name {
				if !field.is_pub || !field.is_mut {
					return error('VML target `app.${name}` must be public and mutable')
				}
				what := 'app.${name}'
				$if field.is_option {
					$if field.typ is ?int {
						model.$(field.name) = if value is VmlNone {
							?int(none)
						} else {
							?int(vml_model_convert(0, value, what)!)
						}
					} $else $if field.typ is ?f64 {
						model.$(field.name) = if value is VmlNone {
							?f64(none)
						} else {
							?f64(vml_model_convert(0.0, value, what)!)
						}
					} $else $if field.typ is ?string {
						model.$(field.name) = if value is VmlNone {
							?string(none)
						} else {
							?string(vml_model_convert('', value, what)!)
						}
					} $else $if field.typ is ?bool {
						model.$(field.name) = if value is VmlNone {
							?bool(none)
						} else {
							?bool(vml_model_convert(false, value, what)!)
						}
					} $else $if field.typ is ?OverlayPoint {
						model.$(field.name) = if value is VmlNone {
							?OverlayPoint(none)
						} else {
							?OverlayPoint(vml_model_convert(OverlayPoint{}, value, what)!)
						}
					} $else {
						return error('VML cannot assign the option `${what}`')
					}
				} $else {
					model.$(field.name) = vml_model_convert(model.$(field.name), value, what)!
				}
				return
			}
		}
	}
	return error('the model has no field `${name}`')
}

// vml_model_convert converts a VmlValue to the type of `current`, with V's
// assignment rules: integers widen to floats, a float assigns to an integer
// only when it is integral, enums take their names.
fn vml_model_convert[F](current F, value VmlValue, what string) !F {
	$if F is string {
		if value is string { return value }
	} $else $if F is bool {
		if value is bool { return value }
	} $else $if F is $int {
		match value {
			i64 {
				return F(value)
			}
			f64 {
				if math.is_finite(value) && value == math.trunc(value) { return F(i64(value)) }
			}
			else {}
		}
	} $else $if F is $float {
		match value {
			i64 { return F(value) }
			f64 { return F(value) }
			else {}
		}
	} $else $if F is $enum {
		name := match value {
			VmlEnum { value.name }
			string { value }
			else { '' }
		}
		if name.len > 0 {
			$for item in F.values {
				if item.name == name { return item.value }
			}
			return error('${what} has no value `${name}`; valid values: ${vml_enum_names(current).join(', ')}')
		}
	} $else $if F is StylePatch {
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
						return error('${what} expects styles, not ${vml_value_description(item)}')
					}
				}
				return compose_styles(patches)
			}
			else {}
		}
	} $else $if F is $array_fixed {
		return error('VML cannot assign the fixed array ${what}')
	} $else $if F is $array {
		return vml_model_array_convert(current, value, what)!
	} $else $if F is $interface || F is $sumtype || F is $map || F is $pointer || F is $function {
		return error('VML cannot assign ${what} of type ${typeof[F]().name}')
	} $else $if F is $struct {
		if value is VmlObject {
			object := value
			if object is VmlReflect {
				if held := vml_reflected[F](object) { return held }
			}
		}
	}
	return error('${what} expects ${typeof[F]().name}, not ${vml_value_description(value)}')
}

fn vml_model_array_convert[E](current []E, value VmlValue, what string) ![]E {
	_ = current
	$if E is $interface || E is $sumtype || E is voidptr {
		return error('VML cannot assign ${what} of type ${typeof[[]E]().name}')
	} $else {
		if value is []VmlValue {
			probe := []E{len: 1}
			mut out := []E{cap: value.len}
			for index, item in value {
				out << vml_model_convert(probe[0], item, '${what}[${index}]')!
			}
			return out
		}
		return error('${what} expects ${typeof[[]E]().name}, not ${vml_value_description(value)}')
	}
}

// ------------------------------------------------------------------- calls

fn vml_model_call_root[T](data voidptr, name string, args []VmlValue) !VmlValue {
	$if T is $struct {
		mut model := unsafe { &T(data) }
		return vml_model_call(mut model, name, args)!
	} $else {
		return error('the model has no method `${name}`')
	}
}

// vml_model_call_event_root calls a method referenced as an event callback:
// `fn ()` or `fn (ui2.ElementEvent)`, like ui2.vml_callback.
fn vml_model_call_event_root[T](data voidptr, name string, event ElementEvent) ! {
	$if T is $struct {
		mut model := unsafe { &T(data) }
		$for method in T.methods {
			if method.name == name {
				$if method.args.len == 0 {
					$if method.return_type is $option {
					} $else {
						model.$method()
						return
					}
				} $else $if method.args.len == 1 {
					$if method.args[0].typ is ElementEvent {
						$if method.return_type is $option {
						} $else {
							model.$method(event)
							return
						}
					}
				}
				return error('callback `app.${name}` requires fn () or fn (ui2.ElementEvent)')
			}
		}
	}
	return error('the model has no method `${name}`')
}

fn vml_model_arity(name string, args []VmlValue, count int) ! {
	if args.len != count {
		return error('`app.${name}` takes ${count} argument(s), not ${args.len}')
	}
}

fn vml_model_unsupported(name string) !VmlValue {
	return error('`app.${name}` has a signature VML cannot call; the interpreter calls methods taking no argument, one int, i64, f64, string, bool or ui2.ElementEvent, or two of int, f64, string and bool, and not returning an option')
}

fn vml_arg_error(name string, index int, expected string, value VmlValue) IError {
	return error('argument ${index + 1} of `app.${name}` expects ${expected}, not ${vml_value_description(value)}')
}

fn vml_arg_i64(value VmlValue, name string, index int) !i64 {
	match value {
		i64 {
			return value
		}
		f64 {
			if math.is_finite(value) && value == math.trunc(value) { return i64(value) }
		}
		else {}
	}
	return vml_arg_error(name, index, 'an integer', value)
}

fn vml_arg_int(value VmlValue, name string, index int) !int {
	whole := vml_arg_i64(value, name, index)!
	if whole < i64(min_i32) || whole > i64(max_i32) {
		return vml_arg_error(name, index, 'an int', value)
	}
	return int(whole)
}

fn vml_arg_f64(value VmlValue, name string, index int) !f64 {
	return match value {
		i64 { f64(value) }
		f64 { value }
		else { vml_arg_error(name, index, 'a number', value) }
	}
}

fn vml_arg_string(value VmlValue, name string, index int) !string {
	return match value {
		string { value }
		else { vml_arg_error(name, index, 'a string', value) }
	}
}

fn vml_arg_bool(value VmlValue, name string, index int) !bool {
	return match value {
		bool { value }
		else { vml_arg_error(name, index, 'a bool', value) }
	}
}

fn vml_arg_event(value VmlValue, name string, index int) !ElementEvent {
	if value is VmlObject {
		object := value
		if object is VmlReflect {
			if event := vml_reflected[ElementEvent](object) { return event }
		}
	}
	return vml_arg_error(name, index, 'a ui2.ElementEvent', value)
}

// ------------------------------------------------------------ sample model

@[heap]
struct VmlSampleData {
mut:
	fields map[string]VmlValue
	calls  []string
	on     ?fn (name string, args []VmlValue)
}

// vml_sample_model is a model without a V type, for previews: `app.x` reads
// the sample value `x`, assignments replace it, and method calls are recorded
// (and reported to `on_call`), returning nothing.
pub fn vml_sample_model(fields map[string]VmlValue, on_call ?fn (name string, args []VmlValue)) &VmlModel {
	mut schema := &VmlModelType{
		name: 'sample'
		kind: .object
	}
	for name, value in fields {
		schema.fields[name] = VmlModelField{
			name:   name
			typ:    vml_value_type(value)
			is_pub: true
			is_mut: true
		}
	}
	data := &VmlSampleData{
		fields: fields.clone()
		on:     on_call
	}
	return &VmlModel{
		type_name:  'sample'
		data:       voidptr(data)
		schema:     schema
		read:       vml_sample_read
		write:      vml_sample_write
		call:       vml_sample_call
		call_event: vml_sample_call_event
	}
}

fn vml_value_type(value VmlValue) &VmlModelType {
	return match value {
		string {
			&VmlModelType{
				name: 'string'
				kind: .text
			}
		}
		i64 {
			&VmlModelType{
				name: 'int'
				kind: .integer
			}
		}
		f64 {
			&VmlModelType{
				name: 'f64'
				kind: .number
			}
		}
		bool {
			&VmlModelType{
				name: 'bool'
				kind: .boolean
			}
		}
		StylePatch {
			&VmlModelType{
				name: 'ui2.StylePatch'
				kind: .style
			}
		}
		else {
			&VmlModelType{
				name: 'value'
				kind: .dynamic
			}
		}
	}
}

fn vml_sample_read(data voidptr, name string) !VmlValue {
	sample := unsafe { &VmlSampleData(data) }
	return sample.fields[name] or { error('the sample model has no field `${name}`') }
}

fn vml_sample_write(data voidptr, name string, value VmlValue) ! {
	mut sample := unsafe { &VmlSampleData(data) }
	sample.fields[name] = value
}

fn vml_sample_call(data voidptr, name string, args []VmlValue) !VmlValue {
	mut sample := unsafe { &VmlSampleData(data) }
	sample.calls << name
	if on := sample.on { on(name, args) }
	return VmlValue(VmlNone{})
}

fn vml_sample_call_event(data voidptr, name string, event ElementEvent) ! {
	vml_sample_call(data, name, [VmlValue(VmlObject(vml_model_object(event)))])!
}

// vml_model_call calls `name` with converted arguments: the signature table of
// design §3.4 (no parameter, one of int, i64, f64, string, bool or
// ui2.ElementEvent, or two of int, f64, string and bool). A void method
// returns VmlNone. Generated by the table in the comment above; keep the
// branches in step with vml_model_methods.
fn vml_model_call[T](mut model T, name string, args []VmlValue) !VmlValue {
	$for method in T.methods {
		if method.name == name {
			$if method.args.len == 0 {
				vml_model_arity(name, args, 0)!
				$if method.return_type is void {
					model.$method()
					return VmlValue(VmlNone{})
				} $else $if method.return_type is $option {
					return vml_model_unsupported(name)
				} $else {
					result := model.$method()
					return vml_model_value(result)!
				}
			} $else $if method.args.len == 1 {
				vml_model_arity(name, args, 1)!
				$if method.args[0].typ is int {
					$if method.return_type is void {
						model.$method(vml_arg_int(args[0], name, 0)!)
						return VmlValue(VmlNone{})
					} $else $if method.return_type is $option {
						return vml_model_unsupported(name)
					} $else {
						result := model.$method(vml_arg_int(args[0], name, 0)!)
						return vml_model_value(result)!
					}
				} $else $if method.args[0].typ is i64 {
					$if method.return_type is void {
						model.$method(vml_arg_i64(args[0], name, 0)!)
						return VmlValue(VmlNone{})
					} $else $if method.return_type is $option {
						return vml_model_unsupported(name)
					} $else {
						result := model.$method(vml_arg_i64(args[0], name, 0)!)
						return vml_model_value(result)!
					}
				} $else $if method.args[0].typ is f64 {
					$if method.return_type is void {
						model.$method(vml_arg_f64(args[0], name, 0)!)
						return VmlValue(VmlNone{})
					} $else $if method.return_type is $option {
						return vml_model_unsupported(name)
					} $else {
						result := model.$method(vml_arg_f64(args[0], name, 0)!)
						return vml_model_value(result)!
					}
				} $else $if method.args[0].typ is string {
					$if method.return_type is void {
						model.$method(vml_arg_string(args[0], name, 0)!)
						return VmlValue(VmlNone{})
					} $else $if method.return_type is $option {
						return vml_model_unsupported(name)
					} $else {
						result := model.$method(vml_arg_string(args[0], name, 0)!)
						return vml_model_value(result)!
					}
				} $else $if method.args[0].typ is bool {
					$if method.return_type is void {
						model.$method(vml_arg_bool(args[0], name, 0)!)
						return VmlValue(VmlNone{})
					} $else $if method.return_type is $option {
						return vml_model_unsupported(name)
					} $else {
						result := model.$method(vml_arg_bool(args[0], name, 0)!)
						return vml_model_value(result)!
					}
				} $else $if method.args[0].typ is ElementEvent {
					$if method.return_type is void {
						model.$method(vml_arg_event(args[0], name, 0)!)
						return VmlValue(VmlNone{})
					} $else $if method.return_type is $option {
						return vml_model_unsupported(name)
					} $else {
						result := model.$method(vml_arg_event(args[0], name, 0)!)
						return vml_model_value(result)!
					}
				}
			} $else $if method.args.len == 2 {
				vml_model_arity(name, args, 2)!
				$if method.args[0].typ is int && method.args[1].typ is int {
					$if method.return_type is void {
						model.$method(vml_arg_int(args[0], name, 0)!, vml_arg_int(args[1], name, 1)!)
						return VmlValue(VmlNone{})
					} $else $if method.return_type is $option {
						return vml_model_unsupported(name)
					} $else {
						result := model.$method(vml_arg_int(args[0], name, 0)!, vml_arg_int(args[1], name, 1)!)
						return vml_model_value(result)!
					}
				} $else $if method.args[0].typ is int && method.args[1].typ is f64 {
					$if method.return_type is void {
						model.$method(vml_arg_int(args[0], name, 0)!, vml_arg_f64(args[1], name, 1)!)
						return VmlValue(VmlNone{})
					} $else $if method.return_type is $option {
						return vml_model_unsupported(name)
					} $else {
						result := model.$method(vml_arg_int(args[0], name, 0)!, vml_arg_f64(args[1], name, 1)!)
						return vml_model_value(result)!
					}
				} $else $if method.args[0].typ is int && method.args[1].typ is string {
					$if method.return_type is void {
						model.$method(vml_arg_int(args[0], name, 0)!, vml_arg_string(args[1], name, 1)!)
						return VmlValue(VmlNone{})
					} $else $if method.return_type is $option {
						return vml_model_unsupported(name)
					} $else {
						result := model.$method(vml_arg_int(args[0], name, 0)!, vml_arg_string(args[1], name, 1)!)
						return vml_model_value(result)!
					}
				} $else $if method.args[0].typ is int && method.args[1].typ is bool {
					$if method.return_type is void {
						model.$method(vml_arg_int(args[0], name, 0)!, vml_arg_bool(args[1], name, 1)!)
						return VmlValue(VmlNone{})
					} $else $if method.return_type is $option {
						return vml_model_unsupported(name)
					} $else {
						result := model.$method(vml_arg_int(args[0], name, 0)!, vml_arg_bool(args[1], name, 1)!)
						return vml_model_value(result)!
					}
				} $else $if method.args[0].typ is f64 && method.args[1].typ is int {
					$if method.return_type is void {
						model.$method(vml_arg_f64(args[0], name, 0)!, vml_arg_int(args[1], name, 1)!)
						return VmlValue(VmlNone{})
					} $else $if method.return_type is $option {
						return vml_model_unsupported(name)
					} $else {
						result := model.$method(vml_arg_f64(args[0], name, 0)!, vml_arg_int(args[1], name, 1)!)
						return vml_model_value(result)!
					}
				} $else $if method.args[0].typ is f64 && method.args[1].typ is f64 {
					$if method.return_type is void {
						model.$method(vml_arg_f64(args[0], name, 0)!, vml_arg_f64(args[1], name, 1)!)
						return VmlValue(VmlNone{})
					} $else $if method.return_type is $option {
						return vml_model_unsupported(name)
					} $else {
						result := model.$method(vml_arg_f64(args[0], name, 0)!, vml_arg_f64(args[1], name, 1)!)
						return vml_model_value(result)!
					}
				} $else $if method.args[0].typ is f64 && method.args[1].typ is string {
					$if method.return_type is void {
						model.$method(vml_arg_f64(args[0], name, 0)!, vml_arg_string(args[1], name, 1)!)
						return VmlValue(VmlNone{})
					} $else $if method.return_type is $option {
						return vml_model_unsupported(name)
					} $else {
						result := model.$method(vml_arg_f64(args[0], name, 0)!, vml_arg_string(args[1], name, 1)!)
						return vml_model_value(result)!
					}
				} $else $if method.args[0].typ is f64 && method.args[1].typ is bool {
					$if method.return_type is void {
						model.$method(vml_arg_f64(args[0], name, 0)!, vml_arg_bool(args[1], name, 1)!)
						return VmlValue(VmlNone{})
					} $else $if method.return_type is $option {
						return vml_model_unsupported(name)
					} $else {
						result := model.$method(vml_arg_f64(args[0], name, 0)!, vml_arg_bool(args[1], name, 1)!)
						return vml_model_value(result)!
					}
				} $else $if method.args[0].typ is string && method.args[1].typ is int {
					$if method.return_type is void {
						model.$method(vml_arg_string(args[0], name, 0)!, vml_arg_int(args[1], name, 1)!)
						return VmlValue(VmlNone{})
					} $else $if method.return_type is $option {
						return vml_model_unsupported(name)
					} $else {
						result := model.$method(vml_arg_string(args[0], name, 0)!, vml_arg_int(args[1], name, 1)!)
						return vml_model_value(result)!
					}
				} $else $if method.args[0].typ is string && method.args[1].typ is f64 {
					$if method.return_type is void {
						model.$method(vml_arg_string(args[0], name, 0)!, vml_arg_f64(args[1], name, 1)!)
						return VmlValue(VmlNone{})
					} $else $if method.return_type is $option {
						return vml_model_unsupported(name)
					} $else {
						result := model.$method(vml_arg_string(args[0], name, 0)!, vml_arg_f64(args[1], name, 1)!)
						return vml_model_value(result)!
					}
				} $else $if method.args[0].typ is string && method.args[1].typ is string {
					$if method.return_type is void {
						model.$method(vml_arg_string(args[0], name, 0)!, vml_arg_string(args[1], name, 1)!)
						return VmlValue(VmlNone{})
					} $else $if method.return_type is $option {
						return vml_model_unsupported(name)
					} $else {
						result := model.$method(vml_arg_string(args[0], name, 0)!, vml_arg_string(args[1], name, 1)!)
						return vml_model_value(result)!
					}
				} $else $if method.args[0].typ is string && method.args[1].typ is bool {
					$if method.return_type is void {
						model.$method(vml_arg_string(args[0], name, 0)!, vml_arg_bool(args[1], name, 1)!)
						return VmlValue(VmlNone{})
					} $else $if method.return_type is $option {
						return vml_model_unsupported(name)
					} $else {
						result := model.$method(vml_arg_string(args[0], name, 0)!, vml_arg_bool(args[1], name, 1)!)
						return vml_model_value(result)!
					}
				} $else $if method.args[0].typ is bool && method.args[1].typ is int {
					$if method.return_type is void {
						model.$method(vml_arg_bool(args[0], name, 0)!, vml_arg_int(args[1], name, 1)!)
						return VmlValue(VmlNone{})
					} $else $if method.return_type is $option {
						return vml_model_unsupported(name)
					} $else {
						result := model.$method(vml_arg_bool(args[0], name, 0)!, vml_arg_int(args[1], name, 1)!)
						return vml_model_value(result)!
					}
				} $else $if method.args[0].typ is bool && method.args[1].typ is f64 {
					$if method.return_type is void {
						model.$method(vml_arg_bool(args[0], name, 0)!, vml_arg_f64(args[1], name, 1)!)
						return VmlValue(VmlNone{})
					} $else $if method.return_type is $option {
						return vml_model_unsupported(name)
					} $else {
						result := model.$method(vml_arg_bool(args[0], name, 0)!, vml_arg_f64(args[1], name, 1)!)
						return vml_model_value(result)!
					}
				} $else $if method.args[0].typ is bool && method.args[1].typ is string {
					$if method.return_type is void {
						model.$method(vml_arg_bool(args[0], name, 0)!, vml_arg_string(args[1], name, 1)!)
						return VmlValue(VmlNone{})
					} $else $if method.return_type is $option {
						return vml_model_unsupported(name)
					} $else {
						result := model.$method(vml_arg_bool(args[0], name, 0)!, vml_arg_string(args[1], name, 1)!)
						return vml_model_value(result)!
					}
				} $else $if method.args[0].typ is bool && method.args[1].typ is bool {
					$if method.return_type is void {
						model.$method(vml_arg_bool(args[0], name, 0)!, vml_arg_bool(args[1], name, 1)!)
						return VmlValue(VmlNone{})
					} $else $if method.return_type is $option {
						return vml_model_unsupported(name)
					} $else {
						result := model.$method(vml_arg_bool(args[0], name, 0)!, vml_arg_bool(args[1], name, 1)!)
						return vml_model_value(result)!
					}
				}
			}
			return vml_model_unsupported(name)
		}
	}
	return error('the model has no method `${name}`')
}

// vml_model_methods describes the methods of T: their parameter types as far
// as the signature table knows them (`?` for any other type).
fn vml_model_methods[T]() map[string]VmlModelMethod {
	mut methods := map[string]VmlModelMethod{}
	$for method in T.methods {
		mut params := []string{}
		$if method.args.len == 1 {
			$if method.args[0].typ is int {
				params << 'int'
			} $else $if method.args[0].typ is i64 {
				params << 'i64'
			} $else $if method.args[0].typ is f64 {
				params << 'f64'
			} $else $if method.args[0].typ is string {
				params << 'string'
			} $else $if method.args[0].typ is bool {
				params << 'bool'
			} $else $if method.args[0].typ is ElementEvent {
				params << 'ElementEvent'
			} $else {
				params << '?'
			}
		} $else $if method.args.len == 2 {
			$if method.args[0].typ is int {
				params << 'int'
			} $else $if method.args[0].typ is f64 {
				params << 'f64'
			} $else $if method.args[0].typ is string {
				params << 'string'
			} $else $if method.args[0].typ is bool {
				params << 'bool'
			} $else {
				params << '?'
			}
			$if method.args[1].typ is int {
				params << 'int'
			} $else $if method.args[1].typ is f64 {
				params << 'f64'
			} $else $if method.args[1].typ is string {
				params << 'string'
			} $else $if method.args[1].typ is bool {
				params << 'bool'
			} $else {
				params << '?'
			}
		} $else {
			for _ in 0 .. method.args.len {
				params << '?'
			}
		}
		mut void := false
		mut optional := false
		$if method.return_type is void {
			void = true
		} $else $if method.return_type is $option {
			optional = true
		}
		methods[method.name] = VmlModelMethod{
			name:      method.name
			params:    params
			void:      void
			supported: !optional && '?' !in params
		}
	}
	return methods
}

fn vml_callback_value(callback ElementCallback) VmlValue {
	if callback == unsafe { nil } {
		return VmlNone{}
	}
	return VmlCallable{
		name: 'callback'
		run:  fn [callback] (event ElementEvent) ! {
			callback(event)
		}
	}
}
