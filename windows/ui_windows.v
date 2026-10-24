// vfmt off
// Keep Win32 declarations out of opt-in custom-renderer builds.
module ui2

$if windows && !ui2_custom_rendering ? && !ui2_headless ? && !ui2_document_library ? {

#flag windows -luser32

#flag windows -lgdi32

#flag windows -lmsimg32

#flag windows -lcomctl32

#flag windows -lshell32

#flag windows -loleacc

#flag windows -lole32

#flag windows -loleaut32

#flag windows -luuid

#insert "@VMODROOT/windows/native_helpers_windows.h"

fn C.ui2_win_register_classes() int

fn C.ui2_win_shutdown_accessibility()

fn C.ui2_win_visual_styles_enabled() int

fn C.ui2_win_create_main_window(title &u16, width int, height int) voidptr

fn C.ui2_win_apply_min_size(hwnd voidptr, lparam isize, width int, height int)

fn C.ui2_win_set_window_title(hwnd voidptr, title &u16)

fn C.ui2_win_create_widget(kind int, parent voidptr, x int, y int, width int, height int, text &u16, alignment int, secure int, readonly int, disable_scroll int, vertical int) voidptr
fn C.ui2_win_label_content_height(hwnd voidptr, width int, lines int) int
fn C.ui2_win_label_text_hwnd(hwnd voidptr) voidptr

fn C.ui2_win_show_main_window(hwnd voidptr)

fn C.ui2_win_message_loop() int

fn C.ui2_win_default_proc(hwnd voidptr, message u32, wparam usize, lparam isize) isize

fn C.ui2_win_post_quit(code int)

fn C.ui2_win_post_refresh(hwnd voidptr)

fn C.ui2_win_close(hwnd voidptr)

fn C.ui2_win_destroy(hwnd voidptr)

fn C.ui2_win_is_window(hwnd voidptr) int

fn C.ui2_win_is_enabled(hwnd voidptr) int

fn C.ui2_win_control_available(hwnd voidptr) int

fn C.ui2_win_parent(hwnd voidptr) voidptr

fn C.ui2_win_set_parent(hwnd voidptr, parent voidptr)

fn C.ui2_win_set_widget_frame(hwnd voidptr, kind int, x int, y int, width int, height int)

fn C.ui2_win_place_after(hwnd voidptr, previous voidptr)

fn C.ui2_win_show(hwnd voidptr, visible int)

fn C.ui2_win_enable(hwnd voidptr, enabled int)

fn C.ui2_win_configure_accessible_button(hwnd voidptr, label &u16, active int)

fn C.ui2_win_is_accessible_button(hwnd voidptr) int

fn C.ui2_win_create_tooltip(hwnd voidptr, text &u16) voidptr

fn C.ui2_win_tooltip_add_target(tooltip voidptr, target voidptr) int

fn C.ui2_win_border_width(width f64, extent int) int

fn C.ui2_win_destroy_tooltip(tooltip voidptr)

fn C.ui2_win_focus(hwnd voidptr)

fn C.ui2_win_open_dropdown(hwnd voidptr)

fn C.ui2_win_dropdown_is_open(hwnd voidptr) int

fn C.ui2_win_draw_focus_rect(hwnd voidptr)

fn C.ui2_win_focus_handle() voidptr

fn C.ui2_win_clear_focus(root voidptr)

fn C.ui2_win_client_width(hwnd voidptr) int

fn C.ui2_win_client_height(hwnd voidptr) int

fn C.ui2_win_text_length(hwnd voidptr) int

fn C.ui2_win_get_text(hwnd voidptr, buffer &u16, capacity int) int

fn C.ui2_win_set_text(hwnd voidptr, text &u16)

fn C.ui2_win_set_checked(hwnd voidptr, checked int)

fn C.ui2_win_get_checked(hwnd voidptr) int

fn C.ui2_win_slider_set_normalized(hwnd voidptr, normalized f64, vertical int)

fn C.ui2_win_slider_normalized(hwnd voidptr, vertical int) f64

fn C.ui2_win_set_edit_options(hwnd voidptr, placeholder &u16, readonly int, padding_left int)

fn C.ui2_win_placeholder_matches(hwnd voidptr, expected &u16) int

fn C.ui2_win_widget_style(hwnd voidptr) usize

fn C.ui2_win_click(hwnd voidptr)

fn C.ui2_win_notify_invoked(hwnd voidptr)

fn C.ui2_win_accessible_button_info(hwnd voidptr, expected_name &u16) u32

fn C.ui2_win_accessible_button_invoke(hwnd voidptr) int

fn C.ui2_win_dispatch_pending_messages()

fn C.ui2_win_get_selection(hwnd voidptr, start &u32, end &u32)

fn C.ui2_win_set_selection(hwnd voidptr, start u32, end u32, focus int)

fn C.ui2_win_replace_selection(hwnd voidptr, text &u16)

fn C.ui2_win_combo_reset(hwnd voidptr)

fn C.ui2_win_combo_add(hwnd voidptr, text &u16)

fn C.ui2_win_combo_select_text(hwnd voidptr, text &u16)

fn C.ui2_win_logical_font_height(logical_size f64, dpi u32) int
fn C.ui2_win_create_font(hwnd voidptr, logical_size f64, family &u16, weight int, italic int, underline int, strikeout int, text &u16) voidptr

fn C.ui2_win_apply_text_font(hwnd voidptr, text &u16)

fn C.ui2_win_font_missing_glyphs(font voidptr, text &u16) int

fn C.ui2_win_font_family(font voidptr, buffer &u16, capacity int)

fn C.ui2_win_widget_font(hwnd voidptr) voidptr

fn C.ui2_win_apply_font(hwnd voidptr, font voidptr)

fn C.ui2_win_create_brush(color u32) voidptr

fn C.ui2_win_delete_object(object voidptr)

fn C.ui2_win_apply_control_colors(dc voidptr, foreground u32, background u32, transparent int, brush voidptr) isize

fn C.ui2_win_paint_background(hwnd voidptr, background u32, radius f64, transparent int, border_color u32, border_left f64, border_top f64, border_right f64, border_bottom f64)

fn C.ui2_win_paint_background_into(hwnd voidptr, dc voidptr, background u32, radius f64, transparent int, border_color u32, border_left f64, border_top f64, border_right f64, border_bottom f64)

struct C.ui2_win_mesh_vertex {
	x     int
	y     int
	color u32
}

fn C.ui2_win_paint_background_fx(hwnd voidptr, background u32, radius f64, transparent int, border_color u32, border_left f64, border_top f64, border_right f64, border_bottom f64, opacity f64, vertices &C.ui2_win_mesh_vertex, vertex_count int, triangles &u32, triangle_count int)

fn C.ui2_win_paint_background_into_fx(hwnd voidptr, dc voidptr, background u32, radius f64, transparent int, border_color u32, border_left f64, border_top f64, border_right f64, border_bottom f64, opacity f64, vertices &C.ui2_win_mesh_vertex, vertex_count int, triangles &u32, triangle_count int)

// WindowsGradientMesh is what GradientFill draws a box's gradient from: a grid of
// cells whose corners take the gradient's color there, two triangles a cell.
struct WindowsGradientMesh {
mut:
	vertices  []C.ui2_win_mesh_vertex
	triangles []u32
}

fn windows_gradient_mesh(box BoxStyle, width int, height int) WindowsGradientMesh {
	mut mesh := WindowsGradientMesh{}
	if !box_has_gradient(box) || width <= 0 || height <= 0 {
		return mesh
	}
	stops := gradient_sorted_stops(box.gradient)
	line := gradient_line(box.gradient.angle, f64(width), f64(height))
	cell := 8
	columns := (width + cell - 1) / cell
	rows := (height + cell - 1) / cell
	for row in 0 .. rows + 1 {
		y := if row * cell < height { row * cell } else { height }
		for column in 0 .. columns + 1 {
			x := if column * cell < width { column * cell } else { width }
			color, _ := gradient_color_at(stops, gradient_position(line, f64(x), f64(y)))
			mesh.vertices << C.ui2_win_mesh_vertex{
				x:     x
				y:     y
				color: color
			}
		}
	}
	for row in 0 .. rows {
		for column in 0 .. columns {
			a := u32(row * (columns + 1) + column)
			d := a + u32(columns + 1)
			mesh.triangles << [a, a + 1, d + 1, a, d + 1, d]
		}
	}
	return mesh
}

// windows_paint_box paints a view's background, fill effects included, into its
// own paint cycle (dc nil) or into a DC a descendant asked for.
fn windows_paint_box(hwnd voidptr, dc voidptr, box BoxStyle, transparent int) {
	mesh := windows_gradient_mesh(box, C.ui2_win_client_width(hwnd), C.ui2_win_client_height(hwnd))
	vertices := if mesh.vertices.len > 0 { &mesh.vertices[0] } else { unsafe { nil } }
	triangles := if mesh.triangles.len > 0 { &mesh.triangles[0] } else { unsafe { nil } }
	opacity := if box.transparent { 1.0 } else { box_fill_opacity(box) }
	if dc == unsafe { nil } {
		C.ui2_win_paint_background_fx(hwnd, box.bg, box.radius, transparent, box.border_color,
			box.border_left, box.border_top, box.border_right, box.border_bottom, opacity,
			vertices, mesh.vertices.len, triangles, mesh.triangles.len / 3)
	} else {
		C.ui2_win_paint_background_into_fx(hwnd, dc, box.bg, box.radius, transparent,
			box.border_color, box.border_left, box.border_top, box.border_right,
			box.border_bottom, opacity, vertices, mesh.vertices.len, triangles,
			mesh.triangles.len / 3)
	}
}

fn C.ui2_win_paint_transparent_button(hwnd voidptr, foreground u32, radius f64, border_color u32, border_left f64, border_top f64, border_right f64, border_bottom f64)

fn C.ui2_win_paint_control_border(hwnd voidptr, color u32, radius f64, left f64, top f64, right f64, bottom f64)

fn C.ui2_win_invalidate(hwnd voidptr)

fn C.ui2_win_invalidate_parent(hwnd voidptr)

fn C.ui2_win_set_bitmap(hwnd voidptr, path &u16, width int, height int) voidptr

fn C.ui2_win_clear_bitmap(hwnd voidptr)

fn C.ui2_win_set_scroll(hwnd voidptr, content int, position int, horizontal int) int

fn C.ui2_win_set_scroll_both(hwnd voidptr, content_width int, content_height int, position_x int, position_y int)

fn C.ui2_win_scroll_position(hwnd voidptr, horizontal int) int

fn C.ui2_win_scroll_message(hwnd voidptr, wparam usize, horizontal int) int

fn C.ui2_win_wheel_distance(wparam usize, tilt int, horizontal int) int

fn C.ui2_win_scroll_by(hwnd voidptr, distance int, horizontal int) int

fn C.ui2_win_scroll_parent(hwnd voidptr, horizontal int) voidptr

fn C.ui2_win_wheel_is_shifted(wparam usize) int

fn C.ui2_win_scroll_to_rect(hwnd voidptr, start int, end int, horizontal int) int
fn C.ui2_win_set_scroll_position(hwnd voidptr, position int, horizontal int) int

fn C.ui2_win_capture_mouse(hwnd voidptr)

fn C.ui2_win_release_mouse()

fn C.ui2_win_ticks() u64

fn C.ui2_win_point_to_root(hwnd voidptr, root voidptr, x &int, y &int)

fn C.ui2_win_hover_target(root voidptr, x &int, y &int) voidptr

fn C.ui2_win_root_point_in_client(root voidptr, target voidptr, x int, y int) int

fn C.ui2_win_menu_create() voidptr

fn C.ui2_win_menu_add(menu voidptr, command u32, title &u16, enabled int)

fn C.ui2_win_menu_track(menu voidptr, hwnd voidptr, x int, y int) u32

fn C.ui2_win_menu_destroy(menu voidptr)

fn C.ui2_win_drop_count(drop voidptr) u32

fn C.ui2_win_drop_path_length(drop voidptr, index u32) u32

fn C.ui2_win_drop_path(drop voidptr, index u32, buffer &u16, capacity u32)

fn C.ui2_win_drop_point(drop voidptr, x &int, y &int)

fn C.ui2_win_drop_finish(drop voidptr)

fn C.ui2_win_key_down(virtual_key int) int

const win_wm_destroy = u32(0x0002)
const win_wm_size = u32(0x0005)
const win_wm_paint = u32(0x000f)
const win_wm_close = u32(0x0010)
const win_wm_erase_background = u32(0x0014)
const win_wm_key_down = u32(0x0100)
const win_wm_key_up = u32(0x0101)
const win_wm_char = u32(0x0102)
const win_wm_activate_app = u32(0x001c)
const win_wm_command = u32(0x0111)
const win_wm_hscroll = u32(0x0114)
const win_wm_vscroll = u32(0x0115)
const win_wm_ctlcolor_edit = u32(0x0133)
const win_wm_ctlcolor_listbox = u32(0x0134)
const win_wm_ctlcolor_button = u32(0x0135)
const win_wm_ctlcolor_static = u32(0x0138)
const win_wm_mouse_move = u32(0x0200)
const win_wm_lbutton_down = u32(0x0201)
const win_wm_mouse_wheel = u32(0x020a)
const win_wm_mouse_hwheel = u32(0x020e)
const win_wm_dropfiles = u32(0x0233)
const win_wm_refresh = u32(0x8000 + 77)
const win_wm_paint_background = u32(0x8000 + 80)
const win_wm_getminmaxinfo = u32(0x0024)

const win_bn_clicked = 0
const win_cbn_selchange = 1
const win_en_change = 0x0300


struct WindowsCallbackBinding {
	id       string
	on_event ElementCallback = unsafe { nil }
	kind     Kind
	event    ElementEventKind
}

fn windows_callback_binding(el Element, event ElementEventKind) WindowsCallbackBinding {
	return WindowsCallbackBinding{ id: el.id, on_event: el.on_event, kind: el.kind, event: event }
}

struct WindowsControlCapture {
	binding WindowsCallbackBinding
	cancelled bool
}

struct WindowsPointerBinding {
	on_event ElementCallback = unsafe { nil }
	id              string
	clickable       bool
	button_behavior bool
	draggable       bool
	long_press      bool
	swipe_left      bool
}

// Window is one top-level Win32 window and the child controls ui2 reconciles
// into it. The window procedure and the control subclasses call back with a
// window handle, which the process's WindowsHost maps back to its Window.
@[heap]
pub struct Window {
mut:
	app             &App = unsafe { nil }
	title           string
	width           int
	height          int
	min_width       int
	min_height      int
	build           BuildFn = BuildFn(unsafe { nil })
	menus           MenuDeclarations
	timers          &TimerRuntime = &TimerRuntime{}
	event_modifiers KeyModifiers
	close_hooks     []fn ()
	closed          bool
	text_key_consumed bool
	// The selection set for a text area while it has no edit control.
	text_area_selections map[string]TextAreaSelectionRange
	layout_tree &LayoutTree = &LayoutTree{}
	layout_environment LayoutEnvironment
	navigation &FocusManager = &FocusManager{}
	navigation_paths map[string]string
	suppressed_keys map[u32]u32
	activation_keys map[u32]bool // Virtual key + scan/extended bit, independent of HWND.
	keyboard_generation u64 // A synchronous callback can release the press/host.
	symbol_font_attempted bool
	hover_bindings        map[u64]HoverTarget // window handle -> hoverable element
	hovered               []HoverTarget       // hovered elements, outermost first
	key_handler        KeyFn = KeyFn(unsafe { nil })
	key_event_handler  KeyEventFn = KeyEventFn(unsafe { nil })
	drop_handler       DropFn = DropFn(unsafe { nil })
	root               voidptr
	nodes              map[string]voidptr
	node_kinds         map[string]Kind
	node_parents       map[string]string
	node_frames        map[string]Rect
	node_structural    map[string]string
	node_declared_text map[string]string
	node_option_sig    map[string]string
	node_image_path    map[string]string
	node_ids           map[string]string
	node_boxes         map[string]BoxStyle
	node_text_styles   map[string]TextStyle
	fonts              map[string]voidptr
	font_sigs          map[string]string
	brushes            map[string]voidptr
	brush_sigs         map[string]u32
	images             map[string]voidptr
	tooltips           map[string]voidptr
	tooltip_sigs       map[string]string
	views              map[string]voidptr
	view_keys          map[string]string
	view_kinds         map[string]Kind
	label_frames       map[string]Rect
	handle_keys        map[u64]string
	action_bindings         map[u64]WindowsCallbackBinding
	control_captures        map[u64]WindowsControlCapture
	control_native_activations map[u64]int
	change_bindings         map[u64]WindowsCallbackBinding
	submit_bindings         map[u64]WindowsCallbackBinding
	pointer_bindings   map[u64]WindowsPointerBinding
	context_menus      map[u64][]MenuEntry
	cursors            map[u64]int
	scroll_callbacks         map[u64]WindowsCallbackBinding
	slider_specs       map[u64]SliderSpec
	toggle_groups      map[u64]string
	toggle_allow_no_selection map[u64]bool
	toggle_ids         map[u64]string
	toggle_views       map[u64]voidptr
	scroll_positions   map[string]int
	scroll_positions_x map[string]int // only the Scroll elements whose mode scrolls sideways
	node_label_boxed   map[string]bool
	pending_scroll     map[string]int // Scroll element id -> offset to apply when it renders
	pending_scroll_x   map[string]int
	rendering          bool
	rebuild_queued     bool // request_refresh posted a rebuild that has not run yet
	key_consumed       bool
	pointer_handle     voidptr
	pointer_binding    WindowsPointerBinding
	pointer_start_x    int
	pointer_start_y    int
	pointer_started    u64
	pointer_moved      bool
	suppress_click     map[u64]bool
}

fn C.AddFontResourceExW(name &u16, flags u32, reserved voidptr) int

const windows_fr_private = u32(0x10)

// Win32 has no symbol images, so a `symbol:` image is drawn as a label holding its
// Material Icons glyph, the way the custom renderer draws it, tinted with the text
// color and sized so the glyph's em fills the smaller side of the frame (a
// point is 4/3 of a 96-DPI pixel). Subtrees without one are returned untouched.
fn (mut w Window) windows_symbol_images_as_labels(el Element) Element {
	if !element_has_symbol_image(el) {
		return el
	}
	mut children := []Element{cap: el.children.len}
	for child in el.children {
		children << w.windows_symbol_images_as_labels(child)
	}
	if el.kind == .image {
		if name := symbol_name(el.image_path) {
			w.windows_load_symbol_font()
			side := if el.frame.width < el.frame.height { el.frame.width } else { el.frame.height }
			return Element{
				...el
				kind:                .label
				text:                symbol_glyph(name)
				image_path:          ''
				children:            children
				text_style:          TextStyle{
					color:       el.text_style.color
					font_family: 'Material Icons'
					size:        side * 0.75
					align:       .center
					valign:      .middle
				}
				accessibility_role:  if el.accessibility_role.len > 0 { el.accessibility_role } else { 'img' }
				accessibility_label: if el.accessibility_label.len > 0 { el.accessibility_label } else { name }
			}
		}
	}
	return Element{
		...el
		children: children
	}
}

fn element_has_symbol_image(el Element) bool {
	if el.kind == .image && el.image_path.starts_with('symbol:') {
		return true
	}
	for child in el.children {
		if element_has_symbol_image(child) {
			return true
		}
	}
	return false
}

// Registers the bundled Material Icons face for this process only, once.
fn (mut w Window) windows_load_symbol_font() {
	if w.symbol_font_attempted {
		return
	}
	w.symbol_font_attempted = true
	path := font_bundle_file('MaterialIcons-Regular.ttf')
	if path.len == 0 {
		eprintln('ui2: MaterialIcons-Regular.ttf was not found; symbol images will not draw')
		return
	}
	wide := path.to_wide()
	if C.AddFontResourceExW(wide, windows_fr_private, unsafe { nil }) == 0 {
		eprintln('ui2: could not load ${path}; symbol images will not draw')
	}
	unsafe { free(wide) }
}


fn windows_handle_id(hwnd voidptr) u64 {
	return u64(hwnd)
}

fn windows_uses_transparent_button_paint(kind Kind, box BoxStyle) bool {
	return box.transparent && kind in [.button, .toggle_button]
}

// Whether a window leaves the background behind it alone. A label paints none of its
// own on Windows: what shows behind its text is whatever its parent put there, which
// is what the control colour handler has always answered. The view holding a label
// has to answer the same, or a label given a border, a tooltip or a menu — any of
// which is enough to put it in one — would come out white on a parent that is not.
fn windows_draws_no_background(kind Kind, box BoxStyle) bool {
	return box.transparent || kind in [.label, .checkbox]
}

// A static control centres one line of text for itself and can do nothing about a
// wrapped block, so a label is measured and given the rectangle its text really
// needs. Every label is, not only one placed away from the top: a static draws as
// many lines as its rectangle has room for, so a frame taller than the line budget
// would otherwise show more lines than were asked for. Measuring holds it to the
// budget, and the top of the rectangle is where the alignment puts it.
//
// The measured rectangle is what gets remembered, so scrolling the pane it sits in
// takes the label with it rather than putting it back where it was laid out.
fn (mut w Window) windows_place_label(key string, hwnd voidptr, el Element, x_offset int, y_offset int) {
	if C.ui2_win_label_text_hwnd(hwnd) != hwnd {
		windows_place_held_label(hwnd, el)
		return
	}
	mut placed := el.frame
	if el.frame.height > 0 && el.text.len > 0 {
		content := f64(C.ui2_win_label_content_height(hwnd, int(el.frame.width), text_line_budget(el.text_style.lines)))
		if content > 0 && content < el.frame.height {
			placed = Rect{
				x:      el.frame.x
				y:      text_block_top(el.frame.y, el.frame.height, content, el.text_style.valign)
				width:  el.frame.width
				height: content
			}
		}
	}
	w.node_frames[key] = placed
	C.ui2_win_set_widget_frame(hwnd, windows_widget_kind(el.kind), int(placed.x) + x_offset,
		int(placed.y) + y_offset, int(placed.width), int(placed.height))
}

// Setting a label's text has to place it again. The label sits on the rectangle the
// text before it needed, so left alone it clips text that is taller and holds text
// that is shorter where it no longer belongs.
fn (mut w Window) windows_place_label_text(id string, hwnd voidptr, value string) {
	key := w.view_keys[id] or { return }
	frame := w.label_frames[id] or { return }
	parent_key := w.node_parents[key] or { '' }
	mut x_offset := 0
	mut y_offset := 0
	if (w.node_kinds[parent_key] or { Kind.view }) == .scroll {
		x_offset = -(w.scroll_positions_x[parent_key] or { 0 })
		y_offset = -(w.scroll_positions[parent_key] or { 0 })
	}
	w.windows_place_label(key, hwnd, Element{
		kind:       .label
		text:       value
		frame:      frame
		box:        w.node_boxes[key] or { BoxStyle{} }
		text_style: w.node_text_styles[key] or { TextStyle{} }
	}, x_offset, y_offset)
}

fn windows_align(align Align) int {
	return match align {
		.left { 0 }
		.center { 1 }
		.right { 2 }
	}
}

fn windows_native_text(hwnd voidptr) string {
	length := C.ui2_win_text_length(hwnd)
	if length <= 0 {
		return ''
	}
	mut buffer := []u16{len: length + 1}
	read := C.ui2_win_get_text(hwnd, unsafe { &buffer[0] }, length + 1)
	if read <= 0 {
		return ''
	}
	return unsafe { string_from_wide2(&buffer[0], read) }
}

fn windows_set_native_text(hwnd voidptr, value string) {
	wide := value.to_wide()
	C.ui2_win_set_text(hwnd, wide)
	unsafe { free(wide) }
}

pub fn (mut w Window) bounds() Rect {
	if w.root == unsafe { nil } || C.ui2_win_is_window(w.root) == 0 {
		return Rect{
			width: f64(w.width)
			height: f64(w.height)
		}
	}
	return Rect{
		width: f64(C.ui2_win_client_width(w.root))
		height: f64(C.ui2_win_client_height(w.root))
	}
}

// rebuild_now builds and renders the window's tree on the UI thread.
fn (mut w Window) rebuild_now() {
	if w.closed || w.root == unsafe { nil } || w.rendering || voidptr(w.build) == unsafe { nil } {
		return
	}
	w.rebuild_queued = false
	// `after` callbacks run on the UI thread before the build, so it declares
	// what they changed.
	w.run_due_timers()
	w.windows_render_declaration(w.build(mut w))
}

pub fn (mut w Window) refresh_element(id string, element Element) {
	w.layout_tree.patch(id, element) or { eprintln('ui2 layout: ${err}'); return }
	w.windows_render_mounted_layout()
}

pub fn (mut w Window) layout_stats() LayoutStats { return w.layout_tree.stats() }

pub fn (mut w Window) invalidate_layout_environment(environment LayoutEnvironment) {
	w.layout_environment = environment
	if w.layout_tree.root.len > 0 { w.windows_render_mounted_layout() }
}

fn (mut w Window) windows_render_declaration(declared Element) {
	w.layout_tree.replace(declared) or { eprintln('ui2 layout: ${err}'); return }
	root := w.layout_tree.resolve(LayoutConstraints{}, measure_layout_text, w.layout_environment) or { eprintln('ui2 layout: ${err}'); return }
	w.windows_render_resolved(root)
}

fn (mut w Window) windows_render_mounted_layout() {
	root := w.layout_tree.resolve(LayoutConstraints{}, measure_layout_text, w.layout_environment) or { eprintln('ui2 layout: ${err}'); return }
	w.windows_render_resolved(root)
}

fn (mut w Window) windows_render_resolved(resolved Element) {
	// Symbol images become glyph labels once their frames are resolved.
	root := w.windows_symbol_images_as_labels(resolved)
	previous_focus := w.focused_id()
	w.rendering = true
	w.views = map[string]voidptr{}
	w.view_keys = map[string]string{}
	w.view_kinds = map[string]Kind{}
	w.label_frames = map[string]Rect{}
	w.handle_keys = map[u64]string{}
	w.action_bindings = map[u64]WindowsCallbackBinding{}
	w.change_bindings = map[u64]WindowsCallbackBinding{}
	w.submit_bindings = map[u64]WindowsCallbackBinding{}
	w.pointer_bindings = map[u64]WindowsPointerBinding{}
	w.hover_bindings = map[u64]HoverTarget{}
	w.context_menus = map[u64][]MenuEntry{}
	w.cursors = map[u64]int{}
	w.scroll_callbacks = map[u64]WindowsCallbackBinding{}
	w.slider_specs = map[u64]SliderSpec{}
	w.toggle_groups = map[u64]string{}
	w.toggle_allow_no_selection = map[u64]bool{}
	w.toggle_ids = map[u64]string{}
	w.toggle_views = map[u64]voidptr{}
	mut active := map[string]bool{}
	if root.kind == .screen {
		w.node_boxes[''] = root.box
		w.windows_render_children(w.root, root.children, '', 0, 0, mut active)
	} else {
		w.node_boxes[''] = BoxStyle{}
		w.windows_render_element(w.root, root, reconciliation_child_key('', 0, root), '', 0, 0, mut active)
	}
	w.windows_remove_stale(active)
	w.rendering = false
	w.reconcile_windows_focus(root, previous_focus)
	C.ui2_win_invalidate(w.root)
	// Content can move under a cursor that stays put.
	w.windows_update_hover()
}

// request_refresh posts a rebuild to the window's message loop.
pub fn (mut w Window) request_refresh() {
	if w.root != unsafe { nil } {
		w.rebuild_queued = true
		C.ui2_win_post_refresh(w.root)
	}
}

pub fn (mut w Window) on_key(handler KeyFn) {
	w.key_handler = handler
}

pub fn (mut w Window) on_key_event(handler KeyEventFn) {
	w.key_event_handler = handler
}

pub fn (mut w Window) on_drop(handler DropFn) {
	w.drop_handler = handler
}

// set_window_title updates the current Win32 window title.
pub fn (mut w Window) set_window_title(title string) {
	if w.root != unsafe { nil } {
		wide_title := title.to_wide()
		C.ui2_win_set_window_title(w.root, wide_title)
		unsafe { free(wide_title) }
	}
}

pub fn (mut w Window) text(id string) string {
	hwnd := w.views[id] or { return '' }
	if (w.view_kinds[id] or { Kind.view }) == .label {
		// A label is its static control, or the view holding one.
		return windows_native_text(C.ui2_win_label_text_hwnd(hwnd))
	}
	return windows_native_text(hwnd)
}

pub fn (mut w Window) set_text(id string, value string) {
	outer := w.views[id] or { return }
	kind := w.view_kinds[id] or { Kind.view }
	mut hwnd := outer
	if kind == .label {
		hwnd = C.ui2_win_label_text_hwnd(outer)
	}
	was_rendering := w.rendering
	w.rendering = true
	if kind == .dropdown {
		wide_value := value.to_wide()
		C.ui2_win_combo_select_text(hwnd, wide_value)
		unsafe { free(wide_value) }
	} else {
		windows_set_native_text(hwnd, value)
	}
	if kind == .label {
		w.windows_place_label_text(id, outer, value)
	}
	w.rendering = was_rendering
}

pub fn (mut w Window) slider_value(id string) f64 {
	hwnd := w.views[id] or { return 0 }
	if (w.view_kinds[id] or { Kind.view }) != .slider {
		return 0
	}
	spec := w.slider_specs[windows_handle_id(hwnd)] or { return 0 }
	return windows_snap_slider_value(hwnd, spec)
}

pub fn (mut w Window) set_slider_value(id string, value f64) {
	hwnd := w.views[id] or { return }
	if (w.view_kinds[id] or { Kind.view }) != .slider {
		return
	}
	spec := w.slider_specs[windows_handle_id(hwnd)] or { return }
	normalized := slider_value_normalized(slider_clamped_value(value, spec.min, spec.max),
		spec.min, spec.max)
	C.ui2_win_slider_set_normalized(hwnd, normalized,
		windows_bool(spec.orientation == .vertical))
}

pub fn (mut w Window) switch_active(id string) bool {
	hwnd := w.views[id] or { return false }
	if (w.view_kinds[id] or { Kind.view }) != .switch_control {
		return false
	}
	return C.ui2_win_get_checked(hwnd) != 0
}

pub fn (mut w Window) set_switch_active(id string, active bool) {
	hwnd := w.views[id] or { return }
	if (w.view_kinds[id] or { Kind.view }) != .switch_control {
		return
	}
	C.ui2_win_set_checked(hwnd, windows_bool(active))
}

pub fn (mut w Window) toggle_button_pressed(id string) bool {
	hwnd := w.views[id] or { return false }
	if (w.view_kinds[id] or { Kind.view }) != .toggle_button {
		return false
	}
	return C.ui2_win_get_checked(hwnd) != 0
}

pub fn (mut w Window) set_toggle_button_pressed(id string, pressed bool) {
	hwnd := w.views[id] or { return }
	if (w.view_kinds[id] or { Kind.view }) != .toggle_button {
		return
	}
	if pressed {
		w.release_windows_toggle_group(windows_handle_id(hwnd))
	}
	C.ui2_win_set_checked(hwnd, windows_bool(pressed))
}

pub fn (mut w Window) toggle_button_group_members(id string) []string {
	hwnd := w.views[id] or { return [] }
	handle := windows_handle_id(hwnd)
	group := w.toggle_groups[handle] or { return [id] }
	if group.len == 0 {
		return [id]
	}
	mut members := []string{}
	for member_handle, member_group in w.toggle_groups {
		if member_group == group {
			member_id := w.toggle_ids[member_handle] or { continue }
			if member_id.len > 0 {
				members << member_id
			}
		}
	}
	return members
}

fn (mut w Window) release_windows_toggle_group(handle u64) {
	group := w.toggle_groups[handle] or { return }
	if group.len == 0 {
		return
	}
	for member_handle, member_group in w.toggle_groups {
		if member_handle == handle || member_group != group {
			continue
		}
		native := w.toggle_views[member_handle] or { continue }
		C.ui2_win_set_checked(native, 0)
	}
}

fn (mut w Window) commit_windows_toggle_button(handle u64, hwnd voidptr) {
	group := w.toggle_groups[handle] or { return }
	if group.len == 0 {
		return
	}
	if C.ui2_win_get_checked(hwnd) != 0 {
		w.release_windows_toggle_group(handle)
	} else if !(w.toggle_allow_no_selection[handle] or { true }) {
		C.ui2_win_set_checked(hwnd, 1)
	}
}

pub fn (mut w Window) focus(id string) {
	w.sync_focus_navigation()
	if !w.navigation.set_focus(id) { return }
	hwnd := w.views[id] or { return }
	C.ui2_win_focus(hwnd)
	w.reveal_windows_focus(id)
}

pub fn (mut w Window) focused_id() string {
	focused := C.ui2_win_focus_handle()
	if focused == unsafe { nil } {
		return ''
	}
	key := w.handle_keys[windows_handle_id(focused)] or { return '' }
	return w.node_ids[key] or { '' }
}

pub fn (mut w Window) focused_text_area_id() string {
	focused := C.ui2_win_focus_handle()
	if focused == unsafe { nil } {
		return ''
	}
	key := w.handle_keys[windows_handle_id(focused)] or { return '' }
	if (w.node_kinds[key] or { Kind.view }) != .text_area {
		return ''
	}
	for id, view_key in w.view_keys {
		if view_key == key {
			return id
		}
	}
	return ''
}

pub fn (mut w Window) dismiss_keyboard() {
	C.ui2_win_clear_focus(w.root)
}

pub fn (mut w Window) consume_key() {
	w.key_consumed = true
}

pub fn (mut w Window) consume_text_key() {
	w.consume_key()
}

pub fn (mut w Window) insert_text_area_text(id string, value string) {
	hwnd := w.windows_text_area_handle(id) or { return }
	wide_value := value.to_wide()
	C.ui2_win_replace_selection(hwnd, wide_value)
	unsafe { free(wide_value) }
}

pub fn (mut w Window) scroll_offset(id string) f64 {
	key := w.view_keys[id] or { return 0 }
	return f64(w.scroll_positions[key] or { 0 })
}

// scroll_horizontal_offset returns how far a Scroll element is scrolled sideways. It
// stays zero for one whose scroll_mode leaves the horizontal axis out.
pub fn (mut w Window) scroll_horizontal_offset(id string) f64 {
	key := w.view_keys[id] or { return 0 }
	return f64(w.scroll_positions_x[key] or { 0 })
}

// scroll_to_offset puts a Scroll element at the given vertical offset. An element on
// screen moves at once. One that does not exist yet has no range to clamp against, so
// the request is kept and taken up the next time the element is laid out — that is
// what lets a screen open where it was last left.
pub fn (mut w Window) scroll_to_offset(id string, offset f64) {
	if id.len == 0 {
		return
	}
	wanted := if offset < 0 { 0 } else { int(offset) }
	if (w.view_kinds[id] or { Kind.view }) == .scroll {
		key := w.view_keys[id] or { '' }
		if key.len > 0 {
			if hwnd := w.views[id] {
				reached := C.ui2_win_set_scroll_position(hwnd, wanted, 0)
				w.scroll_positions[key] = reached
				w.windows_reposition_scroll_children(key)
				// Past the current range while a rebuild is queued: that rebuild's
				// layout takes the offset up again, with the content it adds.
				if reached != wanted && w.rebuild_queued {
					w.pending_scroll[id] = wanted
				} else {
					w.pending_scroll.delete(id)
				}
				return
			}
		}
	}
	w.pending_scroll[id] = wanted
}

// scroll_to_horizontal_offset is scroll_to_offset for the sideways axis, with the same
// promise: an offset asked for before the element exists is kept until it does. An
// element that does not scroll sideways has no horizontal bar to move.
pub fn (mut w Window) scroll_to_horizontal_offset(id string, offset f64) {
	if id.len == 0 {
		return
	}
	wanted := if offset < 0 { 0 } else { int(offset) }
	if (w.view_kinds[id] or { Kind.view }) == .scroll {
		key := w.view_keys[id] or { '' }
		if key.len > 0 {
			if hwnd := w.views[id] {
				mut reached := wanted
				if key in w.scroll_positions_x {
					reached = C.ui2_win_set_scroll_position(hwnd, wanted, 1)
					w.scroll_positions_x[key] = reached
					w.windows_reposition_scroll_children(key)
				}
				if reached != wanted && w.rebuild_queued {
					w.pending_scroll_x[id] = wanted
				} else {
					w.pending_scroll_x.delete(id)
				}
				return
			}
		}
	}
	w.pending_scroll_x[id] = wanted
}

pub fn (mut w Window) scroll_to_rect(id string, x f64, y f64, width f64, height f64) {
	key := w.view_keys[id] or { return }
	if (w.view_kinds[id] or { Kind.view }) != .scroll {
		return
	}
	hwnd := w.views[id] or { return }
	w.scroll_positions[key] = C.ui2_win_scroll_to_rect(hwnd, int(y), int(y + height), 0)
	if key in w.scroll_positions_x {
		w.scroll_positions_x[key] = C.ui2_win_scroll_to_rect(hwnd, int(x), int(x + width), 1)
	}
	w.windows_reposition_scroll_children(key)
}

fn (mut w Window) windows_render_children(parent voidptr, children []Element, parent_key string, x_offset int, y_offset int, mut active map[string]bool) {
	mut previous := voidptr(unsafe { nil })
	for index, child in children {
		key := reconciliation_child_key(parent_key, index, child)
		hwnd := w.windows_render_element(parent, child, key, parent_key, x_offset, y_offset, mut active)
		if hwnd != unsafe { nil } {
			C.ui2_win_place_after(hwnd, previous)
			previous = hwnd
		}
	}
}

fn (mut w Window) windows_render_element(parent voidptr, el Element, key string, parent_key string, x_offset int, y_offset int, mut active map[string]bool) voidptr {
	active[key] = true
	structural := windows_structural_signature(el)
	mut hwnd := w.nodes[key] or { voidptr(unsafe { nil }) }
	old_kind := w.node_kinds[key] or { Kind.screen }
	old_structural := w.node_structural[key] or { '' }
	must_create := hwnd == unsafe { nil } || C.ui2_win_is_window(hwnd) == 0 || old_kind != el.kind
		|| old_structural != structural
	mut restore_text := ''
	mut restore_start := u32(0)
	mut restore_end := u32(0)
	mut restore_focus := false
	mut restore_edit := false
	if must_create && hwnd != unsafe { nil } {
		if (old_kind == .text_field || old_kind == .text_area)
			&& (w.node_declared_text[key] or { '' }) == el.text {
			restore_edit = true
			restore_text = windows_native_text(hwnd)
			C.ui2_win_get_selection(hwnd, &restore_start, &restore_end)
			restore_focus = C.ui2_win_focus_handle() == hwnd
		}
	}
	if must_create {
		created := windows_create_element(parent, el, x_offset, y_offset)
		if created == unsafe { nil } {
			eprintln('ui2: failed to create native Windows control `${el.id}` (${el.kind})')
			return hwnd
		}
		if hwnd != unsafe { nil } {
			w.windows_reparent_direct_children(key, created)
			w.windows_cleanup_node_resources(key, hwnd, old_kind)
			C.ui2_win_destroy(hwnd)
		}
		hwnd = created
		w.nodes[key] = hwnd
		w.node_kinds[key] = el.kind
		w.node_structural[key] = structural
		if restore_edit {
			if restore_text != el.text {
				windows_set_native_text(hwnd, restore_text)
			}
			C.ui2_win_set_selection(hwnd, restore_start, restore_end, windows_bool(restore_focus))
		}
	} else if C.ui2_win_parent(hwnd) != parent {
		C.ui2_win_set_parent(hwnd, parent)
	}
	w.node_parents[key] = parent_key
	w.node_frames[key] = el.frame
	visual_box := if el.kind == .toggle_button && el.checked { el.toggle_down_box() } else { el.box }
	visual_text_style := if el.kind == .toggle_button && el.checked {
		el.toggle_down_text_style()
	} else {
		el.text_style
	}
	w.node_boxes[key] = visual_box
	w.node_text_styles[key] = visual_text_style
	w.node_ids[key] = el.id
	w.handle_keys[windows_handle_id(hwnd)] = key
	if el.kind == .label {
		// A held label's static sends its own WM_CTLCOLORSTATIC, so it has to lead
		// back to the same node or the label loses its colours to the default handler.
		text_hwnd := C.ui2_win_label_text_hwnd(hwnd)
		if text_hwnd != hwnd {
			w.handle_keys[windows_handle_id(text_hwnd)] = key
		}
	}
	if el.id.len > 0 {
		w.views[el.id] = hwnd
		w.view_keys[el.id] = key
		w.view_kinds[el.id] = el.kind
		if el.kind == .label {
			// The area the label was laid out with, as against the rectangle its text
			// ends up on, so text set over it later can be placed the same way.
			w.label_frames[el.id] = el.frame
		}
	}
	w.windows_update_element(key, hwnd, Element{
		...el
		box: visual_box
		text_style: visual_text_style
	}, x_offset, y_offset, must_create)
	if el.kind == .label {
		w.windows_place_label(key, hwnd, Element{
			...el
			text_style: visual_text_style
		}, x_offset, y_offset)
	}
	w.windows_register_bindings(hwnd, key, el)
	if el.kind == .view {
		caption := windows_button_accessibility_caption(el.accessibility_label)
		wide_caption := caption.to_wide()
		C.ui2_win_configure_accessible_button(hwnd, wide_caption,
			windows_bool(el.button_behavior))
		unsafe { free(wide_caption) }
	}
	if el.children.len > 0 {
		if el.kind == .scroll {
			x_position, position := w.windows_layout_scroll(hwnd, el, key)
			w.windows_render_children(hwnd, el.children, key, -x_position, -position, mut active)
		} else {
			w.windows_render_children(hwnd, el.children, key, 0, 0, mut active)
		}
	} else if el.kind == .scroll {
		w.scroll_positions[key] = C.ui2_win_set_scroll(hwnd, 0, 0, 0)
		if key in w.scroll_positions_x {
			w.scroll_positions_x[key] = C.ui2_win_set_scroll(hwnd, 0, 0, 1)
		}
	}
	return hwnd
}

// windows_layout_scroll sets a Scroll element's bars to cover its children along the
// axes its mode scrolls, taking up a position asked for before it was laid out, and
// returns where each bar settled. The horizontal bar is left alone on an element that
// has never scrolled sideways.
fn (mut w Window) windows_layout_scroll(hwnd voidptr, el Element, key string) (int, int) {
	scrolls_x := el.scroll_mode != .vertical_only
	content_height := if el.scroll_mode != .horizontal_only {
		windows_content_height(el.children)
	} else {
		0
	}
	mut requested := w.scroll_positions[key] or { 0 }
	mut requested_x := w.scroll_positions_x[key] or { 0 }
	if el.id.len > 0 {
		if pending := w.pending_scroll[el.id] {
			requested = pending
			w.pending_scroll.delete(el.id)
		}
		if pending := w.pending_scroll_x[el.id] {
			requested_x = pending
			w.pending_scroll_x.delete(el.id)
		}
	}
	mut position := 0
	mut x_position := 0
	if scrolls_x || key in w.scroll_positions_x {
		// Each bar takes room from the axis the other pages over, so the two are
		// settled together rather than one from what the other happened to leave.
		content_width := if scrolls_x { int(scroll_content_width(el.children)) } else { 0 }
		C.ui2_win_set_scroll_both(hwnd, content_width, content_height, requested_x, requested)
		x_position = C.ui2_win_scroll_position(hwnd, 1)
		position = C.ui2_win_scroll_position(hwnd, 0)
		if scrolls_x {
			w.scroll_positions_x[key] = x_position
		} else {
			w.scroll_positions_x.delete(key)
		}
	} else {
		position = C.ui2_win_set_scroll(hwnd, content_height, requested, 0)
	}
	w.scroll_positions[key] = position
	return x_position, position
}

fn windows_create_element(parent voidptr, el Element, x_offset int, y_offset int) voidptr {
	wide := el.text.to_wide()
	boxed := label_needs_container(el)
	mut host := parent
	mut x := int(el.frame.x) + x_offset
	mut y := int(el.frame.y) + y_offset
	mut container := voidptr(unsafe { nil })
	if boxed {
		empty := ''.to_wide()
		container = C.ui2_win_create_widget(windows_widget_kind(.view), parent, x, y,
			int(el.frame.width), int(el.frame.height), empty, 0, 0, 0, 0, 0)
		unsafe { free(empty) }
		host = container
		x = 0
		y = 0
	}
	hwnd := C.ui2_win_create_widget(windows_widget_kind(el.kind), host, x, y, int(el.frame.width),
		windows_native_height(el), wide, windows_align(el.text_style.align), windows_bool(el.secure),
		windows_bool(el.readonly), windows_bool(el.disable_scroll), windows_bool(el.orientation == .vertical))
	unsafe { free(wide) }
	if boxed {
		return container
	}
	return hwnd
}

// The holder covers the declared frame and is what draws the background and the
// border, so the static inside it starts past the border and only ever draws text.
// It is placed again on every pass, because the holder is the window the layout
// resizes and the static would otherwise keep the size it was made at.
fn windows_place_held_label(hwnd voidptr, el Element) {
	text_hwnd := C.ui2_win_label_text_hwnd(hwnd)
	if text_hwnd == hwnd {
		return
	}
	frame_width := int(el.frame.width)
	frame_height := int(el.frame.height)
	// Where the border really ends, asked of the same rounding that paints it: any
	// border at all covers a whole pixel, so an inset taken by truncating would leave
	// the control drawing over the border it was moved aside for.
	left := C.ui2_win_border_width(el.box.border_left, frame_width)
	top := C.ui2_win_border_width(el.box.border_top, frame_height)
	right := C.ui2_win_border_width(el.box.border_right, frame_width)
	bottom := C.ui2_win_border_width(el.box.border_bottom, frame_height)
	// Borders wide enough to meet leave nothing to draw text on. The control is still
	// given that nothing, because a control left at the size it had is a control
	// drawing over them.
	mut width := frame_width - left - right
	if width < 0 {
		width = 0
	}
	mut height := frame_height - top - bottom
	if height < 0 {
		height = 0
	}
	mut y := top
	mut drawn := height
	if el.text.len > 0 && width > 0 && height > 0 {
		content := int(C.ui2_win_label_content_height(text_hwnd, width, text_line_budget(el.text_style.lines)))
		if content > 0 && content < height {
			drawn = content
			y = int(text_block_top(f64(top), f64(height), f64(content), el.text_style.valign))
		}
	}
	C.ui2_win_set_widget_frame(text_hwnd, windows_widget_kind(el.kind), left, y, width,
		drawn)
}

fn windows_native_height(el Element) int {
	height := int(el.frame.height)
	return if el.kind == .dropdown { height + 240 } else { height }
}

fn windows_widget_kind(kind Kind) int {
	return match kind {
		.view { 1 }
		.scroll { 2 }
		.label { 3 }
		.image { 4 }
		.button { 5 }
		.dropdown { 6 }
		.text_field { 7 }
		.text_area { 8 }
		.checkbox { 9 }
		.slider { 10 }
		.switch_control { 11 }
		.toggle_button { 12 }
		.screen { 0 }
	}
}

fn windows_structural_signature(el Element) string {
	return '${int(el.kind)}:${windows_bool(el.secure)}:${windows_align(el.text_style.align)}:${windows_bool(label_needs_container(el))}:${windows_bool(el.disable_scroll)}:${windows_bool(el.native_style)}:${int(el.orientation)}'
}

fn windows_content_height(children []Element) int {
	mut height := 0
	for child in children {
		bottom := int(child.frame.y + child.frame.height)
		if bottom > height {
			height = bottom
		}
	}
	return height
}

fn windows_options_signature(entries []MenuEntry) string {
	mut parts := []string{cap: entries.len}
	for entry in entries {
		parts << entry.id.bytes().hex() + ':' + entry.title.bytes().hex()
	}
	return parts.join('|')
}

fn windows_button_accessibility_caption(label string) string {
	// The standard BUTTON proxy treats ampersands as access-key markers.
	// Escape them so an accessibility label remains literal text.
	return label.replace('&', '&&')
}

fn (mut w Window) windows_update_element(key string, hwnd voidptr, el Element, x_offset int, y_offset int, created bool) {
	C.ui2_win_set_widget_frame(hwnd, windows_widget_kind(el.kind), int(el.frame.x) + x_offset, int(el.frame.y) + y_offset, int(el.frame.width), int(el.frame.height))
	C.ui2_win_show(hwnd, windows_bool(!el.hidden))
	C.ui2_win_enable(hwnd, windows_bool(el.enabled))
	declared_changed := (w.node_declared_text[key] or { '' }) != el.text
	// A held label draws with the control inside it; everything else draws with itself.
	mut text_hwnd := hwnd
	if el.kind == .label {
		text_hwnd = C.ui2_win_label_text_hwnd(hwnd)
	}
	match el.kind {
		.label, .button, .checkbox, .switch_control, .toggle_button {
			if declared_changed || windows_native_text(text_hwnd) != el.text {
				windows_set_native_text(text_hwnd, el.text)
			}
			if el.kind in [.checkbox, .switch_control, .toggle_button] {
				C.ui2_win_set_checked(hwnd, windows_bool(el.checked))
			}
		}
		.dropdown {
			option_sig := windows_options_signature(el.menu)
			if created || (w.node_option_sig[key] or { '' }) != option_sig {
				C.ui2_win_combo_reset(hwnd)
				for entry in el.menu {
					wide_entry := entry.title.to_wide()
					C.ui2_win_combo_add(hwnd, wide_entry)
					unsafe { free(wide_entry) }
				}
				w.node_option_sig[key] = option_sig
			}
			if declared_changed || windows_native_text(hwnd) != el.text {
				wide_selected := el.text.to_wide()
				C.ui2_win_combo_select_text(hwnd, wide_selected)
				unsafe { free(wide_selected) }
			}
		}
		.text_field, .text_area {
			if declared_changed && windows_native_text(hwnd) != el.text {
				windows_set_native_text(hwnd, el.text)
			}
			wide_placeholder := el.placeholder.to_wide()
			C.ui2_win_set_edit_options(hwnd, wide_placeholder, windows_bool(el.readonly), int(el.padding_left))
			unsafe { free(wide_placeholder) }
		}
		.image {
			image_sig := '${el.image_path.bytes().hex()}:${int(el.frame.width)}:${int(el.frame.height)}'
			if created || (w.node_image_path[key] or { '' }) != image_sig {
				wide_path := el.image_path.to_wide()
				bitmap := C.ui2_win_set_bitmap(hwnd, wide_path, int(el.frame.width), int(el.frame.height))
				if bitmap == unsafe { nil } && el.image_path.len > 0 {
					eprintln('ui2: Windows native images currently require a BMP file: ${el.image_path}')
				}
				if bitmap == unsafe { nil } {
					w.images.delete(key)
				} else {
					w.images[key] = bitmap
				}
				unsafe { free(wide_path) }
				w.node_image_path[key] = image_sig
			}
		}
		.slider {
			C.ui2_win_slider_set_normalized(hwnd, slider_value_normalized(el.value,
				el.min_value, el.max_value), windows_bool(el.orientation == .vertical))
		}
		.view, .scroll, .screen {}
	}
	w.node_declared_text[key] = el.text
	w.windows_update_style(key, text_hwnd, el)
	// The tooltip goes on the outer window, which is the declared frame, and on the
	// control inside it, which is what the pointer actually lands on.
	w.windows_update_tooltip(key, hwnd, text_hwnd, el.tooltip)
	if el.kind == .label {
		C.ui2_win_invalidate_parent(hwnd)
		C.ui2_win_invalidate(text_hwnd)
	}
	C.ui2_win_invalidate(hwnd)
}

fn (mut w Window) windows_update_tooltip(key string, hwnd voidptr, text_hwnd voidptr, tooltip string) {
	if (w.tooltip_sigs[key] or { '' }) == tooltip {
		return
	}
	old_tooltip := w.tooltips[key] or { voidptr(unsafe { nil }) }
	if old_tooltip != unsafe { nil } {
		C.ui2_win_destroy_tooltip(old_tooltip)
		w.tooltips.delete(key)
	}
	if tooltip.len == 0 {
		w.tooltip_sigs[key] = tooltip
		return
	}
	wide_tooltip := tooltip.to_wide()
	native_tooltip := C.ui2_win_create_tooltip(hwnd, wide_tooltip)
	unsafe { free(wide_tooltip) }
	if native_tooltip != unsafe { nil } {
		if text_hwnd != hwnd {
			// A held label's static covers the text, so the mouse moves over it and
			// never over the holder the tooltip was put on. It is a target too.
			C.ui2_win_tooltip_add_target(native_tooltip, text_hwnd)
		}
		w.tooltips[key] = native_tooltip
		w.tooltip_sigs[key] = tooltip
	}
}

// GDI has no face called `monospace` and would substitute a proportional one,
// so the generic names resolve to Consolas, as the custom renderer resolves them
// to an installed monospace face.
fn windows_font_family(family string) string {
	return if font_key(family) in ['monospace', 'mono', 'uimonospace'] { 'Consolas' } else { family }
}

// windows_font_text returns every string the control draws with its own font,
// so a fallback family is picked for placeholders and dropdown items too.
fn windows_font_text(el Element) string {
	mut drawn := el.text
	drawn += el.placeholder
	if el.kind == .dropdown {
		for entry in el.menu {
			drawn += entry.title
		}
	}
	return drawn
}

// windows_font_glyph_key keeps the font signature stable for ordinary text and
// only changes when characters that may need a fallback family come and go.
fn windows_font_glyph_key(text string) string {
	mut codes := map[u32]bool{}
	for letter in text.runes() {
		code := u32(letter)
		if code >= 0x2000 {
			codes[code] = true
		}
	}
	if codes.len == 0 {
		return ''
	}
	mut sorted := codes.keys()
	sorted.sort()
	return sorted.map(it.hex()).join('.')
}

fn (mut w Window) windows_update_style(key string, hwnd voidptr, el Element) {
	if el.kind == .button && el.native_style {
		// Native buttons keep the system font. Only its family may have to
		// change, so a check mark is not painted as an empty box.
		font_sig := 'native:${windows_font_glyph_key(el.text)}'
		if (w.font_sigs[key] or { '' }) != font_sig {
			wide_text := el.text.to_wide()
			C.ui2_win_apply_text_font(hwnd, wide_text)
			unsafe { free(wide_text) }
			w.font_sigs[key] = font_sig
		}
	} else if el.kind !in [.view, .scroll, .image, .slider, .switch_control] {
		font_text := windows_font_text(el)
		font_sig := '${el.text_style.size}:${el.text_style.font_family.bytes().hex()}:${text_style_weight(el.text_style)}:${windows_bool(el.text_style.italic)}:${windows_bool(el.text_style.underline)}:${windows_bool(el.text_style.strikethrough)}:${windows_font_glyph_key(font_text)}'
		if (w.font_sigs[key] or { '' }) != font_sig {
			wide_family := windows_font_family(el.text_style.font_family).to_wide()
			wide_text := font_text.to_wide()
			font := C.ui2_win_create_font(hwnd, el.text_style.size, wide_family, text_style_weight(el.text_style), windows_bool(el.text_style.italic), windows_bool(el.text_style.underline), windows_bool(el.text_style.strikethrough), wide_text)
			unsafe { free(wide_family) }
			unsafe { free(wide_text) }
			if font != unsafe { nil } {
				C.ui2_win_apply_font(hwnd, font)
				old_font := w.fonts[key] or { voidptr(unsafe { nil }) }
				if old_font != unsafe { nil } {
					C.ui2_win_delete_object(old_font)
				}
				w.fonts[key] = font
				w.font_sigs[key] = font_sig
			}
		}
	}
	if el.kind !in [.view, .scroll, .image, .slider, .switch_control] {
		old_brush := w.brushes[key] or { voidptr(unsafe { nil }) }
		if old_brush == unsafe { nil } || (w.brush_sigs[key] or { u32(0xffffffff) }) != el.box.bg {
			brush := C.ui2_win_create_brush(el.box.bg)
			if brush != unsafe { nil } {
				if old_brush != unsafe { nil } {
					C.ui2_win_delete_object(old_brush)
				}
				w.brushes[key] = brush
				w.brush_sigs[key] = el.box.bg
			}
		}
	}
}

fn (mut w Window) windows_register_bindings(hwnd voidptr, key string, el Element) {
	handle := windows_handle_id(hwnd)
	if el.on_event != unsafe { nil }
		&& el.kind in [.button, .checkbox, .dropdown, .slider, .switch_control, .toggle_button] {
		w.action_bindings[handle] = windows_callback_binding(el, if el.kind == .button { .click } else { .change })
	}
	if el.kind == .slider {
		w.slider_specs[handle] = slider_spec(el)
	}
	if el.kind == .toggle_button {
		w.toggle_groups[handle] = el.toggle_group()
		w.toggle_allow_no_selection[handle] = el.toggle_allow_no_selection()
		w.toggle_ids[handle] = el.id
		w.toggle_views[handle] = hwnd
		if C.ui2_win_get_checked(hwnd) != 0 {
			w.release_windows_toggle_group(handle)
		}
	}
	if el.on_event != unsafe { nil } && el.kind in [.text_field, .text_area] {
		w.change_bindings[handle] = windows_callback_binding(el, .change)
	}
	if el.on_event != unsafe { nil } && el.kind == .text_field {
		w.submit_bindings[handle] = windows_callback_binding(el, .submit)
	}
	if target := hover_target(key, el) {
		w.hover_bindings[handle] = target
	}
	if el.enabled && !el.hidden
		&& (el.clickable || (el.kind == .view && el.button_behavior) || el.draggable
		|| el.long_press || el.swipe_left) {
		w.pointer_bindings[handle] = WindowsPointerBinding{
			id:              el.id
			on_event:        el.on_event
			clickable:       el.clickable
			button_behavior: el.kind == .view && el.button_behavior
			draggable:       el.draggable
			long_press:      el.long_press
			swipe_left:      el.swipe_left
		}
	}
	if el.menu.len > 0 {
		w.context_menus[handle] = el.menu.clone()
	}
	cursor := windows_cursor_code(el.cursor)
	if cursor != 0 {
		w.cursors[handle] = cursor
	}
	if el.kind == .scroll {
		w.scroll_callbacks[handle] = windows_callback_binding(el, .scroll)
	}
}

fn windows_cursor_code(cursor string) int {
	return match cursor {
		cursor_pointing_hand { 1 }
		cursor_resize_nwse { 2 }
		cursor_resize_nesw { 3 }
		cursor_resize_ew { 4 }
		cursor_resize_ns { 5 }
		cursor_crosshair { 6 }
		else { 0 }
	}
}

fn (mut w Window) windows_reparent_direct_children(key string, new_parent voidptr) {
	for child_key, parent_key in w.node_parents {
		if parent_key == key {
			child := w.nodes[child_key] or { continue }
			C.ui2_win_set_parent(child, new_parent)
		}
	}
}

fn (mut w Window) windows_cleanup_node_resources(key string, hwnd voidptr, kind Kind) {
	handle := windows_handle_id(hwnd)
	if captured := w.control_captures[handle] {
		w.control_captures[handle] = WindowsControlCapture{ ...captured, cancelled: true }
	}
	if w.pointer_handle == hwnd {
		C.ui2_win_release_mouse()
		w.pointer_handle = unsafe { nil }
		w.pointer_binding = WindowsPointerBinding{}
	}
	if kind == .image {
		bitmap := w.images[key] or { voidptr(unsafe { nil }) }
		if hwnd != unsafe { nil } && C.ui2_win_is_window(hwnd) != 0 {
			C.ui2_win_clear_bitmap(hwnd)
		} else if bitmap != unsafe { nil } {
			C.ui2_win_delete_object(bitmap)
		}
		w.images.delete(key)
	}
	font := w.fonts[key] or { voidptr(unsafe { nil }) }
	if font != unsafe { nil } {
		C.ui2_win_delete_object(font)
	}
	brush := w.brushes[key] or { voidptr(unsafe { nil }) }
	if brush != unsafe { nil } {
		C.ui2_win_delete_object(brush)
	}
	w.fonts.delete(key)
	w.font_sigs.delete(key)
	w.brushes.delete(key)
	w.brush_sigs.delete(key)
	tooltip := w.tooltips[key] or { voidptr(unsafe { nil }) }
	if tooltip != unsafe { nil } {
		C.ui2_win_destroy_tooltip(tooltip)
	}
	w.tooltips.delete(key)
	w.tooltip_sigs.delete(key)
}

fn (mut w Window) windows_remove_stale(active map[string]bool) {
	mut stale := map[string]bool{}
	for key, _ in w.nodes {
		if key !in active {
			stale[key] = true
		}
	}
	for key, _ in stale {
		hwnd := w.nodes[key] or { continue }
		kind := w.node_kinds[key] or { Kind.view }
		w.windows_cleanup_node_resources(key, hwnd, kind)
	}
	for key, _ in stale {
		parent_key := w.node_parents[key] or { '' }
		if parent_key !in stale {
			hwnd := w.nodes[key] or { continue }
			C.ui2_win_destroy(hwnd)
		}
	}
	for key, _ in stale {
		old_id := w.node_ids[key] or { '' }
		if old_id.len > 0 {
			w.text_area_selections.delete(old_id)
		}
		w.nodes.delete(key)
		w.node_kinds.delete(key)
		w.node_parents.delete(key)
		w.node_frames.delete(key)
		w.node_structural.delete(key)
		w.node_declared_text.delete(key)
		w.node_option_sig.delete(key)
		w.node_image_path.delete(key)
		w.node_ids.delete(key)
		w.node_boxes.delete(key)
		w.node_label_boxed.delete(key)
		w.node_text_styles.delete(key)
		w.scroll_positions.delete(key)
		w.scroll_positions_x.delete(key)
	}
}

fn (mut w Window) windows_dispose_all() {
	w.layout_tree.clear()
	w.windows_release_all_node_resources()
	w.nodes = map[string]voidptr{}
	w.root = unsafe { nil }
}

fn (mut w Window) windows_release_all_node_resources() {
	w.navigation = &FocusManager{}
	w.suppressed_keys.clear()
	w.activation_keys.clear()
	w.keyboard_generation++
	for key, hwnd in w.nodes {
		w.windows_cleanup_node_resources(key, hwnd, w.node_kinds[key] or { Kind.view })
	}
}

fn (mut w Window) windows_reposition_scroll_children(scroll_key string) {
	x_position := w.scroll_positions_x[scroll_key] or { 0 }
	position := w.scroll_positions[scroll_key] or { 0 }
	for child_key, parent_key in w.node_parents {
		if parent_key != scroll_key {
			continue
		}
		hwnd := w.nodes[child_key] or { continue }
		frame := w.node_frames[child_key] or { continue }
		kind := w.node_kinds[child_key] or { Kind.view }
		C.ui2_win_set_widget_frame(hwnd, windows_widget_kind(kind), int(frame.x) - x_position,
			int(frame.y) - position, int(frame.width), int(frame.height))
	}
	C.ui2_win_invalidate(w.nodes[scroll_key] or { return })
}

// windows_handle_wheel scrolls the Scroll element a wheel message reached, then gives
// whatever distance it could not use to each pane around it in turn, the way the
// custom renderer walks its scroll chain. A pane ten pixels from its end takes those
// ten and the pane around it the rest of the step, so nested panes scroll through a
// boundary instead of stopping short at it.
fn (mut w Window) windows_handle_wheel(hwnd voidptr, message u32, wparam usize) {
	tilt := message == win_wm_mouse_hwheel
	// Shift turns a plain wheel sideways.
	horizontal := tilt || C.ui2_win_wheel_is_shifted(wparam) != 0
	distance := C.ui2_win_wheel_distance(wparam, windows_bool(tilt), windows_bool(horizontal))
	mut remaining := distance - w.windows_scroll_by(hwnd, distance, horizontal)
	mut pane := C.ui2_win_scroll_parent(hwnd, windows_bool(horizontal))
	for remaining != 0 && pane != unsafe { nil } {
		remaining -= w.windows_scroll_by(pane, remaining, horizontal)
		pane = C.ui2_win_scroll_parent(pane, windows_bool(horizontal))
	}
}

// windows_scroll_key is the key of the Scroll element behind a window, when it is one
// and scrolls along the axis.
fn (mut w Window) windows_scroll_key(hwnd voidptr, horizontal bool) ?string {
	key := w.handle_keys[windows_handle_id(hwnd)] or { return none }
	if (w.node_kinds[key] or { Kind.view }) != .scroll {
		return none
	}
	// An element that does not scroll sideways has no horizontal bar to read or move.
	if horizontal && key !in w.scroll_positions_x {
		return none
	}
	return key
}

// windows_scroll_by moves a Scroll element along an axis and returns how far it went.
fn (mut w Window) windows_scroll_by(hwnd voidptr, distance int, horizontal bool) int {
	key := w.windows_scroll_key(hwnd, horizontal) or { return 0 }
	return w.windows_record_scroll(hwnd, key, C.ui2_win_scroll_by(hwnd, distance, windows_bool(horizontal)),
		horizontal)
}

// windows_handle_scroll follows one of a Scroll element's own bars.
fn (mut w Window) windows_handle_scroll(hwnd voidptr, wparam usize, horizontal bool) {
	key := w.windows_scroll_key(hwnd, horizontal) or { return }
	w.windows_record_scroll(hwnd, key, C.ui2_win_scroll_message(hwnd, wparam, windows_bool(horizontal)),
		horizontal)
}

// windows_record_scroll takes up the position a Scroll element's bar settled at: it
// moves the children to match, reports the change, and returns how far that was.
fn (mut w Window) windows_record_scroll(hwnd voidptr, key string, position int, horizontal bool) int {
	old_position := if horizontal {
		w.scroll_positions_x[key] or { 0 }
	} else {
		w.scroll_positions[key] or { 0 }
	}
	if position == old_position {
		return 0
	}
	if horizontal {
		w.scroll_positions_x[key] = position
	} else {
		w.scroll_positions[key] = position
	}
	w.windows_reposition_scroll_children(key)
	w.windows_emit_scroll(hwnd, f64(position))
	return position - old_position
}

@[export: 'ui2_windows_hover_changed']
fn ui2_windows_hover_changed() {
	// The C side reports a cursor move without saying over which window; each
	// window works out what is under the cursor itself.
	mut host := windows_host()
	for _, mut w in host.windows {
		w.windows_update_hover()
	}
}

// windows_update_hover reports the hoverable elements the cursor left and entered:
// the window under it and that window's ancestors, as CSS :hover counts them.
fn (mut w Window) windows_update_hover() {
	if w.root == unsafe { nil } || w.rendering {
		return
	}
	mut x := 0
	mut y := 0
	mut current := []HoverTarget{}
	if w.hover_bindings.len > 0 {
		mut target := C.ui2_win_hover_target(w.root, &x, &y)
		mut inner_first := []HoverTarget{}
		for target != unsafe { nil } {
			if hovered := w.hover_bindings[windows_handle_id(target)] {
				inner_first << hovered
			}
			if target == w.root {
				break
			}
			target = C.ui2_win_parent(target)
		}
		current = inner_first.reverse()
	}
	left, entered := hover_transitions(w.hovered, current)
	w.hovered = current
	for pending in hover_events(left, entered, f64(x), f64(y)) {
		pending.fire(w)
	}
}

fn (mut w Window) windows_emit_scroll(hwnd voidptr, _offset f64) bool {
	binding := w.scroll_callbacks[windows_handle_id(hwnd)] or { return false }
	return w.windows_emit_callback(binding.on_event, ElementEvent{ id: binding.id, kind: .scroll, value: w.scroll_offset(binding.id), x: w.scroll_horizontal_offset(binding.id), y: w.scroll_offset(binding.id) })
}

fn (mut w Window) windows_emit_callback(callback ElementCallback, event ElementEvent) bool {
	if callback == unsafe { nil } { return false }
	callback(ElementEvent{ ...event, window: w })
	return true
}

fn windows_control_release_binding(captured WindowsCallbackBinding, current WindowsCallbackBinding, available bool) ?WindowsCallbackBinding {
	if !available || captured.on_event == unsafe { nil } || current.on_event == unsafe { nil }
		|| captured.kind != current.kind { return none }
	return captured
}

fn windows_control_dispatch_binding(current WindowsCallbackBinding, captured WindowsControlCapture, pointer_captured bool, available bool, native_activation bool) ?WindowsCallbackBinding {
	if !available || current.on_event == unsafe { nil } { return none }
	if native_activation || !pointer_captured { return current }
	return windows_control_release_binding(captured.binding, current, available && !captured.cancelled)
}

fn (mut w Window) windows_control_action_binding(hwnd voidptr) ?WindowsCallbackBinding {
	handle := windows_handle_id(hwnd)
	current := w.action_bindings[handle] or { return none }
	captured := w.control_captures[handle] or { WindowsControlCapture{} }
	return windows_control_dispatch_binding(current, captured, handle in w.control_captures,
		C.ui2_win_control_available(hwnd) != 0, (w.control_native_activations[handle] or { 0 }) > 0)
}

// This hook only snapshots ordinary native controls. Text editing and submit
// dispatch keep their current callbacks, independent of pointer tracking.
@[export: 'ui2_windows_control_tracking']
fn ui2_windows_control_tracking(hwnd voidptr, phase int) {
	mut w := windows_window_for(hwnd) or { return }
	handle := windows_handle_id(hwnd)
	if phase == 4 {
		w.control_native_activations[handle] = (w.control_native_activations[handle] or { 0 }) + 1
		return
	}
	if phase == 5 {
		depth := w.control_native_activations[handle] or { 0 }
		if depth > 1 { w.control_native_activations[handle] = depth - 1 }
		else { w.control_native_activations.delete(handle) }
		return
	}
	if phase == 6 {
		w.control_captures.delete(handle)
		w.control_native_activations.delete(handle)
		return
	}
	if phase == 0 {
		key := w.handle_keys[handle] or { return }
		kind := w.node_kinds[key] or { return }
		if kind !in [.button, .checkbox, .dropdown, .slider, .switch_control, .toggle_button] { return }
		w.control_captures[handle] = WindowsControlCapture{
			binding: w.action_bindings[handle] or { WindowsCallbackBinding{ kind: kind } }
		}
		return
	}
	captured := w.control_captures[handle] or { return }
	if phase == 1 {
		// Combobox menu selection may arrive after the row's mouse release.
		if captured.binding.kind != .dropdown { w.control_captures.delete(handle) }
	} else if phase == 3 || captured.binding.kind != .dropdown {
		w.control_captures[handle] = WindowsControlCapture{ ...captured, cancelled: true }
	}
}

fn (mut w Window) windows_emit_control_action(hwnd voidptr) bool {
	binding := w.windows_control_action_binding(hwnd) or { return false }
	return w.windows_emit_control(hwnd, binding)
}

fn (mut w Window) windows_emit_control(hwnd voidptr, binding WindowsCallbackBinding) bool {
	mut event := ElementEvent{ id: binding.id, kind: binding.event }
	if binding.kind in [.text_field, .text_area, .dropdown] {
		event = ElementEvent{ ...event, text: windows_native_text(hwnd) }
	} else if binding.kind == .slider {
		if spec := w.slider_specs[windows_handle_id(hwnd)] {
			event = ElementEvent{ ...event, value: windows_snap_slider_value(hwnd, spec) }
		}
	} else if binding.kind in [.checkbox, .switch_control, .toggle_button] {
		event = ElementEvent{ ...event, checked: C.ui2_win_get_checked(hwnd) != 0 }
	}
	return w.windows_emit_callback(binding.on_event, event)
}

fn (mut w Window) windows_emit_button_behavior(hwnd voidptr, binding WindowsPointerBinding) bool {
	if binding.on_event == unsafe { nil } { return false }
	C.ui2_win_notify_invoked(hwnd)
	return w.windows_emit_callback(binding.on_event, ElementEvent{ id: binding.id, kind: .click })
}

fn windows_button_behavior_accessibility_available(current WindowsPointerBinding, target_available bool) bool {
	return current.button_behavior && current.on_event != unsafe { nil } && target_available
}

@[export: 'ui2_windows_accessibility_activate']
fn ui2_windows_accessibility_activate(hwnd voidptr) int {
	mut w := windows_window_for(hwnd) or { return 0 }
	current := w.pointer_bindings[windows_handle_id(hwnd)] or { WindowsPointerBinding{} }
	if !windows_button_behavior_accessibility_available(current,
		C.ui2_win_is_window(hwnd) != 0 && C.ui2_win_is_enabled(hwnd) != 0
		&& C.ui2_win_is_accessible_button(hwnd) != 0) { return 0 }
	return windows_bool(w.windows_emit_button_behavior(hwnd, current))
}

fn windows_snap_slider_value(hwnd voidptr, spec SliderSpec) f64 {
	raw_normalized := C.ui2_win_slider_normalized(hwnd,
		windows_bool(spec.orientation == .vertical))
	value := slider_value_from_normalized(raw_normalized, spec.min, spec.max, spec.step)
	exact_normalized := slider_value_normalized(value, spec.min, spec.max)
	if exact_normalized != raw_normalized {
		C.ui2_win_slider_set_normalized(hwnd, exact_normalized,
			windows_bool(spec.orientation == .vertical))
	}
	return value
}

fn windows_key_code(virtual_key u32) KeyCode {
	if (virtual_key >= 0x30 && virtual_key <= 0x39)
		|| (virtual_key >= 0x41 && virtual_key <= 0x5a) {
		return unsafe { KeyCode(virtual_key) }
	}
	if virtual_key >= 0x70 && virtual_key <= 0x87 {
		return unsafe { KeyCode(int(KeyCode.f1) + int(virtual_key - 0x70)) }
	}
	if virtual_key >= 0x60 && virtual_key <= 0x69 {
		return unsafe { KeyCode(int(KeyCode.kp_0) + int(virtual_key - 0x60)) }
	}
	return match virtual_key {
		0x08 { .backspace }
		0x09 { .tab }
		0x0d { .enter }
		0x1b { .escape }
		0x20 { .space }
		0x21 { .page_up }
		0x22 { .page_down }
		0x23 { .end }
		0x24 { .home }
		0x25 { .left }
		0x26 { .up }
		0x27 { .right }
		0x28 { .down }
		0x2d { .insert }
		0x2e { .delete }
		0x6a { .kp_multiply }
		0x6b { .kp_add }
		0x6d { .kp_subtract }
		0x6e { .kp_decimal }
		0x6f { .kp_divide }
		0xba { .semicolon }
		0xbb { .equal }
		0xbc { .comma }
		0xbd { .minus }
		0xbe { .period }
		0xbf { .slash }
		0xc0 { .grave_accent }
		0xdb { .left_bracket }
		0xdc { .backslash }
		0xdd { .right_bracket }
		0xde { .apostrophe }
		else { .invalid }
	}
}

fn windows_key_event(virtual_key u32) KeyEvent {
	return KeyEvent{
		code: windows_key_code(virtual_key)
		ctrl: C.ui2_win_key_down(0x11) != 0
		alt: C.ui2_win_key_down(0x12) != 0
		shift: C.ui2_win_key_down(0x10) != 0
		cmd: C.ui2_win_key_down(0x5b) != 0 || C.ui2_win_key_down(0x5c) != 0
	}
}

fn windows_normalized_key(virtual_key u32) string {
	key_event := windows_key_event(virtual_key)
	mut key := key_event.code.name()
	if key.len == 0 {
		return ''
	}
	mut modifiers := []string{}
	if key_event.ctrl {
		modifiers << 'ctrl'
	}
	if key_event.alt {
		modifiers << 'alt'
	}
	if key_event.shift {
		modifiers << 'shift'
	}
	if key_event.cmd {
		modifiers << 'cmd'
	}
	if modifiers.len > 0 {
		key = modifiers.join('+') + '+' + key
	}
	return key
}

// windows_dispatch_typed_key offers a key press to the focused element's
// declared keys (element_keys.v), then to on_key_event.
fn (mut w Window) windows_dispatch_typed_key(virtual_key u32, repeated bool) bool {
	key := KeyEvent{ ...windows_key_event(virtual_key), window: w }
	if w.element_key(key, repeated) {
		return true
	}
	if voidptr(w.key_event_handler) == unsafe { nil } {
		return false
	}
	w.key_consumed = false
	w.key_event_handler(key)
	consumed := w.key_consumed
	w.key_consumed = false
	return consumed
}

fn (mut w Window) windows_dispatch_key_string(virtual_key u32) bool {
	if voidptr(w.key_handler) == unsafe { nil } {
		return false
	}
	key := windows_normalized_key(virtual_key)
	if key.len == 0 {
		return false
	}
	w.key_consumed = false
	w.key_handler(mut w, key)
	return w.key_consumed
}

fn (mut w Window) windows_dispatch_control_app_key(hwnd voidptr, virtual_key u32, repeated bool) bool {
	// A menu shortcut wins over the application's own binding on the chord.
	if !repeated && w.windows_menu_shortcut(windows_normalized_key(virtual_key)) {
		return true
	}
	if w.windows_dispatch_typed_key(virtual_key, repeated) {
		return true
	}
	if voidptr(w.key_handler) == unsafe { nil } {
		return false
	}
	key_name := windows_normalized_key(virtual_key)
	if key_name.len == 0 {
		return false
	}
	key := w.handle_keys[windows_handle_id(hwnd)] or {
		return w.windows_dispatch_key_string(virtual_key)
	}
	if (w.node_kinds[key] or { Kind.view }) != .text_area {
		return w.windows_dispatch_key_string(virtual_key)
	}
	id := w.node_ids[key] or { '' }
	if id.len == 0 {
		return w.windows_dispatch_key_string(virtual_key)
	}
	w.key_consumed = false
	w.key_handler(mut w, 'text:${id}:${key_name}')
	return w.key_consumed
}

fn (mut w Window) windows_dispatch_control_key(hwnd voidptr, virtual_key u32, repeated bool, scan_code u32) bool {
	physical := windows_physical_key(virtual_key, scan_code)
	owned := repeated && (w.activation_keys[physical] or { false })
	if !repeated {
		w.activation_keys.delete(physical)
		w.suppressed_keys.delete(physical)
	}
	// Observers run once even for owned repeats. Ownership precedes the native
	// edit-submit shortcut and navigation, which can both change the focused HWND.
	generation := w.keyboard_generation
	observed := w.windows_dispatch_control_app_key(hwnd, virtual_key, repeated)
	if owned || observed || w.keyboard_generation != generation { return true }
	if virtual_key == 0x0d && w.windows_edit_submit(hwnd) { return true }
	key := windows_key_event(virtual_key)
	if key.code in [.enter, .kp_enter] {
		control := w.handle_keys[windows_handle_id(hwnd)] or { '' }
		if (w.node_kinds[control] or { Kind.view }) == .dropdown
			&& C.ui2_win_dropdown_is_open(hwnd) != 0 {
			// An open native popup owns confirmation/close. Owned activation
			// repeats were consumed above; this key must reach DefSubclassProc
			// without claiming another generic activation or suppressing CHAR.
			return false
		}
	}
	if !repeated && scan_code != 0 && !key.ctrl && !key.cmd && !key.alt && !key.shift
		&& key.code in [.enter, .kp_enter, .space] {
		if node := w.navigation.node(w.focused_id()) {
			if w.navigation.can_focus(node.el.id) && semantic_activatable(node.el) {
				// Claim before synchronous native activation. Deactivate/dispose in
				// the callback clears it without a post-callback re-latch.
				w.activation_keys[physical] = true
			}
		}
	}
	return w.handle_focus_key(KeyEvent{ ...key, window: w }, repeated)
}

fn windows_physical_key(virtual_key u32, scan_code u32) u32 {
	return (virtual_key << 9) | (scan_code & 0x1ff)
}

fn (mut w Window) windows_handle_drop(drop voidptr) {
	if voidptr(w.drop_handler) == unsafe { nil } {
		C.ui2_win_drop_finish(drop)
		return
	}
	count := C.ui2_win_drop_count(drop)
	mut paths := []string{cap: int(count)}
	for index := u32(0); index < count; index++ {
		length := C.ui2_win_drop_path_length(drop, index)
		mut buffer := []u16{len: int(length) + 1}
		C.ui2_win_drop_path(drop, index, unsafe { &buffer[0] }, length + 1)
		paths << unsafe { string_from_wide2(&buffer[0], int(length)) }
	}
	mut x := 0
	mut y := 0
	C.ui2_win_drop_point(drop, &x, &y)
	C.ui2_win_drop_finish(drop)
	w.drop_handler(DropEvent{
		window: w
		paths: paths
		x: f64(x)
		y: f64(y)
	})
}

@[export: 'ui2_windows_window_proc']
fn ui2_windows_window_proc(hwnd voidptr, message u32, wparam usize, lparam isize) isize {
	mut w := windows_window_for(hwnd) or { return C.ui2_win_default_proc(hwnd, message, wparam, lparam) }
	match message {
		win_wm_getminmaxinfo {
			C.ui2_win_apply_min_size(hwnd, lparam, w.min_width,
				w.min_height)
			return 0
		}
		win_wm_command {
			child := voidptr(usize(lparam))
			if child == unsafe { nil } {
				// The host's menu subclass takes the menu bar's rows first
				// (menu_host_windows.h); nothing else sends one.
				return 0
			}
			handle := windows_handle_id(child)
			code := int((wparam >> 16) & 0xffff)
			if code == win_en_change {
				if !w.rendering {
					w.windows_emit_control(child, w.change_bindings[handle] or { WindowsCallbackBinding{} })
				}
				return 0
			}
			if code == 8 { // CBN_CLOSEUP
				w.control_captures.delete(handle)
				return 0
			}
			if code == win_cbn_selchange {
				w.windows_emit_control_action(child)
				return 0
			}
			if code == win_bn_clicked {
				if w.suppress_click[handle] or { false } {
					w.suppress_click.delete(handle)
					return 0
				}
				w.commit_windows_toggle_button(handle, child)
				w.windows_emit_control_action(child)
				return 0
			}
		}
		win_wm_ctlcolor_edit, win_wm_ctlcolor_listbox, win_wm_ctlcolor_button, win_wm_ctlcolor_static {
			child := voidptr(usize(lparam))
			key := w.handle_keys[windows_handle_id(child)] or {
				return C.ui2_win_default_proc(hwnd, message, wparam, lparam)
			}
			style := w.node_text_styles[key] or { TextStyle{} }
			box := w.node_boxes[key] or { BoxStyle{} }
			kind := w.node_kinds[key] or { Kind.view }
			brush := w.brushes[key] or { voidptr(unsafe { nil }) }
			return C.ui2_win_apply_control_colors(voidptr(wparam), style.color, box.bg,
				windows_bool(windows_draws_no_background(kind, box)), brush)
		}
		win_wm_paint_background {
			mut box := BoxStyle{}
			mut kind := Kind.screen
			if hwnd == w.root {
				box = w.node_boxes[''] or { BoxStyle{} }
			} else {
				key := w.handle_keys[windows_handle_id(hwnd)] or { return 0 }
				box = w.node_boxes[key] or { return 0 }
				kind = w.node_kinds[key] or { Kind.screen }
			}
			windows_paint_box(hwnd, voidptr(wparam), box, windows_bool(windows_draws_no_background(kind,
				box)))
			return 0
		}
		win_wm_paint {
			if hwnd == w.root {
				box := w.node_boxes[''] or { BoxStyle{} }
				windows_paint_box(hwnd, unsafe { nil }, box, windows_bool(box.transparent))
				return 0
			}
			key := w.handle_keys[windows_handle_id(hwnd)] or {
				return C.ui2_win_default_proc(hwnd, message, wparam, lparam)
			}
			kind := w.node_kinds[key] or { Kind.screen }
			if kind == .view || kind == .scroll || w.windows_is_label_container(key, hwnd) {
				box := w.node_boxes[key] or { BoxStyle{} }
				transparent := windows_bool(windows_draws_no_background(kind, box))
				windows_paint_box(hwnd, unsafe { nil }, box, transparent)
				if kind == .view {
					binding := w.pointer_bindings[windows_handle_id(hwnd)] or {
						WindowsPointerBinding{}
					}
					if binding.button_behavior {
						C.ui2_win_draw_focus_rect(hwnd)
					}
				}
				return 0
			}
		}
		win_wm_erase_background {
			if hwnd == w.root {
				return 1
			}
			key := w.handle_keys[windows_handle_id(hwnd)] or { '' }
			kind := w.node_kinds[key] or { Kind.screen }
			if kind == .view || kind == .scroll || w.windows_is_label_container(key, hwnd) {
				return 1
			}
		}
		win_wm_hscroll, win_wm_vscroll {
			child := voidptr(usize(lparam))
			if child != unsafe { nil } {
				handle := windows_handle_id(child)
				if spec := w.slider_specs[handle] {
					windows_snap_slider_value(child, spec)
					w.windows_emit_control_action(child)
					return 0
				}
			}
			// A control's own bar is the control's to handle; one with no control behind
			// it is the standard bar of a Scroll element.
			if message == win_wm_hscroll && child != unsafe { nil } {
				return C.ui2_win_default_proc(hwnd, message, wparam, lparam)
			}
			w.windows_handle_scroll(hwnd, wparam, message == win_wm_hscroll)
			return 0
		}
		win_wm_mouse_wheel, win_wm_mouse_hwheel {
			w.windows_handle_wheel(hwnd, message, wparam)
			return 0
		}
		win_wm_key_down {
			if ui2_windows_control_key(hwnd, u32(wparam), windows_bool((usize(lparam) & (usize(1) << 30)) != 0), u32((usize(lparam) >> 16) & 0x1ff)) != 0 {
				return 0
			}
		}
		win_wm_key_up { if ui2_windows_control_key_up(u32(wparam), u32((usize(lparam) >> 16) & 0x1ff)) != 0 { return 0 } }
		win_wm_char { if ui2_windows_control_char(u32(wparam), u32((usize(lparam) >> 16) & 0x1ff)) != 0 { return 0 } }
		win_wm_activate_app {
			if wparam == 0 {
				w.suppressed_keys.clear()
				w.activation_keys.clear()
				w.keyboard_generation++
			}
		}

		win_wm_dropfiles {
			w.windows_handle_drop(voidptr(wparam))
			return 0
		}
		win_wm_size {
			if hwnd == w.root && !w.rendering {
				w.rebuild_now()
			}
			return 0
		}
		win_wm_refresh {
			w.rebuild_now()
			return 0
		}
		win_wm_close {
			w.windows_release_all_node_resources()
			C.ui2_win_destroy(hwnd)
			return 0
		}
		win_wm_destroy {
			if hwnd == w.root {
				w.close_native()
			}
			return 0
		}
		else {}
	}
	return C.ui2_win_default_proc(hwnd, message, wparam, lparam)
}

// A held label is the container covering the declared frame; the static inside it is
// mapped to the same node so its colours can be found, but it is not what that node's
// border belongs to — drawn there the border would close around the text rather than
// around the label. Only the window a node actually is draws that node's border.
fn (mut w Window) windows_is_label_container(key string, hwnd voidptr) bool {
	if (w.node_kinds[key] or { Kind.screen }) != .label {
		return false
	}
	node := w.nodes[key] or { return false }
	return node == hwnd && C.ui2_win_label_text_hwnd(hwnd) != hwnd
}

@[export: 'ui2_windows_control_border']
fn ui2_windows_control_border(hwnd voidptr) {
	mut w := windows_window_for(hwnd) or { return }
	key := w.handle_keys[windows_handle_id(hwnd)] or { return }
	if node := w.nodes[key] {
		if node != hwnd {
			return
		}
	}
	box := w.node_boxes[key] or { return }
	C.ui2_win_paint_control_border(hwnd, box.border_color, box.radius, box.border_left,
		box.border_top, box.border_right, box.border_bottom)
}

@[export: 'ui2_windows_paint_transparent_button']
fn ui2_windows_paint_transparent_button(hwnd voidptr) int {
	mut w := windows_window_for(hwnd) or { return 0 }
	key := w.handle_keys[windows_handle_id(hwnd)] or { return 0 }
	kind := w.node_kinds[key] or { return 0 }
	box := w.node_boxes[key] or { return 0 }
	if !windows_uses_transparent_button_paint(kind, box) {
		return 0
	}
	style := w.node_text_styles[key] or { TextStyle{} }
	C.ui2_win_paint_transparent_button(hwnd, style.color, box.radius, box.border_color,
		box.border_left, box.border_top, box.border_right, box.border_bottom)
	return 1
}

@[export: 'ui2_windows_is_transparent_button']
fn ui2_windows_is_transparent_button(hwnd voidptr) int {
	mut w := windows_window_for(hwnd) or { return 0 }
	key := w.handle_keys[windows_handle_id(hwnd)] or { return 0 }
	kind := w.node_kinds[key] or { return 0 }
	box := w.node_boxes[key] or { return 0 }
	return windows_bool(windows_uses_transparent_button_paint(kind, box))
}

fn (mut w Window) windows_edit_submit(hwnd voidptr) bool {
	binding := w.submit_bindings[windows_handle_id(hwnd)] or { return false }
	return w.windows_emit_control(hwnd, binding)
}

@[export: 'ui2_windows_control_key']
fn ui2_windows_control_key(hwnd voidptr, virtual_key u32, repeated int, scan_code u32) int {
	mut w := windows_window_for(hwnd) or { return 0 }
	generation := w.keyboard_generation
	consumed := w.windows_dispatch_control_key(hwnd, virtual_key, repeated != 0, scan_code)
	if consumed && w.keyboard_generation == generation {
		w.suppressed_keys[windows_physical_key(virtual_key, scan_code)] = scan_code
	}
	return windows_bool(consumed)
}

@[export: 'ui2_windows_context_menu']
fn ui2_windows_context_menu(hwnd voidptr, screen_x int, screen_y int) int {
	mut w := windows_window_for(hwnd) or { return 0 }
	mut target := hwnd
	mut entries := []MenuEntry{}
	for target != unsafe { nil } {
		entries = w.context_menus[windows_handle_id(target)] or { []MenuEntry{} }
		if entries.len > 0 || target == w.root {
			break
		}
		target = C.ui2_win_parent(target)
	}
	if entries.len == 0 {
		return 0
	}
	menu := C.ui2_win_menu_create()
	if menu == unsafe { nil } {
		return 0
	}
	for index, entry in entries {
		wide_title := entry.title.to_wide()
		C.ui2_win_menu_add(menu, u32(index + 1), wide_title, 1)
		unsafe { free(wide_title) }
	}
	command := C.ui2_win_menu_track(menu, target, screen_x, screen_y)
	C.ui2_win_menu_destroy(menu)
	if command > 0 && int(command) <= entries.len {
		entry := entries[int(command) - 1]
		w.windows_emit_callback(entry.on_select, ElementEvent{ id: entry.id, kind: .click })
	}
	return 1
}

@[export: 'ui2_windows_cursor']
fn ui2_windows_cursor(hwnd voidptr) int {
	mut w := windows_window_for(hwnd) or { return 0 }
	mut target := hwnd
	for target != unsafe { nil } {
		cursor := w.cursors[windows_handle_id(target)] or { 0 }
		if cursor != 0 {
			return cursor
		}
		if target == w.root {
			break
		}
		target = C.ui2_win_parent(target)
	}
	return 0
}

@[export: 'ui2_windows_control_pointer']
fn ui2_windows_control_pointer(hwnd voidptr, message u32, local_x int, local_y int) {
	mut w := windows_window_for(hwnd) or { return }
	mut x := local_x
	mut y := local_y
	C.ui2_win_point_to_root(hwnd, w.root, &x, &y)
	if message == win_wm_lbutton_down {
		mut target := voidptr(usize(hwnd))
		mut binding := WindowsPointerBinding{}
		for target != unsafe { nil } {
			handle := windows_handle_id(target)
			binding = w.pointer_bindings[handle] or { WindowsPointerBinding{} }
			if binding.on_event != unsafe { nil } || target == w.root {
				break
			}
			key := w.handle_keys[handle] or { '' }
			if key.len > 0 {
				kind := w.node_kinds[key] or { Kind.screen }
				if kind !in [.screen, .view, .label, .image] {
					// A nested native control owns its pointer interaction.
					return
				}
			}
			target = C.ui2_win_parent(target)
		}
		if binding.on_event == unsafe { nil } {
			return
		}
		if binding.button_behavior {
			// Validate eligibility and the active scope before SetFocus, using
			// the same public focus path as keyboard/semantic navigation.
			w.focus(binding.id)
		}
		w.pointer_handle = target
		w.pointer_binding = binding
		w.pointer_start_x = x
		w.pointer_start_y = y
		w.pointer_started = C.ui2_win_ticks()
		w.pointer_moved = false
		C.ui2_win_capture_mouse(target)
		if binding.clickable || binding.draggable {
			w.windows_emit_callback(binding.on_event, ElementEvent{ id: binding.id, kind: .pointer_down, x: f64(x), y: f64(y) })
		}
		return
	}
	if w.pointer_handle == unsafe { nil } {
		return
	}
	target := w.pointer_handle
	binding := w.pointer_binding
	current_binding := w.pointer_bindings[windows_handle_id(target)] or { WindowsPointerBinding{} }
	available := current_binding.on_event != unsafe { nil }
		&& C.ui2_win_is_window(target) != 0 && C.ui2_win_is_enabled(target) != 0
	if message == win_wm_mouse_move {
		if !available { return }
		move_x := x - w.pointer_start_x
		move_y := y - w.pointer_start_y
		if move_x < -8 || move_x > 8 || move_y < -8 || move_y > 8 {
			w.pointer_moved = true
		}
		if binding.draggable {
			w.windows_emit_callback(binding.on_event, ElementEvent{ id: binding.id, kind: .pointer_drag, x: f64(x), y: f64(y) })
		}
		return
	}
	if message != win_wm_lbutton_up {
		return
	}
	C.ui2_win_release_mouse()
	w.pointer_handle = unsafe { nil }
	w.pointer_binding = WindowsPointerBinding{}
	if !available { return }
	delta_x := x - w.pointer_start_x
	delta_y := y - w.pointer_start_y
	duration := C.ui2_win_ticks() - w.pointer_started
	mut gesture := false
	mut gesture_kind := ElementEventKind.click
	if binding.swipe_left && delta_x <= -60 && delta_y >= -40 && delta_y <= 40 {
		gesture_kind = .swipe_left
		gesture = true
	} else if binding.long_press && !w.pointer_moved && duration >= 500 && delta_x >= -8 && delta_x <= 8
		&& delta_y >= -8 && delta_y <= 8 {
		gesture_kind = .long_press
		gesture = true
	}
	activate := windows_button_behavior_available(binding, current_binding, gesture,
		w.pointer_moved, C.ui2_win_is_window(target) != 0
		&& C.ui2_win_is_enabled(target) != 0
		&& C.ui2_win_root_point_in_client(w.root, target, x, y) != 0)
	if gesture {
		w.windows_emit_callback(binding.on_event, ElementEvent{ id: binding.id, kind: gesture_kind })
	}
	if binding.clickable || binding.draggable {
		w.windows_emit_callback(binding.on_event, ElementEvent{ id: binding.id, kind: .pointer_up, x: f64(x), y: f64(y) })
	}
	if activate {
		w.windows_emit_button_behavior(target, binding)
	}
	if gesture {
		w.suppress_click[windows_handle_id(target)] = true
	}
}

fn windows_button_behavior_available(captured WindowsPointerBinding, current WindowsPointerBinding, gesture bool, moved bool, target_available bool) bool {
	return captured.button_behavior && captured.on_event != unsafe { nil } && current.button_behavior
		&& current.on_event != unsafe { nil } && !gesture && !moved && target_available
}

fn (mut w Window) windows_text_area_handle(id string) ?voidptr {
	hwnd := w.views[id] or { return none }
	if (w.view_kinds[id] or { Kind.view }) != .text_area {
		return none
	}
	return hwnd
}

fn windows_native_get_selection(hwnd voidptr) TextAreaSelectionRange {
	mut start := u32(0)
	mut end := u32(0)
	C.ui2_win_get_selection(hwnd, &start, &end)
	return TextAreaSelectionRange{
		location: int(start)
		length: if end >= start { int(end - start) } else { 0 }
	}
}

fn windows_native_set_selection(hwnd voidptr, selection TextAreaSelectionRange) {
	start := u32(selection.location)
	C.ui2_win_set_selection(hwnd, start, start + u32(selection.length), 0)
}
}
