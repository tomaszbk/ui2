// vfmt off
// Keep native imports and declarations inside the backend switch. Hoisting
// them makes AppKit's MRC bridge conflict with gg/Sokol's ARC build.
module ui2

$if macos && !ui2_custom_rendering ? && !ui2_headless ? && !ui2_document_library ? {

import encoding.base64
import macos
import os

#flag darwin -framework Cocoa

#flag darwin -framework QuartzCore

#flag darwin -framework CoreGraphics

#include "@VMODROOT/appkit/ui_macos_geometry_darwin.h"

struct C.ui2_macos_rect {
	x      f64
	y      f64
	width  f64
	height f64
}

fn C.ui2_macos_control_mouse_down(control voidptr, event voidptr)

fn C.ui2_macos_msg_rect_rect(obj voidptr, sel voidptr, rect C.ui2_macos_rect) C.ui2_macos_rect

fn C.ui2_macos_msg_super_void_id(obj voidptr, superclass voidptr, sel voidptr, arg voidptr)

fn C.ui2_macos_msg_id_point(obj voidptr, sel voidptr, x f64, y f64) voidptr

fn C.ui2_macos_add_tracking_area(view voidptr)

fn C.ui2_macos_msg_void_float(obj voidptr, sel voidptr, value f32)

fn C.ui2_macos_set_shadow_path(layer voidptr, x f64, y f64, width f64, height f64, radius f64)

const ns_window_style_titled = u64(1)
const ns_window_style_closable = u64(2)
const ns_window_style_miniaturizable = u64(4)
const ns_window_style_resizable = u64(8)
const ns_backing_store_buffered = u64(2)
const ns_button_type_momentary_change = i64(5)
const ns_button_type_momentary_push_in = i64(7)
const ns_button_type_switch = i64(3)
const ns_button_type_push_on_push_off = i64(1)

type NativeView = voidptr

struct NativeRect {
	x      f64
	y      f64
	width  f64
	height f64
}

struct AppkitCallbackBinding {
	id       string
	on_event ElementCallback = unsafe { nil }
	kind     Kind
	event    ElementEventKind
	clickable bool
	button_behavior bool
	draggable bool
}

fn appkit_binding(el Element, event ElementEventKind) AppkitCallbackBinding {
	return AppkitCallbackBinding{ id: el.id, on_event: el.on_event, kind: el.kind, event: event, clickable: el.clickable, button_behavior: el.kind == .view && el.button_behavior, draggable: el.draggable }
}

fn appkit_callback_present(binding AppkitCallbackBinding) bool {
	return binding.on_event != unsafe { nil }
}

fn appkit_pointer_release_binding(captured AppkitCallbackBinding, current AppkitCallbackBinding) ?AppkitCallbackBinding {
	if !appkit_callback_present(captured) || !appkit_callback_present(current) { return none }
	return captured
}

fn (mut w Window) appkit_emit_callback(binding AppkitCallbackBinding, event ElementEvent) bool {
	if !appkit_callback_present(binding) {
		return false
	}
	binding.on_event(ElementEvent{ ...event, window: w, id: binding.id })
	return true
}

// Window is one NSWindow and the native views ui2 reconciles into it. AppKit
// calls back with the receiver alone, so the window registers its NSWindow
// and its control handler with the process's AppkitHost, which each callback
// asks for its window.
@[heap]
pub struct Window {
mut:
	app             &App = unsafe { nil }
	title           string
	menus           MenuDeclarations
	timers          &TimerRuntime = &TimerRuntime{}
	event_modifiers KeyModifiers
	close_hooks     []fn ()
	closed          bool
	layout_tree &LayoutTree = &LayoutTree{}
	layout_environment LayoutEnvironment
	navigation &FocusManager = &FocusManager{}
	navigation_paths map[string]string
	focus_selections map[string]macos.Range
	activation_keys map[u64]bool // Physical NSEvent keyCode, owned until release/blur.
	keyboard_generation u64 // Lifecycle changes during a synchronous key observer.
	typed_key_event voidptr
	typed_key_timestamp f64 = -1
	typed_key_consumed bool
	build               BuildFn = BuildFn(unsafe { nil })
	width               int
	height              int
	min_width           int
	min_height          int
	key_handler         KeyFn = KeyFn(unsafe { nil })
	key_event_handler   KeyEventFn = KeyEventFn(unsafe { nil })
	key_consumed        bool
	text_key_consumed   bool
	// A navigation key forwarded to the native input context has already
	// visited KeyFn; its text/window delegates must not dispatch it again.
	navigation_key_dispatched bool
	drop_handler        DropFn = DropFn(unsafe { nil })
	window              NativeView
	root_view           NativeView
	button_handler      NativeView
	views               map[string]NativeView
	view_keys           map[string]string
	view_kinds          map[string]Kind
	text_area_direct    map[string]bool
	label_places        map[string]LabelPlacement
	nodes               map[string]NativeView
	node_kinds          map[string]Kind
	node_text_direct    map[string]bool
	node_interactive    map[string]bool
	node_label_boxed    map[string]bool
	node_secure         map[string]bool
	node_declared_text  map[string]string
	node_content_sig    map[string]string
	node_tooltips       map[string]string
	node_shortened      map[string]ShortenedText
	label_line_heights  map[string]f64 // font name and size -> one laid-out line of ASCII
	node_menu_sig       map[string]string
	node_menu_items     map[string][]u64
	textview_ids        map[u64]string // NSTextView pointer -> lookup id (no tag on NSView)
	textview_callbacks map[u64]AppkitCallbackBinding // NSTextView pointer -> typed callback
	scroll_callbacks          map[u64]AppkitCallbackBinding // NSClipView pointer -> Scroll callback
	pointer_callbacks         map[u64]AppkitCallbackBinding // NSView pointer -> typed callback
	hover_callbacks     map[u64]HoverTarget // NSView pointer -> hoverable element
	rendering           bool // rebuild_now is building or applying the tree
	refresh_pending     bool // a rebuild was asked for while one was rendering
	// request_refresh posted a rebuild that has not rendered yet. A background
	// thread may set it; the main thread clears it when the rebuild starts.
	rebuild_queued      bool
	image_symbols       map[u64]string // NSImageView pointer -> the symbol and tint it shows
	hovered             []HoverTarget  // hovered elements, outermost first
	hover_window_point  macos.Point    // last pointer location, window coordinates
	hover_root_point    macos.Point    // the same in the root view's coordinates
	hover_inside        bool
	pointer_clickable   map[u64]bool
	pointer_buttons     map[u64]bool
	pointer_draggable   map[u64]bool
	pointer_button_down u64
	pointer_button_x    f64
	pointer_button_y    f64
	pointer_button_moved bool
	pointer_button_binding AppkitCallbackBinding
	cursor_ids          map[u64]string // NSView pointer -> cursor name
	control_callbacks         map[u64]AppkitCallbackBinding // NSControl pointer -> typed callback
	control_captures          map[u64]AppkitCallbackBinding // Native tracking loop press snapshot
	checkbox_controls   map[u64]bool // NSButton pointers whose state is persistent
	toggle_groups       map[u64]string
	toggle_allow_no_selection map[u64]bool
	toggle_ids          map[u64]string
	toggle_views        map[u64]NativeView
	slider_specs        map[u64]SliderSpec // NSSlider pointer -> range behavior
	control_change_callbacks  map[u64]AppkitCallbackBinding // NSTextField pointer -> typed callback
	observed            map[u64]bool // clip views we already observe for scroll changes
	pending_scroll      map[string]f64 // Scroll element id -> offset to apply once it exists
	pending_scroll_x    map[string]f64 // the same, for the sideways axis
	scroll_forwarding   map[u64]bool // NSScrollView pointer -> the gesture under way belongs to an enclosing Scroll
	screenshot_pending  bool
	screenshot_captured bool
}

pub fn (mut w Window) bounds() Rect {
	if native_is_nil(w.root_view) {
		return Rect{
			width: f64(w.width)
			height: f64(w.height)
		}
	}
	b := native_bounds(w.root_view)
	return Rect{
		x: b.x
		y: b.y
		width: b.width
		height: b.height
	}
}

// rebuild_now builds and renders the window's tree on the main thread.
fn (mut w Window) rebuild_now() {
	if w.closed || native_is_nil(w.root_view) || voidptr(w.build) == unsafe { nil } {
		return
	}
	// Moving and resizing views posts notifications (a scroll view's bounds, for
	// one) whose handlers may ask for a refresh. Rendering again inside a render
	// tore the tree it was in the middle of updating, so such a request waits for
	// the render to finish.
	if w.rendering {
		w.refresh_pending = true
		return
	}
	w.rendering = true
	w.rebuild_queued = false
	// `after` callbacks run on the UI thread before the build, so it declares
	// what they changed.
	w.run_due_timers()
	root := w.build(mut w)
	w.render_root(root)
	w.rendering = false
	if w.refresh_pending {
		w.refresh_pending = false
		w.request_refresh()
	}
	w.schedule_screenshot_capture()
}

// A subtree's intrinsic size can move ancestors and siblings. Reconcile their
// resulting frames through the existing native identity/edit-preserving path.
pub fn (mut w Window) refresh_element(id string, element Element) {
	w.layout_tree.patch(id, element) or { eprintln('ui2 layout: ${err}'); return }
	w.render_mounted_layout()
	w.schedule_screenshot_capture()
}

pub fn (mut w Window) layout_stats() LayoutStats { return w.layout_tree.stats() }

pub fn (mut w Window) invalidate_layout_environment(environment LayoutEnvironment) {
	w.layout_environment = environment
	if w.layout_tree.root.len > 0 { w.render_mounted_layout() }
}

// on_key registers a handler for key events that reach the window, plus
// intercepted editing commands such as Tab. Keys arrive normalized:
// 'up', 'forward_delete', 'escape', 'cmd+shift+r', 'f5', ...
pub fn (mut w Window) on_key(handler KeyFn) {
	w.key_handler = handler
}

// on_key_event registers a typed, layout-independent physical-key handler.
pub fn (mut w Window) on_key_event(handler KeyEventFn) {
	w.key_event_handler = handler
}

// on_drop registers a handler for files or plain text dropped on the window.
pub fn (mut w Window) on_drop(handler DropFn) {
	w.drop_handler = handler
}


// scroll_offset returns the current vertical scroll position of a Scroll element.
pub fn (mut w Window) scroll_offset(id string) f64 {
	scrollv := w.views[id] or { return 0 }
	r := macos.msg_rect(scrollv, 'documentVisibleRect')
	return r.y
}

// scroll_horizontal_offset returns how far a Scroll element is scrolled sideways. It
// stays zero for one whose scroll_mode leaves the horizontal axis out.
pub fn (mut w Window) scroll_horizontal_offset(id string) f64 {
	scrollv := w.views[id] or { return 0 }
	if !scroll_view_has_axis(scrollv, true) {
		return 0
	}
	r := macos.msg_rect(scrollv, 'documentVisibleRect')
	return r.x
}

// scroll_to_rect scrolls a Scroll element so the given document rect is visible. Along
// an axis the element does not scroll, the rect is taken to be what already shows from
// the start, so bringing it into view never moves the element that way.
pub fn (mut w Window) scroll_to_rect(id string, x f64, y f64, width f64, height f64) {
	scrollv := w.views[id] or { return }
	doc := macos.msg_id(scrollv, 'documentView')
	if native_is_nil(doc) {
		return
	}
	visible := macos.msg_rect(macos.msg_id(scrollv, 'contentView'), 'bounds')
	across := scroll_view_has_axis(scrollv, true)
	down := scroll_view_has_axis(scrollv, false)
	macos.msg_void_rect(doc, 'scrollRectToVisible:', macos.rect(if across { x } else { 0.0 },
		if down { y } else { 0.0 }, if across { width } else { visible.width }, if down {
		height
	} else {
		visible.height
	}))
}

// scroll_view_has_axis reports whether a scroll view's mode scrolls an axis. One it
// leaves out can still have a range in AppKit's eyes: a scroller that takes room of
// its own leaves the document that much longer than what shows of it. That is not
// somewhere to scroll to, so no position along such an axis is reported or asked for.
fn scroll_view_has_axis(scroll NativeView, horizontal bool) bool {
	return macos.msg_bool(scroll, if horizontal { 'hasHorizontalScroller' } else { 'hasVerticalScroller' })
}

// scroll_to_offset puts a Scroll element at the given vertical offset. Asking for a
// position before the element exists is the ordinary case — a screen that opens where
// it was last left knows the offset while it is still building its first tree — so the
// request is kept and carried out when the element is created.
pub fn (mut w Window) scroll_to_offset(id string, offset f64) {
	if id.len == 0 {
		return
	}
	w.pending_scroll[id] = offset
	w.apply_scroll_offset(id, true)
}

// scroll_to_horizontal_offset is scroll_to_offset for the sideways axis, with the same
// promise: an offset asked for before the element exists is kept until it does.
pub fn (mut w Window) scroll_to_horizontal_offset(id string, offset f64) {
	if id.len == 0 {
		return
	}
	w.pending_scroll_x[id] = offset
	w.apply_scroll_offset(id, true)
}

// apply_scroll_offset takes up the offsets asked for an existing Scroll element.
// With `requested`, an offset past the current range, asked for while a rebuild is
// queued, stays pending so that rebuild's render can reach the content it adds.
fn (mut w Window) apply_scroll_offset(id string, requested bool) {
	if id !in w.pending_scroll && id !in w.pending_scroll_x {
		return
	}
	scrollv := w.views[id] or { return }
	doc := macos.msg_id(scrollv, 'documentView')
	if native_is_nil(doc) {
		return
	}
	clip := macos.msg_id(scrollv, 'contentView')
	visible := macos.msg_rect(clip, 'bounds')
	// A rect the size of the visible area lands its corner at the corner of the view,
	// which is the offset that was asked for. The scroll view clamps it to the
	// document, so an offset past the end settles at the end. An axis nothing was
	// asked of keeps the position it is at, and one the element does not scroll stays
	// at its start whatever was asked.
	x := if scroll_view_has_axis(scrollv, true) { w.pending_scroll_x[id] or { visible.x } } else { 0.0 }
	y := if scroll_view_has_axis(scrollv, false) { w.pending_scroll[id] or { visible.y } } else { 0.0 }
	macos.msg_void_rect(doc, 'scrollRectToVisible:', macos.rect(x, y, visible.width, visible.height))
	if requested && w.rebuild_queued {
		reached := macos.msg_rect(clip, 'bounds')
		if reached.x == x { w.pending_scroll_x.delete(id) }
		if reached.y == y { w.pending_scroll.delete(id) }
		return
	}
	w.pending_scroll.delete(id)
	w.pending_scroll_x.delete(id)
}

pub fn (mut w Window) text(id string) string {
	native := w.views[id] or { return '' }
	kind := w.view_kinds[id] or { Kind.view }
	if kind == .text_area {
		tv := text_area_text_view(native, w.text_area_direct[id] or { false })
		return macos.utf8_string(macos.msg_id(tv, 'string'))
	}
	if kind == .dropdown {
		return native_dropdown_text(native)
	}
	if kind == .label {
		// A label is its text field, or the view holding one.
		return native_text(label_text_field(native))
	}
	return native_text(native)
}

pub fn (mut w Window) set_text(id string, t string) {
	native := w.views[id] or { return }
	kind := w.view_kinds[id] or { Kind.view }
	if kind == .text_area {
		tv := text_area_text_view(native, w.text_area_direct[id] or { false })
		macos.msg_void1(tv, 'setString:', macos.nsstring(t))
		return
	}
	if kind == .dropdown {
		native_select_dropdown_item(native, t)
		return
	}
	if kind == .label {
		// A label is its text field, or the view holding one.
		field := label_text_field(native)
		native_set_text(field, t)
		if place := w.label_places[id] {
			native_place_label_text(field, place.frame, place.lines, place.valign, place.boxed, mut w.label_line_heights)
		}
		return
	}
	native_set_text(native, t)
}

pub fn (mut w Window) slider_value(id string) f64 {
	native := w.views[id] or { return 0 }
	if (w.view_kinds[id] or { Kind.view }) != .slider {
		return 0
	}
	spec := w.slider_specs[u64(voidptr(native))] or { return 0 }
	return native_snap_slider_value(native, spec)
}

pub fn (mut w Window) set_slider_value(id string, value f64) {
	native := w.views[id] or { return }
	if (w.view_kinds[id] or { Kind.view }) != .slider {
		return
	}
	spec := w.slider_specs[u64(voidptr(native))] or { return }
	macos.msg_void_f64(native, 'setDoubleValue:', slider_clamped_value(value, spec.min,
		spec.max))
}

pub fn (mut w Window) switch_active(id string) bool {
	native := w.views[id] or { return false }
	if (w.view_kinds[id] or { Kind.view }) != .switch_control {
		return false
	}
	return macos.msg_i64(native, 'state') != 0
}

pub fn (mut w Window) set_switch_active(id string, active bool) {
	native := w.views[id] or { return }
	if (w.view_kinds[id] or { Kind.view }) != .switch_control {
		return
	}
	macos.msg_void_i64(native, 'setState:', if active { i64(1) } else { i64(0) })
}

pub fn (mut w Window) toggle_button_pressed(id string) bool {
	native := w.views[id] or { return false }
	if (w.view_kinds[id] or { Kind.view }) != .toggle_button {
		return false
	}
	return macos.msg_i64(native, 'state') != 0
}

pub fn (mut w Window) set_toggle_button_pressed(id string, pressed bool) {
	native := w.views[id] or { return }
	if (w.view_kinds[id] or { Kind.view }) != .toggle_button {
		return
	}
	if pressed {
		w.release_macos_toggle_group(u64(voidptr(native)))
	}
	macos.msg_void_i64(native, 'setState:', if pressed { i64(1) } else { i64(0) })
}

pub fn (mut w Window) toggle_button_group_members(id string) []string {
	native := w.views[id] or { return [] }
	pointer := u64(voidptr(native))
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

pub fn (mut w Window) focus(id string) {
	w.sync_focus_navigation()
	if !w.navigation.can_focus(id) { return }
	previous := w.focused_id()
	if previous != id {
		if old := w.views[previous] {
			if (w.view_kinds[previous] or { Kind.view }) == .text_field && native_control_is_editing(old) {
				w.focus_selections[previous] = native_control_selected_range(old)
			}
		}
	}
	native := w.views[id] or { return }
	target := if (w.view_kinds[id] or { Kind.view }) == .text_area {
		text_area_text_view(native, w.text_area_direct[id] or { false })
	} else { native }
	if previous != id && !native_focus(target) { return }
	if previous != id && (w.view_kinds[id] or { Kind.view }) == .text_field {
		if selection := w.focus_selections[id] { native_restore_control_selection(native, selection.location, selection.length) }
	}
	w.navigation.current = id
	w.reveal_appkit_focus(id)
}

// focused_id returns the declarative id of the control that currently owns
// keyboard focus. NSTextField edits through a shared field editor, so compare
// that responder with each field's currentEditor as well as direct responders.
// NSScrollView redirects explicit focus to its document view. Match that exact
// internal responder only; a Scroll never owns its children's editor/control.
pub fn (mut w Window) focused_id() string {
	if native_is_nil(w.window) {
		return ''
	}
	responder := macos.msg_id(w.window, 'firstResponder')
	if native_is_nil(NativeView(responder)) {
		return ''
	}
	if id := w.textview_ids[u64(voidptr(responder))] {
		return id
	}
	for id, native in w.views {
		if native == NativeView(responder) {
			return id
		}
		if (w.view_kinds[id] or { Kind.view }) == .scroll
			&& macos.msg_id(native, 'documentView') == responder {
			return id
		}
		if (w.view_kinds[id] or { Kind.view }) == .text_field
			&& macos.msg_id(native, 'currentEditor') == responder {
			return id
		}
	}
	return ''
}

// focused_text_area_id returns the id of the text area that currently holds
// keyboard focus (is the window's first responder), or '' when no registered
// text view is focused. Clicking or selecting inside a text view emits no app
// event, so this lets callers target the editor the user is actually editing
// instead of tracking focus changes manually.
pub fn (mut w Window) focused_text_area_id() string {
	if native_is_nil(w.window) {
		return ''
	}
	responder := macos.msg_id(w.window, 'firstResponder')
	if native_is_nil(NativeView(responder)) {
		return ''
	}
	return w.textview_ids[u64(voidptr(responder))] or { '' }
}

// text_area_set_selection selects a UTF-16 range, matching NSTextView's native
// selection storage and the offsets exposed by text_area_caret.
pub fn (mut w Window) text_area_set_selection(id string, location int, length int) {
	tv := w.text_area_document_view(id) or { return }
	start := if location < 0 { u64(0) } else { u64(location) }
	selection_length := if length < 0 { u64(0) } else { u64(length) }
	native_text_view_set_selected_range(tv, start, selection_length)
}

// text_area_set_caret positions and collapses the selection at a UTF-16 offset.
pub fn (mut w Window) text_area_set_caret(id string, pos int) {
	w.text_area_set_selection(id, pos, 0)
}

pub fn (mut w Window) text_area_caret(id string) int {
	tv := w.text_area_document_view(id) or { return 0 }
	return int(native_text_view_selected_range(tv).location)
}

pub fn (mut w Window) text_area_selection_length(id string) int {
	tv := w.text_area_document_view(id) or { return 0 }
	return int(native_text_view_selected_range(tv).length)
}

pub fn (mut w Window) insert_text_area_text(id string, text string) {
	tv := w.text_area_document_view(id) or { return }
	native_text_view_insert_text(tv, text)
}

// consume_text_key tells the current text-view key delegate call that the app
// handled the key and native NSTextView deletion should not also run.
pub fn (mut w Window) consume_text_key() {
	w.text_key_consumed = true
}

// consume_key tells the current key handler dispatch that the app handled the
// key and ui2 should not run its default native command.
pub fn (mut w Window) consume_key() {
	w.key_consumed = true
}

pub fn clipboard_has_image() bool {
	return native_pasteboard_has_image()
}

pub fn save_clipboard_image_png(path string) bool {
	return native_pasteboard_write_image_png(path)
}

pub fn (mut w Window) dismiss_keyboard() {
	if !native_is_nil(w.root_view) {
		native_end_editing(w.root_view)
	}
}

pub fn quit() {
	native_terminate_app()
}

pub fn safe_area_top() f64 {
	return 0
}


fn screenshot_path() string {
	office_path := os.getenv('OFFICE_SCREENSHOT_PATH')
	if office_path.trim_space() != '' {
		return office_path
	}
	return os.getenv('UI2_SCREENSHOT_PATH')
}

fn screenshot_should_exit() bool {
	return (os.getenv_opt('OFFICE_EXIT_AFTER_SCREENSHOT') or { '0' }) == '1' || (os.getenv_opt('UI2_EXIT_AFTER_SCREENSHOT') or {
		'0'
	}) == '1'
}

fn (mut w Window) schedule_screenshot_capture() {
	if w.screenshot_captured || w.screenshot_pending || screenshot_path().trim_space() == '' {
		return
	}
	w.screenshot_pending = true
	native_dispatch_window_screenshot(w)
}

fn (mut w Window) capture_screenshot_on_main() {
	w.screenshot_pending = false
	if w.screenshot_captured || native_is_nil(w.root_view) {
		return
	}
	path := screenshot_path().trim_space()
	if path == '' {
		return
	}
	if !native_view_save_png(w.root_view, path) {
		eprintln('ui2 screenshot failed: ${path}')
		return
	}
	w.screenshot_captured = true
	if screenshot_should_exit() {
		native_terminate_app()
	}
}

pub fn (mut w Window) toggle_text_area_format(id string, format TextFormat) TextFormatState {
	tv := w.text_area_document_view(id) or { return TextFormatState{} }
	native_text_view_toggle_format(tv, int(format))
	return w.text_area_format_state(id)
}

pub fn (mut w Window) set_text_area_font_family(id string, family string) TextFormatState {
	tv := w.text_area_document_view(id) or { return TextFormatState{} }
	native_text_view_set_font_family(tv, family)
	return w.text_area_format_state(id)
}

pub fn (mut w Window) set_text_area_font_size(id string, size f64) TextFormatState {
	tv := w.text_area_document_view(id) or { return TextFormatState{} }
	native_text_view_set_font_size(tv, size)
	return w.text_area_format_state(id)
}

pub fn (mut w Window) set_text_area_color(id string, color u32) TextFormatState {
	tv := w.text_area_document_view(id) or { return TextFormatState{} }
	native_text_view_set_color(tv, color)
	return w.text_area_format_state(id)
}

pub fn (mut w Window) set_text_area_background_color(id string, color u32) TextFormatState {
	tv := w.text_area_document_view(id) or { return TextFormatState{} }
	native_text_view_set_background_color(tv, color)
	return w.text_area_format_state(id)
}

pub fn (mut w Window) set_text_area_effect(id string, effect string) TextFormatState {
	tv := w.text_area_document_view(id) or { return TextFormatState{} }
	native_text_view_set_effect(tv, text_effect_value(effect))
	return w.text_area_format_state(id)
}

fn text_effect_value(effect string) int {
	return match effect {
		'shadow' { 1 }
		'outline' { 2 }
		else { 0 }
	}
}

pub fn (mut w Window) toggle_text_area_superscript(id string) TextFormatState {
	return w.toggle_text_area_vertical_align(id, 'superscript')
}

pub fn (mut w Window) toggle_text_area_subscript(id string) TextFormatState {
	return w.toggle_text_area_vertical_align(id, 'subscript')
}

pub fn (mut w Window) toggle_text_area_vertical_align(id string, align string) TextFormatState {
	tv := w.text_area_document_view(id) or { return TextFormatState{} }
	native_text_view_toggle_vertical_align(tv, vertical_align_value(align))
	return w.text_area_format_state(id)
}

fn vertical_align_value(align string) int {
	return match align {
		'superscript' { 1 }
		'subscript' { -1 }
		else { 0 }
	}
}

pub fn (mut w Window) text_area_runs(id string) []TextRun {
	tv := w.text_area_document_view(id) or { return []TextRun{} }
	return native_text_view_runs(tv)
}

fn parse_text_area_runs(raw string) []TextRun {
	mut runs := []TextRun{}
	for line in raw.split_into_lines() {
		if line.len == 0 {
			continue
		}
		parts := line.split('\t')
		if parts.len < 6 {
			continue
		}
		run_text := base64.decode_str(parts[0])
		if run_text.len == 0 {
			continue
		}
		runs << TextRun{
			text: run_text
			style: TextStyle{
				font_family: base64.decode_str(parts[1])
				size: parts[2].f64()
				bold: parts[3] == '1'
				italic: parts[4] == '1'
				underline: parts[5] == '1'
				vertical_align: text_run_vertical_align(if parts.len > 6 { parts[6] } else { '' })
				strikethrough: parts.len > 7 && parts[7] == '1'
				color: if parts.len > 8 { u32(parts[8].u64()) } else { u32(0x111111) }
				background_color: if parts.len > 9 { u32(parts[9].u64()) } else { u32(0) }
				shadow: parts.len > 10 && (parts[10].int() & 1) != 0
				outline: parts.len > 10 && (parts[10].int() & 2) != 0
				link: if parts.len > 11 { base64.decode_str(parts[11]) } else { '' }
			}
		}
	}
	return runs
}

fn text_run_vertical_align(value string) string {
	return match value {
		'superscript', 'subscript' { value }
		else { '' }
	}
}

pub fn (mut w Window) text_area_format_state(id string) TextFormatState {
	tv := w.text_area_document_view(id) or { return TextFormatState{} }
	vertical := native_text_view_vertical_align_active(tv)
	effect := native_text_view_effect_active(tv)
	return TextFormatState{
		bold: native_text_view_format_active(tv, int(TextFormat.bold))
		italic: native_text_view_format_active(tv, int(TextFormat.italic))
		underline: native_text_view_format_active(tv, int(TextFormat.underline))
		strikethrough: native_text_view_format_active(tv, int(TextFormat.strikethrough))
		shadow: (effect & 1) != 0
		outline: (effect & 2) != 0
		subscript: vertical < 0
		superscript: vertical > 0
	}
}

fn (mut w Window) text_area_document_view(id string) ?NativeView {
	native := w.views[id] or { return none }
	if (w.view_kinds[id] or { Kind.view }) != .text_area {
		return none
	}
	tv := text_area_text_view(native, w.text_area_direct[id] or { false })
	if native_is_nil(tv) {
		return none
	}
	return tv
}

fn text_area_text_view(native NativeView, direct bool) NativeView {
	if direct {
		return native
	}
	return macos.msg_id(native, 'documentView')
}

fn ensure_runtime_classes() {
	for native_class in ['NSTextField', 'NSSecureTextField', 'NSTextView'] {
		name := 'UI2Focus' + native_class
		if macos.get_class(name) == unsafe { nil } {
			cls := macos.allocate_class_pair(macos.get_class(native_class), name)
			macos.add_method(cls, 'acceptsFirstResponder', voidptr(ui2_focus_accepts_first_responder), 'B@:')
			macos.register_class_pair(cls)
		}
	}

	for native_class in ['NSButton', 'NSSlider', 'NSPopUpButton', 'NSSwitch'] {
		if macos.get_class(native_class) == unsafe { nil } { continue }
		tracking_class := 'UI2Tracking' + native_class
		if macos.get_class(tracking_class) == unsafe { nil } {
			cls := macos.allocate_class_pair(macos.get_class(native_class), tracking_class)
			macos.add_method(cls, 'acceptsFirstResponder', voidptr(ui2_focus_accepts_first_responder), 'B@:')
			macos.add_method(cls, 'mouseDown:', voidptr(ui2_control_mouse_down), 'v@:@')
			macos.register_class_pair(cls)
		}
	}
	if macos.get_class('UI2FlippedView') == unsafe { nil } {
		cls := macos.allocate_class_pair(macos.get_class('NSView'), 'UI2FlippedView')
		macos.add_method(cls, 'acceptsFirstResponder', voidptr(ui2_focus_accepts_first_responder), 'B@:')
		macos.add_method(cls, 'isFlipped', voidptr(ui2_view_is_flipped), 'B@:')
		// Only the root view carries a tracking area, so only it receives these.
		macos.add_method(cls, 'mouseEntered:', voidptr(ui2_root_mouse_moved), 'v@:@')
		macos.add_method(cls, 'mouseMoved:', voidptr(ui2_root_mouse_moved), 'v@:@')
		macos.add_method(cls, 'mouseExited:', voidptr(ui2_root_mouse_exited), 'v@:@')
		macos.add_method(cls, 'draggingEntered:', voidptr(ui2_dragging_entered), 'Q@:@')
		macos.add_method(cls, 'performDragOperation:', voidptr(ui2_perform_drag_operation), 'B@:@')
		macos.register_class_pair(cls)
	}
	if macos.get_class('UI2ScrollView') == unsafe { nil } {
		cls := macos.allocate_class_pair(macos.get_class('NSScrollView'), 'UI2ScrollView')
		macos.add_method(cls, 'scrollWheel:', voidptr(ui2_scroll_view_scroll_wheel), 'v@:@')
		macos.register_class_pair(cls)
	}
	if macos.get_class('UI2PointerView') == unsafe { nil } {
		cls := macos.allocate_class_pair(macos.get_class('NSView'), 'UI2PointerView')
		macos.add_method(cls, 'acceptsFirstResponder', voidptr(ui2_focus_accepts_first_responder), 'B@:')
		macos.add_method(cls, 'isFlipped', voidptr(ui2_view_is_flipped), 'B@:')
		macos.add_method(cls, 'mouseDown:', voidptr(ui2_pointer_mouse_down), 'v@:@')
		macos.add_method(cls, 'mouseDragged:', voidptr(ui2_pointer_mouse_dragged), 'v@:@')
		macos.add_method(cls, 'mouseUp:', voidptr(ui2_pointer_mouse_up), 'v@:@')
		macos.add_method(cls, 'accessibilityPerformPress', voidptr(ui2_pointer_accessibility_press),
			'B@:')
		macos.add_method(cls, 'resetCursorRects', voidptr(ui2_pointer_reset_cursor_rects), 'v@:')
		macos.register_class_pair(cls)
	}
	if macos.get_class('UI2PointerChildView') == unsafe { nil } {
		cls := macos.allocate_class_pair(macos.get_class('UI2FlippedView'), 'UI2PointerChildView')
		macos.add_method(cls, 'mouseDown:', voidptr(ui2_pointer_mouse_down), 'v@:@')
		macos.add_method(cls, 'mouseDragged:', voidptr(ui2_pointer_mouse_dragged), 'v@:@')
		macos.add_method(cls, 'mouseUp:', voidptr(ui2_pointer_mouse_up), 'v@:@')
		macos.register_class_pair(cls)
	}
	if macos.get_class('UI2PointerImageView') == unsafe { nil } {
		cls := macos.allocate_class_pair(macos.get_class('NSImageView'), 'UI2PointerImageView')
		macos.add_method(cls, 'acceptsFirstResponder', voidptr(ui2_focus_accepts_first_responder), 'B@:')
		macos.add_method(cls, 'mouseDown:', voidptr(ui2_pointer_mouse_down), 'v@:@')
		macos.add_method(cls, 'mouseDragged:', voidptr(ui2_pointer_mouse_dragged), 'v@:@')
		macos.add_method(cls, 'mouseUp:', voidptr(ui2_pointer_mouse_up), 'v@:@')
		macos.add_method(cls, 'resetCursorRects', voidptr(ui2_pointer_reset_cursor_rects), 'v@:')
		macos.register_class_pair(cls)
	}
	if macos.get_class('UI2PointerLabel') == unsafe { nil } {
		cls := macos.allocate_class_pair(macos.get_class('NSTextField'), 'UI2PointerLabel')
		macos.add_method(cls, 'acceptsFirstResponder', voidptr(ui2_focus_accepts_first_responder), 'B@:')
		macos.add_method(cls, 'mouseDown:', voidptr(ui2_pointer_mouse_down), 'v@:@')
		macos.add_method(cls, 'mouseDragged:', voidptr(ui2_pointer_mouse_dragged), 'v@:@')
		macos.add_method(cls, 'mouseUp:', voidptr(ui2_pointer_mouse_up), 'v@:@')
		macos.register_class_pair(cls)
	}
	if macos.get_class('UI2AppDelegate') == unsafe { nil } {
		cls := macos.allocate_class_pair(macos.get_class('NSObject'), 'UI2AppDelegate')
		macos.add_method(cls, 'applicationDidFinishLaunching:', voidptr(ui2_app_did_finish_launching), 'v@:@')
		macos.add_method(cls, 'applicationDidResignActive:', voidptr(ui2_app_release_activation), 'v@:@')
		macos.add_method(cls, 'applicationShouldTerminateAfterLastWindowClosed:', voidptr(ui2_app_should_terminate_after_last_window_closed), 'B@:@')
		macos.add_method(cls, 'windowDidResize:', voidptr(ui2_window_did_resize), 'v@:@')
		macos.add_method(cls, 'windowWillClose:', voidptr(ui2_window_will_close), 'v@:@')
		macos.register_class_pair(cls)
	}
	if macos.get_class('UI2ButtonHandler') == unsafe { nil } {
		cls := macos.allocate_class_pair(macos.get_class('NSObject'), 'UI2ButtonHandler')
		macos.add_method(cls, 'handleTap:', voidptr(ui2_button_tap), 'v@:@')
		macos.add_method(cls, 'controlTextDidChange:', voidptr(ui2_control_text_changed), 'v@:@')
		macos.add_method(cls, 'control:textView:doCommandBySelector:', voidptr(ui2_control_do_command), 'B@:@@:')
		macos.add_method(cls, 'textDidChange:', voidptr(ui2_text_view_changed), 'v@:@')
		macos.add_method(cls, 'textView:doCommandBySelector:', voidptr(ui2_text_view_do_command), 'B@:@:')
		macos.add_method(cls, 'textView:clickedOnLink:atIndex:', voidptr(ui2_text_view_clicked_on_link), 'B@:@@Q')
		macos.add_method(cls, 'ui2BoundsChanged:', voidptr(ui2_bounds_changed), 'v@:@')
		macos.register_class_pair(cls)
	}
	if macos.get_class('UI2Window') == unsafe { nil } {
		cls := macos.allocate_class_pair(macos.get_class('NSWindow'), 'UI2Window')
		macos.add_method(cls, 'sendEvent:', voidptr(ui2_window_send_event), 'v@:@')
		macos.add_method(cls, 'resignKeyWindow', voidptr(ui2_window_release_activation), 'v@:')
		macos.add_method(cls, 'close', voidptr(ui2_window_release_activation), 'v@:')
		macos.add_method(cls, 'keyDown:', voidptr(ui2_window_key_down), 'v@:@')
		macos.add_method(cls, 'performKeyEquivalent:', voidptr(ui2_window_perform_key_equiv), 'B@:@')
		macos.register_class_pair(cls)
	}
	if macos.get_class('UI2MainDispatcher') == unsafe { nil } {
		cls := macos.allocate_class_pair(macos.get_class('NSObject'), 'UI2MainDispatcher')
		macos.add_method(cls, 'runCallback:', voidptr(ui2_dispatch_callback), 'v@:@')
		macos.add_method(cls, 'refreshWindow:', voidptr(ui2_dispatch_window_refresh), 'v@:@')
		macos.add_method(cls, 'captureWindow:', voidptr(ui2_dispatch_window_screenshot), 'v@:@')
		macos.register_class_pair(cls)
	}
}

fn align_value(a Align) int {
	return match a {
		.left { 0 }
		.center { 1 }
		.right { 2 }
	}
}

fn element_rect(r Rect) NativeRect {
	return native_rect(r.x, r.y, r.width, r.height)
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
	w.views = map[string]NativeView{}
	w.view_keys = map[string]string{}
	w.label_places = map[string]LabelPlacement{}
	w.view_kinds = map[string]Kind{}
	w.text_area_direct = map[string]bool{}
	w.pointer_callbacks = map[u64]AppkitCallbackBinding{}
	w.hover_callbacks = map[u64]HoverTarget{}
	w.pointer_clickable = map[u64]bool{}
	w.pointer_buttons = map[u64]bool{}
	w.pointer_draggable = map[u64]bool{}
	w.cursor_ids = map[u64]string{}
	w.control_callbacks = map[u64]AppkitCallbackBinding{}
	w.checkbox_controls = map[u64]bool{}
	w.toggle_groups = map[u64]string{}
	w.toggle_allow_no_selection = map[u64]bool{}
	w.toggle_ids = map[u64]string{}
	w.toggle_views = map[u64]NativeView{}
	w.slider_specs = map[u64]SliderSpec{}
	w.control_change_callbacks = map[u64]AppkitCallbackBinding{}
	w.textview_ids = map[u64]string{}
	w.textview_callbacks = map[u64]AppkitCallbackBinding{}
	w.scroll_callbacks = map[u64]AppkitCallbackBinding{}
	native_set_box_background(w.root_view, root.box)
	// Controls draw in the window's appearance. ui2 paints the content itself,
	// so the window takes the appearance its root's declared colors call for,
	// not the system's: a dark-mode bezel would vanish on a light screen.
	native_match_appearance(w.window, root.box, root.text_style.color)
	mut active := map[string]bool{}
	w.render_children(w.root_view, root.children, '', mut active)
	w.remove_stale_nodes(active)
	w.reconcile_appkit_focus(root, previous_focus)
	// Content can move under a pointer that stays put.
	w.native_update_hover()
}

fn (mut w Window) render_children(parent NativeView, children []Element, parent_key string, mut active map[string]bool) {
	mut previous := native_nil_view()
	for i, child in children {
		key := reconciliation_child_key(parent_key, i, child)
		native := w.render_element(parent, child, key, mut active)
		if child.kind == .screen {
			continue
		}
		native_place_subview(parent, native, previous)
		previous = native
	}
}

fn (mut w Window) render_element(parent NativeView, el Element, key string, mut active map[string]bool) NativeView {
	active[key] = true
	mut native := w.nodes[key] or { native_nil_view() }
	existing_kind := w.node_kinds[key] or { Kind.screen }
	existing_direct := w.node_text_direct[key] or { false }
	existing_interactive := w.node_interactive[key] or { false }
	existing_secure := w.node_secure[key] or { false }
	interactive := element_interactive(el)
	text_area_mode_changed := el.kind == .text_area && existing_kind == .text_area
		&& existing_direct != el.disable_scroll
	interactive_changed := (el.kind == .view || el.kind == .image) && existing_kind == el.kind
		&& existing_interactive != interactive
	label_boxed_changed := el.kind == .label && existing_kind == .label
		&& (w.node_label_boxed[key] or { false }) != label_needs_container(el)
	secure_changed := el.kind == .text_field && existing_kind == .text_field
		&& existing_secure != el.secure
	declared_text_changed := key !in w.node_declared_text || (w.node_declared_text[key] or { '' }) != el.text
	content_sig := text_area_content_signature(el)
	content_changed := key !in w.node_content_sig || (w.node_content_sig[key] or { '' }) != content_sig
	if native_is_nil(native) || existing_kind != el.kind || text_area_mode_changed
		|| interactive_changed || secure_changed || label_boxed_changed {
		old_native := native
		mut create_el := el
		mut restore_editing := false
		mut restore_location := u64(0)
		mut restore_length := u64(0)
		if !native_is_nil(old_native) && existing_kind == .text_field && el.kind == .text_field {
			current := native_text(old_native)
			if !declared_text_changed {
				create_el = Element{
					...el
					text: current
				}
			}
			restore_editing = native_control_is_editing(old_native)
			selected := native_control_selected_range(old_native)
			restore_location = selected.location
			restore_length = selected.length
		} else if !native_is_nil(old_native) && existing_kind == .text_area
			&& el.kind == .text_area {
			old_tv := text_area_text_view(old_native, existing_direct)
			if !declared_text_changed {
				create_el = Element{
					...el
					text: macos.utf8_string(macos.msg_id(old_tv, 'string'))
				}
			}
			restore_editing = w.native_is_first_responder(old_tv)
			selected := native_text_view_selected_range(old_tv)
			restore_location = selected.location
			restore_length = selected.length
		}
		if !native_is_nil(old_native) {
			w.unregister_node(key, old_native, existing_kind, existing_direct)
			if !interactive_changed && existing_kind in [.view, .scroll] {
				w.forget_descendant_nodes(key)
			}
		}
		w.node_tooltips.delete(key)
		w.node_shortened.delete(key)
		native = w.native_create_element(create_el)
		w.nodes[key] = native
		w.node_kinds[key] = el.kind
		w.node_interactive[key] = interactive
		w.node_label_boxed[key] = label_needs_container(el)
		w.node_secure[key] = el.secure
		if el.kind == .text_area {
			w.node_text_direct[key] = el.disable_scroll
		} else {
			w.node_text_direct.delete(key)
		}
		if el.kind != .screen {
			native_add_subview(parent, native)
			if interactive_changed && !native_is_nil(old_native) {
				w.reparent_direct_children(key, native)
			}
			macos.release(native)
		}
		if !native_is_nil(old_native) {
			native_remove_from_superview(old_native)
		}
		if restore_editing {
			if el.kind == .text_field {
				native_restore_control_selection(native, restore_location, restore_length)
			} else if el.kind == .text_area {
				tv := text_area_text_view(native, el.disable_scroll)
				if native_focus(tv) {
					native_text_view_set_selected_range(tv, restore_location, restore_length)
				}
			}
		}
	} else {
		w.native_update_element(native, el, declared_text_changed, content_changed)
	}
	if el.kind != .screen {
		w.register_hover(native, key, el)
		border_box := if el.kind == .toggle_button && el.checked {
			el.toggle_down_box()
		} else {
			el.box
		}
		native_set_box_borders(native, border_box)
	}

	match el.kind {
		.screen {
			native = parent
			w.render_children(parent, el.children, key, mut active)
		}
		.view {
			w.register_pointer(native, el)
			w.render_children(native, el.children, key, mut active)
		}
		.scroll {
			// Observe scroll position changes for virtualized lists
			clip := macos.msg_id(native, 'contentView')
			w.scroll_callbacks[u64(voidptr(clip))] = appkit_binding(el, .scroll)
			if u64(voidptr(clip)) !in w.observed {
				w.observed[u64(voidptr(clip))] = true
				macos.msg_void_bool(clip, 'setPostsBoundsChangedNotifications:', true)
				native_observe_bounds(w.button_handler, clip)
			}
			doc_key := key + '/document'
			active[doc_key] = true
			mut doc := w.nodes[doc_key] or { native_nil_view() }
			if native_is_nil(doc) {
				doc = native_new_flipped_view(native_rect(0, 0, el.frame.width, el.frame.height),
					el.box)
				w.nodes[doc_key] = doc
				w.node_kinds[doc_key] = .view
				native_size_scroll_document(native, doc, el)
				native_set_document_view(native, doc)
				macos.release(doc)
			} else {
				native_set_box_background(doc, el.box)
			}
			// Attaching a document lays the scrollers out, so what shows of a new one is
			// only settled from here.
			native_size_scroll_document(native, doc, el)
			w.render_children(doc, el.children, doc_key, mut active)
		}
		.button {
			w.register_button(native, appkit_binding(el, .click))
		}
		.checkbox {
			w.register_checkbox(native, appkit_binding(el, .change))
		}
		.switch_control {
			w.register_checkbox(native, appkit_binding(el, .change))
		}
		.toggle_button {
			w.register_toggle_button(native, el)
		}
		.dropdown {
			w.register_action_control(native, appkit_binding(el, .change))
		}
		.slider {
			w.register_slider(native, el)
		}
		.text_field {
			w.register_control(native, el)
		}
		.text_area {
			tv := text_area_text_view(native, el.disable_scroll)
			if el.id.len > 0 {
				w.textview_ids[u64(voidptr(tv))] = el.id
				w.text_area_direct[el.id] = el.disable_scroll
			}
			if el.on_event != unsafe { nil } {
				w.textview_callbacks[u64(voidptr(tv))] = appkit_binding(el, .change)
			}
		}
		.label {
			// Labels are updated by native_update_element.
		}
		.image {
			w.register_pointer(native, el)
		}
	}

	if el.kind != .dropdown && el.enabled {
		w.reconcile_menu(key, native, el.menu)
	} else if el.kind != .dropdown {
		w.clear_menu(key, native)
	}
	if el.kind != .screen {
		tooltip := w.native_hover_text(key, native, el)
		previous_tooltip := w.node_tooltips[key] or { '' }
		if previous_tooltip != tooltip {
			macos.msg_void1(native, 'setToolTip:', macos.nsstring(tooltip))
		}
		if tooltip.len > 0 {
			w.node_tooltips[key] = tooltip
		} else {
			// Do not cache the default empty value. Apart from avoiding a map entry
			// per node, this keeps newly-created views from installing thousands of
			// empty AppKit tooltip tracking areas during virtual-list refreshes.
			w.node_tooltips.delete(key)
		}
	}

	if el.id.len > 0 {
		w.views[el.id] = native
		w.view_keys[el.id] = key
		w.view_kinds[el.id] = el.kind
		if el.kind == .label {
			w.label_places[el.id] = LabelPlacement{
				frame:  element_rect(el.frame)
				lines:  text_line_budget(el.text_style.lines)
				valign: el.text_style.valign
				boxed:  label_needs_container(el)
			}
		}
		if el.kind == .scroll {
			// The element exists now, so a position asked for before it did can finally
			// be taken up.
			w.apply_scroll_offset(el.id, false)
		}
	}
	w.node_declared_text[key] = el.text
	w.node_content_sig[key] = content_sig
	apply_common_native_state(native, el)
	return native
}

fn menu_signature(entries []MenuEntry) string {
	mut signature := ''
	for entry in entries {
		signature += '${entry.id.len}:${entry.id}${entry.title.len}:${entry.title};'
	}
	return signature
}

fn (mut w Window) clear_menu(key string, native NativeView) {
	for pointer in w.node_menu_items[key] or { []u64{} } {
		w.control_callbacks.delete(pointer)
	}
	w.node_menu_items.delete(key)
	w.node_menu_sig.delete(key)
	macos.msg_void1(native, 'setMenu:', native_nil_view())
}

fn (mut w Window) reconcile_menu(key string, native NativeView, entries []MenuEntry) {
	signature := menu_signature(entries)
	if (w.node_menu_sig[key] or { '' }) == signature {
		pointers := w.node_menu_items[key] or { []u64{} }
		for index, pointer in pointers {
			if index < entries.len {
				w.control_callbacks[pointer] = AppkitCallbackBinding{ id: entries[index].id, on_event: entries[index].on_select }
			}
		}
		return
	}
	w.clear_menu(key, native)
	if entries.len == 0 {
		return
	}
	w.attach_menu(key, native, entries, signature)
}

// attach_menu uses sender-pointer bindings, so a retained old item can never
// dispatch through a refresh-local positional tag.
fn (mut w Window) attach_menu(key string, native NativeView, entries []MenuEntry, signature string) {
	menu := macos.msg_id(macos.alloc('NSMenu'), 'init')
	mut pointers := []u64{cap: entries.len}
	for e in entries {
		item := macos.msg_id3(macos.alloc('NSMenuItem'), 'initWithTitle:action:keyEquivalent:', macos.nsstring(e.title), macos.Id(voidptr(macos.sel('handleTap:'))), macos.nsstring(''))
		macos.msg_void1(item, 'setTarget:', w.button_handler)
		pointer := u64(voidptr(item))
		w.control_callbacks[pointer] = AppkitCallbackBinding{ id: e.id, on_event: e.on_select }
		pointers << pointer
		macos.msg_void1(menu, 'addItem:', item)
		macos.release(item)
	}
	macos.msg_void1(native, 'setMenu:', menu)
	macos.release(menu)
	w.node_menu_items[key] = pointers
	w.node_menu_sig[key] = signature
}

fn (mut w Window) native_create_element(el Element) NativeView {
	return match el.kind {
		.screen {
			native_nil_view()
		}
		.view {
			native_new_view(element_rect(el.frame), el.box, element_interactive(el))
		}
		.scroll {
			native_new_scroll(element_rect(el.frame), el.box, el.persistent_scrollbars,
				el.scroll_mode)
		}
		.label {
			native_new_label(element_rect(el.frame), el.text, el.text_style.color, el.text_style.size, el.text_style.font_family, text_style_weight(el.text_style), el.text_style.italic, el.text_style.underline, align_value(el.text_style.align), text_line_budget(el.text_style.lines), el.text_style.valign, label_needs_container(el), mut w.label_line_heights)
		}
		.image {
			w.native_new_image(element_rect(el.frame), el.image_path, el.text_style.color)
		}
		.button {
			native_new_button(element_rect(el.frame), el.text, el.box, el.text_style.color, el.text_style.size, text_style_weight(el.text_style), el.text_style.italic, el.text_style.underline, text_line_budget(el.text_style.lines), el.image_path, el.native_style)
		}
		.checkbox {
			native_new_checkbox(el)
		}
		.switch_control {
			native_new_switch_control(el)
		}
		.toggle_button {
			native_new_toggle_button(el)
		}
		.dropdown {
			native_new_dropdown(el)
		}
		.text_field {
			native_new_text_field(el)
		}
		.text_area {
			w.native_new_text_area(el)
		}
		.slider {
			native_new_slider(el)
		}
	}
}

fn (mut w Window) native_update_element(native NativeView, el Element, declared_text_changed bool, content_changed bool) {
	match el.kind {
		.screen {}
		.view {
			native_set_frame(native, element_rect(el.frame))
			native_set_box_background(native, el.box)
			native_set_box_corners(native, el.box)
		}
		.scroll {
			native_set_frame(native, element_rect(el.frame))
			native_set_scroll_background(native, el.box)
			native_set_scroll_axes(native, el.scroll_mode)
			native_set_scrollbar_mode(native, el.persistent_scrollbars)
		}
		.label {
			native_update_label(native, element_rect(el.frame), el.text, el.text_style.color, el.text_style.size, el.text_style.font_family, text_style_weight(el.text_style), el.text_style.italic, el.text_style.underline, align_value(el.text_style.align), text_line_budget(el.text_style.lines), el.text_style.valign, label_needs_container(el), mut w.label_line_heights)
		}
		.image {
			w.native_update_image(native, element_rect(el.frame), el.image_path, el.text_style.color)
		}
		.button {
			native_update_button(native, element_rect(el.frame), el.text, el.box, el.text_style.color, el.text_style.size, text_style_weight(el.text_style), el.text_style.italic, el.text_style.underline, text_line_budget(el.text_style.lines), el.image_path, el.native_style)
		}
		.checkbox {
			native_update_checkbox(native, el)
		}
		.switch_control {
			native_update_switch_control(native, el)
		}
		.toggle_button {
			native_update_toggle_button(native, el)
		}
		.dropdown {
			native_update_dropdown(native, el)
		}
		.text_field {
			native_update_text_field(native, element_rect(el.frame), el.placeholder, el.text,
				el.box, el.text_style.color, el.text_style.size,
				declared_text_changed, el.readonly, el.enabled, el.text_style.align)
		}
		.text_area {
			w.native_update_text_area(native, el, declared_text_changed, content_changed)
		}
		.slider {
			native_update_slider(native, el)
		}
	}
}

fn element_interactive(el Element) bool {
	return el.clickable || (el.kind == .view && el.button_behavior) || el.draggable
		|| el.cursor.len > 0
}

fn (mut w Window) register_pointer(native NativeView, el Element) {
	key := u64(voidptr(native))
	w.pointer_callbacks.delete(key)
	w.pointer_clickable.delete(key)
	w.pointer_buttons.delete(key)
	w.pointer_draggable.delete(key)
	w.cursor_ids.delete(key)
	if el.enabled && !el.hidden && el.on_event != unsafe { nil }
		&& (el.clickable || (el.kind == .view && el.button_behavior) || el.draggable) {
		w.pointer_callbacks[key] = appkit_binding(el, .click)
		w.pointer_clickable[key] = el.clickable
		w.pointer_buttons[key] = el.kind == .view && el.button_behavior
		w.pointer_draggable[key] = el.draggable
	}
	if el.cursor.len > 0 {
		w.cursor_ids[key] = el.cursor
	}
	if element_interactive(el) {
		native_invalidate_cursor_rects(native)
	}
}

fn (mut w Window) register_hover(native NativeView, key string, el Element) {
	if target := hover_target(key, el) {
		w.hover_callbacks[u64(voidptr(native))] = target
	}
}

@[export: 'ui2_root_mouse_moved']
fn ui2_root_mouse_moved(self voidptr, _cmd voidptr, event voidptr) {
	mut w := appkit_window_for(self) or { return }
	if NativeView(self) != w.root_view {
		return
	}
	w.hover_window_point = macos.msg_point(event, 'locationInWindow')
	w.hover_root_point = native_event_point(w.root_view, event)
	w.hover_inside = true
	w.native_update_hover()
}

@[export: 'ui2_root_mouse_exited']
fn ui2_root_mouse_exited(self voidptr, _cmd voidptr, event voidptr) {
	mut w := appkit_window_for(self) or { return }
	if NativeView(self) != w.root_view {
		return
	}
	w.hover_root_point = native_event_point(w.root_view, event)
	w.hover_inside = false
	w.native_update_hover()
}

// native_hovered_chain returns the hoverable elements at a window point, outermost
// first: the topmost view there and its superviews, as CSS :hover counts them.
// hitTest: skips hidden views and the parts of a scroll view's content clipped away.
fn (mut w Window) native_hovered_chain(window_point macos.Point) []HoverTarget {
	if w.hover_callbacks.len == 0 || native_is_nil(w.root_view) {
		return []HoverTarget{}
	}
	// hitTest: takes a point in the receiver's superview, which for the window's
	// content view shares the window's coordinates.
	superview := macos.msg_id(w.root_view, 'superview')
	point := if objc_is_nil(superview) {
		window_point
	} else {
		macos.msg_point_point_id(superview, 'convertPoint:fromView:', window_point, objc_nil())
	}
	mut hit_view := NativeView(C.ui2_macos_msg_id_point(w.root_view, macos.sel('hitTest:'), point.x,
		point.y))
	mut inner_first := []HoverTarget{}
	for !native_is_nil(hit_view) {
		if target := w.hover_callbacks[u64(voidptr(hit_view))] {
			inner_first << target
		}
		if hit_view == w.root_view {
			break
		}
		hit_view = NativeView(macos.msg_id(hit_view, 'superview'))
	}
	return inner_first.reverse()
}

fn (mut w Window) native_update_hover() {
	current := if w.hover_inside { w.native_hovered_chain(w.hover_window_point) } else { []HoverTarget{} }
	left, entered := hover_transitions(w.hovered, current)
	w.hovered = current
	point := w.hover_root_point
	for pending in hover_events(left, entered, point.x, point.y) {
		pending.fire(w)
	}
}

fn (mut w Window) register_button(native NativeView, binding AppkitCallbackBinding) {
	pointer := u64(voidptr(native))
	w.control_callbacks[pointer] = binding
	w.checkbox_controls.delete(pointer)
	native_set_button_target(native, w.button_handler)
	native_set_associated_object(native, assoc_handler_key(), w.button_handler)
}

fn (mut w Window) register_checkbox(native NativeView, binding AppkitCallbackBinding) {
	pointer := u64(voidptr(native))
	w.control_callbacks[pointer] = binding
	w.checkbox_controls[pointer] = true
	native_set_button_target(native, w.button_handler)
	native_set_associated_object(native, assoc_handler_key(), w.button_handler)
}

fn (mut w Window) register_toggle_button(native NativeView, el Element) {
	w.register_checkbox(native, appkit_binding(el, .change))
	pointer := u64(voidptr(native))
	w.toggle_groups[pointer] = el.toggle_group()
	w.toggle_allow_no_selection[pointer] = el.toggle_allow_no_selection()
	w.toggle_ids[pointer] = el.id
	w.toggle_views[pointer] = native
	if macos.msg_i64(native, 'state') != 0 {
		w.release_macos_toggle_group(pointer)
	}
}

fn (mut w Window) release_macos_toggle_group(pointer u64) {
	group := w.toggle_groups[pointer] or { return }
	if group.len == 0 {
		return
	}
	for member_pointer, member_group in w.toggle_groups {
		if member_pointer == pointer || member_group != group {
			continue
		}
		native := w.toggle_views[member_pointer] or { continue }
		macos.msg_void_i64(native, 'setState:', i64(0))
	}
}

fn (mut w Window) commit_macos_toggle_button(pointer u64, native NativeView) {
	group := w.toggle_groups[pointer] or { return }
	if group.len == 0 {
		return
	}
	if macos.msg_i64(native, 'state') != 0 {
		w.release_macos_toggle_group(pointer)
	} else if !(w.toggle_allow_no_selection[pointer] or { true }) {
		macos.msg_void_i64(native, 'setState:', i64(1))
	}
}

fn (mut w Window) register_action_control(native NativeView, binding AppkitCallbackBinding) {
	pointer := u64(voidptr(native))
	w.control_callbacks[pointer] = binding
	native_set_control_target(native, w.button_handler)
	native_set_associated_object(native, assoc_handler_key(), w.button_handler)
}

fn (mut w Window) register_slider(native NativeView, el Element) {
	pointer := u64(voidptr(native))
	w.slider_specs[pointer] = slider_spec(el)
	w.register_action_control(native, appkit_binding(el, .change))
}

fn (mut w Window) register_control(native NativeView, el Element) {
	pointer := u64(voidptr(native))
	w.control_callbacks.delete(pointer)
	w.control_change_callbacks.delete(pointer)
	if el.on_event != unsafe { nil } {
		w.control_callbacks[pointer] = appkit_binding(el, .submit)
		w.control_change_callbacks[pointer] = appkit_binding(el, .change)
		native_set_control_target(native, w.button_handler)
		macos.msg_void1(native, 'setDelegate:', w.button_handler)
		native_set_associated_object(native, assoc_handler_key(), w.button_handler)
	} else {
		native_clear_control_target(native)
		macos.msg_void1(native, 'setDelegate:', native_nil_view())
		native_set_associated_object(native, assoc_handler_key(), native_nil_view())
	}
}

fn (mut w Window) unregister_node(key string, native NativeView, kind Kind, text_direct bool) {
	pointer := u64(voidptr(native))
	if w.pointer_button_down == pointer {
		w.pointer_button_down = 0
		w.pointer_button_moved = false
		w.pointer_button_binding = AppkitCallbackBinding{}
	}
	w.pointer_callbacks.delete(pointer)
	w.image_symbols.delete(pointer)
	w.pointer_clickable.delete(pointer)
	w.pointer_buttons.delete(pointer)
	w.pointer_draggable.delete(pointer)
	w.cursor_ids.delete(pointer)
	w.control_callbacks.delete(pointer)
	// Keep a cancelled snapshot until the native tracking loop exits. Reusing an
	// id (or installing a callback during the press) cannot redirect that action.
	if pointer in w.control_captures { w.control_captures[pointer] = AppkitCallbackBinding{} }
	w.checkbox_controls.delete(pointer)
	w.toggle_groups.delete(pointer)
	w.toggle_allow_no_selection.delete(pointer)
	w.toggle_ids.delete(pointer)
	w.toggle_views.delete(pointer)
	w.slider_specs.delete(pointer)
	w.control_change_callbacks.delete(pointer)
	if kind == .text_field {
		native_clear_control_target(native)
		macos.msg_void1(native, 'setDelegate:', native_nil_view())
	}
	if kind == .text_area {
		tv := text_area_text_view(native, text_direct)
		if !native_is_nil(tv) {
			w.textview_ids.delete(u64(voidptr(tv)))
			w.textview_callbacks.delete(u64(voidptr(tv)))
			macos.msg_void1(tv, 'setDelegate:', native_nil_view())
		}
	}
	if kind == .scroll {
		w.scroll_forwarding.delete(u64(voidptr(native)))
		clip := macos.msg_id(native, 'contentView')
		clip_pointer := u64(voidptr(clip))
		w.scroll_callbacks.delete(clip_pointer)
		if clip_pointer in w.observed {
			native_unobserve_bounds(w.button_handler, clip)
			w.observed.delete(clip_pointer)
		}
	}
	w.clear_menu(key, native)
}

fn (mut w Window) reparent_direct_children(key string, new_parent NativeView) {
	prefix := key + '/'
	for child_key_, child in w.nodes {
		if !child_key_.starts_with(prefix) {
			continue
		}
		remainder := child_key_[prefix.len..]
		if !remainder.contains('/') {
			native_add_subview(new_parent, child)
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
		w.unregister_node(child_key_, child, w.node_kinds[child_key_] or { Kind.view }, w.node_text_direct[child_key_] or { false })
		w.nodes.delete(child_key_)
		w.node_kinds.delete(child_key_)
		w.node_text_direct.delete(child_key_)
		w.node_interactive.delete(child_key_)
		w.node_label_boxed.delete(child_key_)
		w.node_secure.delete(child_key_)
		w.node_declared_text.delete(child_key_)
		w.node_content_sig.delete(child_key_)
		w.node_tooltips.delete(child_key_)
		w.node_shortened.delete(child_key_)
	}
}

fn (mut w Window) native_is_first_responder(view NativeView) bool {
	if native_is_nil(w.window) || native_is_nil(view) {
		return false
	}
	return macos.msg_id(w.window, 'firstResponder') == view
}

fn text_area_content_signature(el Element) string {
	if el.kind != .text_area {
		return ''
	}
	return '${el.text_style}|${el.text_runs}'
}

fn apply_common_native_state(native NativeView, el Element) {
	if native_is_nil(native) || el.kind == .screen {
		return
	}
	native_apply_common_view_state(native, el.hidden, el.enabled, el.accessibility_role, el.accessibility_label, el.accessibility_value)
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
		kind := w.node_kinds[key] or { Kind.view }
		direct := w.node_text_direct[key] or { false }
		w.unregister_node(key, native, kind, direct)
	}
	for key in stale {
		native := w.nodes[key] or { continue }
		if !node_has_ancestor_in_set(key, stale_set) {
			// Removing a native parent already removes its whole subtree. Avoid
			// making the same AppKit call again for every stale descendant.
			native_remove_from_superview(native)
		}
	}
	for key in stale {
		w.nodes.delete(key)
		w.node_kinds.delete(key)
		w.node_text_direct.delete(key)
		w.node_interactive.delete(key)
		w.node_label_boxed.delete(key)
		w.node_secure.delete(key)
		w.node_declared_text.delete(key)
		w.node_content_sig.delete(key)
		w.node_tooltips.delete(key)
		w.node_shortened.delete(key)
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

fn content_height(children []Element) f64 {
	mut h := f64(0)
	for child in children {
		bottom := child.frame.y + child.frame.height
		if bottom > h {
			h = bottom
		}
	}
	return h
}

// native_size_scroll_document gives a Scroll element's document the size its content
// and what shows of it call for. The mask goes on first: sizing the document can bring
// a scroller in or take one away, which changes what shows, and a side held to that
// has to follow it rather than keep the length measured a moment earlier.
fn native_size_scroll_document(scroll NativeView, doc NativeView, el Element) {
	shown := macos.msg_rect(macos.msg_id(scroll, 'contentView'), 'bounds')
	document := scroll_document_size(el, shown.width, shown.height)
	macos.msg_void_u64(doc, 'setAutoresizingMask:', document.autoresizing_mask())
	native_set_frame(doc, native_rect(0, 0, document.width, document.height))
}

// ScrollDocument is the size of the view a Scroll element scrolls over, and which of
// its sides are as long as what shows rather than as long as the content.
struct ScrollDocument {
	width          f64
	height         f64
	follows_width  bool
	follows_height bool
}

fn (document ScrollDocument) autoresizing_mask() u64 {
	mut mask := u64(0)
	if document.follows_width {
		mask |= ns_view_width_sizable
	}
	if document.follows_height {
		mask |= ns_view_height_sizable
	}
	return mask
}

// scroll_document_size sizes the view a Scroll element scrolls over. An axis its mode
// scrolls covers the content and is never shorter than what shows; one it leaves out
// is held to what shows, so there is nothing along it to scroll to. What shows is
// measured from the scroll view rather than taken from the frame, because a scroller
// that takes room of its own makes it less, and a document sized to the frame would
// then have a range the width of that scroller: one a wheel could push the element
// into along an axis it is not meant to scroll.
fn scroll_document_size(el Element, visible_width f64, visible_height f64) ScrollDocument {
	shown_width := if visible_width > 0 { visible_width } else { el.frame.width }
	shown_height := if visible_height > 0 { visible_height } else { el.frame.height }
	scrolls_x := el.scroll_mode != .vertical_only
	scrolls_y := el.scroll_mode != .horizontal_only
	content_width := if scrolls_x { scroll_content_width(el.children) } else { 0.0 }
	fits_across := content_width <= shown_width
	return ScrollDocument{
		width:          if fits_across { shown_width } else { content_width }
		height:         if scrolls_y { content_height(el.children) + 16 } else { shown_height }
		follows_width:  fits_across
		follows_height: !scrolls_y
	}
}

fn assoc_handler_key() voidptr {
	return voidptr(macos.sel('ui2_button_handler_assoc'))
}

fn native_border_key(side string) voidptr {
	return voidptr(macos.sel('ui2_border_${side}_assoc'))
}

fn native_rect(x f64, y f64, width f64, height f64) NativeRect {
	return NativeRect{
		x: x
		y: y
		width: width
		height: height
	}
}

fn appkit_rect(r NativeRect) macos.Rect {
	return macos.rect(r.x, r.y, r.width, r.height)
}

fn native_nil_view() NativeView {
	return NativeView(unsafe { nil })
}

fn native_is_nil(v NativeView) bool {
	return voidptr(v) == unsafe { nil }
}

fn native_color(hex u32) macos.Id {
	return native_color_from_hex(hex)
}

fn native_run_app() {
	macos.msg_void(native_current_app(), 'run')
}

fn native_current_app() macos.Id {
	return macos.msg_id(macos.get_class('NSApplication'), 'sharedApplication')
}

fn native_activate() {
	macos.msg_void_bool(native_current_app(), 'activateIgnoringOtherApps:', true)
}

fn native_set_activation_policy_regular() {
	macos.msg_void_i64(native_current_app(), 'setActivationPolicy:', 0)
}

fn native_set_delegate(delegate NativeView) {
	macos.msg_void1(native_current_app(), 'setDelegate:', delegate)
}

fn native_new_window(frame NativeRect, title string) NativeView {
	style := ns_window_style_titled | ns_window_style_closable | ns_window_style_miniaturizable | ns_window_style_resizable
	window := macos.msg_id_rect_u64_u64_bool(macos.alloc('UI2Window'), 'initWithContentRect:styleMask:backing:defer:', appkit_rect(frame), style, ns_backing_store_buffered, false)
	macos.msg_void1(window, 'setTitle:', macos.nsstring(title))
	macos.msg_void_bool(window, 'setReleasedWhenClosed:', false)
	return window
}

fn native_make_key_and_order_front(window NativeView) {
	macos.msg_void1(window, 'makeKeyAndOrderFront:', native_nil_view())
}

fn native_set_content_view(window NativeView, view NativeView) {
	macos.msg_void1(window, 'setContentView:', view)
}

fn native_set_content_min_size(window NativeView, width f64, height f64) {
	macos.msg_void_point(window, 'setContentMinSize:', macos.point(width, height))
}

fn native_bounds(view NativeView) NativeRect {
	b := macos.msg_rect(view, 'bounds')
	return native_rect(b.x, b.y, b.width, b.height)
}

fn native_add_subview(parent NativeView, child NativeView) {
	macos.msg_void1(parent, 'addSubview:', child)
}

fn native_place_subview(parent NativeView, child NativeView, previous NativeView) {
	if native_is_nil(parent) || native_is_nil(child) {
		return
	}
	objc_place_subview(parent, child, previous)
}

fn native_remove_from_superview(view NativeView) {
	if native_is_nil(view) {
		return
	}
	macos.msg_void(view, 'removeFromSuperview')
}

fn native_invalidate_cursor_rects(view NativeView) {
	if native_is_nil(view) {
		return
	}
	objc_invalidate_cursor_rects(view)
}

fn native_new_object(class_name string) NativeView {
	return macos.msg_id(macos.alloc(class_name), 'init')
}

fn native_set_associated_object(obj NativeView, key voidptr, value NativeView) {
	macos.set_associated_object(obj, key, value, macos.assoc_retain_nonatomic)
}

fn native_new_flipped_view(frame NativeRect, box BoxStyle) NativeView {
	native := macos.msg_id_rect(macos.alloc('UI2FlippedView'), 'initWithFrame:', appkit_rect(frame))
	native_set_box_background(native, box)
	return native
}

fn native_new_view(frame NativeRect, box BoxStyle, interactive bool) NativeView {
	class_name := if interactive {
		'UI2PointerView'
	} else if macos.get_class('UI2PointerChildView') == unsafe { nil } {
		'UI2FlippedView'
	} else {
		'UI2PointerChildView'
	}
	native := macos.msg_id_rect(macos.alloc(class_name), 'initWithFrame:', appkit_rect(frame))
	native_set_box_background(native, box)
	native_set_box_corners(native, box)
	return native
}

fn native_new_scroll(frame NativeRect, box BoxStyle, persistent_scrollbars bool, mode ScrollMode) NativeView {
	scroll_view := macos.msg_id_rect(macos.alloc('UI2ScrollView'), 'initWithFrame:', appkit_rect(frame))
	native_set_scroll_axes(scroll_view, mode)
	native_set_scrollbar_mode(scroll_view, persistent_scrollbars)
	native_set_scroll_background(scroll_view, box)
	return scroll_view
}

// native_set_scroll_axes gives a scroll view a scroller for each axis its mode scrolls.
fn native_set_scroll_axes(scroll NativeView, mode ScrollMode) {
	macos.msg_void_bool(scroll, 'setHasVerticalScroller:', mode != .horizontal_only)
	macos.msg_void_bool(scroll, 'setHasHorizontalScroller:', mode != .vertical_only)
}

fn native_set_scrollbar_mode(scroll NativeView, persistent bool) {
	// NSScrollerStyleLegacy is 0 and overlay is 1.
	macos.msg_void_i64(scroll, 'setScrollerStyle:', if persistent { i64(0) } else { i64(1) })
	macos.msg_void_bool(scroll, 'setAutohidesScrollers:', !persistent)
}

fn native_set_document_view(scroll NativeView, view NativeView) {
	macos.msg_void1(scroll, 'setDocumentView:', view)
}

fn native_set_scroll_background(scroll NativeView, box BoxStyle) {
	draws_background := box_draws_fill(box)
	macos.msg_void_bool(scroll, 'setDrawsBackground:', draws_background)
	if draws_background {
		macos.msg_void1(scroll, 'setBackgroundColor:', native_color(box.bg))
	}
}

fn (mut w Window) native_new_image(frame NativeRect, path string, tint u32) NativeView {
	image_view := macos.msg_id_rect(macos.alloc('UI2PointerImageView'), 'initWithFrame:', appkit_rect(frame))
	w.native_update_image(image_view, frame, path, tint)
	return image_view
}

// A `symbol:` path draws that SF Symbol, scaled to the frame and tinted with the
// element's text color the way the other backends tint its glyph; a file image
// keeps its own colors.
fn (mut w Window) native_update_image(image_view NativeView, frame NativeRect, path string, tint u32) {
	native_set_frame(image_view, frame)
	macos.msg_void_i64(image_view, 'setImageScaling:', 3)
	if path.trim_space() == '' {
		macos.msg_void1(image_view, 'setImage:', macos.Id(unsafe { nil }))
		return
	}
	tints := macos.responds_to(image_view, 'setContentTintColor:')
	pointer := u64(voidptr(image_view))
	if path.starts_with('symbol:') {
		// Looking a symbol up and tinting it again on every refresh cost half the
		// main thread while an animation kept the window refreshing.
		symbol_sig := '${path}:${tint}'
		if (w.image_symbols[pointer] or { '' }) == symbol_sig {
			return
		}
		w.image_symbols[pointer] = symbol_sig
		macos.msg_void1(image_view, 'setImage:', native_image_from_name(path))
		if tints {
			macos.msg_void1(image_view, 'setContentTintColor:', native_color(tint))
		}
		return
	}
	w.image_symbols.delete(pointer)
	if tints {
		macos.msg_void1(image_view, 'setContentTintColor:', macos.Id(unsafe { nil }))
	}
	img := macos.msg_id1(macos.alloc('NSImage'), 'initWithContentsOfFile:', macos.nsstring(path))
	macos.msg_void1(image_view, 'setImage:', img)
	if !native_is_nil(img) {
		macos.release(img)
	}
}

fn native_new_label(frame NativeRect, text string, text_hex u32, size f64, family string, weight int, italic bool, underline bool, align int, lines int, valign VAlign, boxed bool, mut heights map[string]f64) NativeView {
	inner := if boxed {
		NativeRect{
			width:  frame.width
			height: frame.height
		}
	} else {
		frame
	}
	label_class := if macos.get_class('UI2PointerLabel') == unsafe { nil } {
		'NSTextField'
	} else {
		'UI2PointerLabel'
	}
	field := macos.msg_id_rect(macos.alloc(label_class), 'initWithFrame:', appkit_rect(inner))
	if !boxed {
		native_update_label(field, frame, text, text_hex, size, family, weight, italic,
			underline, align, lines, valign, boxed, mut heights)
		return field
	}
	container := macos.msg_id_rect(macos.alloc('UI2FlippedView'), 'initWithFrame:', appkit_rect(frame))
	native_add_subview(container, field)
	macos.release(field)
	native_update_label(container, frame, text, text_hex, size, family, weight, italic, underline,
		align, lines, valign, boxed, mut heights)
	return container
}

// What a label's text was last laid out against, kept for the labels that can be
// written to by id so setting their text can place the new text the same way the
// layout would have. Only those labels are kept: a grid of thousands of unnamed ones
// pays nothing for a setter it can never be the target of.
struct LabelPlacement {
	frame  NativeRect
	lines  int
	valign VAlign
	boxed  bool
}

// The text field a label draws with: the view itself, or the one it holds.
fn label_text_field(view NativeView) NativeView {
	subviews := macos.msg_id(view, 'subviews')
	if native_is_nil(subviews) || macos.msg_u64(subviews, 'count') == 0 {
		return view
	}
	return NativeView(macos.msg_id_u64(subviews, 'objectAtIndex:', 0))
}

fn native_update_label(view NativeView, frame NativeRect, text string, text_hex u32, size f64, family string, weight int, italic bool, underline bool, align int, lines int, valign VAlign, boxed bool, mut heights map[string]f64) {
	native_set_frame(view, frame)
	label_view := if boxed { label_text_field(view) } else { view }
	macos.msg_void1(label_view, 'setStringValue:', macos.nsstring(text))
	macos.msg_void_bool(label_view, 'setEditable:', false)
	macos.msg_void_bool(label_view, 'setSelectable:', false)
	macos.msg_void_bool(label_view, 'setBordered:', false)
	macos.msg_void_bool(label_view, 'setBezeled:', false)
	macos.msg_void_bool(label_view, 'setDrawsBackground:', false)
	macos.msg_void1(label_view, 'setTextColor:', native_color(text_hex))
	macos.msg_void1(label_view, 'setFont:', native_text_style_font(TextStyle{
		size:        size
		font_family: family
		weight:      weight
		italic:      italic
	}))
	if italic || underline {
		native_control_set_attributed_title(label_view, text, text_hex, size, family, weight, italic,
			underline)
	}
	macos.msg_void_i64(label_view, 'setAlignment:', native_text_alignment(align))
	native_apply_line_limit(label_view, lines)
	// Only NSTextField carries a line budget; an NSButton has none to set.
	macos.msg_void_i64(label_view, 'setMaximumNumberOfLines:', i64(if lines > 1 {
		lines
	} else {
		1
	}))
	native_place_label_text(label_view, frame, lines, valign, boxed, mut heights)
}

// Put the text field back over the whole area the label was laid out with, then move
// its drawing to where this text wants to sit. Going back first is what lets text
// that has changed be measured against the label's real width and given all the room
// the label has, rather than the strip the text before it happened to need.
fn native_place_label_text(label_view NativeView, frame NativeRect, lines int, valign VAlign, boxed bool, mut heights map[string]f64) {
	native_set_frame(label_view, if boxed {
		NativeRect{
			width:  frame.width
			height: frame.height
		}
	} else {
		frame
	})
	native_apply_label_valign(label_view, frame, lines, valign, boxed, mut heights)
}

// A text field draws its content from the top of its frame however tall that frame
// is, so a label given a box taller than its text needs the text block moved to sit
// in the middle or at the bottom.
//
// The drawing is moved, not the field. The field keeps the frame it was given, so the
// tooltip, the context menu and any pointer attached to the label still answer over
// the whole area the caller laid out, not just the strip the text ended up on.
fn native_apply_label_valign(label_view NativeView, frame NativeRect, lines int, valign VAlign, boxed bool, mut heights map[string]f64) {
	if valign == .top || frame.height <= 0 {
		return
	}
	content := native_label_content_height(label_view, frame, lines, mut heights)
	if content <= 0 || content >= frame.height {
		return
	}
	offset := if valign == .middle { (frame.height - content) / 2 } else { frame.height - content }
	// Inside the holding view when there is one, so that view keeps the declared frame.
	native_set_frame(label_view, if boxed {
		NativeRect{
			y:      offset
			width:  frame.width
			height: content
		}
	} else {
		NativeRect{
			x:      frame.x
			y:      frame.y + offset
			width:  frame.width
			height: content
		}
	})
}

// How tall the field's text is.
//
// Wrapped text is only as tall as the lines it broke into, which depends on the width
// it had to break against. Telling the field that width makes its intrinsic size the
// size the text really wants, so that is what a wrapping label is measured by.
//
// One line is not the font's ascender, descender and leading: the cell lays it out a
// little taller, and some faces (Helvetica) much taller, so a field cut to those
// metrics clips descenders. A line of ASCII is as tall as its font makes it, so that
// is measured once per font and a grid of labels pays no layout pass for it. Other
// text may draw with a taller fallback face and is measured each time.
fn native_label_content_height(label_view NativeView, frame NativeRect, lines int, mut heights map[string]f64) f64 {
	if lines > 1 {
		macos.msg_void_f64(label_view, 'setPreferredMaxLayoutWidth:', frame.width)
		// Point carries a Cocoa size as well as a point; y is the height.
		return macos.msg_point(label_view, 'intrinsicContentSize').y
	}
	font := macos.msg_id(label_view, 'font')
	if native_is_nil(font) {
		return 0
	}
	label_text := macos.utf8_string(macos.msg_id(label_view, 'stringValue'))
	if label_text.len == 0 {
		return 0
	}
	if !label_text.is_ascii() {
		return native_single_line_height(label_view)
	}
	key := '${macos.utf8_string(macos.msg_id(font, 'fontName'))}:${macos.msg_f64(font, 'pointSize')}'
	if height := heights[key] {
		return height
	}
	height := native_single_line_height(label_view)
	heights[key] = height
	return height
}

// A width left over from when the label wrapped would make it measure as wrapped.
fn native_single_line_height(label_view NativeView) f64 {
	macos.msg_void_f64(label_view, 'setPreferredMaxLayoutWidth:', 0)
	return macos.msg_point(label_view, 'intrinsicContentSize').y
}

// NSLineBreakMode values.
const ns_line_break_by_word_wrapping = 0
const ns_line_break_by_truncating_tail = 4

// Give a control its line budget. One line means whatever does not fit is truncated,
// which is what a button title and an ordinary label want. More than one line only
// means anything if the text may flow onto them, so the break mode has to change with
// it: left at truncate-tail, a multi-line label still laid its text out on one line
// and clipped the rest, and asking for more lines did nothing.
fn native_apply_line_limit(view NativeView, lines int) {
	single := lines <= 1
	cell := macos.msg_id(view, 'cell')
	macos.msg_void_i64(cell, 'setLineBreakMode:', if single {
		ns_line_break_by_truncating_tail
	} else {
		ns_line_break_by_word_wrapping
	})
	macos.msg_void_bool(cell, 'setUsesSingleLineMode:', single)
	// Wrapped text that outgrows its budget ends in an ellipsis rather than being cut
	// off mid-line.
	macos.msg_void_bool(cell, 'setTruncatesLastVisibleLine:', !single)
}

// What a control was last measured with, and whether its text had to be cut short.
// A refresh visits every node, so a control is measured again only when something the
// measurement depends on has changed.
struct ShortenedText {
	text      string
	width     f64
	height    f64
	size      f64
	family    string
	weight    int
	italic    bool
	image     string
	shortened bool
}

// What a control shows when the pointer rests on it: the help its caller gave it, or
// else, when its text did not fit and ends in an ellipsis, the whole of that text.
// Without it the rest of a shortened title can only be read by resizing something.
fn (mut w Window) native_hover_text(key string, native NativeView, el Element) string {
	if el.tooltip.len > 0 {
		return el.tooltip
	}
	full_text := shortenable_text(el)
	if full_text.len == 0 || el.frame.width <= 0 || native_is_nil(native) {
		return ''
	}
	if text_surely_fits(full_text, el) {
		return ''
	}
	if cached := w.node_shortened[key] {
		if cached.text == full_text && cached.width == el.frame.width
			&& cached.height == el.frame.height && cached.size == el.text_style.size
			&& cached.family == el.text_style.font_family && cached.weight == text_style_weight(el.text_style) && cached.italic == el.text_style.italic
			&& cached.image == el.image_path {
			return if cached.shortened { full_text } else { '' }
		}
	}
	shortened := native_text_shortened(native, el)
	w.node_shortened[key] = ShortenedText{
		text:      full_text
		width:     el.frame.width
		height:    el.frame.height
		size:      el.text_style.size
		family:    el.text_style.font_family
		weight:    text_style_weight(el.text_style)
		italic:    el.text_style.italic
		image:     el.image_path
		shortened: shortened
	}
	return if shortened { full_text } else { '' }
}

// The text AppKit truncates with an ellipsis: a one-line label, a button or check box
// title, and the selected entry of a dropdown. Editable text scrolls rather than being
// shortened, and wrapped text is left to the lines it was given.
fn shortenable_text(el Element) string {
	return match el.kind {
		.label, .button, .toggle_button, .checkbox {
			if text_line_budget(el.text_style.lines) > 1 { '' } else { el.text }
		}
		.dropdown {
			el.text
		}
		else {
			''
		}
	}
}

// No glyph in a UI font is much wider than the font is tall, so text that would fit
// with every character that wide, beside whatever the control draws next to it, needs
// no measuring. Most labels in a grid are short numbers and stop here.
fn text_surely_fits(text string, el Element) bool {
	size := if el.text_style.size > 0 { el.text_style.size } else { 13.0 }
	reserve := match el.kind {
		.label { 6.0 }
		.checkbox { 28.0 }
		.dropdown { 44.0 }
		else { if el.image_path.len > 0 { 36.0 } else { 16.0 } }
	}
	return f64(text.len_utf8()) * size * 1.3 + reserve <= el.frame.width
}

// Whether AppKit has had to shorten the control's text. A label's cell reports the
// width its whole text needs; a button's title is measured against the part of the
// frame its cell leaves for the title once the image, check box or arrows are drawn.
fn native_text_shortened(native NativeView, el Element) bool {
	if el.kind == .label {
		field := if label_needs_container(el) { label_text_field(native) } else { native }
		cell := macos.msg_id(field, 'cell')
		if native_is_nil(cell) {
			return false
		}
		return macos.msg_point(cell, 'cellSize').x > el.frame.width + 0.01
	}
	cell := macos.msg_id(native, 'cell')
	if native_is_nil(cell) {
		return false
	}
	title := macos.msg_id(cell, 'attributedTitle')
	if native_is_nil(title) {
		return false
	}
	frame := macos.msg_rect(native, 'bounds')
	title_rect := C.ui2_macos_msg_rect_rect(cell, macos.sel('titleRectForBounds:'), C.ui2_macos_rect{
		x:      frame.x
		y:      frame.y
		width:  frame.width
		height: frame.height
	})
	return macos.msg_point(title, 'size').x > title_rect.width + 0.5
}

fn native_new_button(frame NativeRect, title string, box BoxStyle, text_hex u32, size f64, weight int, italic bool, underline bool, lines int, image_name string, native_style bool) NativeView {
	ensure_runtime_classes()
	native_button := macos.msg_id_rect(macos.alloc('UI2TrackingNSButton'), 'initWithFrame:', appkit_rect(frame))
	native_update_button(native_button, frame, title, box, text_hex, size, weight, italic, underline,
		lines, image_name, native_style)
	return native_button
}

fn native_update_button(button_view NativeView, frame NativeRect, title string, box BoxStyle, text_hex u32, size f64, weight int, italic bool, underline bool, lines int, image_name string, native_style bool) {
	native_set_frame(button_view, frame)
	macos.msg_void1(button_view, 'setTitle:', macos.nsstring(title))
	macos.msg_void_u64(button_view, 'setBezelStyle:', 1)
	if native_style && box_draws_fill(box) {
		macos.msg_void_i64(button_view, 'setButtonType:', ns_button_type_momentary_push_in)
		macos.msg_void_bool(button_view, 'setBordered:', true)
		macos.msg_void_bool(button_view, 'setWantsLayer:', false)
	} else {
		macos.msg_void_i64(button_view, 'setButtonType:', ns_button_type_momentary_change)
		macos.msg_void_bool(button_view, 'setBordered:', false)
		macos.msg_void1(button_view, 'setFont:', native_font(size, weight, italic))
		native_button_set_attributed_title(button_view, title, text_hex, size, weight, italic, underline,
			lines)
		native_set_box_background(button_view, box)
		native_set_box_corners(button_view, box)
	}
	native_apply_line_limit(button_view, lines)
	native_update_button_image(button_view, frame, image_name)
	native_clear_control_state(button_view)
}

fn native_new_checkbox(el Element) NativeView {
	ensure_runtime_classes()
	checkbox_view := macos.msg_id_rect(macos.alloc('UI2TrackingNSButton'), 'initWithFrame:', appkit_rect(element_rect(el.frame)))
	native_update_checkbox(checkbox_view, el)
	return checkbox_view
}

fn native_update_checkbox(checkbox_view NativeView, el Element) {
	native_set_frame(checkbox_view, element_rect(el.frame))
	macos.msg_void_i64(checkbox_view, 'setButtonType:', ns_button_type_switch)
	macos.msg_void1(checkbox_view, 'setTitle:', macos.nsstring(el.text))
	macos.msg_void_i64(checkbox_view, 'setState:', if el.checked { i64(1) } else { i64(0) })
	macos.msg_void_bool(checkbox_view, 'setAllowsMixedState:', false)
	macos.msg_void1(checkbox_view, 'setFont:', native_font(el.text_style.size, text_style_weight(el.text_style), el.text_style.italic))
	native_match_appearance(checkbox_view, el.box, el.text_style.color)
}

fn native_new_switch_control(el Element) NativeView {
	ensure_runtime_classes()
	class_name := if macos.get_class('NSSwitch') == unsafe { nil } { 'UI2TrackingNSButton' } else { 'UI2TrackingNSSwitch' }
	switch_view := macos.msg_id_rect(macos.alloc(class_name), 'initWithFrame:', appkit_rect(element_rect(el.frame)))
	native_update_switch_control(switch_view, el)
	return switch_view
}

fn native_update_switch_control(view NativeView, el Element) {
	native_set_frame(view, element_rect(el.frame))
	if macos.msg_bool_id(view, 'isKindOfClass:', macos.get_class('NSButton')) {
		macos.msg_void_i64(view, 'setButtonType:', ns_button_type_switch)
		macos.msg_void1(view, 'setTitle:', macos.nsstring(''))
		macos.msg_void_bool(view, 'setAllowsMixedState:', false)
	}
	macos.msg_void_i64(view, 'setState:', if el.checked { i64(1) } else { i64(0) })
}

fn native_new_toggle_button(el Element) NativeView {
	native := native_new_button(element_rect(el.frame), el.text, el.box, el.text_style.color,
		el.text_style.size, text_style_weight(el.text_style), el.text_style.italic, el.text_style.underline,
		text_line_budget(el.text_style.lines), el.image_path, el.native_style)
	native_update_toggle_button(native, el)
	return native
}

fn native_update_toggle_button(native NativeView, el Element) {
	box := if el.checked { el.toggle_down_box() } else { el.box }
	style := if el.checked { el.toggle_down_text_style() } else { el.text_style }
	native_update_button(native, element_rect(el.frame), el.text, box, style.color, style.size,
		text_style_weight(style), style.italic, style.underline, text_line_budget(style.lines), el.image_path,
		el.native_style)
	macos.msg_void_i64(native, 'setButtonType:', ns_button_type_push_on_push_off)
	macos.msg_void_i64(native, 'setState:', if el.checked { i64(1) } else { i64(0) })
}

fn native_new_slider(el Element) NativeView {
	ensure_runtime_classes()
	slider_view := macos.msg_id_rect(macos.alloc('UI2TrackingNSSlider'), 'initWithFrame:', appkit_rect(element_rect(el.frame)))
	native_update_slider(slider_view, el)
	return slider_view
}

fn native_update_slider(slider_view NativeView, el Element) {
	native_set_frame(slider_view, element_rect(el.frame))
	maximum := if el.max_value > el.min_value { el.max_value } else { el.min_value }
	macos.msg_void_f64(slider_view, 'setMinValue:', el.min_value)
	macos.msg_void_f64(slider_view, 'setMaxValue:', maximum)
	macos.msg_void_f64(slider_view, 'setDoubleValue:', slider_clamped_value(el.value,
		el.min_value, el.max_value))
	macos.msg_void_bool(slider_view, 'setContinuous:', true)
	if macos.responds_to(slider_view, 'setVertical:') {
		macos.msg_void_bool(slider_view, 'setVertical:', el.orientation == .vertical)
	}
}

fn native_snap_slider_value(slider_view NativeView, spec SliderSpec) f64 {
	raw := macos.msg_f64(slider_view, 'doubleValue')
	normalized := slider_value_normalized(raw, spec.min, spec.max)
	value := slider_value_from_normalized(normalized, spec.min, spec.max, spec.step)
	if value != raw {
		macos.msg_void_f64(slider_view, 'setDoubleValue:', value)
	}
	return value
}

fn native_update_button_image(button_view NativeView, frame NativeRect, image_name string) {
	if image_name.trim_space() == '' {
		macos.msg_void1(button_view, 'setImage:', macos.Id(unsafe { nil }))
		macos.msg_void_i64(button_view, 'setImagePosition:', 0)
		return
	}
	icon_size := if frame.height >= 42 {
		if frame.height - 12 < 46.0 { frame.height - 12 } else { 46.0 }
	} else {
		13.0
	}
	icon_image := native_image_from_name_sized(image_name, icon_size, icon_size)
	macos.msg_void1(button_view, 'setImage:', icon_image)
	macos.msg_void_i64(button_view, 'setImagePosition:', if frame.height >= 42 {
		i64(5)
	} else {
		i64(2)
	})
	macos.msg_void_i64(button_view, 'setImageScaling:', 3)
}

fn native_new_dropdown(el Element) NativeView {
	ensure_runtime_classes()
	dropdown_view := macos.msg_id_rect(macos.alloc('UI2TrackingNSPopUpButton'), 'initWithFrame:', appkit_rect(element_rect(el.frame)))
	native_update_dropdown(dropdown_view, el)
	return dropdown_view
}

fn native_update_dropdown(popup NativeView, el Element) {
	native_set_frame(popup, element_rect(el.frame))
	macos.msg_void(popup, 'removeAllItems')
	for item in el.menu {
		macos.msg_void1(popup, 'addItemWithTitle:', macos.nsstring(item.title))
	}
	native_select_dropdown_item(popup, el.text)
	macos.msg_void1(popup, 'setFont:', native_font(el.text_style.size, text_style_weight(el.text_style), el.text_style.italic))
	macos.msg_void_bool(popup, 'setBordered:', box_draws_fill(el.box))
	macos.msg_void_u64(popup, 'setBezelStyle:', 1)
	native_match_appearance(popup, el.box, el.text_style.color)
}

fn native_new_text_field(el Element) NativeView {
	ensure_runtime_classes()
	frame := element_rect(el.frame)
	cls := if el.secure { 'UI2FocusNSSecureTextField' } else { 'UI2FocusNSTextField' }
	field := macos.msg_id_rect(macos.alloc(cls), 'initWithFrame:', appkit_rect(frame))
	native_update_text_field(field, frame, el.placeholder, el.text, el.box, el.text_style.color,
		el.text_style.size, true, el.readonly, el.enabled, el.text_style.align)
	return field
}

fn native_update_text_field(field NativeView, frame NativeRect, placeholder string, text string, box BoxStyle, text_hex u32, size f64, declared_text_changed bool, readonly bool, enabled bool, align Align) {
	native_set_frame(field, frame)
	// Unrelated refreshes preserve native edits. A changed declaration remains
	// controlled and is applied explicitly.
	if declared_text_changed && native_text(field) != text {
		macos.msg_void1(field, 'setStringValue:', macos.nsstring(text))
	}
	macos.msg_void1(field, 'setPlaceholderString:', macos.nsstring(placeholder))
	macos.msg_void1(field, 'setTextColor:', native_color(text_hex))
	macos.msg_void1(field, 'setFont:', native_font(size, 400, false))
	macos.msg_void_i64(field, 'setAlignment:', native_text_alignment(align_value(align)))
	macos.msg_void_bool(field, 'setBordered:', true)
	macos.msg_void_bool(field, 'setBezeled:', true)
	macos.msg_void_u64(field, 'setBezelStyle:', 1)
	draws_background := box_draws_fill(box)
	macos.msg_void_bool(field, 'setDrawsBackground:', draws_background)
	if draws_background {
		macos.msg_void1(field, 'setBackgroundColor:', native_color(box.bg))
	}
	native_match_appearance(field, box, text_hex)
	macos.msg_void_bool(field, 'setEditable:', !readonly && enabled)
	macos.msg_void_bool(field, 'setSelectable:', true)
	macos.msg_void_bool(field, 'setEnabled:', enabled)
}

// native_match_appearance gives a native control the light or dark system
// appearance its declared colors call for, so its bezel, check box, placeholder
// and insertion point suit a light or dark ui2 theme whatever the system's own
// appearance is. A filled control goes by its fill, an unfilled one by its text:
// light text on an unfilled field would otherwise sit on a light bezel.
fn native_match_appearance(view NativeView, box BoxStyle, text_hex u32) {
	dark := if box_draws_fill(box) {
		!native_color_is_light(box.bg)
	} else {
		native_color_is_light(text_hex)
	}
	name := if dark { 'NSAppearanceNameDarkAqua' } else { 'NSAppearanceNameAqua' }
	appearance := macos.msg_id1(macos.get_class('NSAppearance'), 'appearanceNamed:',
		macos.nsstring(name))
	macos.msg_void1(view, 'setAppearance:', appearance)
}

// native_color_is_light reports whether a 0xRRGGBB color's relative luminance
// is above the middle.
fn native_color_is_light(hex u32) bool {
	r := f64((hex >> 16) & 0xff) / 255.0
	g := f64((hex >> 8) & 0xff) / 255.0
	b := f64(hex & 0xff) / 255.0
	return 0.2126 * r + 0.7152 * g + 0.0722 * b > 0.5
}

// native_new_text_area builds an NSScrollView wrapping an NSTextView —
// native multi-line editing with wrapping, selection, clipboard and undo.
fn (mut w Window) native_new_text_area(el Element) NativeView {
	frame := element_rect(el.frame)
	if el.disable_scroll {
		tv := w.native_new_text_view(appkit_rect(frame), el)
		native_match_appearance(tv, el.box, el.text_style.color)
		return tv
	}
	scroll_view := macos.msg_id_rect(macos.alloc('NSScrollView'), 'initWithFrame:', appkit_rect(frame))
	macos.msg_void_bool(scroll_view, 'setHasVerticalScroller:', true)
	macos.msg_void_bool(scroll_view, 'setAutohidesScrollers:', true)
	native_set_scroll_background(scroll_view, el.box)
	tv := w.native_new_text_view(macos.rect(0, 0, frame.width, frame.height), el)
	macos.msg_void1(scroll_view, 'setDocumentView:', tv)
	macos.release(tv)
	native_set_corner_radius(scroll_view, el.box.radius)
	native_match_appearance(scroll_view, el.box, el.text_style.color)
	return scroll_view
}

fn (mut w Window) native_new_text_view(frame macos.Rect, el Element) NativeView {
	ensure_runtime_classes()
	tv := macos.msg_id_rect(macos.alloc('UI2FocusNSTextView'), 'initWithFrame:', frame)
	macos.msg_void1(tv, 'setFont:', native_text_style_font(el.text_style))
	macos.msg_void_bool(tv, 'setRichText:', el.text_runs.len > 0)
	macos.msg_void_bool(tv, 'setAllowsUndo:', true)
	macos.msg_void_bool(tv, 'setVerticallyResizable:', true)
	macos.msg_void_bool(tv, 'setHorizontallyResizable:', false)
	macos.msg_void_u64(tv, 'setAutoresizingMask:', 2) // NSViewWidthSizable
	macos.msg_void_bool(tv, 'setDrawsBackground:', box_draws_fill(el.box))
	if box_draws_fill(el.box) {
		macos.msg_void1(tv, 'setBackgroundColor:', native_color(el.box.bg))
	}
	macos.msg_void1(tv, 'setTextColor:', native_color(el.text_style.color))
	macos.msg_void_bool(tv, 'setEditable:', !el.readonly && el.enabled)
	macos.msg_void_bool(tv, 'setSelectable:', true)
	native_set_text_area_content(tv, el)
	native_text_view_set_paragraph_style(tv, align_value(el.text_style.align), el.text_style.head_indent, el.text_style.first_line_indent, el.text_style.hyphenation_factor)
	macos.msg_void1(tv, 'setDelegate:', w.button_handler)
	return tv
}

fn (mut w Window) native_update_text_area(native NativeView, el Element, declared_text_changed bool, content_changed bool) {
	frame := element_rect(el.frame)
	native_set_frame(native, frame)
	if !el.disable_scroll {
		macos.msg_void_bool(native, 'setHasVerticalScroller:', true)
		macos.msg_void_bool(native, 'setAutohidesScrollers:', true)
		native_set_scroll_background(native, el.box)
	}
	tv := text_area_text_view(native, el.disable_scroll)
	if native_is_nil(tv) {
		return
	}
	macos.msg_void_bool(tv, 'setEditable:', !el.readonly && el.enabled)
	macos.msg_void_bool(tv, 'setSelectable:', true)
	macos.msg_void1(tv, 'setFont:', native_text_style_font(el.text_style))
	macos.msg_void1(tv, 'setTextColor:', native_color(el.text_style.color))
	macos.msg_void_bool(tv, 'setDrawsBackground:', box_draws_fill(el.box))
	if box_draws_fill(el.box) {
		macos.msg_void1(tv, 'setBackgroundColor:', native_color(el.box.bg))
	}
	native_match_appearance(native, el.box, el.text_style.color)
	current := macos.utf8_string(macos.msg_id(tv, 'string'))
	replace_text := declared_text_changed && current != el.text
	if replace_text || content_changed {
		was_editing := w.native_is_first_responder(tv)
		selection := native_text_view_selected_range(tv)
		native_set_text_area_content(tv, Element{
			...el
			text: if replace_text { el.text } else { current }
		})
		native_text_view_restore_selected_range(tv, selection.location, selection.length, was_editing)
	}
	native_text_view_set_paragraph_style(tv, align_value(el.text_style.align), el.text_style.head_indent, el.text_style.first_line_indent, el.text_style.hyphenation_factor)
}

fn native_set_text_area_content(tv NativeView, el Element) {
	if el.text_runs.len == 0 {
		macos.msg_void_bool(tv, 'setRichText:', false)
		macos.msg_void1(tv, 'setString:', macos.nsstring(el.text))
		return
	}
	macos.msg_void_bool(tv, 'setRichText:', true)
	native_text_view_set_attributed_string(tv, el.text, el.text_style.color, el.text_style.background_color, el.text_style.size, el.text_style.font_family, text_style_weight(el.text_style), el.text_style.italic, el.text_style.underline, el.text_style.strikethrough, el.text_style.vertical_align)
	base_length := native_utf16_length(el.text)
	if base_length > 0 {
		native_text_view_add_effect(tv, 0, base_length, text_style_effect_value(el.text_style))
	}
	mut location := u64(0)
	for run in el.text_runs {
		length := native_utf16_length(run.text)
		if length > 0 {
			native_text_view_add_style(tv, location, length, run.style.color, run.style.background_color, run.style.size, run.style.font_family, text_style_weight(run.style), run.style.italic, run.style.underline, run.style.strikethrough, run.style.vertical_align)
			native_text_view_add_effect(tv, location, length, text_style_effect_value(run.style))
			if run.style.link.len > 0 {
				native_text_view_add_link(tv, location, length, run.style.link)
			}
		}
		location += length
	}
}

fn text_style_effect_value(style TextStyle) int {
	return (if style.shadow {
		1
	} else {
		0
	}) | (if style.outline {
		2
	} else {
		0
	})
}

fn native_set_button_target(button NativeView, target NativeView) {
	macos.msg_void1(button, 'setTarget:', target)
	macos.msg_void1(button, 'setAction:', macos.sel('handleTap:'))
}

fn native_set_control_target(control NativeView, target NativeView) {
	macos.msg_void1(control, 'setTarget:', target)
	macos.msg_void1(control, 'setAction:', macos.sel('handleTap:'))
}

fn native_clear_control_target(control NativeView) {
	macos.msg_void1(control, 'setTarget:', native_nil_view())
	macos.msg_void1(control, 'setAction:', macos.Id(unsafe { nil }))
}

fn native_clear_control_state(control NativeView) {
	objc_clear_control_state(control)
}

fn native_finish_button_action(control NativeView, persistent_state bool) {
	if !persistent_state {
		native_clear_control_state(control)
	}
}

fn native_text(view NativeView) string {
	return macos.utf8_string(macos.msg_id(view, 'stringValue'))
}

fn native_dropdown_text(view NativeView) string {
	item := macos.msg_id(view, 'selectedItem')
	if native_is_nil(item) {
		return ''
	}
	return macos.utf8_string(macos.msg_id(item, 'title'))
}

fn native_set_text(view NativeView, text string) {
	macos.msg_void1(view, 'setStringValue:', macos.nsstring(text))
}

fn native_select_dropdown_item(view NativeView, text string) {
	macos.msg_void1(view, 'selectItemWithTitle:', macos.nsstring(text))
}

fn native_focus(view NativeView) bool {
	return native_focus_view(view)
}

fn native_end_editing(view NativeView) {
	window := macos.msg_id(view, 'window')
	native_end_window_editing(window)
}

fn native_terminate_app() {
	macos.msg_void1(native_current_app(), 'terminate:', macos.Id(unsafe { nil }))
}

fn native_set_frame(view NativeView, frame NativeRect) {
	macos.msg_void_rect(view, 'setFrame:', appkit_rect(frame))
}

fn native_set_background(view NativeView, hex u32) {
	macos.msg_void_bool(view, 'setWantsLayer:', true)
	layer := macos.msg_id(view, 'layer')
	macos.msg_void1(layer, 'setBackgroundColor:', macos.msg_id(native_color(hex), 'CGColor'))
}

// native_set_box_background paints what a BoxStyle puts beneath its borders: the
// solid fill at its opacity or a CAGradientLayer, and the drop shadow.
fn native_set_box_background(view NativeView, box BoxStyle) {
	macos.msg_void_bool(view, 'setWantsLayer:', true)
	layer := macos.msg_id(view, 'layer')
	transaction := macos.Id(macos.get_class('CATransaction'))
	macos.msg_void(transaction, 'begin')
	macos.msg_void_bool(transaction, 'setDisableActions:', true)
	opacity := box_fill_opacity(box)
	// A control draws its title in its own layer, beneath any sublayer, so only
	// views take a gradient; a button keeps its solid fill.
	gradient := box_has_gradient(box)
		&& !macos.msg_bool_id(view, 'isKindOfClass:', macos.get_class('NSControl'))
	if gradient {
		macos.msg_void1(layer, 'setBackgroundColor:', macos.Id(unsafe { nil }))
		native_set_gradient_layer(view, layer, box, opacity)
	} else {
		native_hide_gradient_layer(view)
		fill := if opacity <= 0 {
			macos.Id(unsafe { nil })
		} else if opacity < 1 {
			macos.msg_id(macos.msg_id_f64(native_color(box.bg), 'colorWithAlphaComponent:',
				opacity), 'CGColor')
		} else {
			macos.msg_id(native_color(box.bg), 'CGColor')
		}
		macos.msg_void1(layer, 'setBackgroundColor:', fill)
	}
	native_set_layer_shadow(view, layer, box)
	macos.msg_void(transaction, 'commit')
}

fn native_gradient_key() voidptr {
	return voidptr(macos.sel('ui2_gradient_assoc'))
}

// The gradient is a sublayer kept behind the subviews' layers and the borders by
// its z position, sized to the view and rounded like it, since a shadowed box
// cannot clip its sublayers.
fn native_set_gradient_layer(view NativeView, layer macos.Id, box BoxStyle, opacity f64) {
	mut gradient := NativeView(macos.get_associated_object(view, native_gradient_key()))
	if native_is_nil(gradient) {
		gradient = macos.msg_id(macos.alloc('CAGradientLayer'), 'init')
		macos.msg_void_f64(gradient, 'setZPosition:', -1000)
		native_set_associated_object(view, native_gradient_key(), gradient)
		macos.release(gradient)
	}
	if macos.msg_id(gradient, 'superlayer') != layer {
		macos.msg_void1(layer, 'addSublayer:', gradient)
	}
	layer_bounds := macos.msg_rect(view, 'bounds')
	macos.msg_void_rect(gradient, 'setFrame:', layer_bounds)
	macos.msg_void_f64(gradient, 'setCornerRadius:', box.radius)
	stops := gradient_sorted_stops(box.gradient)
	colors := macos.msg_id(macos.alloc('NSMutableArray'), 'init')
	locations := macos.msg_id(macos.alloc('NSMutableArray'), 'init')
	for stop in stops {
		color := macos.msg_id_f64(native_color(stop.color), 'colorWithAlphaComponent:', stop.opacity * opacity)
		macos.msg_void1(colors, 'addObject:', macos.msg_id(color, 'CGColor'))
		macos.msg_void1(locations, 'addObject:', macos.msg_id_f64(macos.get_class('NSNumber'),
			'numberWithDouble:', stop.position))
	}
	macos.msg_void1(gradient, 'setColors:', colors)
	macos.msg_void1(gradient, 'setLocations:', locations)
	macos.release(colors)
	macos.release(locations)
	// The gradient runs along a line in the box's top-left based points; the layer
	// takes its ends as fractions of its bounds, with y up unless the view flips it.
	line := gradient_line(box.gradient.angle, layer_bounds.width, layer_bounds.height)
	w := if layer_bounds.width > 0 { layer_bounds.width } else { 1.0 }
	h := if layer_bounds.height > 0 { layer_bounds.height } else { 1.0 }
	flipped := macos.msg_bool(view, 'isFlipped')
	y0 := if flipped { line.y0 / h } else { 1 - line.y0 / h }
	y1 := if flipped { line.y1 / h } else { 1 - line.y1 / h }
	macos.msg_void_point(gradient, 'setStartPoint:', macos.point(line.x0 / w, y0))
	macos.msg_void_point(gradient, 'setEndPoint:', macos.point(line.x1 / w, y1))
	macos.msg_void_bool(gradient, 'setHidden:', false)
}

fn native_hide_gradient_layer(view NativeView) {
	gradient := NativeView(macos.get_associated_object(view, native_gradient_key()))
	if !native_is_nil(gradient) {
		macos.msg_void_bool(gradient, 'setHidden:', true)
	}
}

// A layer-backed view owns its layer's shadow through its NSShadow and resets the
// layer's shadow opacity whenever it has none, so the shadow is given to the view.
// The rounded shadow path then lets CoreAnimation draw it from the box's shape
// rather than from its rendered content, which a transparent box does not have.
fn native_set_layer_shadow(view NativeView, layer macos.Id, box BoxStyle) {
	if !box_has_shadow(box) {
		if !objc_is_nil(macos.msg_id(view, 'shadow')) {
			macos.msg_void1(view, 'setShadow:', objc_nil())
		}
		return
	}
	shadow := box.shadow
	ns_shadow := macos.msg_id(macos.alloc('NSShadow'), 'init')
	macos.msg_void1(ns_shadow, 'setShadowColor:', macos.msg_id_f64(native_color(shadow.color),
		'colorWithAlphaComponent:', unit_clamp(shadow.opacity)))
	// AppKit hands the blur radius to CoreAnimation, whose radius is the blur's
	// standard deviation: about half the CSS-style blur the box declares.
	macos.msg_void_f64(ns_shadow, 'setShadowBlurRadius:', if shadow.blur > 0 { shadow.blur / 2 } else { 0.0 })
	// NSShadow measures its offset upward, whatever the view's flipping.
	macos.msg_void_point(ns_shadow, 'setShadowOffset:', macos.point(shadow.x, -shadow.y))
	macos.msg_void1(view, 'setShadow:', ns_shadow)
	macos.release(ns_shadow)
	layer_bounds := macos.msg_rect(view, 'bounds')
	C.ui2_macos_set_shadow_path(layer, -shadow.spread, -shadow.spread, layer_bounds.width + 2 * shadow.spread,
		layer_bounds.height + 2 * shadow.spread, box.radius + shadow.spread)
}

// A rounded box clips its subviews to its corners, except when it casts a shadow:
// a layer that masks to its bounds masks its own shadow away too.
fn native_box_clips(box BoxStyle) bool {
	return box.radius > 0 && !box_has_shadow(box)
}

fn native_set_corner_radius(view NativeView, radius f64) {
	macos.msg_void_bool(view, 'setWantsLayer:', true)
	layer := macos.msg_id(view, 'layer')
	macos.msg_void_f64(layer, 'setCornerRadius:', radius)
	macos.msg_void_bool(layer, 'setMasksToBounds:', radius > 0)
}

fn native_set_box_corners(view NativeView, box BoxStyle) {
	macos.msg_void_bool(view, 'setWantsLayer:', true)
	layer := macos.msg_id(view, 'layer')
	macos.msg_void_f64(layer, 'setCornerRadius:', box.radius)
	macos.msg_void_bool(layer, 'setMasksToBounds:', native_box_clips(box))
}

fn native_set_border_layer(view NativeView, side string, frame NativeRect, color u32, visible bool) {
	key := native_border_key(side)
	mut border := NativeView(macos.get_associated_object(view, key))
	if !visible {
		if !native_is_nil(border) {
			macos.msg_void_bool(border, 'setHidden:', true)
		}
		return
	}
	parent_layer := macos.msg_id(view, 'layer')
	if native_is_nil(border) {
		border = macos.msg_id(macos.alloc('CALayer'), 'init')
		native_set_associated_object(view, key, border)
		macos.release(border)
	}
	// A native control can replace its backing layer while its style changes.
	// Attach only when needed so routine refreshes do not reorder sublayers.
	if macos.msg_id(border, 'superlayer') != parent_layer {
		macos.msg_void1(parent_layer, 'addSublayer:', border)
	}
	macos.msg_void_rect(border, 'setFrame:', appkit_rect(frame))
	macos.msg_void1(border, 'setBackgroundColor:', macos.msg_id(native_color(color), 'CGColor'))
	macos.msg_void_bool(border, 'setHidden:', false)
}

fn native_set_box_borders(view NativeView, box BoxStyle) {
	view_bounds := macos.msg_rect(view, 'bounds')
	left := box_border_width(box.border_left, view_bounds.width)
	top := box_border_width(box.border_top, view_bounds.height)
	right := box_border_width(box.border_right, view_bounds.width)
	bottom := box_border_width(box.border_bottom, view_bounds.height)
	rounded := box_rounded_border(box)
	if (left <= 0 && top <= 0 && right <= 0 && bottom <= 0) || rounded > 0 {
		for side in ['left', 'top', 'right', 'bottom'] {
			native_set_border_layer(view, side, NativeRect{}, box.border_color, false)
		}
	}
	if left <= 0 && top <= 0 && right <= 0 && bottom <= 0 {
		macos.msg_void_f64(macos.msg_id(view, 'layer'), 'setBorderWidth:', 0)
		return
	}
	macos.msg_void_bool(view, 'setWantsLayer:', true)
	layer := macos.msg_id(view, 'layer')
	if box.radius > 0 {
		macos.msg_void_f64(layer, 'setCornerRadius:', box.radius)
		macos.msg_void_bool(layer, 'setMasksToBounds:', native_box_clips(box))
	}
	// An even border on a rounded box is the layer's own, which follows the
	// corners; straight side layers would leave them bare.
	if rounded > 0 {
		macos.msg_void_f64(layer, 'setBorderWidth:', rounded)
		macos.msg_void1(layer, 'setBorderColor:', macos.msg_id(native_color(box.border_color), 'CGColor'))
		return
	}
	macos.msg_void_f64(layer, 'setBorderWidth:', 0)
	transaction := macos.Id(macos.get_class('CATransaction'))
	macos.msg_void(transaction, 'begin')
	macos.msg_void_bool(transaction, 'setDisableActions:', true)
	flipped := macos.msg_bool(view, 'isFlipped')
	top_y := if flipped { 0.0 } else { view_bounds.height - top }
	bottom_y := if flipped { view_bounds.height - bottom } else { 0.0 }
	native_set_border_layer(view, 'left', native_rect(0, 0, left, view_bounds.height),
		box.border_color, left > 0)
	native_set_border_layer(view, 'top', native_rect(0, top_y, view_bounds.width, top),
		box.border_color, top > 0)
	native_set_border_layer(view, 'right', native_rect(view_bounds.width - right, 0, right,
		view_bounds.height), box.border_color, right > 0)
	native_set_border_layer(view, 'bottom', native_rect(0, bottom_y, view_bounds.width, bottom),
		box.border_color, bottom > 0)
	macos.msg_void(transaction, 'commit')
}

fn native_font(size f64, weight int, italic bool) NativeView {
	return NativeView(native_font_object(size, weight, italic))
}

// Native text areas used to ignore TextStyle.font_family and always install
// the system face. Keep the same weight/italic base, then resolve the declared
// family through the text formatting helper used by rich text operations.
fn native_text_style_font(style TextStyle) NativeView {
	base := macos.Id(native_font(style.size, text_style_weight(style), style.italic))
	return NativeView(native_font_with_family(base, style.font_family, style.size))
}

@[export: 'ui2_view_is_flipped']
fn ui2_view_is_flipped(_self voidptr, _cmd voidptr) bool {
	return true
}


fn (mut w Window) fire_pointer_event(native NativeView, phase ElementEventKind, event voidptr) {
	pressed := w.pointer_button_down
	button_moved := w.pointer_button_moved
	pressed_binding := w.pointer_button_binding
	if phase == .pointer_up {
		w.pointer_button_down = 0
		w.pointer_button_moved = false
		w.pointer_button_binding = AppkitCallbackBinding{}
	}
	mut target := NativeView(usize(native))
	mut binding := AppkitCallbackBinding{}
	if phase == .pointer_down {
		// Non-interactive labels/images forward to their enclosing pointer surface.
		binding = w.pointer_callbacks[u64(voidptr(target))] or { AppkitCallbackBinding{} }
		for !appkit_callback_present(binding) {
			target = NativeView(macos.msg_id(target, 'superview'))
			if native_is_nil(target) { return }
			binding = w.pointer_callbacks[u64(voidptr(target))] or { AppkitCallbackBinding{} }
		}
	} else {
		// Release uses the pressed callback, provided that surface is still available.
		if pressed == 0 || !appkit_callback_present(pressed_binding) { return }
		target = NativeView(voidptr(usize(pressed)))
		current := w.pointer_callbacks[pressed] or { return }
		binding = appkit_pointer_release_binding(pressed_binding, current) or { return }
	}
	target_key := u64(voidptr(target))
	button_behavior := w.pointer_buttons[target_key] or { false }
	if phase == .pointer_down {
		w.pointer_button_down = target_key
		w.pointer_button_moved = false
		w.pointer_button_binding = binding
		start := native_event_point(w.root_view, event)
		w.pointer_button_x = start.x
		w.pointer_button_y = start.y
	}
	if phase == .pointer_drag {
		current := native_event_point(w.root_view, event)
		dx := current.x - w.pointer_button_x
		dy := current.y - w.pointer_button_y
		if dx * dx + dy * dy > 100 { w.pointer_button_moved = true }
		if !binding.draggable { return }
	}
	mut should_activate := false
	if phase == .pointer_up && binding.button_behavior && button_behavior && !button_moved {
		point := native_event_point(target, event)
		target_bounds := macos.msg_rect(target, 'bounds')
		should_activate = point.x >= target_bounds.x && point.x <= target_bounds.x + target_bounds.width
			&& point.y >= target_bounds.y && point.y <= target_bounds.y + target_bounds.height
	}
	if binding.clickable || binding.draggable {
		point := native_event_point(w.root_view, event)
		w.appkit_emit_callback(binding, ElementEvent{ kind: phase, x: point.x, y: point.y })
	}
	if should_activate { w.appkit_emit_callback(binding, ElementEvent{ kind: .click }) }
}

@[export: 'ui2_pointer_mouse_down']
fn ui2_pointer_mouse_down(self voidptr, _cmd voidptr, event voidptr) {
	mut w := appkit_window_for(self) or { return }
	w.fire_pointer_event(NativeView(self), .pointer_down, event)
}

@[export: 'ui2_pointer_mouse_dragged']
fn ui2_pointer_mouse_dragged(self voidptr, _cmd voidptr, event voidptr) {
	mut w := appkit_window_for(self) or { return }
	w.fire_pointer_event(NativeView(self), .pointer_drag, event)
}

@[export: 'ui2_pointer_mouse_up']
fn ui2_pointer_mouse_up(self voidptr, _cmd voidptr, event voidptr) {
	mut w := appkit_window_for(self) or { return }
	w.fire_pointer_event(NativeView(self), .pointer_up, event)
}

@[export: 'ui2_pointer_accessibility_press']
fn ui2_pointer_accessibility_press(self voidptr, _cmd voidptr) bool {
	mut w := appkit_window_for(self) or { return false }
	pointer := u64(self)
	if !(w.pointer_buttons[pointer] or { false }) { return false }
	binding := w.pointer_callbacks[pointer] or { return false }
	return w.appkit_emit_callback(binding, ElementEvent{ kind: .click })
}

@[export: 'ui2_pointer_reset_cursor_rects']
fn ui2_pointer_reset_cursor_rects(self voidptr, _cmd voidptr) {
	mut w := appkit_window_for(self) or { return }
	cursor := w.cursor_ids[u64(self)] or { return }
	if cursor.len == 0 {
		return
	}
	native_add_cursor_rect(self, cursor)
}

@[export: 'ui2_dragging_entered']
fn ui2_dragging_entered(self voidptr, _cmd voidptr, _dragging_info voidptr) u64 {
	mut w := appkit_window_for(self) or { return 0 }
	return if voidptr(w.drop_handler) == unsafe { nil } { u64(0) } else { u64(1) }
}

@[export: 'ui2_perform_drag_operation']
fn ui2_perform_drag_operation(self voidptr, _cmd voidptr, dragging_info voidptr) bool {
	mut w := appkit_window_for(self) or { return false }
	if voidptr(w.drop_handler) == unsafe { nil } {
		return false
	}
	paths := native_dragging_file_paths(dragging_info, 256)
	dropped_text := native_dragging_text(dragging_info)
	point := native_dragging_point(self, dragging_info)
	w.drop_handler(DropEvent{
		window: w
		paths: paths
		text: dropped_text
		x: point.x
		y: point.y
	})
	return paths.len > 0 || dropped_text.len > 0
}

// Text change/submit registration is intentionally independent of mouse
// tracking: keyboard edits always read committed text and the current callback.
fn appkit_control_release_binding(captured AppkitCallbackBinding, current AppkitCallbackBinding, available bool) ?AppkitCallbackBinding {
	if !available || !appkit_callback_present(current) || !appkit_callback_present(captured)
		|| current.kind != captured.kind { return none }
	return captured
}

@[export: 'ui2_appkit_control_tracking_begin']
fn ui2_appkit_control_tracking_begin(control voidptr) {
	mut w := appkit_window_for(control) or { return }
	pointer := u64(control)
	w.control_captures[pointer] = w.control_callbacks[pointer] or { AppkitCallbackBinding{} }
}

@[export: 'ui2_appkit_control_tracking_end']
fn ui2_appkit_control_tracking_end(control voidptr) {
	mut w := appkit_window_for(control) or { return }
	w.control_captures.delete(u64(control))
}

fn ui2_control_mouse_down(self voidptr, _cmd voidptr, event voidptr) {
	C.ui2_macos_control_mouse_down(self, event)
}

fn appkit_control_event(native NativeView, binding AppkitCallbackBinding) ElementEvent {
	return match binding.kind {
		.text_field { ElementEvent{ kind: binding.event, text: macos.utf8_string(macos.msg_id(native, 'stringValue')) } }
		.text_area { ElementEvent{ kind: binding.event, text: macos.utf8_string(macos.msg_id(native, 'string')) } }
		.dropdown { ElementEvent{ kind: .change, text: macos.utf8_string(macos.msg_id(native, 'titleOfSelectedItem')) } }
		.slider { ElementEvent{ kind: .change, value: macos.msg_f64(native, 'doubleValue') } }
		.checkbox, .switch_control, .toggle_button { ElementEvent{ kind: .change, checked: macos.msg_i64(native, 'state') != 0 } }
		else { ElementEvent{ kind: binding.event } }
	}
}

@[export: 'ui2_button_tap']
fn ui2_button_tap(self voidptr, _cmd voidptr, sender voidptr) {
	mut w := appkit_window_for(self) or { return }
	native := NativeView(sender)
	pointer := u64(voidptr(native))
	current := w.control_callbacks[pointer] or { return }
	mut binding := current
	if captured := w.control_captures[pointer] {
		binding = appkit_control_release_binding(captured, current,
			macos.msg_bool(native, 'isEnabled') && !macos.msg_bool(native, 'isHiddenOrHasHiddenAncestor')) or { return }
	}
	w.commit_macos_toggle_button(pointer, native)
	if spec := w.slider_specs[pointer] { native_snap_slider_value(native, spec) }
	native_finish_button_action(native, w.checkbox_controls[pointer] or { false })
	w.appkit_emit_callback(binding, appkit_control_event(native, binding))
}

@[export: 'ui2_control_text_changed']
fn ui2_control_text_changed(self voidptr, _cmd voidptr, notification voidptr) {
	mut w := appkit_window_for(self) or { return }
	field := macos.msg_id(macos.Id(notification), 'object')
	binding := w.control_change_callbacks[u64(voidptr(field))] or { return }
	w.appkit_emit_callback(binding, appkit_control_event(field, binding))
}

@[export: 'ui2_control_do_command']
fn ui2_control_do_command(self voidptr, _cmd voidptr, control voidptr, _text_view voidptr, command voidptr) bool {
	mut w := appkit_window_for(self) or { return false }
	if w.navigation_key_dispatched { return false }
	if u64(control) !in w.control_change_callbacks {
		return false
	}
	modifiers := native_current_event_modifier_flags()
	key := text_command_key(command, modifiers) or { return false }
	// The field editor turns Backspace and Delete into commands before any key
	// handler sees them, so on_key_event is offered the key here, and a handler
	// that consumes it (moving back from an empty code cell, say) keeps the field
	// from acting on it.
	if key in ['backspace', 'forward_delete'] {
		if voidptr(w.key_event_handler) == unsafe { nil } {
			return false
		}
		w.key_consumed = false
		w.key_event_handler(KeyEvent{
			window: w
			code:  if key == 'backspace' { KeyCode.backspace } else { KeyCode.delete }
			shift: modifiers & 0x20000 != 0
			ctrl:  modifiers & 0x40000 != 0
			alt:   modifiers & 0x80000 != 0
			cmd:   modifiers & 0x100000 != 0
		})
		consumed := w.key_consumed
		w.key_consumed = false
		return consumed
	}
	if voidptr(w.key_handler) == unsafe { nil } || (key != 'tab' && key != 'shift+tab') {
		return false
	}
	w.key_consumed = false
	w.key_handler(mut w, key)
	consumed := w.key_consumed
	w.key_consumed = false
	return consumed
}

@[export: 'ui2_text_view_changed']
fn ui2_text_view_changed(self voidptr, _cmd voidptr, notification voidptr) {
	mut w := appkit_window_for(self) or { return }
	tv := macos.msg_id(macos.Id(notification), 'object')
	binding := w.textview_callbacks[u64(voidptr(tv))] or { return }
	w.appkit_emit_callback(binding, appkit_control_event(tv, binding))
}

@[export: 'ui2_text_view_do_command']
fn ui2_text_view_do_command(self voidptr, _cmd voidptr, text_view voidptr, command voidptr) bool {
	mut w := appkit_window_for(self) or { return false }
	if w.navigation_key_dispatched { return false }
	if voidptr(w.key_handler) == unsafe { nil } {
		return false
	}
	key := text_command_key(command, native_current_event_modifier_flags()) or { return false }
	id := w.textview_ids[u64(text_view)] or { return false }
	boundary_noop := text_command_boundary_noop(text_view, key)
	w.text_key_consumed = false
	w.key_handler(mut w, 'text:${id}:${key}')
	consumed := w.text_key_consumed || boundary_noop
	w.text_key_consumed = false
	return consumed
}

@[export: 'ui2_text_view_clicked_on_link']
fn ui2_text_view_clicked_on_link(self voidptr, _cmd voidptr, text_view voidptr, link voidptr, _char_index u64) bool {
	mut w := appkit_window_for(self) or { return false }
	binding := w.textview_callbacks[u64(text_view)] or { return false }
	target := macos.utf8_string(macos.msg_id(macos.Id(link), 'description'))
	if target.len == 0 { return false }
	return w.appkit_emit_callback(binding, ElementEvent{ kind: .link, target: target })
}

fn text_command_key(command voidptr, modifiers u64) ?string {
	selector := macos.Sel(command)
	shift := modifiers & 0x20000 != 0
	if selector == macos.sel('deleteBackward:') {
		return 'backspace'
	}
	if selector == macos.sel('deleteForward:') {
		return 'forward_delete'
	}
	if selector == macos.sel('insertLineBreak:') {
		return 'line_break'
	}
	if selector == macos.sel('insertNewline:') || selector == macos.sel('insertParagraphSeparator:') {
		return if shift { 'line_break' } else { 'enter' }
	}
	if selector == macos.sel('insertTab:') {
		return if shift { 'shift+tab' } else { 'tab' }
	}
	if selector == macos.sel('insertBacktab:') {
		return 'shift+tab'
	}
	return none
}

fn text_command_boundary_noop(text_view voidptr, key string) bool {
	selected := native_text_view_selected_range(text_view)
	if selected.length > 0 {
		return false
	}
	text_length := native_text_view_text_length(text_view)
	return match key {
		'backspace' { selected.location == 0 }
		'forward_delete' { selected.location >= text_length }
		else { false }
	}
}

@[export: 'ui2_bounds_changed']
fn ui2_bounds_changed(self voidptr, _cmd voidptr, notification voidptr) {
	mut w := appkit_window_for(self) or { return }
	clip := macos.msg_id(macos.Id(notification), 'object')
	binding := w.scroll_callbacks[u64(voidptr(clip))] or { return }
	offset := native_bounds(clip)
	w.appkit_emit_callback(binding, ElementEvent{ kind: .scroll, value: offset.y, x: offset.x, y: offset.y })
}

const ns_event_phase_began = u64(1)
const ns_view_width_sizable = u64(2)
const ns_view_height_sizable = u64(16)

// A scroll view takes every wheel event it is under, including one it has no way to
// follow: along an axis it does not scroll, or further in a direction it is already at
// the end of. That leaves a strip of columns stuck whenever the pointer is over a
// column that scrolls the other way, and a list stalled wherever a list inside it has
// run out. The view a gesture starts on therefore decides once, from the direction the
// gesture sets off in, whether an enclosing Scroll element is the one to move, and
// hands it the whole gesture if so.
@[export: 'ui2_scroll_view_scroll_wheel']
fn ui2_scroll_view_scroll_wheel(self voidptr, _cmd voidptr, event voidptr) {
	mut w := appkit_window_for(self) or { return }
	scroll_view := NativeView(self)
	wheel := macos.Id(event)
	handle := u64(self)
	// A wheel click stands alone and is decided each time. A trackpad gesture is decided
	// where it begins and keeps that answer through the momentum that follows it, even
	// once this view has run out partway: scrolling stays with the view it began on, as
	// it does elsewhere on macOS. AppKit follows a gesture from its beginning to its end,
	// so handing the rest of one over would give the view around this one a gesture with
	// no beginning and leave this one without the end that settles its rubber band.
	phase := macos.msg_u64(wheel, 'phase')
	click := phase == 0 && macos.msg_u64(wheel, 'momentumPhase') == 0
	if phase == ns_event_phase_began || click {
		dx := macos.msg_f64(wheel, 'scrollingDeltaX')
		dy := macos.msg_f64(wheel, 'scrollingDeltaY')
		sideways := dx * dx > dy * dy
		w.scroll_forwarding[handle] = dx * dx != dy * dy
			&& scroll_view_passes_gesture(scroll_view, sideways, if sideways { dx } else { dy })
	}
	if w.scroll_forwarding[handle] or { false } {
		next := macos.msg_id(scroll_view, 'nextResponder')
		if !native_is_nil(next) {
			macos.msg_void1(next, 'scrollWheel:', wheel)
		}
		return
	}
	if click {
		scroll_view_pass_on_unused(scroll_view, wheel)
	}
	C.ui2_macos_msg_super_void_id(self, voidptr(macos.get_class('NSScrollView')), voidptr(macos.sel('scrollWheel:')),
		event)
}

// scroll_view_scrolls_axis reports whether a scroll view has anywhere to go along an
// axis: its mode scrolls that axis, and its document is longer than what shows of it.
fn scroll_view_scrolls_axis(scroll NativeView, horizontal bool) bool {
	if !scroll_view_has_axis(scroll, horizontal) {
		return false
	}
	document_view := macos.msg_id(scroll, 'documentView')
	if native_is_nil(document_view) {
		return false
	}
	document := macos.msg_rect(document_view, 'frame')
	visible := macos.msg_rect(macos.msg_id(scroll, 'contentView'), 'bounds')
	return if horizontal {
		document.width > visible.width + 0.5
	} else {
		document.height > visible.height + 0.5
	}
}

// scroll_view_room is how much of a distance along an axis a scroll view has room for:
// all of it, what is left before the end it heads for, or none. The distance is a
// change in offset, positive towards the end of the content. Documents are flipped
// views, so the vertical offset grows downwards the way the horizontal one grows to
// the right.
fn scroll_view_room(scroll NativeView, horizontal bool, distance f64) f64 {
	if !scroll_view_scrolls_axis(scroll, horizontal) {
		return 0
	}
	document := macos.msg_rect(macos.msg_id(scroll, 'documentView'), 'frame')
	visible := macos.msg_rect(macos.msg_id(scroll, 'contentView'), 'bounds')
	offset := if horizontal { visible.x } else { visible.y }
	maximum := if horizontal {
		document.width - visible.width
	} else {
		document.height - visible.height
	}
	room := if distance > 0 { maximum - offset } else { offset }
	if room <= 0.5 {
		return 0
	}
	if distance > 0 {
		return if distance < room { distance } else { room }
	}
	return if -distance < room { distance } else { -room }
}

// scroll_view_can_move reports whether a scroll view can follow a wheel delta along an
// axis: it has a range there, and is not already at the end the delta pushes towards.
// A positive delta carries the content with it, back towards its start.
fn scroll_view_can_move(scroll NativeView, horizontal bool, delta f64) bool {
	return scroll_view_room(scroll, horizontal, -delta) != 0
}

fn scroll_view_enclosing(scroll NativeView) NativeView {
	return macos.msg_id(macos.msg_id(scroll, 'superview'), 'enclosingScrollView')
}

// scroll_view_passes_gesture reports whether a gesture starting on a scroll view
// belongs to a scroll view around it: this one cannot follow it and one of those can.
// Content that fits counts as unable to follow, the same as an axis the mode leaves
// out, and so does a view already at the end the gesture heads for, so a pane does
// not hold on to a gesture the pane around it could use. With no one to take it the
// gesture stays where it began.
fn scroll_view_passes_gesture(scroll NativeView, horizontal bool, delta f64) bool {
	if scroll_view_can_move(scroll, horizontal, delta) {
		return false
	}
	mut parent := scroll_view_enclosing(scroll)
	for !native_is_nil(parent) {
		if scroll_view_can_move(parent, horizontal, delta) {
			return true
		}
		parent = scroll_view_enclosing(parent)
	}
	return false
}

// scroll_view_pass_on_unused gives the views around a scroll view the part of a wheel
// click that it has no room for. AppKit moves the view itself once the click is handed
// to it, as far as its end, and the rest of the step would be dropped there. How far a
// click goes is the distance the device reports, or that many of the view's own lines
// when it reports lines. Each view around it that can still move takes what it has
// room for in turn, the way the custom renderer walks its scroll chain.
fn scroll_view_pass_on_unused(scroll NativeView, wheel macos.Id) {
	precise := macos.msg_bool(wheel, 'hasPreciseScrollingDeltas')
	for horizontal in [true, false] {
		delta := macos.msg_f64(wheel, if horizontal { 'scrollingDeltaX' } else { 'scrollingDeltaY' })
		if delta == 0 {
			continue
		}
		line := if precise {
			1.0
		} else {
			macos.msg_f64(scroll, if horizontal { 'horizontalLineScroll' } else { 'verticalLineScroll' })
		}
		// A positive delta carries the content with it, back towards its start.
		mut remaining := -delta * line
		remaining -= scroll_view_room(scroll, horizontal, remaining)
		mut parent := scroll_view_enclosing(scroll)
		for remaining != 0 && !native_is_nil(parent) {
			taken := scroll_view_room(parent, horizontal, remaining)
			if taken != 0 {
				scroll_view_move(parent, horizontal, taken)
				remaining -= taken
			}
			parent = scroll_view_enclosing(parent)
		}
	}
}

// scroll_view_move shifts a scroll view along an axis by a distance it has room for.
fn scroll_view_move(scroll NativeView, horizontal bool, distance f64) {
	visible := macos.msg_rect(macos.msg_id(scroll, 'contentView'), 'bounds')
	macos.msg_void_rect(macos.msg_id(scroll, 'documentView'), 'scrollRectToVisible:', macos.rect(visible.x +
		if horizontal { distance } else { 0.0 }, visible.y + if horizontal { 0.0 } else { distance },
		visible.width, visible.height))
}


@[export: 'ui2_window_key_down']
fn ui2_window_key_down(self voidptr, _cmd voidptr, event voidptr) {
	mut w := appkit_window_for(self) or { return }
	if w.dispatch_typed_key_event(macos.Id(event)) {
		return
	}
	if w.navigation_key_dispatched || voidptr(w.key_handler) == unsafe { nil } {
		return
	}
	w.key_handler(mut w, key_event_string(macos.Id(event)))
}

@[export: 'ui2_window_perform_key_equiv']
fn ui2_window_perform_key_equiv(self voidptr, _cmd voidptr, event voidptr) bool {
	mut w := appkit_window_for(self) or { return false }
	if w.dispatch_typed_key_event(macos.Id(event)) {
		return true
	}
	s := key_event_string(macos.Id(event))
	if s == 'cmd+v' && native_pasteboard_has_image() {
		if voidptr(w.key_handler) != unsafe { nil } {
			w.key_handler(mut w, s)
			return true
		}
	}
	if w.dispatch_pre_native_command_key(s) {
		return true
	}
	if handle_native_edit_key(s) {
		return true
	}
	if voidptr(w.key_handler) == unsafe { nil } || !s.starts_with('cmd+') || s == 'cmd+q' {
		return false
	}
	w.key_handler(mut w, s)
	return true
}

// dispatch_typed_key_event offers a key press to the focused element's
// declared keys (element_keys.v), then to on_key_event.
fn (mut w Window) dispatch_typed_key_event(event macos.Id) bool {
	// AppKit may consult performKeyEquivalent before routing the same event
	// through sendEvent/keyDown. An observer still receives it exactly once.
	timestamp := macos.msg_f64(event, 'timestamp')
	if w.typed_key_event == voidptr(event) && w.typed_key_timestamp == timestamp { return w.typed_key_consumed }
	w.typed_key_event = voidptr(event)
	w.typed_key_timestamp = timestamp
	key := KeyEvent{ ...appkit_key_event(event), window: w }
	if macos.msg_u64(event, 'type') == 10 && w.element_key(key, macos.msg_bool(event, 'isARepeat')) {
		w.typed_key_consumed = true
		return true
	}
	if voidptr(w.key_event_handler) == unsafe { nil } {
		w.typed_key_consumed = false
		return false
	}
	w.key_consumed = false
	w.text_key_consumed = false
	w.key_event_handler(key)
	consumed := w.key_consumed || w.text_key_consumed
	w.key_consumed = false
	w.text_key_consumed = false
	w.typed_key_consumed = consumed
	return consumed
}

fn (mut w Window) dispatch_pre_native_command_key(key string) bool {
	if key != 'cmd+z' && key != 'cmd+shift+z' && key != 'cmd+y' && key != 'cmd+q' {
		return false
	}
	if voidptr(w.key_handler) == unsafe { nil } {
		return false
	}
	w.key_consumed = false
	w.key_handler(mut w, key)
	consumed := w.key_consumed
	w.key_consumed = false
	return consumed
}

fn handle_native_edit_key(key string) bool {
	command := match key {
		'cmd+a' { 0 }
		'cmd+x' { 1 }
		'cmd+c' { 2 }
		'cmd+v' { 3 }
		'cmd+z' { 4 }
		'cmd+y', 'cmd+shift+z' { 5 }
		else {
			return false
		}
	}

	return native_app_send_edit_command(command)
}

fn appkit_key_code(native_code u64) KeyCode {
	return match native_code {
		0x00 { .a }
		0x01 { .s }
		0x02 { .d }
		0x03 { .f }
		0x04 { .h }
		0x05 { .g }
		0x06 { .z }
		0x07 { .x }
		0x08 { .c }
		0x09 { .v }
		0x0a { .world_1 }
		0x0b { .b }
		0x0c { .q }
		0x0d { .w }
		0x0e { .e }
		0x0f { .r }
		0x10 { .y }
		0x11 { .t }
		0x12 { ._1 }
		0x13 { ._2 }
		0x14 { ._3 }
		0x15 { ._4 }
		0x16 { ._6 }
		0x17 { ._5 }
		0x18 { .equal }
		0x19 { ._9 }
		0x1a { ._7 }
		0x1b { .minus }
		0x1c { ._8 }
		0x1d { ._0 }
		0x1e { .right_bracket }
		0x1f { .o }
		0x20 { .u }
		0x21 { .left_bracket }
		0x22 { .i }
		0x23 { .p }
		0x24 { .enter }
		0x25 { .l }
		0x26 { .j }
		0x27 { .apostrophe }
		0x28 { .k }
		0x29 { .semicolon }
		0x2a { .backslash }
		0x2b { .comma }
		0x2c { .slash }
		0x2d { .n }
		0x2e { .m }
		0x2f { .period }
		0x30 { .tab }
		0x31 { .space }
		0x32 { .grave_accent }
		0x33 { .backspace }
		0x35 { .escape }
		0x41 { .kp_decimal }
		0x43 { .kp_multiply }
		0x45 { .kp_add }
		0x4b { .kp_divide }
		0x4c { .kp_enter }
		0x4e { .kp_subtract }
		0x51 { .kp_equal }
		0x52 { .kp_0 }
		0x53 { .kp_1 }
		0x54 { .kp_2 }
		0x55 { .kp_3 }
		0x56 { .kp_4 }
		0x57 { .kp_5 }
		0x58 { .kp_6 }
		0x59 { .kp_7 }
		0x5b { .kp_8 }
		0x5c { .kp_9 }
		0x60 { .f5 }
		0x61 { .f6 }
		0x62 { .f7 }
		0x63 { .f3 }
		0x64 { .f8 }
		0x65 { .f9 }
		0x67 { .f11 }
		0x69 { .f13 }
		0x6a { .f16 }
		0x6b { .f14 }
		0x6d { .f10 }
		0x6f { .f12 }
		0x71 { .f15 }
		0x72 { .insert }
		0x73 { .home }
		0x74 { .page_up }
		0x75 { .delete }
		0x76 { .f4 }
		0x77 { .end }
		0x78 { .f2 }
		0x79 { .page_down }
		0x7a { .f1 }
		0x7b { .left }
		0x7c { .right }
		0x7d { .down }
		0x7e { .up }
		else { .invalid }
	}
}

fn appkit_key_event(event macos.Id) KeyEvent {
	mods := macos.msg_u64(event, 'modifierFlags')
	return KeyEvent{
		code: appkit_key_code(macos.msg_u64(event, 'keyCode'))
		shift: mods & 0x20000 != 0
		ctrl: mods & 0x40000 != 0
		alt: mods & 0x80000 != 0
		cmd: mods & 0x100000 != 0
	}
}

// key_event_string normalizes an NSEvent into 'cmd+shift+r' style strings.
// Known keys come from the physical AppKit key code, not layout-dependent
// charactersIgnoringModifiers.
fn key_event_string(event macos.Id) string {
	key_event := appkit_key_event(event)
	mut name := key_event.code.name()
	if name.len == 0 {
		name = macos.utf8_string(macos.msg_id(event, 'charactersIgnoringModifiers')).to_lower()
	}
	mut prefix := ''
	if key_event.cmd {
		prefix += 'cmd+'
	}
	if key_event.ctrl {
		prefix += 'ctrl+'
	}
	if key_event.alt {
		prefix += 'alt+'
	}
	if key_event.shift {
		prefix += 'shift+'
	}
	return prefix + name
}
}

