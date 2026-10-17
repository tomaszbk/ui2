module ui2

// Marker types describe the control referred to by a declaration. They are
// type parameters, not values in a component's state or binding snapshots.
pub struct VmlButton {}

pub struct VmlView {}

pub struct VmlLabel {}

pub struct VmlImage {}

pub struct VmlTextInput {}

pub struct VmlTextArea {}

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

// Called from the generic ref methods, which a program without refs never instantiates.
// A ref names its control by a marker type or, for generic nodes, by the
// props type of the node it binds (overlays are Views).
@[markused]
fn vml_ref_kind[T]() Kind {
	$if T is VmlButton || T is ButtonProps {
		return .button
	} $else $if T is VmlView || T is ViewProps || T is DialogProps || T is PopoverProps || T is MenuOverlayProps || T is ContextMenuProps || T is TooltipProps {
		return .view
	} $else $if T is VmlLabel || T is LabelProps {
		return .label
	} $else $if T is VmlImage || T is ImageProps {
		return .image
	} $else $if T is VmlTextInput || T is TextInputProps {
		return .text_field
	} $else $if T is VmlTextArea || T is TextAreaProps {
		return .text_area
	} $else $if T is VmlScroll || T is ScrollProps {
		return .scroll
	} $else $if T is VmlCheckbox || T is CheckboxProps {
		return .checkbox
	} $else $if T is VmlDropdown || T is DropdownProps {
		return .dropdown
	} $else $if T is VmlSlider || T is SliderProps {
		return .slider
	} $else $if T is VmlSwitch || T is SwitchProps {
		return .switch_control
	} $else $if T is VmlToggleButton || T is ToggleButtonProps {
		return .toggle_button
	} $else {
		$compile_error('VML refs require a control marker or props type')
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
	valid := node.element().kind == vml_ref_kind[T]()
	if !valid {
		return error('compiled VML ref expects `${vml_ref_kind[T]()}`, got `${node.element().kind}`')
	}
	if ref.node != unsafe { nil } && ref.node != node && ref.node.mounted && !ref.node.component.is_disposed() {
		return error('compiled VML ref already refers to a mounted control')
	}
	ref.node = node
}

// VmlNodeRef is a ref held by a generic node, bound when the node is built.
interface VmlNodeRef {
mut:
	bind(node &CompiledVmlNode) !
}

// bind_widget binds the ref to a generic node (vml_widget_node.v). The ref
// follows the node's retained element, which exists once the document is built.
pub fn (mut ref VmlRef[T]) bind_widget(mut node VmlWidgetNode[T]) ! {
	ref.owner.require_alive()!
	_ = vml_ref_kind[T]()
	node.refs << VmlNodeRef(&ref)
	if retained := node.node() {
		ref.bind(retained)!
	}
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
	$if T is VmlButton || T is VmlView || T is VmlTextInput || T is VmlTextArea || T is VmlCheckbox || T is VmlDropdown || T is VmlSlider || T is VmlSwitch || T is VmlToggleButton || T is ButtonProps || T is ViewProps || T is DialogProps || T is PopoverProps || T is MenuOverlayProps || T is ContextMenuProps || T is TooltipProps || T is TextInputProps || T is TextAreaProps || T is CheckboxProps || T is DropdownProps || T is SliderProps || T is SwitchProps || T is ToggleButtonProps {
		ref.require_node()!.component.dispatch_command(VmlHostCommand{ kind: .focus, id: ref.command_id()! })!
	} $else {
		$compile_error('VML ref target does not support focus')
	}
}

// set_text is an explicit edit-buffer replacement, preserving the distinction
// between a declared text effect and an imperative replacement of local edits.
pub fn (ref &VmlRef[T]) set_text(text string) ! {
	$if T is VmlTextInput || T is VmlTextArea || T is TextInputProps || T is TextAreaProps {
		ref.require_node()!.component.dispatch_command(VmlHostCommand{ kind: .set_text, id: ref.command_id()!, text: text })!
	} $else {
		$compile_error('VML ref target does not support set_text')
	}
}
