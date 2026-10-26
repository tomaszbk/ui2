module ui2

$if ios && !ui2_custom_rendering ? && !ui2_headless ? && !ui2_document_library ? {

import macos

// The iOS backend drives UIKit through the Objective-C runtime only.
// Nothing here may be written in Objective-C: V compiles the generated
// sources with -fobjc-arc on iOS, and ARC rejects the manual retain and
// release calls this backend is built on.

fn extern_u64(name string, fallback u64) u64 {
	address := extern_symbol(name)
	if address == unsafe { nil } {
		return fallback
	}
	return unsafe { *(&u64(address)) }
}

// ── Objective-C conveniences ───────────────────────────────────────
// The shared runtime helpers (objc_nil, objc_string, extern_id, blocks) live
// with the iOS host services in ui/objc_ios.v.

@[inline]
fn objc_number_u64(value u64) macos.Id {
	return macos.msg_id_u64(macos.get_class('NSNumber'), 'numberWithUnsignedLongLong:', value)
}

// ── Rotation ───────────────────────────────────────────────────────

// native_set_view_rotation rotates a view around its center. The layer key
// path is used instead of UIView.transform so no CGAffineTransform has to
// cross the message send boundary.
fn native_set_view_rotation(view View, degrees f64) {
	if objc_is_nil(view) {
		return
	}
	layer := macos.msg_id(view, 'layer')
	if objc_is_nil(layer) {
		return
	}
	transaction := macos.get_class('CATransaction')
	macos.msg_void(transaction, 'begin')
	macos.msg_void_bool(transaction, 'setDisableActions:', true)
	radians := degrees * 0.017453292519943295
	macos.msg_void2(layer, 'setValue:forKeyPath:', macos.msg_id_f64(macos.get_class('NSNumber'), 'numberWithDouble:', radians), macos.nsstring('transform.rotation'))
	macos.msg_void(transaction, 'commit')
}

// ── Hidden, enabled and accessibility state ────────────────────────

// Association keys only need stable addresses, so the fields of this global
// double as the four keys used to remember the state a view had before ui2
// overrode it.
struct AccessibilityKeys {
mut:
	role    u8
	label   u8
	value   u8
	element u8
}

__global g_accessibility_keys = AccessibilityKeys{}

fn accessibility_traits(role string) u64 {
	return match role {
		'button' { extern_u64('UIAccessibilityTraitButton', 1) }
		'image', 'img' { extern_u64('UIAccessibilityTraitImage', 4) }
		'link' { extern_u64('UIAccessibilityTraitLink', 2) }
		'header' { extern_u64('UIAccessibilityTraitHeader', 0x10000) }
		'adjustable', 'slider' { extern_u64('UIAccessibilityTraitAdjustable', 0x1000) }
		'switch' { extern_u64('UIAccessibilityTraitButton', 1) }
		else { extern_u64('UIAccessibilityTraitNone', 0) }
	}
}

fn saved_accessibility_value(value macos.Id) macos.Id {
	return if objc_is_nil(value) {
		macos.msg_id(macos.get_class('NSNull'), 'null')
	} else {
		value
	}
}

fn restored_accessibility_value(value macos.Id) macos.Id {
	return if value == macos.msg_id(macos.get_class('NSNull'), 'null') {
		objc_nil()
	} else {
		value
	}
}

fn apply_accessibility_string(view View, raw string, getter string, setter string, key voidptr) {
	saved := macos.get_associated_object(view, key)
	if raw.len > 0 {
		if objc_is_nil(saved) {
			macos.set_associated_object(view, key, saved_accessibility_value(macos.msg_id(view, getter)), macos.assoc_retain_nonatomic)
		}
		macos.msg_void1(view, setter, macos.nsstring(raw))
	} else if !objc_is_nil(saved) {
		macos.msg_void1(view, setter, restored_accessibility_value(saved))
		macos.set_associated_object(view, key, objc_nil(), macos.assoc_retain_nonatomic)
	}
}

fn apply_accessibility_traits(view View, role string, enabled bool) {
	key := voidptr(&g_accessibility_keys.role)
	saved := macos.get_associated_object(view, key)
	if role.len > 0 {
		if objc_is_nil(saved) {
			macos.set_associated_object(view, key, objc_number_u64(macos.msg_u64(view, 'accessibilityTraits')), macos.assoc_retain_nonatomic)
		}
		disabled_trait := if enabled {
			u64(0)
		} else {
			extern_u64('UIAccessibilityTraitNotEnabled', 0x100)
		}
		macos.msg_void_u64(view, 'setAccessibilityTraits:', accessibility_traits(role) | disabled_trait)
	} else if !objc_is_nil(saved) {
		macos.msg_void_u64(view, 'setAccessibilityTraits:', macos.msg_u64(saved, 'unsignedLongLongValue'))
		macos.set_associated_object(view, key, objc_nil(), macos.assoc_retain_nonatomic)
	}
}

fn apply_accessibility_element(view View, described bool) {
	key := voidptr(&g_accessibility_keys.element)
	saved := macos.get_associated_object(view, key)
	if described {
		if objc_is_nil(saved) {
			element := if macos.msg_bool(view, 'isAccessibilityElement') { u64(1) } else { u64(0) }
			macos.set_associated_object(view, key, objc_number_u64(element), macos.assoc_retain_nonatomic)
		}
		macos.msg_void_bool(view, 'setIsAccessibilityElement:', true)
	} else if !objc_is_nil(saved) {
		macos.msg_void_bool(view, 'setIsAccessibilityElement:', macos.msg_u64(saved, 'unsignedLongLongValue') != 0)
		macos.set_associated_object(view, key, objc_nil(), macos.assoc_retain_nonatomic)
	}
}

fn native_apply_common_view_state(view View, hidden bool, enabled bool, role string, label string, value string) {
	if objc_is_nil(view) {
		return
	}
	macos.msg_void_bool(view, 'setHidden:', hidden)
	apply_accessibility_string(view, label, 'accessibilityLabel', 'setAccessibilityLabel:', voidptr(&g_accessibility_keys.label))
	apply_accessibility_string(view, value, 'accessibilityValue', 'setAccessibilityValue:', voidptr(&g_accessibility_keys.value))
	apply_accessibility_traits(view, role, enabled)
	apply_accessibility_element(view, role.len > 0 || label.len > 0 || value.len > 0)
	if objc_is_kind_of(view, 'UIControl') {
		macos.msg_void_bool(view, 'setEnabled:', enabled)
	} else {
		macos.msg_void_bool(view, 'setUserInteractionEnabled:', enabled)
	}
}

// ── Dropdown menus ─────────────────────────────────────────────────

// UIAction takes a block, which V cannot build, so the menu is made of
// UICommands instead. A command sends a selector up the responder chain,
// where the application delegate answers it, and carries the button it was
// built for in its property list.
fn native_configure_dropdown(button View, entries []MenuEntry) {
	if objc_is_nil(button) || !macos.responds_to(button, 'setShowsMenuAsPrimaryAction:') {
		return
	}
	commands := macos.msg_id(macos.alloc('NSMutableArray'), 'init')
	owner := macos.nsstring(u64(button).str())
	for entry in entries {
		if entry.title.len == 0 {
			continue
		}
		command := macos.msg_id4(macos.get_class('UICommand'), 'commandWithTitle:image:action:propertyList:', macos.nsstring(entry.title), objc_nil(), macos.Id(macos.sel('vuiDropdownSelected:')), owner)
		if !objc_is_nil(command) {
			macos.msg_void1(commands, 'addObject:', command)
		}
	}
	menu := macos.msg_id2(macos.get_class('UIMenu'), 'menuWithTitle:children:', macos.nsstring(''), commands)
	macos.msg_void1(button, 'setMenu:', menu)
	macos.msg_void_bool(button, 'setShowsMenuAsPrimaryAction:', true)
	macos.release(commands)
}

// dropdown_button_for resolves the pointer a command was built with, but
// only while that button is still part of the rendered tree: a refresh
// between opening and picking a menu entry drops the view.
fn (mut w Window) dropdown_button_for(pointer u64) View {
	if pointer == 0 {
		return View(unsafe { nil })
	}
	for _, native in w.nodes {
		if u64(native) == pointer {
			return native
		}
	}
	return View(unsafe { nil })
}

@[export: 'vui_dropdown_selected']
fn vui_dropdown_selected(_self voidptr, _cmd voidptr, sender voidptr) {
	mut w := ios_window() or { return }
	command := View(sender)
	if objc_is_nil(command) {
		return
	}
	title := objc_string(macos.msg_id(command, 'title'))
	button := w.dropdown_button_for(objc_string(macos.msg_id(command, 'propertyList')).u64())
	if objc_is_nil(button) || title.len == 0 {
		return
	}
	current := w.action_callbacks[u64(button)] or { return }
	binding := w.ios_control_action_binding(button, current) or { return }
	w.control_captures.delete(u64(button))
	macos.msg_void2(button, 'setTitle:forState:', macos.nsstring(title), macos.Id(uint(0)))
	w.ios_emit_callback(binding, ElementEvent{ kind: .change, text: title })
}

// ── Text view selection ────────────────────────────────────────────

const ns_not_found = u64(0x7FFFFFFFFFFFFFFF)

fn native_text_view_set_selected_range(view View, location u64, length u64) {
	if !objc_is_kind_of(view, 'UITextView') {
		return
	}
	text_length := macos.msg_u64(macos.msg_id(view, 'text'), 'length')
	safe_location := if location > text_length { text_length } else { location }
	safe_length := if length > text_length - safe_location {
		text_length - safe_location
	} else {
		length
	}
	selection := macos.range(safe_location, safe_length)
	macos.msg_bool(view, 'becomeFirstResponder')
	macos.msg_void_range(view, 'setSelectedRange:', selection)
	macos.msg_void_range(view, 'scrollRangeToVisible:', selection)
}

fn native_text_view_selected_range(view View) macos.Range {
	if !objc_is_kind_of(view, 'UITextView') {
		return macos.range(0, 0)
	}
	selection := macos.msg_range(view, 'selectedRange')
	if selection.location == ns_not_found {
		return macos.range(0, 0)
	}
	return selection
}

}
