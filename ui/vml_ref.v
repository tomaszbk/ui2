module ui2

// Marker types describe the control referred to by a declaration. They are
// type parameters, not values in a component's state or binding snapshots.
pub struct VmlButton {}

pub struct VmlView {}

pub struct VmlLabel {}

pub struct VmlImage {}

pub struct VmlTextField {}

pub struct VmlTextArea {}

pub struct VmlTextInput {}

pub struct VmlScroll {}

pub struct VmlCheckbox {}

pub struct VmlDropdown {}

pub struct VmlSlider {}

pub struct VmlSwitch {}

pub struct VmlToggleButton {}

@[heap]
pub struct VmlRef[T] {
	owner &CompiledVmlComponent
mut:
	node &CompiledVmlNode = unsafe { nil }
}

fn vml_ref_kind[T]() Kind {
	$if T is VmlButton {
		return .button
	} $else $if T is VmlView {
		return .view
	} $else $if T is VmlLabel {
		return .label
	} $else $if T is VmlImage {
		return .image
	} $else $if T is VmlTextField {
		return .text_field
	} $else $if T is VmlTextArea {
		return .text_area
	} $else $if T is VmlTextInput {
		return .text_field
	} $else $if T is VmlScroll {
		return .scroll
	} $else $if T is VmlCheckbox {
		return .checkbox
	} $else $if T is VmlDropdown {
		return .dropdown
	} $else $if T is VmlSlider {
		return .slider
	} $else $if T is VmlSwitch {
		return .switch_control
	} $else $if T is VmlToggleButton {
		return .toggle_button
	} $else {
		$compile_error('VML refs require a control marker type')
	}
}

pub fn (mut component CompiledVmlComponent) ref[T](name string) !&VmlRef[T] {
	component.require_alive()!
	key := 'ref:' + name
	if value := component.values[key] {
		if component.value_types[key] != T.name {
			return error('compiled VML ref `${name}` changed type')
		}
		return unsafe { &VmlRef[T](value) }
	}
	_ = vml_ref_kind[T]()
	ref := &VmlRef[T]{ owner: &component }
	component.values[key] = voidptr(ref)
	component.value_types[key] = T.name
	return ref
}

pub fn (mut ref VmlRef[T]) bind(node &CompiledVmlNode) ! {
	ref.owner.require_alive()!
	valid := $if T is VmlTextInput { node.element().kind in [.text_field, .text_area] } $else { node.element().kind == vml_ref_kind[T]() }
	if !valid {
		return error('compiled VML ref expects `${vml_ref_kind[T]()}`, got `${node.element().kind}`')
	}
	if ref.node != unsafe { nil } && ref.node != node && ref.node.mounted && !ref.node.component.is_disposed() {
		return error('compiled VML ref already refers to a mounted control')
	}
	ref.node = node
}

fn (ref &VmlRef[T]) require_node() !&CompiledVmlNode {
	ref.owner.require_alive()!
	if ref.node == unsafe { nil } || !ref.node.mounted || ref.node.component.is_disposed() {
		return error('compiled VML ref is unavailable before mount or after unmount')
	}
	return ref.node
}

pub fn (ref &VmlRef[T]) is_available() bool {
	return !ref.owner.is_disposed() && ref.node != unsafe { nil }
		&& ref.node.mounted && !ref.node.component.is_disposed()
}

pub fn (ref &VmlRef[T]) id() !string { return ref.require_node()!.element().id }

pub fn (ref &VmlRef[T]) element() !Element { return ref.require_node()!.element() }

fn (ref &VmlRef[T]) command_id() !string {
	id := ref.id()!
	if id.len == 0 { return error('compiled VML ref command requires an explicit authored id') }
	return id
}

pub fn (ref &VmlRef[T]) focus() ! {
	$if T is VmlButton || T is VmlView || T is VmlTextField || T is VmlTextArea || T is VmlTextInput || T is VmlCheckbox || T is VmlDropdown || T is VmlSlider || T is VmlSwitch || T is VmlToggleButton {
		focus(ref.command_id()!)
	} $else {
		$compile_error('VML ref target does not support focus')
	}
}

// set_text is an explicit edit-buffer replacement, preserving the distinction
// between a declared text effect and an imperative replacement of local edits.
pub fn (ref &VmlRef[T]) set_text(text string) ! {
	$if T is VmlTextField || T is VmlTextArea || T is VmlTextInput {
		set_text(ref.command_id()!, text)
	} $else {
		$compile_error('VML ref target does not support set_text')
	}
}
