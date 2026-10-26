module ui2

$if ios && !ui2_custom_rendering ? && !ui2_headless ? && !ui2_document_library ? {

import ios
import macos

#include "@VMODROOT/uikit/ui_tracking_ios.h"

fn C.ui2_ios_system_font(size f64, weight f64) voidptr

fn C.ui2_ios_scroll_rect_visible(view voidptr, x f64, y f64, width f64, height f64, animated bool)

fn C.ui2_ios_install_control_tracking(control voidptr)

fn C.vui_app_did_finish_launching(self voidptr, cmd voidptr, application voidptr, launch_options voidptr) bool

fn C.vui_button_tap(self voidptr, cmd voidptr, sender voidptr)

fn C.vui_view_tap(self voidptr, cmd voidptr, sender voidptr)

fn C.vui_view_tap_should_receive(self voidptr, cmd voidptr, sender voidptr, touch voidptr) bool

fn C.vui_gesture_should_receive(self voidptr, cmd voidptr, sender voidptr, touch voidptr) bool

fn C.vui_button_behavior_accessibility_activate(self voidptr, cmd voidptr) bool

fn C.vui_text_field_changed(self voidptr, cmd voidptr, sender voidptr)

fn C.vui_text_field_submitted(self voidptr, cmd voidptr, sender voidptr)

fn C.vui_text_view_changed(self voidptr, cmd voidptr, sender voidptr)

fn C.vui_scroll_did_scroll(self voidptr, cmd voidptr, sender voidptr)

fn C.vui_button_long_press(self voidptr, cmd voidptr, sender voidptr)

fn C.vui_swipe_left(self voidptr, cmd voidptr, sender voidptr)

fn C.vui_swipe_should_begin(self voidptr, cmd voidptr, sender voidptr) bool

fn C.vui_swipe_should_recognize_simultaneously(self voidptr, cmd voidptr, sender voidptr, other voidptr) bool

fn C.vui_dropdown_selected(self voidptr, cmd voidptr, sender voidptr)

const swipe_delete_threshold = f64(72)
const swipe_max_translation = f64(140)
const gesture_state_began = 1
const gesture_state_changed = 2
const gesture_state_ended = 3
const gesture_state_cancelled = 4
const gesture_state_failed = 5

type View = voidptr

struct ObjcPoint {
mut:
	x f64
	y f64
}

fn C.objc_msgSend()

fn C.vui_request_refresh(self voidptr, cmd voidptr, sender voidptr)

type ObjcPointMsg1 = fn (voidptr, voidptr, voidptr) ObjcPoint

type ObjcPointMsg0 = fn (voidptr, voidptr) ObjcPoint

type ObjcVoidPointBoolMsg = fn (voidptr, voidptr, ObjcPoint, bool)

struct IosCallbackBinding {
	id       string
	on_event ElementCallback = unsafe { nil }
	kind     Kind
	event    ElementEventKind
}

fn ios_binding(el Element, event ElementEventKind) IosCallbackBinding {
	return IosCallbackBinding{ id: el.id, on_event: el.on_event, kind: el.kind, event: event }
}

fn ios_callback_present(binding IosCallbackBinding) bool {
	return binding.on_event != unsafe { nil }
}

fn (mut w Window) ios_emit_callback(binding IosCallbackBinding, event ElementEvent) bool {
	if !ios_callback_present(binding) { return false }
	binding.on_event(ElementEvent{ ...event, window: w, id: binding.id })
	return true
}

// Window is the app's UIWindow and the views ui2 reconciles into it. An iOS
// app shows one window, so the process's IosHost holds the one that runs and
// the UIKit callbacks, which carry no ui2 context, act on it.
@[heap]
pub struct Window {
mut:
	app             &App = unsafe { nil }
	title           string
	build           BuildFn = BuildFn(unsafe { nil })
	menus           MenuDeclarations
	timers          &TimerRuntime = &TimerRuntime{}
	event_modifiers KeyModifiers
	close_hooks     []fn ()
	// The selection set for a text area while it has no view.
	text_area_selections map[string]TextAreaSelectionRange
	control_captures map[u64]IosCallbackBinding
	gesture_captures map[u64]IosCallbackBinding
	gesture_capture_owners map[u64]u64
	window View = View(unsafe { nil })
	root_vc View = View(unsafe { nil })
	root_view View = View(unsafe { nil })
	ios_rendering bool
	ios_refresh_pending bool
	button_handler View = View(unsafe { nil })
	long_press_handler View = View(unsafe { nil })
	swipe_handler View = View(unsafe { nil })
	views map[string]View
	view_kinds map[string]Kind
	label_places map[string]LabelPlacement
	nodes map[string]View
	node_kinds map[string]Kind
	node_gestures map[string]string
	node_label_boxed map[string]bool
	layout_tree &LayoutTree = &LayoutTree{}
	layout_environment LayoutEnvironment
	node_declared_text map[string]string
	action_callbacks map[u64]IosCallbackBinding
	button_behavior_views map[u64]bool
	text_change_callbacks map[u64]IosCallbackBinding
	text_submit_callbacks map[u64]IosCallbackBinding
	text_area_callbacks map[u64]IosCallbackBinding
	slider_specs map[u64]SliderSpec
	toggle_groups map[u64]string
	toggle_allow_no_selection map[u64]bool
	toggle_ids map[u64]string
	toggle_views map[u64]View
	scroll_callbacks map[u64]IosCallbackBinding
	scroll_ids map[string]bool
	scroll_offsets map[string]f64
	scroll_offsets_x map[string]f64
	view_translation_x map[voidptr]f64
	ios_navigation &FocusManager = &FocusManager{}
	ios_navigation_paths map[string]string
}

@[heap]
struct IosHost {
mut:
	window &Window = unsafe { nil }
}

const ios_host_singleton = &IosHost{}

fn ios_host() &IosHost {
	return unsafe { ios_host_singleton }
}

// ios_window is the window UIKit's callbacks act on.
fn ios_window() ?&Window {
	host := ios_host()
	if host.window == unsafe { nil } { return none }
	return host.window
}

// UIApplicationMain runs one window per process.
fn (mut app App) open_backend_window(config WindowConfig) !&Window {
	if app.windows.len > 0 {
		return error('an iOS app runs one window')
	}
	mut w := &Window{
		app: app
		title: config.title
		build: config.build
	}
	mut host := ios_host()
	host.window = w
	return w
}

fn (mut app App) run_backend() {
	if app.windows.len == 0 { return }
	ensure_runtime_classes()
	pool := macos.autorelease_pool_new()
	defer {
		macos.release(pool)
	}
	code := ios.application_main(g_main_argc, &&char(g_main_argv), 'VuiAppDelegate')
	if code != 0 {
		exit(code)
	}
}

// on_close runs hook as the window closes; the system ends an iOS app
// without closing its window, so the hooks run only if it ever does.
fn (mut w Window) on_close(hook fn ()) { w.close_hooks << hook }

// A refresh asked for while one renders waits for it, as on AppKit.
// What a label's text was last laid out against, kept for the labels that can be
// written to by id so setting their text can place it the way the layout would have.

// ── Public API ─────────────────────────────────────────────────────

pub fn (mut w Window) bounds() Rect {
	return ios_screen_bounds()
}

fn ios_screen_bounds() Rect {
	b := macos.msg_rect(macos.msg_id(macos.get_class('UIScreen'), 'mainScreen'), 'bounds')
	return Rect{
		x:      b.x
		y:      b.y
		width:  b.width
		height: b.height
	}
}

// rebuild_now builds and renders the window's tree on the main thread.
fn (mut w Window) rebuild_now() {
	if w.root_view == unsafe { nil } || voidptr(w.build) == unsafe { nil } {
		return
	}
	if w.ios_rendering {
		w.ios_refresh_pending = true
		return
	}
	w.ios_rendering = true
	// `after` callbacks run on the UI thread before the build, so it declares
	// what they changed.
	w.run_due_timers()
	root := w.build(mut w)
	w.render_root(root)
	w.ios_rendering = false
	if w.ios_refresh_pending {
		w.ios_refresh_pending = false
		w.request_refresh()
	}
}

// request_refresh schedules a declarative rebuild on UIKit's main thread.
// Animation drivers and background work use this instead of touching views.
pub fn (mut w Window) request_refresh() {
	if w.button_handler == unsafe { nil } {
		return
	}
	macos.msg_void_sel_id_bool(w.button_handler, 'performSelectorOnMainThread:withObject:waitUntilDone:', macos.sel('vuiRefresh:'), objc_nil(), false)
}

pub fn (mut w Window) text(id string) string {
	view := w.views[id] or { return '' }
	kind := w.view_kinds[id] or { Kind.view }
	ns_text := if kind == .dropdown {
		macos.msg_id(view, 'currentTitle')
	} else if kind == .label {
		macos.msg_id(label_text_view(view), 'text')
	} else {
		macos.msg_id(view, 'text')
	}
	return macos.utf8_string(ns_text)
}

pub fn (mut w Window) set_text(id string, t string) {
	if id in w.views {
		view := w.views[id] or { return }
		kind := w.view_kinds[id] or { Kind.view }
		if kind == .dropdown {
			macos.msg_void2(view, 'setTitle:forState:', macos.nsstring(t), macos.Id(uint(0)))
		} else if kind == .label {
			lbl := label_text_view(view)
			macos.msg_void1(lbl, 'setText:', macos.nsstring(t))
			if place := w.label_places[id] {
				place_label_text(lbl, place.frame, place.lines, place.valign, place.boxed)
			}
		} else {
			macos.msg_void1(view, 'setText:', macos.nsstring(t))
		}
	}
}

pub fn (mut w Window) slider_value(id string) f64 {
	view := w.views[id] or { return 0 }
	if (w.view_kinds[id] or { Kind.view }) != .slider {
		return 0
	}
	spec := w.slider_specs[u64(view)] or { return 0 }
	return native_snap_slider_value(view, spec)
}

pub fn (mut w Window) set_slider_value(id string, value f64) {
	view := w.views[id] or { return }
	if (w.view_kinds[id] or { Kind.view }) != .slider {
		return
	}
	spec := w.slider_specs[u64(view)] or { return }
	slider_set_number(view, 'value', slider_clamped_value(value, spec.min, spec.max))
}

pub fn (mut w Window) switch_active(id string) bool {
	view := w.views[id] or { return false }
	if (w.view_kinds[id] or { Kind.view }) != .switch_control {
		return false
	}
	return macos.msg_bool(view, 'isOn')
}

pub fn (mut w Window) set_switch_active(id string, active bool) {
	view := w.views[id] or { return }
	if (w.view_kinds[id] or { Kind.view }) != .switch_control {
		return
	}
	macos.msg_void_bool(view, 'setOn:', active)
}

pub fn (mut w Window) toggle_button_pressed(id string) bool {
	view := w.views[id] or { return false }
	if (w.view_kinds[id] or { Kind.view }) != .toggle_button {
		return false
	}
	return macos.msg_bool(view, 'isSelected')
}

pub fn (mut w Window) set_toggle_button_pressed(id string, pressed bool) {
	view := w.views[id] or { return }
	if (w.view_kinds[id] or { Kind.view }) != .toggle_button {
		return
	}
	if pressed {
		w.release_ios_toggle_group(u64(view))
	}
	macos.msg_void_bool(view, 'setSelected:', pressed)
}

pub fn (mut w Window) toggle_button_group_members(id string) []string {
	view := w.views[id] or { return [] }
	pointer := u64(view)
	group := w.toggle_groups[pointer] or { return [id] }
	if group.len == 0 {
		return [id]
	}
	mut members := []string{}
	for member_pointer, member_group in w.toggle_groups {
		if member_group == group {
			member_id := w.toggle_ids[member_pointer] or { continue }
			if member_id.len > 0 {
				members << member_id
			}
		}
	}
	return members
}

fn (mut w Window) release_ios_toggle_group(pointer u64) {
	group := w.toggle_groups[pointer] or { return }
	if group.len == 0 {
		return
	}
	for member_pointer, member_group in w.toggle_groups {
		if member_pointer == pointer || member_group != group {
			continue
		}
		native := w.toggle_views[member_pointer] or { continue }
		macos.msg_void_bool(native, 'setSelected:', false)
	}
}

fn (mut w Window) commit_ios_toggle_button(pointer u64, control View) {
	current := macos.msg_bool(control, 'isSelected')
	group := w.toggle_groups[pointer] or { '' }
	pressed := if group.len > 0 && current
		&& !(w.toggle_allow_no_selection[pointer] or { true }) {
		true
	} else {
		!current
	}
	macos.msg_void_bool(control, 'setSelected:', pressed)
	if pressed {
		w.release_ios_toggle_group(pointer)
	}
}

pub fn (mut w Window) focus(id string) {
	w.sync_focus_navigation()
	if !w.ios_navigation.can_focus(id) { return }
	native := w.views[id] or { return }
	window := w.window
	root_view := w.root_view
	mut manager := w.ios_navigation
	root := manager.root
	tree := w.layout_tree
	revision := tree.revision
	if !macos.msg_bool(native, 'becomeFirstResponder') { return }
	if w.window != window || w.root_view != root_view || w.ios_navigation != manager
		|| manager.root != root || w.layout_tree != tree || tree.revision != revision
		|| (w.views[id] or { View(unsafe { nil }) }) != native || w.focused_id() != id { return }
	manager.current = id
	for request in w.ios_navigation.reveals(id) {
		key := w.ios_navigation_paths[request.path] or { continue }
		pane := w.nodes[key] or { continue }
		C.ui2_ios_scroll_rect_visible(pane, request.rect.x, request.rect.y,
			request.rect.width, request.rect.height, false)
		// Non-animated scrolling can synchronously invoke the Scroll delegate.
		if w.window != window || w.root_view != root_view || w.ios_navigation != manager
			|| manager.root != root || w.layout_tree != tree || tree.revision != revision
			|| (w.views[id] or { View(unsafe { nil }) }) != native
			|| (w.nodes[key] or { View(unsafe { nil }) }) != pane
			|| manager.current != id || w.focused_id() != id { return }
	}
	w.sync_focus_navigation()
}

pub fn (mut w Window) focused_id() string {
	for id, native in w.views {
		if macos.msg_bool(native, 'isFirstResponder') {
			return id
		}
	}
	return ''
}

pub fn (mut w Window) focused_text_area_id() string {
	for id, native in w.views {
		if (w.view_kinds[id] or { Kind.view }) == .text_area && macos.msg_bool(native, 'isFirstResponder') {
			return id
		}
	}
	return ''
}

pub fn (mut w Window) dismiss_keyboard() {
	if w.root_view != unsafe { nil } {
		macos.msg_void_bool(w.root_view, 'endEditing:', true)
	}
}

pub fn (mut w Window) safe_area_top() f64 {
	if w.root_view == unsafe { nil } {
		return 0
	}
	insets := macos.msg_rect(w.root_view, 'safeAreaInsets')
	return insets.x
}

// The camera scanner is the iOS host's (scanner_ios.v).
pub fn start_barcode_scan(on_result ScanCallback) { host_start_barcode_scan(on_result) }

// ── Native bridge helpers ──────────────────────────────────────────

fn native_rect(r Rect) macos.Rect {
	return macos.rect(r.x, r.y, r.width, r.height)
}

// font is the system font at a size and a 100–900 weight (text_style_weight).
fn font(size f64, weight int) macos.Id {
	if weight == 700 {
		return macos.msg_id_f64(macos.get_class('UIFont'), 'boldSystemFontOfSize:', size)
	}
	if weight != 400 {
		return macos.Id(C.ui2_ios_system_font(size, native_font_weight(weight)))
	}
	return macos.msg_id_f64(macos.get_class('UIFont'), 'systemFontOfSize:', size)
}

// set_box_background paints what a BoxStyle puts beneath its borders: the solid
// fill at its opacity or a CAGradientLayer, and the drop shadow.
fn set_box_background(view View, box BoxStyle) {
	opacity := box_fill_opacity(box)
	layer := macos.msg_id(view, 'layer')
	transaction := macos.Id(macos.get_class('CATransaction'))
	macos.msg_void(transaction, 'begin')
	macos.msg_void_bool(transaction, 'setDisableActions:', true)
	color := if opacity <= 0 || box_has_gradient(box) {
		macos.msg_id(macos.get_class('UIColor'), 'clearColor')
	} else if opacity < 1 {
		ios.color_alpha(box.bg, opacity)
	} else {
		ios.color(box.bg)
	}
	macos.msg_void1(view, 'setBackgroundColor:', color)
	if box_has_gradient(box) {
		set_gradient_layer(view, layer, box, opacity)
	} else {
		gradient := macos.get_associated_object(view, gradient_key())
		if !objc_is_nil(gradient) {
			macos.msg_void_bool(gradient, 'setHidden:', true)
		}
	}
	set_layer_shadow(layer, box)
	macos.msg_void(transaction, 'commit')
}

fn gradient_key() voidptr {
	return voidptr(macos.sel('ui2_gradient_assoc'))
}

// The gradient is a sublayer kept behind the subviews' layers and the borders by
// its z position, sized to the view and rounded like it.
fn set_gradient_layer(view View, layer macos.Id, box BoxStyle, opacity f64) {
	mut gradient := macos.get_associated_object(view, gradient_key())
	if objc_is_nil(gradient) {
		gradient = macos.msg_id(macos.alloc('CAGradientLayer'), 'init')
		macos.msg_void_f64(gradient, 'setZPosition:', -1000)
		macos.set_associated_object(view, gradient_key(), gradient, macos.assoc_retain_nonatomic)
		macos.release(gradient)
	}
	if macos.msg_id(gradient, 'superlayer') != layer {
		macos.msg_void1(layer, 'addSublayer:', gradient)
	}
	bounds := macos.msg_rect(view, 'bounds')
	macos.msg_void_rect(gradient, 'setFrame:', bounds)
	macos.msg_void_f64(gradient, 'setCornerRadius:', box.radius)
	colors := macos.msg_id(macos.alloc('NSMutableArray'), 'init')
	locations := macos.msg_id(macos.alloc('NSMutableArray'), 'init')
	for stop in gradient_sorted_stops(box.gradient) {
		macos.msg_void1(colors, 'addObject:', macos.msg_id(ios.color_alpha(stop.color, stop.opacity * opacity),
			'CGColor'))
		macos.msg_void1(locations, 'addObject:', macos.msg_id_f64(macos.get_class('NSNumber'),
			'numberWithDouble:', stop.position))
	}
	macos.msg_void1(gradient, 'setColors:', colors)
	macos.msg_void1(gradient, 'setLocations:', locations)
	macos.release(colors)
	macos.release(locations)
	// UIKit layers already measure from the top left, as the gradient line does.
	line := gradient_line(box.gradient.angle, bounds.width, bounds.height)
	w := if bounds.width > 0 { bounds.width } else { 1.0 }
	h := if bounds.height > 0 { bounds.height } else { 1.0 }
	macos.msg_void_point(gradient, 'setStartPoint:', macos.point(line.x0 / w, line.y0 / h))
	macos.msg_void_point(gradient, 'setEndPoint:', macos.point(line.x1 / w, line.y1 / h))
	macos.msg_void_bool(gradient, 'setHidden:', false)
}

// shadowOpacity is a float, set through key-value coding so the bridge's double
// setters are not handed a float slot.
fn set_layer_shadow(layer macos.Id, box BoxStyle) {
	opacity := if box_has_shadow(box) { unit_clamp(box.shadow.opacity) } else { 0.0 }
	macos.msg_void2(layer, 'setValue:forKey:', macos.msg_id_f64(macos.get_class('NSNumber'),
		'numberWithDouble:', opacity), macos.nsstring('shadowOpacity'))
	if opacity <= 0 {
		return
	}
	shadow := box.shadow
	macos.msg_void1(layer, 'setShadowColor:', macos.msg_id(ios.color(shadow.color), 'CGColor'))
	// CoreAnimation's radius is the blur's standard deviation, about half the
	// CSS-style blur the box declares.
	macos.msg_void_f64(layer, 'setShadowRadius:', if shadow.blur > 0 { shadow.blur / 2 } else { 0.0 })
	macos.msg_void_point(layer, 'setShadowOffset:', macos.point(shadow.x, shadow.y))
}

// A rounded box clips its subviews to its corners, except when it casts a shadow:
// a layer that masks to its bounds masks its own shadow away too.
fn set_box_corners(view View, box BoxStyle) {
	layer := macos.msg_id(view, 'layer')
	macos.msg_void_f64(layer, 'setCornerRadius:', box.radius)
	macos.msg_void_bool(layer, 'setMasksToBounds:', !box_has_shadow(box))
}

fn set_corner_radius(view View, radius f64) {
	layer := macos.msg_id(view, 'layer')
	macos.msg_void_f64(layer, 'setCornerRadius:', radius)
	macos.msg_void_bool(layer, 'setMasksToBounds:', true)
}

fn border_key(side string) voidptr {
	return voidptr(macos.sel('ui2_border_${side}_assoc'))
}

fn set_border_layer(view View, side string, frame Rect, color u32, visible bool) {
	key := border_key(side)
	mut border := View(macos.get_associated_object(view, key))
	if !visible {
		if border != unsafe { nil } {
			macos.msg_void_bool(border, 'setHidden:', true)
		}
		return
	}
	parent_layer := macos.msg_id(view, 'layer')
	if border == unsafe { nil } {
		border = macos.msg_id(macos.alloc('CALayer'), 'init')
		macos.set_associated_object(view, key, border, macos.assoc_retain_nonatomic)
		macos.release(border)
	}
	if macos.msg_id(border, 'superlayer') != parent_layer {
		macos.msg_void1(parent_layer, 'addSublayer:', border)
	}
	macos.msg_void_rect(border, 'setFrame:', native_rect(frame))
	macos.msg_void1(border, 'setBackgroundColor:', macos.msg_id(ios.color(color), 'CGColor'))
	macos.msg_void_bool(border, 'setHidden:', false)
}

fn set_box_borders(view View, box BoxStyle) {
	view_bounds := macos.msg_rect(view, 'bounds')
	left := box_border_width(box.border_left, view_bounds.width)
	top := box_border_width(box.border_top, view_bounds.height)
	right := box_border_width(box.border_right, view_bounds.width)
	bottom := box_border_width(box.border_bottom, view_bounds.height)
	rounded := box_rounded_border(box)
	layer := macos.msg_id(view, 'layer')
	if (left <= 0 && top <= 0 && right <= 0 && bottom <= 0) || rounded > 0 {
		for side in ['left', 'top', 'right', 'bottom'] {
			set_border_layer(view, side, Rect{}, box.border_color, false)
		}
	}
	if left <= 0 && top <= 0 && right <= 0 && bottom <= 0 {
		macos.msg_void_f64(layer, 'setBorderWidth:', 0)
		return
	}
	if box.radius > 0 {
		set_box_corners(view, box)
	}
	// An even border on a rounded box is the layer's own, which follows the
	// corners; straight side layers would leave them bare.
	if rounded > 0 {
		macos.msg_void_f64(layer, 'setBorderWidth:', rounded)
		macos.msg_void1(layer, 'setBorderColor:', macos.msg_id(ios.color(box.border_color), 'CGColor'))
		return
	}
	macos.msg_void_f64(layer, 'setBorderWidth:', 0)
	transaction := macos.Id(macos.get_class('CATransaction'))
	macos.msg_void(transaction, 'begin')
	macos.msg_void_bool(transaction, 'setDisableActions:', true)
	set_border_layer(view, 'left', rect(0, 0, left, view_bounds.height), box.border_color, left > 0)
	set_border_layer(view, 'top', rect(0, 0, view_bounds.width, top), box.border_color, top > 0)
	set_border_layer(view, 'right', rect(view_bounds.width - right, 0, right, view_bounds.height), box.border_color, right > 0)
	set_border_layer(view, 'bottom', rect(0, view_bounds.height - bottom, view_bounds.width, bottom), box.border_color, bottom > 0)
	macos.msg_void(transaction, 'commit')
}

fn add_button_target(btn View, target View) {
	macos.msg_void3(btn, 'addTarget:action:forControlEvents:', target, macos.sel('handleTap:'), macos.Id(uint(64)))
}

fn add_view_tap_target(view View, target View) {
	recognizer := macos.msg_id2(macos.alloc('UITapGestureRecognizer'), 'initWithTarget:action:',
		target, macos.sel('handleViewTap:'))
	macos.msg_void_bool(recognizer, 'setCancelsTouchesInView:', false)
	macos.msg_void1(recognizer, 'setDelegate:', target)
	macos.msg_void1(view, 'addGestureRecognizer:', recognizer)
	macos.release(recognizer)
}

fn add_control_target_action(control View, target View, action string, event_mask u64) {
	macos.msg_void3(control, 'addTarget:action:forControlEvents:', target, macos.sel(action), macos.Id(uint(event_mask)))
}

fn remove_control_target_action(control View, target View, action string, event_mask u64) {
	macos.msg_void3(control, 'removeTarget:action:forControlEvents:', target, macos.sel(action), macos.Id(uint(event_mask)))
}

fn add_long_press_target(view View, target View) {
	recognizer := macos.msg_id2(macos.alloc('UILongPressGestureRecognizer'), 'initWithTarget:action:', target, macos.sel('handleLongPress:'))
	macos.msg_void_f64(recognizer, 'setMinimumPressDuration:', 0.45)
	macos.msg_void1(recognizer, 'setDelegate:', target)
	macos.msg_void1(view, 'addGestureRecognizer:', recognizer)
	macos.release(recognizer)
}

fn add_swipe_left_target(view View, target View) {
	recognizer := macos.msg_id2(macos.alloc('UIPanGestureRecognizer'), 'initWithTarget:action:', target, macos.sel('handleSwipe:'))
	macos.msg_void_bool(recognizer, 'setCancelsTouchesInView:', false)
	macos.msg_void1(recognizer, 'setDelegate:', target)
	macos.msg_void1(view, 'addGestureRecognizer:', recognizer)
	macos.release(recognizer)
}

fn gesture_state(gesture View) int {
	return int(macos.msg_i64(gesture, 'state'))
}

fn gesture_view(gesture View) View {
	return macos.msg_id(gesture, 'view')
}

fn gesture_location(gesture View, view View) ObjcPoint {
	if gesture == unsafe { nil } || view == unsafe { nil } {
		return ObjcPoint{}
	}
	sender := unsafe { ObjcPointMsg1(C.objc_msgSend) }
	return sender(voidptr(gesture), voidptr(macos.sel('locationInView:')), voidptr(view))
}

fn pan_base_view(view View) View {
	superview := macos.msg_id(view, 'superview')
	if superview == unsafe { nil } {
		return view
	}
	return superview
}

fn pan_point(gesture View, selector string, view View) ObjcPoint {
	if gesture == unsafe { nil } || view == unsafe { nil } {
		return ObjcPoint{}
	}
	sender := unsafe { ObjcPointMsg1(C.objc_msgSend) }
	base := pan_base_view(view)
	return sender(voidptr(gesture), voidptr(macos.sel(selector)), voidptr(base))
}

fn pan_translation_x(gesture View, view View) f64 {
	return pan_point(gesture, 'translationInView:', view).x
}

fn pan_translation_y(gesture View, view View) f64 {
	return pan_point(gesture, 'translationInView:', view).y
}

fn pan_velocity_x(gesture View, view View) f64 {
	return pan_point(gesture, 'velocityInView:', view).x
}

fn pan_velocity_y(gesture View, view View) f64 {
	return pan_point(gesture, 'velocityInView:', view).y
}

fn (mut w Window) set_view_translation_x(view View, x f64) {
	if view == unsafe { nil } {
		return
	}
	key := voidptr(view)
	current := w.view_translation_x[key] or { f64(0) }
	delta := x - current
	if delta == 0 {
		return
	}
	mut frame := macos.msg_rect(view, 'frame')
	frame.x += delta
	macos.msg_void_rect(view, 'setFrame:', frame)
	if x == 0 {
		w.view_translation_x.delete(key)
	} else {
		w.view_translation_x[key] = x
	}
}

fn point_message0(view View, selector string) ObjcPoint {
	if view == unsafe { nil } {
		return ObjcPoint{}
	}
	sender := unsafe { ObjcPointMsg0(C.objc_msgSend) }
	return sender(voidptr(view), voidptr(macos.sel(selector)))
}

fn scroll_content_offset(scroll View) ObjcPoint {
	return point_message0(scroll, 'contentOffset')
}

fn set_scroll_content_offset(scroll View, x f64, y f64) {
	if scroll == unsafe { nil } {
		return
	}
	mut offset := point_message0(scroll, 'contentOffset')
	offset.x = x
	offset.y = y
	sender := unsafe { ObjcVoidPointBoolMsg(C.objc_msgSend) }
	sender(voidptr(scroll), voidptr(macos.sel('setContentOffset:animated:')), offset, false)
}

fn new_native_view(frame Rect, box BoxStyle, button_behavior bool) View {
	class_name := if button_behavior { 'VuiButtonBehaviorView' } else { 'UIView' }
	view := macos.msg_id_rect(macos.alloc(class_name), 'initWithFrame:', native_rect(frame))
	set_box_background(view, box)
	set_box_corners(view, box)
	return view
}

fn new_scroll_view(frame Rect, box BoxStyle) View {
	scroll := macos.msg_id_rect(macos.alloc('UIScrollView'), 'initWithFrame:', native_rect(frame))
	set_box_background(scroll, box)
	set_corner_radius(scroll, box.radius)
	macos.msg_void_bool(scroll, 'setAlwaysBounceVertical:', true)
	macos.msg_void_i64(scroll, 'setKeyboardDismissMode:', 1)
	macos.msg_void_i64(scroll, 'setContentInsetAdjustmentBehavior:', 2)
	return scroll
}

fn new_label_view(frame Rect, t string, text_hex u32, size f64, weight int, align int, lines int, valign VAlign, boxed bool) View {
	inner := if boxed {
		Rect{
			width:  frame.width
			height: frame.height
		}
	} else {
		frame
	}
	lbl := macos.msg_id_rect(macos.alloc('UILabel'), 'initWithFrame:', native_rect(inner))
	if !boxed {
		update_label_view(lbl, frame, t, text_hex, size, weight, align, lines, valign, boxed)
		return lbl
	}
	container := macos.msg_id_rect(macos.alloc('UIView'), 'initWithFrame:', native_rect(frame))
	macos.msg_void1(container, 'addSubview:', lbl)
	macos.release(lbl)
	update_label_view(container, frame, t, text_hex, size, weight, align, lines, valign,
		boxed)
	return container
}

struct LabelPlacement {
	frame  Rect
	lines  int
	valign VAlign
	boxed  bool
}

// The label a view draws its text with: itself, or the one it holds.
fn label_text_view(view View) View {
	subviews := macos.msg_id(view, 'subviews')
	if subviews == macos.Id(unsafe { nil }) || macos.msg_u64(subviews, 'count') == 0 {
		return view
	}
	return View(macos.msg_id_u64(subviews, 'objectAtIndex:', 0))
}

fn update_label_view(view View, frame Rect, t string, text_hex u32, size f64, weight int, align int, lines int, valign VAlign, boxed bool) {
	macos.msg_void_rect(view, 'setFrame:', native_rect(frame))
	lbl := if boxed { label_text_view(view) } else { view }
	macos.msg_void1(lbl, 'setText:', macos.nsstring(t))
	macos.msg_void1(lbl, 'setTextColor:', ios.color(text_hex))
	macos.msg_void1(lbl, 'setFont:', font(size, weight))
	macos.msg_void_i64(lbl, 'setTextAlignment:', i64(align))
	budget := label_line_budget(lines)
	macos.msg_void_i64(lbl, 'setNumberOfLines:', i64(budget))
	// A label allowed more than one line has to be allowed to wrap onto them; left
	// truncating, asking for more lines only clips one line instead of filling them.
	macos.msg_void_i64(lbl, 'setLineBreakMode:', if budget == 1 {
		ns_line_break_by_truncating_tail
	} else {
		ns_line_break_by_word_wrapping
	})
	place_label_text(lbl, frame, budget, valign, boxed)
}

// What a label is really allowed to draw. Callers resolve TextStyle.lines through
// text_line_budget first, so `lines: 0` already arrives as a large finite budget;
// UIKit reads a budget of no lines at all as no limit, so anything left below one
// is kept to a single truncated line here.
fn label_line_budget(lines int) int {
	return if lines > 1 { lines } else { 1 }
}

// Put the label back over the whole area it was laid out with, then move it to where
// this text wants to sit. Going back first is what lets changed text be measured
// against the label's real width and given all the room the label has, rather than
// the strip the text before it happened to need.
fn place_label_text(lbl View, frame Rect, lines int, valign VAlign, boxed bool) {
	macos.msg_void_rect(lbl, 'setFrame:', native_rect(if boxed {
		Rect{
			width:  frame.width
			height: frame.height
		}
	} else {
		frame
	}))
	apply_label_valign(lbl, frame, label_line_budget(lines), valign, boxed)
}

// NSLineBreakMode values, shared with UILabel.
const ns_line_break_by_word_wrapping = 0
const ns_line_break_by_truncating_tail = 4

// A UILabel centres its text in its frame, so middle is already what it does. Top and
// bottom shrink the label to the height its text actually wants and put that where it
// was asked for; a wrapping label is measured against the width it has to break on.
fn apply_label_valign(lbl View, frame Rect, lines int, valign VAlign, boxed bool) {
	if valign == .middle || frame.height <= 0 {
		return
	}
	if lines > 1 {
		macos.msg_void_f64(lbl, 'setPreferredMaxLayoutWidth:', frame.width)
	}
	// Point carries a Cocoa size as well as a point; y is the height.
	content := macos.msg_point(lbl, 'intrinsicContentSize').y
	if content <= 0 || content >= frame.height {
		return
	}
	offset := if valign == .top { 0.0 } else { frame.height - content }
	// Inside the holding view when there is one, so that view keeps the declared frame
	// and the border drawn round it stays round the label rather than round the text.
	macos.msg_void_rect(lbl, 'setFrame:', native_rect(if boxed {
		Rect{
			y:      offset
			width:  frame.width
			height: content
		}
	} else {
		Rect{
			x:      frame.x
			y:      frame.y + offset
			width:  frame.width
			height: content
		}
	}))
}

fn new_image_view(frame Rect, path string, tint u32) View {
	image_view := macos.msg_id_rect(macos.alloc('UIImageView'), 'initWithFrame:', native_rect(frame))
	update_image_view(image_view, frame, path, tint)
	return image_view
}

// A `symbol:` path draws that SF Symbol tinted with the element's text color, as
// every backend tints its symbol glyph; a file image keeps its own colors.
fn update_image_view(image_view View, frame Rect, path string, tint u32) {
	macos.msg_void_rect(image_view, 'setFrame:', native_rect(frame))
	macos.msg_void_i64(image_view, 'setContentMode:', 1)
	symbol := path.starts_with('symbol:')
	image := if path.trim_space().len == 0 {
		View(unsafe { nil })
	} else if symbol {
		macos.msg_id1(macos.get_class('UIImage'), 'systemImageNamed:', macos.nsstring(path['symbol:'.len..]))
	} else {
		macos.msg_id1(macos.get_class('UIImage'), 'imageWithContentsOfFile:', macos.nsstring(path))
	}
	macos.msg_void1(image_view, 'setImage:', image)
	macos.msg_void1(image_view, 'setTintColor:', if symbol { ios.color(tint) } else { View(unsafe { nil }) })
}

fn new_text_area_view(el Element) View {
	view := macos.msg_id_rect(macos.alloc('UITextView'), 'initWithFrame:', native_rect(el.frame))
	update_text_area_view(view, el, true)
	return view
}

fn update_text_area_view(view View, el Element, declared_text_changed bool) {
	macos.msg_void_rect(view, 'setFrame:', native_rect(el.frame))
	set_box_background(view, el.box)
	macos.msg_void1(view, 'setTextColor:', ios.color(el.text_style.color))
	macos.msg_void1(view, 'setFont:', font(el.text_style.size, text_style_weight(el.text_style)))
	macos.msg_void_bool(view, 'setEditable:', !el.readonly && el.enabled)
	macos.msg_void_bool(view, 'setSelectable:', true)
	macos.msg_void_bool(view, 'setScrollEnabled:', !el.disable_scroll)
	if declared_text_changed && macos.utf8_string(macos.msg_id(view, 'text')) != el.text {
		macos.msg_void1(view, 'setText:', macos.nsstring(el.text))
	}
	set_corner_radius(view, el.box.radius)
}

fn new_dropdown_view(el Element) View {
	view := new_button_view(el.frame, el.text, el.box, el.text_style.color, el.text_style.size, text_style_weight(el.text_style), text_line_budget(el.text_style.lines))
	update_dropdown_view(view, el, true)
	return view
}

fn update_dropdown_view(view View, el Element, declared_text_changed bool) {
	macos.msg_void_rect(view, 'setFrame:', native_rect(el.frame))
	if declared_text_changed && macos.utf8_string(macos.msg_id(view, 'currentTitle')) != el.text {
		macos.msg_void2(view, 'setTitle:forState:', macos.nsstring(el.text), macos.Id(uint(0)))
	}
	set_box_background(view, el.box)
	set_corner_radius(view, el.box.radius)
	native_configure_dropdown(view, el.menu)
}

fn new_button_view(frame Rect, title string, box BoxStyle, text_hex u32, size f64, weight int, lines int) View {
	btn := macos.msg_id_u64(macos.get_class('UIButton'), 'buttonWithType:', u64(0))
	// buttonWithType: is autoreleased. Retain so all native_create_element
	// results follow the same +1 ownership contract.
	macos.msg_id(btn, 'retain')
	update_button_view(btn, frame, title, box, text_hex, size, weight, lines)
	return btn
}

fn update_button_view(btn View, frame Rect, title string, box BoxStyle, text_hex u32, size f64, weight int, lines int) {
	macos.msg_void_rect(btn, 'setFrame:', native_rect(frame))
	macos.msg_void2(btn, 'setTitle:forState:', macos.nsstring(title), macos.Id(uint(0)))
	macos.msg_void2(btn, 'setTitleColor:forState:', ios.color(text_hex), macos.Id(uint(0)))
	set_box_background(btn, box)
	title_label := macos.msg_id(btn, 'titleLabel')
	macos.msg_void1(title_label, 'setFont:', font(size, weight))
	set_corner_radius(btn, box.radius)
	macos.msg_void_i64(title_label, 'setNumberOfLines:', i64(lines))
	macos.msg_void_i64(title_label, 'setTextAlignment:', 1)
	macos.msg_void_i64(title_label, 'setLineBreakMode:', 4)
	macos.msg_void_rect(btn, 'setContentEdgeInsets:', macos.rect(6, 8, 6, 8))
}

fn checkbox_title(el Element) string {
	return '${if el.checked { '☑' } else { '☐' }}  ${el.text}'
}

fn new_checkbox_view(el Element) View {
	view := new_button_view(el.frame, checkbox_title(el), el.box, el.text_style.color, el.text_style.size, text_style_weight(el.text_style), text_line_budget(el.text_style.lines))
	update_checkbox_view(view, el)
	return view
}

fn update_checkbox_view(view View, el Element) {
	macos.msg_void_bool(view, 'setSelected:', el.checked)
	update_button_view(view, el.frame, checkbox_title(el), el.box, el.text_style.color, el.text_style.size, text_style_weight(el.text_style), text_line_budget(el.text_style.lines))
	macos.msg_void_i64(view, 'setContentHorizontalAlignment:', 1)
}

fn new_switch_control_view(el Element) View {
	view := macos.msg_id_rect(macos.alloc('UISwitch'), 'initWithFrame:', native_rect(el.frame))
	update_switch_control_view(view, el)
	return view
}

fn update_switch_control_view(view View, el Element) {
	macos.msg_void_rect(view, 'setFrame:', native_rect(el.frame))
	macos.msg_void_bool(view, 'setOn:', el.checked)
	macos.msg_void1(view, 'setOnTintColor:', ios.color(el.switch_style.active_track_color))
	macos.msg_void1(view, 'setTintColor:', ios.color(el.switch_style.inactive_track_color))
	macos.msg_void1(view, 'setThumbTintColor:', ios.color(el.switch_style.thumb_color))
}

fn new_toggle_button_view(el Element) View {
	view := new_button_view(el.frame, el.text, el.box, el.text_style.color, el.text_style.size, text_style_weight(el.text_style), text_line_budget(el.text_style.lines))
	update_toggle_button_view(view, el)
	return view
}

fn update_toggle_button_view(view View, el Element) {
	box := if el.checked { el.toggle_down_box() } else { el.box }
	style := if el.checked { el.toggle_down_text_style() } else { el.text_style }
	update_button_view(view, el.frame, el.text, box, style.color, style.size, text_style_weight(style), text_line_budget(style.lines))
	macos.msg_void_bool(view, 'setSelected:', el.checked)
}

fn slider_number_value(view View, key string) f64 {
	number := macos.msg_id1(view, 'valueForKey:', macos.nsstring(key))
	if number == unsafe { nil } {
		return 0
	}
	return macos.msg_f64(number, 'doubleValue')
}

fn slider_set_number(view View, key string, value f64) {
	number := macos.msg_id_f64(macos.get_class('NSNumber'), 'numberWithDouble:', value)
	macos.msg_void2(view, 'setValue:forKey:', number, macos.nsstring(key))
}

fn new_slider_view(el Element) View {
	view := macos.msg_id_rect(macos.alloc('UISlider'), 'initWithFrame:', native_rect(el.frame))
	update_slider_view(view, el)
	return view
}

fn update_slider_view(view View, el Element) {
	native_set_view_rotation(view, 0)
	if el.orientation == .vertical {
		macos.msg_void_rect(view, 'setFrame:', native_rect(rect(
			el.frame.x + (el.frame.width - el.frame.height) / 2,
			el.frame.y + (el.frame.height - el.frame.width) / 2,
			el.frame.height,
			el.frame.width,
		)))
		native_set_view_rotation(view, -90)
	} else {
		macos.msg_void_rect(view, 'setFrame:', native_rect(el.frame))
	}
	maximum := if el.max_value > el.min_value { el.max_value } else { el.min_value }
	slider_set_number(view, 'minimumValue', el.min_value)
	slider_set_number(view, 'maximumValue', maximum)
	slider_set_number(view, 'value', slider_clamped_value(el.value, el.min_value, el.max_value))
	macos.msg_void_bool(view, 'setContinuous:', true)
	minimum_track_color := if el.value_track {
		el.slider_style.value_track_color
	} else {
		el.slider_style.track_color
	}
	macos.msg_void1(view, 'setMinimumTrackTintColor:', ios.color(minimum_track_color))
	macos.msg_void1(view, 'setMaximumTrackTintColor:', ios.color(el.slider_style.track_color))
	macos.msg_void1(view, 'setThumbTintColor:', ios.color(el.slider_style.thumb_color))
}

fn native_snap_slider_value(view View, spec SliderSpec) f64 {
	raw := slider_number_value(view, 'value')
	normalized := slider_value_normalized(raw, spec.min, spec.max)
	value := slider_value_from_normalized(normalized, spec.min, spec.max, spec.step)
	if value != raw {
		slider_set_number(view, 'value', value)
	}
	return value
}

fn new_text_field_view(frame Rect, placeholder string, t string, box BoxStyle, text_hex u32, size f64, keyboard int, secure bool) View {
	field := macos.msg_id_rect(macos.alloc('UITextField'), 'initWithFrame:', native_rect(frame))
	update_text_field_view(field, frame, placeholder, t, box, text_hex, size, keyboard, secure, true, true, 12, false, true)
	return field
}

fn update_text_field_view(field View, frame Rect, placeholder string, t string, box BoxStyle, text_hex u32, size f64, keyboard int, secure bool, autocorrect bool, declared_text_changed bool, padding_left f64, readonly bool, enabled bool) {
	macos.msg_void_rect(field, 'setFrame:', native_rect(frame))
	set_box_background(field, box)
	macos.msg_void1(field, 'setTextColor:', ios.color(text_hex))
	macos.msg_void1(field, 'setFont:', font(size, 400))
	macos.msg_void1(field, 'setPlaceholder:', macos.nsstring(placeholder))
	if declared_text_changed && macos.utf8_string(macos.msg_id(field, 'text')) != t {
		macos.msg_void1(field, 'setText:', macos.nsstring(t))
	}
	macos.msg_void_i64(field, 'setKeyboardType:', i64(keyboard))
	if macos.msg_bool(field, 'isSecureTextEntry') != secure {
		macos.msg_void_bool(field, 'setSecureTextEntry:', secure)
	}
	macos.msg_void_i64(field, 'setAutocorrectionType:', if autocorrect { i64(0) } else { i64(1) })
	macos.msg_void_bool(field, 'setEnabled:', enabled && !readonly)
	macos.msg_void_i64(field, 'setClearButtonMode:', 1)
	set_corner_radius(field, box.radius)
	mut pad := macos.msg_id(field, 'leftView')
	if pad == unsafe { nil } {
		pad = macos.msg_id_rect(macos.alloc('UIView'), 'initWithFrame:', macos.rect(0, 0, padding_left, frame.height))
		macos.msg_void1(field, 'setLeftView:', pad)
		macos.release(pad)
	} else {
		macos.msg_void_rect(pad, 'setFrame:', macos.rect(0, 0, padding_left, frame.height))
	}
	macos.msg_void_i64(field, 'setLeftViewMode:', 3)
}

// ── Runtime class registration ─────────────────────────────────────

fn ensure_runtime_classes() {
	if macos.get_class('VuiAppDelegate') == unsafe { nil } {
		cls := macos.allocate_class_pair(macos.get_class('UIResponder'), 'VuiAppDelegate')
		macos.add_protocol(cls, macos.get_protocol('UIApplicationDelegate'))
		macos.add_method(cls, 'application:didFinishLaunchingWithOptions:', voidptr(C.vui_app_did_finish_launching), 'B@:@@')
		// A dropdown's UICommand sends its selector up the responder chain,
		// which ends at the application delegate.
		macos.add_method(cls, 'vuiDropdownSelected:', voidptr(C.vui_dropdown_selected), 'v@:@')
		macos.register_class_pair(cls)
	}
	if macos.get_class('VuiButtonHandler') == unsafe { nil } {
		cls := macos.allocate_class_pair(macos.get_class('NSObject'), 'VuiButtonHandler')
		macos.add_protocol(cls, macos.get_protocol('UIGestureRecognizerDelegate'))
		macos.add_method(cls, 'handleTap:', voidptr(C.vui_button_tap), 'v@:@')
		macos.add_method(cls, 'handleViewTap:', voidptr(C.vui_view_tap), 'v@:@')
		macos.add_method(cls, 'gestureRecognizer:shouldReceiveTouch:',
			voidptr(C.vui_view_tap_should_receive), 'B@:@@')
		macos.add_method(cls, 'handleTextChange:', voidptr(C.vui_text_field_changed), 'v@:@')
		macos.add_method(cls, 'handleTextSubmit:', voidptr(C.vui_text_field_submitted), 'v@:@')
		macos.add_method(cls, 'textViewDidChange:', voidptr(C.vui_text_view_changed), 'v@:@')
		macos.add_protocol(cls, macos.get_protocol('UIScrollViewDelegate'))
		macos.add_method(cls, 'scrollViewDidScroll:', voidptr(C.vui_scroll_did_scroll), 'v@:@')
		macos.add_method(cls, 'vuiRefresh:', voidptr(C.vui_request_refresh), 'v@:@')
		macos.register_class_pair(cls)
	}
	if macos.get_class('VuiButtonBehaviorView') == unsafe { nil } {
		cls := macos.allocate_class_pair(macos.get_class('UIView'), 'VuiButtonBehaviorView')
		macos.add_method(cls, 'accessibilityActivate',
			voidptr(C.vui_button_behavior_accessibility_activate), 'B@:')
		macos.register_class_pair(cls)
	}
	if macos.get_class('VuiLongPressHandler') == unsafe { nil } {
		cls := macos.allocate_class_pair(macos.get_class('NSObject'), 'VuiLongPressHandler')
		macos.add_protocol(cls, macos.get_protocol('UIGestureRecognizerDelegate'))
		macos.add_method(cls, 'gestureRecognizer:shouldReceiveTouch:', voidptr(C.vui_gesture_should_receive), 'B@:@@')
		macos.add_method(cls, 'handleLongPress:', voidptr(C.vui_button_long_press), 'v@:@')
		macos.register_class_pair(cls)
	}
	if macos.get_class('VuiSwipeHandler') == unsafe { nil } {
		cls := macos.allocate_class_pair(macos.get_class('NSObject'), 'VuiSwipeHandler')
		macos.add_protocol(cls, macos.get_protocol('UIGestureRecognizerDelegate'))
		macos.add_method(cls, 'handleSwipe:', voidptr(C.vui_swipe_left), 'v@:@')
		macos.add_method(cls, 'gestureRecognizer:shouldReceiveTouch:', voidptr(C.vui_gesture_should_receive), 'B@:@@')
		macos.add_method(cls, 'gestureRecognizerShouldBegin:', voidptr(C.vui_swipe_should_begin), 'B@:@')
		macos.add_method(cls, 'gestureRecognizer:shouldRecognizeSimultaneouslyWithGestureRecognizer:', voidptr(C.vui_swipe_should_recognize_simultaneously), 'B@:@@')
		macos.register_class_pair(cls)
	}
}

// ── Association keys ───────────────────────────────────────────────

fn assoc_window_key() voidptr {
	return voidptr(C.vui_app_did_finish_launching)
}

fn assoc_handler_key() voidptr {
	return voidptr(C.vui_button_tap)
}

fn assoc_long_handler_key() voidptr {
	return voidptr(C.vui_button_long_press)
}

fn assoc_swipe_handler_key() voidptr {
	return voidptr(C.vui_swipe_left)
}

// ── Rendering ──────────────────────────────────────────────────────

fn align_value(a Align) int {
	return match a {
		.left { 0 }
		.center { 1 }
		.right { 2 }
	}
}

fn (mut w Window) remember(id string, native View) {
	if id.len > 0 {
		w.views[id] = native
	}
}

fn (mut w Window) remember_scroll_offsets() {
	for id, _ in w.scroll_ids {
		view := w.views[id] or { continue }
		offset := scroll_content_offset(view)
		w.scroll_offsets[id] = offset.y
		w.scroll_offsets_x[id] = offset.x
	}
}

pub fn (mut w Window) refresh_element(id string, element Element) {
	w.layout_tree.patch(id, element) or { eprintln('ui2 layout: ${err}'); return }
	w.render_mounted_layout()
}

pub fn (mut w Window) layout_stats() LayoutStats { return w.layout_tree.stats() }

pub fn (mut w Window) invalidate_layout_environment(environment LayoutEnvironment) {
	w.layout_environment = environment
	if w.layout_tree.root.len > 0 { w.render_mounted_layout() }
}

fn (mut w Window) render_root(declared Element) {
	w.layout_tree.replace(declared) or { eprintln('ui2 layout: ${err}'); return }
	root := w.layout_tree.resolve(LayoutConstraints{}, measure_layout_text, w.layout_environment) or { eprintln('ui2 layout: ${err}'); return }
	w.render_resolved_root(root)
}

fn (mut w Window) render_mounted_layout() {
	root := w.layout_tree.resolve(LayoutConstraints{}, measure_layout_text, w.layout_environment) or { eprintln('ui2 layout: ${err}'); return }
	w.render_resolved_root(root)
}

fn (mut w Window) render_resolved_root(root Element) {
	previous_focus := w.focused_id()
	previous_responder := w.views[previous_focus] or { objc_nil() }
	// Stale-node removal can release the previous responder.
	if !objc_is_nil(previous_responder) { macos.retain(previous_responder) }
	defer { if !objc_is_nil(previous_responder) { macos.release(previous_responder) } }
	w.remember_scroll_offsets()
	w.views = map[string]View{}
	w.view_kinds = map[string]Kind{}
	w.label_places = map[string]LabelPlacement{}
	w.action_callbacks = map[u64]IosCallbackBinding{}
	w.button_behavior_views = map[u64]bool{}
	w.text_change_callbacks = map[u64]IosCallbackBinding{}
	w.text_submit_callbacks = map[u64]IosCallbackBinding{}
	w.text_area_callbacks = map[u64]IosCallbackBinding{}
	w.slider_specs = map[u64]SliderSpec{}
	w.toggle_groups = map[u64]string{}
	w.toggle_allow_no_selection = map[u64]bool{}
	w.toggle_ids = map[u64]string{}
	w.toggle_views = map[u64]View{}
	w.scroll_ids = map[string]bool{}
	w.scroll_callbacks = map[u64]IosCallbackBinding{}
	set_box_background(w.root_view, root.box)
	mut active := map[string]bool{}
	w.render_children(w.root_view, root.children, '', mut active)
	w.remove_stale_nodes(active)
	w.ios_navigation.set_root(root)
	w.ios_navigation.current = previous_focus
	w.sync_focus_navigation()
	if w.ios_navigation.current.len > 0 {
		if w.focused_id() != w.ios_navigation.current { w.focus(w.ios_navigation.current) }
	} else if !objc_is_nil(previous_responder) {
		macos.msg_bool(previous_responder, 'resignFirstResponder')
	}
	mut removed_scrolls := []string{}
	for id, _ in w.scroll_offsets {
		if id !in w.scroll_ids {
			removed_scrolls << id
		}
	}
	for id in removed_scrolls {
		w.scroll_offsets.delete(id)
		w.scroll_offsets_x.delete(id)
	}
}

fn gesture_signature(el Element) string {
	button_behavior := el.kind == .view && el.button_behavior
	has_gesture := button_behavior || el.long_press || el.swipe_left
	return '${has_gesture && el.on_event != unsafe { nil }}:${button_behavior}:${el.long_press}:${el.swipe_left}'
}

fn (mut w Window) attach_view_gestures(native View, binding IosCallbackBinding, button_behavior bool, long_press bool, swipe_left bool) {
	if !ios_callback_present(binding) { return }
	w.action_callbacks[u64(native)] = binding
	if button_behavior {
		w.button_behavior_views[u64(native)] = true
		add_view_tap_target(native, w.button_handler)
		macos.set_associated_object(native, assoc_handler_key(), w.button_handler,
			macos.assoc_retain_nonatomic)
	}
	if long_press {
		add_long_press_target(native, w.long_press_handler)
		macos.set_associated_object(native, assoc_long_handler_key(), w.long_press_handler, macos.assoc_retain_nonatomic)
	}
	if swipe_left {
		add_swipe_left_target(native, w.swipe_handler)
		macos.set_associated_object(native, assoc_swipe_handler_key(), w.swipe_handler, macos.assoc_retain_nonatomic)
	}
}

fn (mut w Window) render_children(parent View, children []Element, parent_key string, mut active map[string]bool) {
	for index, child in children {
		native := w.render_element(parent, child, reconciliation_child_key(parent_key, index, child), mut active)
		if child.kind == .screen {
			continue
		}
		// UIKit moves an existing child to the end, reconciling visual and hit-test order.
		macos.msg_void1(parent, 'addSubview:', native)
	}
}

fn native_create_element(el Element) View {
	return match el.kind {
		.screen { View(unsafe { nil }) }
		.view { new_native_view(el.frame, el.box, el.button_behavior) }
		.scroll { new_scroll_view(el.frame, el.box) }
		.label {
			new_label_view(el.frame, el.text, el.text_style.color, el.text_style.size, text_style_weight(el.text_style), align_value(el.text_style.align), text_line_budget(el.text_style.lines), el.text_style.valign, label_needs_container(el))
		}
		.image { new_image_view(el.frame, el.image_path, el.text_style.color) }
		.button {
			new_button_view(el.frame, el.text, el.box, el.text_style.color, el.text_style.size, text_style_weight(el.text_style), text_line_budget(el.text_style.lines))
		}
		.checkbox { new_checkbox_view(el) }
		.switch_control { new_switch_control_view(el) }
		.toggle_button { new_toggle_button_view(el) }
		.dropdown { new_dropdown_view(el) }
		.text_field {
			field := new_text_field_view(el.frame, el.placeholder, el.text, el.box, el.text_style.color, el.text_style.size, el.keyboard, el.secure)
			update_text_field_view(field, el.frame, el.placeholder, el.text, el.box, el.text_style.color, el.text_style.size, el.keyboard, el.secure, el.autocorrect, true, el.padding_left, el.readonly, el.enabled)
			field
		}
		.text_area { new_text_area_view(el) }
		.slider { new_slider_view(el) }
	}
}

fn native_update_element(native View, el Element, declared_text_changed bool) {
	match el.kind {
		.screen {}
		.view {
			macos.msg_void_rect(native, 'setFrame:', native_rect(el.frame))
			set_box_background(native, el.box)
			set_box_corners(native, el.box)
		}
		.scroll {
			macos.msg_void_rect(native, 'setFrame:', native_rect(el.frame))
			set_box_background(native, el.box)
			set_corner_radius(native, el.box.radius)
		}
		.label {
			update_label_view(native, el.frame, el.text, el.text_style.color, el.text_style.size, text_style_weight(el.text_style), align_value(el.text_style.align), text_line_budget(el.text_style.lines), el.text_style.valign, label_needs_container(el))
		}
		.image { update_image_view(native, el.frame, el.image_path, el.text_style.color) }
		.button {
			update_button_view(native, el.frame, el.text, el.box, el.text_style.color, el.text_style.size, text_style_weight(el.text_style), text_line_budget(el.text_style.lines))
		}
		.checkbox { update_checkbox_view(native, el) }
		.switch_control { update_switch_control_view(native, el) }
		.toggle_button { update_toggle_button_view(native, el) }
		.dropdown { update_dropdown_view(native, el, declared_text_changed) }
		.text_field {
			update_text_field_view(native, el.frame, el.placeholder, el.text, el.box, el.text_style.color, el.text_style.size, el.keyboard, el.secure, el.autocorrect, declared_text_changed, el.padding_left, el.readonly, el.enabled)
		}
		.text_area { update_text_area_view(native, el, declared_text_changed) }
		.slider { update_slider_view(native, el) }
	}
}

fn (mut w Window) reparent_direct_children(key string, new_parent View) {
	prefix := key + '/'
	for child_key_, child in w.nodes {
		if child_key_.starts_with(prefix) && !child_key_[prefix.len..].contains('/') {
			macos.msg_void1(new_parent, 'addSubview:', child)
		}
	}
}

fn (mut w Window) forget_descendant_nodes(key string) {
	prefix := key + '/'
	mut descendants := []string{}
	for child_key_, _ in w.nodes {
		if child_key_.starts_with(prefix) {
			descendants << child_key_
		}
	}
	for child_key_ in descendants {
		child := w.nodes[child_key_] or { continue }
		w.clear_ios_gesture_captures(u64(child))
		w.control_captures.delete(u64(child))
		w.action_callbacks.delete(u64(child))
		w.text_change_callbacks.delete(u64(child))
		w.text_submit_callbacks.delete(u64(child))
		w.text_area_callbacks.delete(u64(child))
		w.scroll_callbacks.delete(u64(child))
		w.slider_specs.delete(u64(child))
		w.toggle_groups.delete(u64(child))
		w.toggle_allow_no_selection.delete(u64(child))
		w.toggle_ids.delete(u64(child))
		w.toggle_views.delete(u64(child))
		w.view_translation_x.delete(voidptr(child))
		w.nodes.delete(child_key_)
		w.node_kinds.delete(child_key_)
		w.node_gestures.delete(child_key_)
		w.node_label_boxed.delete(child_key_)
		w.node_declared_text.delete(child_key_)
	}
}

fn (mut w Window) register_native_handlers(native View, el Element) {
	if el.kind in [.button, .checkbox, .toggle_button, .slider, .switch_control, .dropdown] {
		C.ui2_ios_install_control_tracking(native)
	}
	pointer := u64(native)
	if el.kind == .scroll {
		w.scroll_callbacks[pointer] = ios_binding(el, .scroll)
		macos.msg_void1(native, 'setDelegate:', w.button_handler)
	}
	has_callback := el.on_event != unsafe { nil }
	if has_callback && el.kind in [.view, .button]
		&& (el.button_behavior || el.long_press || el.swipe_left) {
		w.action_callbacks[pointer] = ios_binding(el, if el.kind in [.view, .button] {
			.click
		} else {
			.change
		})
		if el.kind == .view && el.button_behavior {
			w.button_behavior_views[pointer] = true
		}
	}
	if el.kind == .slider {
		remove_control_target_action(native, w.button_handler, 'handleTap:', 131072)
		w.slider_specs[pointer] = slider_spec(el)
		if has_callback {
			w.action_callbacks[pointer] = ios_binding(el, if el.kind in [.view, .button] {
				.click
			} else {
				.change
			})
			add_control_target_action(native, w.button_handler, 'handleTap:', 131072)
			macos.set_associated_object(native, assoc_handler_key(), w.button_handler, macos.assoc_retain_nonatomic)
		} else {
			macos.set_associated_object(native, assoc_handler_key(), View(unsafe { nil }), macos.assoc_retain_nonatomic)
		}
	} else if el.kind == .switch_control {
		remove_control_target_action(native, w.button_handler, 'handleTap:', 131072)
		if has_callback {
			w.action_callbacks[pointer] = ios_binding(el, if el.kind in [.view, .button] {
				.click
			} else {
				.change
			})
			add_control_target_action(native, w.button_handler, 'handleTap:', 131072)
			macos.set_associated_object(native, assoc_handler_key(), w.button_handler, macos.assoc_retain_nonatomic)
		} else {
			macos.set_associated_object(native, assoc_handler_key(), View(unsafe { nil }), macos.assoc_retain_nonatomic)
		}
	} else if el.kind in [.button, .checkbox, .toggle_button] {
		remove_control_target_action(native, w.button_handler, 'handleTap:', 64)
		if el.kind == .toggle_button {
			w.toggle_groups[pointer] = el.toggle_group()
			w.toggle_allow_no_selection[pointer] = el.toggle_allow_no_selection()
			w.toggle_ids[pointer] = el.id
			w.toggle_views[pointer] = native
			if macos.msg_bool(native, 'isSelected') {
				w.release_ios_toggle_group(pointer)
			}
		}
		if has_callback || el.kind in [.checkbox, .toggle_button] {
			w.action_callbacks[pointer] = ios_binding(el, if el.kind == .button { .click } else { .change })
			add_button_target(native, w.button_handler)
			macos.set_associated_object(native, assoc_handler_key(), w.button_handler, macos.assoc_retain_nonatomic)
		} else {
			macos.set_associated_object(native, assoc_handler_key(), View(unsafe { nil }), macos.assoc_retain_nonatomic)
		}
	} else if el.kind == .dropdown {
		remove_control_target_action(native, w.button_handler, 'handleTap:', 64)
		// Opening a UIMenu is not a value change. UICommand selection owns the
		// state commit and optional callback, including controls without one.
		w.action_callbacks[pointer] = ios_binding(el, .change)
		macos.set_associated_object(native, assoc_handler_key(), View(unsafe { nil }), macos.assoc_retain_nonatomic)
	} else if el.kind == .text_field {
		remove_control_target_action(native, w.button_handler, 'handleTextChange:', 131072)
		remove_control_target_action(native, w.button_handler, 'handleTextSubmit:', 524288)
		if has_callback {
			w.text_change_callbacks[pointer] = ios_binding(el, .change)
			add_control_target_action(native, w.button_handler, 'handleTextChange:', 131072)
		}
		if has_callback {
			w.text_submit_callbacks[pointer] = ios_binding(el, .submit)
			add_control_target_action(native, w.button_handler, 'handleTextSubmit:', 524288)
		}
		if has_callback {
			macos.set_associated_object(native, assoc_handler_key(), w.button_handler, macos.assoc_retain_nonatomic)
		} else {
			macos.set_associated_object(native, assoc_handler_key(), View(unsafe { nil }), macos.assoc_retain_nonatomic)
		}
	} else if el.kind == .text_area {
		if has_callback {
			w.text_area_callbacks[pointer] = ios_binding(el, .change)
			macos.msg_void1(native, 'setDelegate:', w.button_handler)
		} else {
			macos.msg_void1(native, 'setDelegate:', View(unsafe { nil }))
		}
	}
}

fn (mut w Window) render_element(parent View, el Element, key string, mut active map[string]bool) View {
	active[key] = true
	if el.kind == .screen {
		set_box_background(parent, el.box)
		w.render_children(parent, el.children, key, mut active)
		return parent
	}
	mut native := w.nodes[key] or { View(unsafe { nil }) }
	existing_kind := w.node_kinds[key] or { Kind.screen }
	old_gestures := w.node_gestures[key] or { '' }
	new_gestures := gesture_signature(el)
	gesture_changed := existing_kind == el.kind && el.kind in [.view, .button]
		&& old_gestures != new_gestures
	// Whether a label is held in a view is decided when it is made, so gaining or
	// losing a border, a tooltip or a menu has to make it again. Reusing it would
	// leave the backend sending setText: to a plain view, which it cannot answer.
	label_boxed_changed := el.kind == .label && existing_kind == .label
		&& (w.node_label_boxed[key] or { false }) != label_needs_container(el)
	created := native == unsafe { nil } || existing_kind != el.kind || gesture_changed
		|| label_boxed_changed
	declared_text_changed := key !in w.node_declared_text || (w.node_declared_text[key] or { '' }) != el.text
	if created {
		old_native := native
		can_reparent := old_native != unsafe { nil } && existing_kind in [.view, .scroll]
			&& el.kind in [.view, .scroll]
		native = native_create_element(el)
		w.nodes[key] = native
		w.node_kinds[key] = el.kind
		w.node_gestures[key] = new_gestures
		w.node_label_boxed[key] = label_needs_container(el)
		macos.msg_void1(parent, 'addSubview:', native)
		if can_reparent {
			w.reparent_direct_children(key, native)
		} else if old_native != unsafe { nil } {
			w.forget_descendant_nodes(key)
		}
		macos.release(native)
		if old_native != unsafe { nil } {
			w.view_translation_x.delete(voidptr(old_native))
			macos.msg_void(old_native, 'removeFromSuperview')
		}
		if (el.kind == .view && el.button_behavior) || el.long_press || el.swipe_left {
			w.attach_view_gestures(native, ios_binding(el, .click), el.kind == .view
				&& el.button_behavior, el.long_press, el.swipe_left)
		}
	} else {
		native_update_element(native, el, declared_text_changed)
	}
	border_box := if el.kind == .toggle_button && el.checked {
		el.toggle_down_box()
	} else {
		el.box
	}
	set_box_borders(native, border_box)

	match el.kind {
		.screen {}
		.view { w.render_children(native, el.children, key, mut active) }
		.scroll {
			w.render_children(native, el.children, key, mut active)
			mut content_h := f64(0)
			for child in el.children {
				bottom := child.frame.y + child.frame.height
				if bottom > content_h {
					content_h = bottom
				}
			}
			// An axis the mode leaves out is held to the frame, so nothing along it scrolls.
			content_w := scroll_content_width(el.children)
			width := if el.scroll_mode != .vertical_only && content_w > el.frame.width {
				content_w
			} else {
				el.frame.width
			}
			height := if el.scroll_mode != .horizontal_only { content_h + 16 } else { el.frame.height }
			macos.msg_void_rect(native, 'setContentSize:', macos.rect(width, height, 0, 0))
			macos.msg_void_bool(native, 'setAlwaysBounceVertical:', el.scroll_mode != .horizontal_only)
			// Where the view should be: where it is, or where it was before it was
			// rebuilt. A view that is kept keeps its offset through a change of mode, and
			// shrinking its content does not bring it back, so the part of either along an
			// axis the mode no longer scrolls is dropped here.
			current := scroll_content_offset(native)
			mut wanted_x := current.x
			mut wanted_y := current.y
			if el.id.len > 0 {
				if created && el.id in w.scroll_offsets {
					wanted_x = w.scroll_offsets_x[el.id] or { 0.0 }
					wanted_y = w.scroll_offsets[el.id]
				}
				w.scroll_ids[el.id] = true
			}
			offset_x, offset_y := scroll_mode_offset(el.scroll_mode, wanted_x, wanted_y)
			if offset_x != current.x || offset_y != current.y {
				set_scroll_content_offset(native, offset_x, offset_y)
			}
		}
		else {}
	}

	w.register_native_handlers(native, el)
	native_apply_common_view_state(native, el.hidden, el.enabled, el.accessibility_role, el.accessibility_label, el.accessibility_value)
	if el.id.len > 0 {
		w.remember(el.id, native)
		w.view_kinds[el.id] = el.kind
		if el.kind == .label {
			w.label_places[el.id] = LabelPlacement{
				frame:  el.frame
				lines:  text_line_budget(el.text_style.lines)
				valign: el.text_style.valign
				boxed:  label_needs_container(el)
			}
		}
	}
	w.node_declared_text[key] = el.text
	return native
}

fn (mut w Window) remove_stale_nodes(active map[string]bool) {
	mut stale := []string{}
	mut stale_set := map[string]bool{}
	for key, _ in w.nodes {
		if key !in active {
			stale << key
			stale_set[key] = true
		}
	}
	for key in stale {
		native := w.nodes[key] or { continue }
		if !node_has_ancestor_in_set(key, stale_set) {
			macos.msg_void(native, 'removeFromSuperview')
		}
		w.clear_ios_gesture_captures(u64(native))
		w.control_captures.delete(u64(native))
		w.action_callbacks.delete(u64(native))
		w.text_change_callbacks.delete(u64(native))
		w.text_submit_callbacks.delete(u64(native))
		w.text_area_callbacks.delete(u64(native))
		w.scroll_callbacks.delete(u64(native))
		w.slider_specs.delete(u64(native))
		w.toggle_groups.delete(u64(native))
		w.toggle_allow_no_selection.delete(u64(native))
		w.toggle_ids.delete(u64(native))
		w.toggle_views.delete(u64(native))
		w.view_translation_x.delete(voidptr(native))
		w.nodes.delete(key)
		w.node_kinds.delete(key)
		w.node_gestures.delete(key)
		w.node_label_boxed.delete(key)
		w.node_declared_text.delete(key)
	}
}

fn node_has_ancestor_in_set(key string, keys map[string]bool) bool {
	mut ancestor := key
	for {
		slash := ancestor.last_index('/') or { return false }
		ancestor = ancestor[..slash]
		if ancestor in keys {
			return true
		}
	}
	return false
}

// ── App lifecycle ──────────────────────────────────────────────────

@[export: 'vui_app_did_finish_launching']
fn vui_app_did_finish_launching(self voidptr, _cmd voidptr, _application voidptr, _launch_options voidptr) bool {
	mut w := ios_window() or { return true }
	b := ios_screen_bounds()
	w.window = macos.msg_id_rect(macos.alloc('UIWindow'), 'initWithFrame:', macos.rect(b.x, b.y, b.width, b.height))
	w.root_vc = macos.msg_id(macos.alloc('UIViewController'), 'init')
	w.root_view = macos.msg_id(w.root_vc, 'view')
	if w.button_handler == unsafe { nil } {
		w.button_handler = macos.msg_id(macos.alloc('VuiButtonHandler'), 'init')
	}
	if w.long_press_handler == unsafe { nil } {
		w.long_press_handler = macos.msg_id(macos.alloc('VuiLongPressHandler'), 'init')
	}
	if w.swipe_handler == unsafe { nil } {
		w.swipe_handler = macos.msg_id(macos.alloc('VuiSwipeHandler'), 'init')
	}
	macos.msg_void1(w.window, 'setRootViewController:', w.root_vc)
	macos.msg_void(w.window, 'makeKeyAndVisible')
	macos.set_associated_object(View(self), assoc_window_key(), w.window, macos.assoc_retain_nonatomic)
	w.rebuild_now()
	return true
}

// ── Event handlers ─────────────────────────────────────────────────

fn (mut w Window) clear_ios_gesture_captures(owner u64) {
	mut removed := []u64{}
	for gesture, captured_owner in w.gesture_capture_owners {
		if captured_owner == owner { removed << gesture }
	}
	for gesture in removed {
		w.gesture_captures.delete(gesture)
		w.gesture_capture_owners.delete(gesture)
	}
}

fn ios_control_release_binding(captured IosCallbackBinding, current IosCallbackBinding, available bool) ?IosCallbackBinding {
	if !available || captured.kind != current.kind {
		return none
	}
	if ios_callback_present(captured) && ios_callback_present(current) { return captured }
	// Stateful controls also commit with no handler. Installing or removing a
	// handler during a physical press still cancels that captured activation.
	if !ios_callback_present(captured) && !ios_callback_present(current)
		&& captured.kind in [.checkbox, .toggle_button, .dropdown] { return captured }
	return none
}

fn ios_interaction_available(native View) bool {
	if objc_is_nil(native) { return false }
	if objc_is_kind_of(native, 'UIControl') && !macos.msg_bool(native, 'isEnabled') { return false }
	mut ancestor := native
	for !objc_is_nil(ancestor) {
		if macos.msg_bool(ancestor, 'isHidden') || !macos.msg_bool(ancestor, 'isUserInteractionEnabled') {
			return false
		}
		ancestor = macos.msg_id(ancestor, 'superview')
	}
	return true
}

fn (mut w Window) ios_control_action_binding(native View, current IosCallbackBinding) ?IosCallbackBinding {
	if !ios_interaction_available(native) { return none }
	if captured := w.control_captures[u64(native)] {
		return ios_control_release_binding(captured, current,
			ios_interaction_available(native))
	}
	return current
}

@[export: 'vui_control_tracking_begin']
fn vui_control_tracking_begin(control voidptr) {
	mut w := ios_window() or { return }
	pointer := u64(control)
	captured := w.control_captures[pointer] or { IosCallbackBinding{} }
	if pointer !in w.control_captures || captured.kind == .dropdown {
		w.control_captures[pointer] = w.action_callbacks[pointer] or { IosCallbackBinding{} }
	}
}

@[export: 'vui_control_tracking_end']
fn vui_control_tracking_end(control voidptr) {
	mut w := ios_window() or { return }
	pointer := u64(control)
	// A dropdown's native menu outlives UIControl tracking. Its command consumes
	// this snapshot; cancellation or a new press replaces it.
	binding := w.control_captures[pointer] or { return }
	if binding.kind != .dropdown { w.control_captures.delete(pointer) }
}

@[export: 'vui_control_tracking_cancel']
fn vui_control_tracking_cancel(control voidptr) {
	mut w := ios_window() or { return }
	w.control_captures.delete(u64(control))
}

fn ios_control_event(native View, binding IosCallbackBinding) ElementEvent {
	return match binding.kind {
		.text_field, .text_area {
			ElementEvent{ kind: binding.event, text: objc_string(macos.msg_id(native, 'text')) }
		}
		.dropdown {
			ElementEvent{ kind: .change, text: objc_string(macos.msg_id(native, 'currentTitle')) }
		}
		.slider { ElementEvent{ kind: .change, value: slider_number_value(native, 'value') } }
		.switch_control { ElementEvent{ kind: .change, checked: macos.msg_bool(native, 'isOn') } }
		.checkbox, .toggle_button {
			ElementEvent{ kind: .change, checked: macos.msg_bool(native, 'isSelected') }
		}
		else { ElementEvent{ kind: binding.event } }
	}
}

@[export: 'vui_button_tap']
fn vui_button_tap(_self voidptr, _cmd voidptr, sender voidptr) {
	mut w := ios_window() or { return }
	pointer := u64(sender)
	native := View(sender)
	current := w.action_callbacks[pointer] or { return }
	if current.kind == .dropdown { return }
	binding := w.ios_control_action_binding(native, current) or { return }
	w.commit_ios_button_activation(native, current.kind)
	w.ios_emit_callback(binding, ios_control_event(native, binding))
}

fn (mut w Window) commit_ios_button_activation(native View, kind Kind) {
	pointer := u64(native)
	if kind == .toggle_button { w.commit_ios_toggle_button(pointer, native) }
	if spec := w.slider_specs[pointer] { native_snap_slider_value(native, spec) }
	if kind == .checkbox {
		checked := !macos.msg_bool(native, 'isSelected')
		macos.msg_void_bool(native, 'setSelected:', checked)
		caption := objc_string(macos.msg_id(native, 'currentTitle')).all_after('  ')
		title := '${if checked { '☑' } else { '☐' }}  ${caption}'
		macos.msg_void2(native, 'setTitle:forState:', macos.nsstring(title), macos.Id(uint(0)))
	}
}

fn ios_button_behavior_release_available(captured IosCallbackBinding, current IosCallbackBinding, registered bool, enabled bool, hidden bool, inside bool) bool {
	return ios_callback_present(captured) && ios_callback_present(current) && registered && enabled && !hidden && inside
}

fn ios_button_behavior_capture_binding(captured IosCallbackBinding, current IosCallbackBinding, active_touches u64, accepted bool) IosCallbackBinding {
	if active_touches > 0 { return captured }
	return if accepted { current } else { IosCallbackBinding{} }
}

@[export: 'vui_view_tap']
fn vui_view_tap(_self voidptr, _cmd voidptr, sender voidptr) {
	mut w := ios_window() or { return }
	gesture := View(sender)
	gesture_key := u64(sender)
	captured := w.gesture_captures[gesture_key] or { IosCallbackBinding{} }
	w.gesture_captures.delete(gesture_key)
	w.gesture_capture_owners.delete(gesture_key)
	if gesture_state(gesture) != gesture_state_ended { return }
	view := gesture_view(gesture)
	pointer := u64(view)
	current := w.action_callbacks[pointer] or { IosCallbackBinding{} }
	view_bounds := macos.msg_rect(view, 'bounds')
	location := gesture_location(gesture, view)
	inside := location.x >= view_bounds.x && location.x <= view_bounds.x + view_bounds.width
		&& location.y >= view_bounds.y && location.y <= view_bounds.y + view_bounds.height
	if ios_button_behavior_release_available(captured, current, w.button_behavior_views[pointer] or { false },
		macos.msg_bool(view, 'isUserInteractionEnabled'), macos.msg_bool(view, 'isHidden'), inside) {
		w.ios_emit_callback(captured, ElementEvent{ kind: .click })
	}
}

@[export: 'vui_view_tap_should_receive']
fn vui_view_tap_should_receive(_self voidptr, _cmd voidptr, sender voidptr, touch voidptr) bool {
	mut w := ios_window() or { return false }
	gesture := View(sender)
	active_touches := macos.msg_u64(gesture, 'numberOfTouches')
	owner := gesture_view(gesture)
	mut accepted := true
	mut target := macos.msg_id(View(touch), 'view')
	for target != unsafe { nil } && target != owner {
		if macos.msg_bool_id(target, 'isKindOfClass:', macos.get_class('UIControl'))
			|| macos.msg_bool_id(target, 'isKindOfClass:', macos.get_class('UIScrollView'))
			|| (w.button_behavior_views[u64(target)] or { false }) {
			accepted = false
			break
		}
		target = macos.msg_id(target, 'superview')
	}
	pointer := u64(owner)
	current := w.action_callbacks[pointer] or { IosCallbackBinding{} }
	if !ios_callback_present(current) || !(w.button_behavior_views[pointer] or { false }) {
		accepted = false
	}
	return w.ios_capture_gesture_callback(u64(sender), pointer, current, active_touches, accepted)
}

fn (mut w Window) ios_clear_gesture_capture(gesture u64) {
	w.gesture_captures.delete(gesture)
	w.gesture_capture_owners.delete(gesture)
}

fn (mut w Window) ios_capture_gesture_callback(gesture u64, owner u64, current IosCallbackBinding, active_touches u64, accepted bool) bool {
	captured := w.gesture_captures[gesture] or { IosCallbackBinding{} }
	next := ios_button_behavior_capture_binding(captured, current, active_touches, accepted)
	if ios_callback_present(next) {
		w.gesture_captures[gesture] = next
		w.gesture_capture_owners[gesture] = owner
	} else {
		w.ios_clear_gesture_capture(gesture)
	}
	return accepted
}

@[export: 'vui_gesture_should_receive']
fn vui_gesture_should_receive(_self voidptr, _cmd voidptr, sender voidptr, _touch voidptr) bool {
	mut w := ios_window() or { return false }
	gesture := View(sender)
	owner := gesture_view(gesture)
	current := w.action_callbacks[u64(owner)] or { IosCallbackBinding{} }
	return w.ios_capture_gesture_callback(u64(sender), u64(owner), current,
		macos.msg_u64(gesture, 'numberOfTouches'), ios_callback_present(current) && ios_interaction_available(owner))
}

@[export: 'vui_button_behavior_accessibility_activate']
fn vui_button_behavior_accessibility_activate(self voidptr, _cmd voidptr) bool {
	mut w := ios_window() or { return false }
	if !macos.msg_bool(View(self), 'isUserInteractionEnabled') || macos.msg_bool(View(self), 'isHidden') {
		return false
	}
	binding := w.action_callbacks[u64(self)] or { return false }
	return w.ios_emit_callback(binding, ElementEvent{ kind: .click })
}

@[export: 'vui_request_refresh']
fn vui_request_refresh(_self voidptr, _cmd voidptr, _sender voidptr) {
	mut w := ios_window() or { return }
	w.rebuild_now()
}

@[export: 'vui_text_field_changed']
fn vui_text_field_changed(_self voidptr, _cmd voidptr, sender voidptr) {
	mut w := ios_window() or { return }
	binding := w.text_change_callbacks[u64(sender)] or { return }
	w.ios_emit_callback(binding, ios_control_event(View(sender), binding))
}

@[export: 'vui_text_field_submitted']
fn vui_text_field_submitted(_self voidptr, _cmd voidptr, sender voidptr) {
	mut w := ios_window() or { return }
	binding := w.text_submit_callbacks[u64(sender)] or { return }
	w.ios_emit_callback(binding, ios_control_event(View(sender), binding))
}

fn (mut w Window) ios_emit_scroll(native View, offset f64) bool {
	binding := w.scroll_callbacks[u64(native)] or { return false }
	position := scroll_content_offset(native)
	return w.ios_emit_callback(binding, ElementEvent{ kind: .scroll, value: offset, x: position.x, y: position.y })
}

@[export: 'vui_scroll_did_scroll']
fn vui_scroll_did_scroll(_self voidptr, _cmd voidptr, sender voidptr) {
	mut w := ios_window() or { return }
	w.ios_emit_scroll(View(sender), scroll_content_offset(View(sender)).y)
}

@[export: 'vui_text_view_changed']
fn vui_text_view_changed(_self voidptr, _cmd voidptr, sender voidptr) {
	mut w := ios_window() or { return }
	binding := w.text_area_callbacks[u64(sender)] or { return }
	w.ios_emit_callback(binding, ios_control_event(View(sender), binding))
}

@[export: 'vui_button_long_press']
fn vui_button_long_press(_self voidptr, _cmd voidptr, sender voidptr) {
	mut w := ios_window() or { return }
	gesture := View(sender)
	gesture_key := u64(sender)
	status := gesture_state(gesture)
	if status in [gesture_state_ended, gesture_state_cancelled, gesture_state_failed] {
		w.ios_clear_gesture_capture(gesture_key)
		return
	}
	if status != gesture_state_began { return }
	view := gesture_view(gesture)
	current := w.action_callbacks[u64(view)] or { IosCallbackBinding{} }
	captured := w.gesture_captures[gesture_key] or { IosCallbackBinding{} }
	binding := ios_control_release_binding(captured, current, ios_interaction_available(view)) or { return }
	w.ios_emit_callback(binding, ElementEvent{ kind: .long_press })
}

@[export: 'vui_swipe_left']
fn vui_swipe_left(_self voidptr, _cmd voidptr, sender voidptr) {
	mut w := ios_window() or { return }
	gesture := View(sender)
	view := gesture_view(gesture)
	gesture_key := u64(sender)
	current := w.action_callbacks[u64(view)] or { IosCallbackBinding{} }
	captured := w.gesture_captures[gesture_key] or { IosCallbackBinding{} }
	binding := ios_control_release_binding(captured, current, ios_interaction_available(view)) or {
		w.ios_clear_gesture_capture(gesture_key)
		if !objc_is_nil(view) { w.set_view_translation_x(view, 0) }
		return
	}
	state := gesture_state(gesture)
	x := pan_translation_x(gesture, view)
	if state == gesture_state_began || state == gesture_state_changed {
		mut shift := x
		if shift > 0 { shift = 0 }
		if shift < -swipe_max_translation { shift = -swipe_max_translation }
		w.set_view_translation_x(view, shift)
		return
	}
	if state == gesture_state_ended {
		w.ios_clear_gesture_capture(gesture_key)
		if x < -swipe_delete_threshold {
			w.set_view_translation_x(view, -swipe_max_translation)
			w.ios_emit_callback(binding, ElementEvent{ kind: .swipe_left })
		} else {
			w.set_view_translation_x(view, 0)
		}
		return
	}
	w.ios_clear_gesture_capture(gesture_key)
	w.set_view_translation_x(view, 0)
}

@[export: 'vui_swipe_should_begin']
fn vui_swipe_should_begin(_self voidptr, _cmd voidptr, sender voidptr) bool {
	gesture := View(sender)
	view := gesture_view(gesture)
	tx := pan_translation_x(gesture, view)
	ty := pan_translation_y(gesture, view)
	vx := pan_velocity_x(gesture, view)
	vy := pan_velocity_y(gesture, view)
	abs_tx := if tx < 0 { -tx } else { tx }
	abs_ty := if ty < 0 { -ty } else { ty }
	abs_vx := if vx < 0 { -vx } else { vx }
	abs_vy := if vy < 0 { -vy } else { vy }
	return (tx < 0 && abs_tx > abs_ty) || (vx < 0 && abs_vx > abs_vy)
}

@[export: 'vui_swipe_should_recognize_simultaneously']
fn vui_swipe_should_recognize_simultaneously(_self voidptr, _cmd voidptr, _sender voidptr, _other voidptr) bool {
	return true
}

}
