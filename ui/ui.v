module ui2

const named_scroll_prefix = '@scroll-id:'
const anonymous_text_area_scroll_prefix = '@text-area-key:'
const anonymous_scroll_prefix = '@scroll-path:'

// BuildFn declares a window's tree. It receives the window it builds, so it
// can read its bounds and live control state.
pub type BuildFn = fn (mut w Window) Element

// Element callbacks are attached to their declaration. An id identifies live
// state; it never chooses a handler. The event names the window it happened
// in, which is how a callback asks that window for a refresh or a focus change.
pub type ElementCallback = fn (ElementEvent)

pub enum ElementEventKind {
	click
	change
	submit
	scroll
	pointer_down
	pointer_drag
	pointer_up
	long_press
	swipe_left
	link
	drag_start
	drag_enter
	drag_leave
	drag_over
	drop
	drag_end
	drag_cancel
	dismiss
	open
	// Hoverable elements report the pointer coming over them and leaving them.
	// New kinds go last: the C ABI passes the kind's ordinal.
	pointer_enter
	pointer_leave
}

pub struct ElementEvent {
pub:
	// window is the window the event happened in; nil only for an event that
	// application code made up itself.
	window         &Window = unsafe { nil }
	kind           ElementEventKind
	drag           ?DragEvent
	dismiss_reason OverlayDismissReason
	id             string
	x              f64
	y              f64
	text           string
	// Scroll events carry both logical offsets in x/y and the vertical offset in value.
	value   f64
	checked bool
	target  string
}

pub enum ScanResultKind {
	code
	error
	cancelled
}

pub struct ScanResult {
pub:
	kind ScanResultKind
	text string
}

pub type ScanCallback = fn (ScanResult)

// KeyFn receives the window and a normalized key string: 'up',
// 'forward_delete', 'tab', 'cmd+shift+r', 'f5', or text-view commands like
// 'text:editor:backspace' and 'text:editor:line_break'.
pub type KeyFn = fn (mut w Window, key string)

// KeyEventFn receives a layout-independent physical key plus the active
// modifiers. It complements KeyFn, which remains available for callers that
// prefer normalized shortcut strings.
pub type KeyEventFn = fn (KeyEvent)

// KeyCode names the physical key positions shared by UI2's desktop backends.
// Printable values follow the conventional US key labels; the active keyboard
// layout affects inserted text, but never changes this code.
pub enum KeyCode {
	invalid       = 0
	space         = 32
	apostrophe    = 39
	comma         = 44
	minus         = 45
	period        = 46
	slash         = 47
	_0            = 48
	_1            = 49
	_2            = 50
	_3            = 51
	_4            = 52
	_5            = 53
	_6            = 54
	_7            = 55
	_8            = 56
	_9            = 57
	semicolon     = 59
	equal         = 61
	a             = 65
	b             = 66
	c             = 67
	d             = 68
	e             = 69
	f             = 70
	g             = 71
	h             = 72
	i             = 73
	j             = 74
	k             = 75
	l             = 76
	m             = 77
	n             = 78
	o             = 79
	p             = 80
	q             = 81
	r             = 82
	s             = 83
	t             = 84
	u             = 85
	v             = 86
	w             = 87
	x             = 88
	y             = 89
	z             = 90
	left_bracket  = 91
	backslash     = 92
	right_bracket = 93
	grave_accent  = 96
	world_1       = 161
	world_2       = 162
	escape        = 256
	enter         = 257
	tab           = 258
	backspace     = 259
	insert        = 260
	delete        = 261
	right         = 262
	left          = 263
	down          = 264
	up            = 265
	page_up       = 266
	page_down     = 267
	home          = 268
	end           = 269
	caps_lock     = 280
	scroll_lock   = 281
	num_lock      = 282
	print_screen  = 283
	pause         = 284
	f1            = 290
	f2            = 291
	f3            = 292
	f4            = 293
	f5            = 294
	f6            = 295
	f7            = 296
	f8            = 297
	f9            = 298
	f10           = 299
	f11           = 300
	f12           = 301
	f13           = 302
	f14           = 303
	f15           = 304
	f16           = 305
	f17           = 306
	f18           = 307
	f19           = 308
	f20           = 309
	f21           = 310
	f22           = 311
	f23           = 312
	f24           = 313
	f25           = 314
	kp_0          = 320
	kp_1          = 321
	kp_2          = 322
	kp_3          = 323
	kp_4          = 324
	kp_5          = 325
	kp_6          = 326
	kp_7          = 327
	kp_8          = 328
	kp_9          = 329
	kp_decimal    = 330
	kp_divide     = 331
	kp_multiply   = 332
	kp_subtract   = 333
	kp_add        = 334
	kp_enter      = 335
	kp_equal      = 336
	left_shift    = 340
	left_control  = 341
	left_alt      = 342
	left_super    = 343
	right_shift   = 344
	right_control = 345
	right_alt     = 346
	right_super   = 347
	menu          = 348
}

pub struct KeyEvent {
pub:
	// window is the window that received the key.
	window &Window = unsafe { nil }
	code   KeyCode
	shift  bool
	ctrl   bool
	alt    bool
	cmd    bool
}

// name returns the normalized key name used by the KeyFn callback.
pub fn (code KeyCode) name() string {
	return match code {
		.invalid { '' }
		.world_1, .world_2 { '' }
		.space { 'space' }
		.apostrophe { "'" }
		.comma { ',' }
		.minus { '-' }
		.period { '.' }
		.slash { '/' }
		._0, ._1, ._2, ._3, ._4, ._5, ._6, ._7, ._8, ._9 { code.str()[1..] }
		.semicolon { ';' }
		.equal { '=' }
		.left_bracket { '[' }
		.backslash { '\\' }
		.right_bracket { ']' }
		.grave_accent { '`' }
		.delete { 'forward_delete' }
		.kp_0, .kp_1, .kp_2, .kp_3, .kp_4, .kp_5, .kp_6, .kp_7, .kp_8, .kp_9 {
			code.str()[3..]
		}
		.kp_decimal { '.' }
		.kp_divide { '/' }
		.kp_multiply { '*' }
		.kp_subtract { '-' }
		.kp_add { '+' }
		.kp_enter { 'enter' }
		.kp_equal { '=' }
		else { code.str() }
	}
}

// DropFn receives file URLs and/or plain text dropped on the application
// window, plus the pointer location in root-view coordinates.
pub type DropFn = fn (DropEvent)

pub struct DropEvent {
pub:
	// window is the window the drop landed on.
	window &Window = unsafe { nil }
	paths  []string
	text   string
	x      f64
	y      f64
}

pub enum Align {
	left
	center
	right
}

// Where a label's text sits in a frame taller than the text itself. Both backends
// draw from the top by default, which is what a label sized to its own text wants;
// a label given a box — a table cell, a caption panel — usually wants otherwise.
pub enum VAlign {
	top
	middle
	bottom
}

// ScrollMode names the axes a Scroll element scrolls along, after vlang/gui's
// setting of the same name. Content past the edge of an axis the mode leaves
// out is clipped, which is why vertical_only, the behaviour Scroll always had,
// stays the default.
pub enum ScrollMode {
	vertical_only
	horizontal_only
	both
}

// scroll_mode reads a ScrollMode from its VML spelling.
pub fn scroll_mode(value string) !ScrollMode {
	return match value {
		'', 'vertical_only', 'vertical' { .vertical_only }
		'horizontal_only', 'horizontal' { .horizontal_only }
		'both' { .both }
		else {
			return error('unknown scroll mode `${value}`')
		}
	}
}

pub enum Kind {
	screen
	view
	label
	image
	button
	checkbox
	dropdown
	text_field
	text_area
	scroll
	slider
	switch_control
	toggle_button
}

// MenuEntry is one right-click context menu item attached to an element.
pub struct MenuEntry {
pub:
	on_select ElementCallback = unsafe { nil }
	id        string
	title     string
}

pub struct Rect {
pub:
	x      f64
	y      f64
	width  f64
	height f64
}

pub struct TextStyle {
pub:
	color            u32 = 0x111111
	background_color u32
	size             f64 = 15.0 // logical em size, independent of device DPI
	font_family      string
	// weight 0 preserves bold compatibility; explicit 100–900 overrides bold.
	weight             int
	letter_spacing     f64
	line_height        f64
	line_height_factor f64
	baseline_offset    f64
	tabular_figures    bool
	bold               bool
	italic             bool
	underline          bool
	strikethrough      bool
	shadow             bool
	outline            bool
	vertical_align     string
	link               string
	align              Align
	valign             VAlign = .middle
	head_indent        f64
	first_line_indent  f64
	hyphenation_factor f64
	lines              int = 1 // most lines to wrap onto; 0 wraps as many as the frame shows
}

pub struct TextRun {
pub:
	text  string
	style TextStyle
}

pub enum TextFormat {
	bold
	italic
	underline
	strikethrough
}

pub struct TextFormatState {
pub:
	bold          bool
	italic        bool
	underline     bool
	strikethrough bool
	shadow        bool
	outline       bool
	subscript     bool
	superscript   bool
}

pub enum BorderPattern {
	solid
	dashed
}

pub struct BoxStyle {
pub:
	bg                  u32 = 0xffffff
	radius              f64
	transparent         bool
	border_color        u32
	border_left         f64
	border_top          f64
	border_right        f64
	border_bottom       f64
	border_left_color   ?u32
	border_top_color    ?u32
	border_right_color  ?u32
	border_bottom_color ?u32
	border_pattern      BorderPattern
	dash_length         f64 = 6
	dash_gap            f64 = 4
	outline_color       u32
	outline_width       f64
	outline_offset      f64
	opacity             f64 = 1.0 // fill opacity, 0 (clear) to 1; borders and children keep theirs
	gradient            Gradient  // with two or more stops, fills the box instead of bg
	shadow              BoxShadow // drop shadow beneath the box; none while its opacity is zero
}

// box_draws_fill is shared by native and custom renderers so every element
// backed by BoxStyle gives transparent the same meaning.
fn box_draws_fill(box BoxStyle) bool {
	return !box.transparent
}

fn box_draws_border(box BoxStyle) bool {
	return box.border_left > 0 || box.border_top > 0 || box.border_right > 0
		|| box.border_bottom > 0
}

// box_border_width keeps a declared border inside its element. Border widths
// are logical units, just like Rect and corner radii; each backend is
// responsible for mapping those units to its native device scale.
fn box_border_width(width f64, extent f64) f64 {
	if width <= 0 || extent <= 0 {
		return 0
	}
	return if width < extent { width } else { extent }
}

pub struct Element {
	// Runtime records borrowed from the retained runtime; nil in every authored
	// declaration (element_runtime.v).
	mount   &ElementMount   = unsafe { nil }
	runtime &ElementRuntime = unsafe { nil }
pub:
	// Compiled components retain their declaration owner independently of layout.
	// It is not an authored property or a model/binding value. The retained
	// runtime maps a built element back to its owner through it in O(1), and
	// generated code reads it.
	compiled_node     &CompiledVmlNode     = unsafe { nil }
	compiled_metadata &CompiledVmlMetadata = unsafe { nil }
	// kind is readable from outside the module so a renderer can live in
	// another package: dispatching on it is the first thing any backend does.
	kind        Kind
	id          string // lookup/state identity
	on_event    ElementCallback = unsafe { nil }
	key         string // stable identity for reconciliation (falls back to child index)
	text        string
	checked     bool // checkbox: declared on/off state
	image_path  string
	image_asset ImageAsset
	image_style ImageStyle
	tooltip     string
	placeholder string
	frame       Rect
	// Authored geometry is retained separately from the resolved frame.
	layout_input          ?Rect
	layout                LayoutSpec
	box                   BoxStyle
	interaction_style     InteractionStyle // custom renderer: sparse visual state overrides
	content_padding       ?LayoutPadding   // custom button text/image content inset
	content_size          LayoutSize       // custom: fixed logical composition, fit within frame
	is_vector_canvas      bool             // preserves vector semantics with an empty shapes array
	vector_shapes         []VectorShape    // custom: retained local geometry, clipped to the view frame
	vector_hit_mode       VectorHitMode
	text_style            TextStyle
	native_style          bool      // button: draw the standard bezel unless a fill is declared
	text_runs             []TextRun // label/text_area: optional rich text style runs
	keyboard              int
	long_press            bool
	swipe_left            bool
	readonly              bool // text_area: selectable but not editable
	disable_scroll        bool // text_area: hide the internal scroll view scroller
	persistent_scrollbars bool // scroll: keep a legacy always-visible scroller instead of the auto-fading overlay one
	secure                bool // text_field: native password entry
	clickable             bool // view/image: emit pointer down/up events
	button_behavior       bool // view: invoke its callback when released like a button
	// Sparse properties are shared references: an element without them pays
	// one word each, and copies share the record.
	drag_source ?&DragSource
	drop_target ?DropTarget
	draggable   bool // view/image: emit pointer drag events
	hoverable   bool // any element: report pointer enter/leave as the pointer moves over it
	opacity     f64 = 1 // custom: inherited per-primitive opacity
	motion      ?MotionConfig
	overlay     ?&OverlayConfig
	rotation    f64 // custom: clockwise visual rotation, for every element
	translate_x f64
	translate_y f64
	scale_x     f64 = 1
	scale_y     f64 = 1
	origin_x    f64
	origin_y    f64
	cursor      string // view/image: hover cursor hint
	menu        []MenuEntry
	children    []Element
	hidden      bool
	enabled     bool = true
	// Keyboard identity is id. Negative tab_index permits programmatic focus
	// while excluding a control from sequential and directional traversal.
	focus_policy        FocusPolicy
	tab_index           int
	focus_scope         bool
	accessibility_name  string
	accessibility_role  string
	accessibility_label string
	accessibility_value string
	autocorrect         bool = true // native text inputs
	padding_left        f64  = 12.0 // text input content inset
	value               f64 // slider: current value
	min_value           f64 // slider: lower range boundary
	max_value           f64 = 100.0 // slider: upper range boundary
	step                f64         // slider: zero is continuous
	orientation         Orientation // slider: horizontal or vertical
	padding             f64 = 16.0 // slider: inset from each end of its track
	value_track         bool // slider: color the track between min and value
	slider_style        SliderStyle
	switch_style        SwitchStyle
	toggle              ?&ToggleSpec // toggle_button: group and pressed presentation
	scroll_mode         ScrollMode   // scroll: the axes the content scrolls along
}

// BackendSupport is what control_support reports for a control kind. Partial
// means the control works but lacks some native behavior (for example rich
// text on Android and iOS). Each backend defines control_support (backend.v).
pub enum BackendSupport {
	unsupported
	partial
	supported
}

// reconciliation_child_key encodes user keys so separators inside a key
// cannot alias a nested key path.
fn reconciliation_child_key(parent string, index int, el Element) string {
	if el.mount != unsafe { nil } && el.mount.path.len > 0 && el.mount.parent_path == parent {
		return el.mount.path
	}
	return authored_child_key(parent, index, el)
}

fn authored_child_key(parent string, index int, el Element) string {
	suffix := if el.key.len > 0 {
		'k:' + el.key.bytes().hex()
	} else if el.compiled_node != unsafe { nil } {
		'c:' + el.compiled_node.identity_path()
	} else {
		'i:' + index.str()
	}
	return if parent.len == 0 { suffix } else { parent + '/' + suffix }
}

// These private keys keep authored ids, keyed anonymous editors and scroll
// paths in disjoint namespaces. Resolved declarations retain the string so
// input refreshes and repaints do not concatenate it again.
fn authored_scroll_state_id(el Element, path string) string {
	if el.kind !in [.scroll, .text_area] { return '' }
	if el.id.len > 0 { return named_scroll_prefix + el.id }
	if el.kind == .text_area {
		return if el.key.len > 0 { anonymous_text_area_scroll_prefix + el.key } else { '' }
	}
	return anonymous_scroll_prefix + path
}

// Tooltip ownership follows mounted identity, so scrolling or repainting an
// anonymous keyed element does not restart its hover delay.
fn authored_tooltip_key(el Element, path string) string {
	if el.id.len > 0 { return '${el.kind}#${el.id}' }
	return '${el.kind}@${path}'
}

// validate_element_tree rejects ambiguous declarative identity before a
// renderer mutates native state.
pub fn validate_element_tree(root Element) ! {
	mut ids := map[string]bool{}
	validate_element_node(root, 'root', mut ids)!
}

fn validate_element_node(el Element, path string, mut ids map[string]bool) ! {
	mut walk := ElementValidation{
		root: path
	}
	walk.node(el, mut ids)!
}

// Paths in diagnostics are built only when a check fails, so validating a
// valid tree allocates no per-node strings or sibling-key sets.
struct ElementValidation {
	root string
mut:
	indices []int
}

fn (walk &ElementValidation) path() string {
	mut path := walk.root
	for index in walk.indices { path += '/${index}' }
	return path
}

fn (mut walk ElementValidation) node(el Element, mut ids map[string]bool) ! {
	if walk.indices.len == 0 {
		validate_element_properties(el, walk.root)!
	} else {
		validate_element_properties(el, '') or {
			// Repeat the failing check with its location for the message.
			validate_element_properties(el, walk.path())!
			return err
		}
	}
	if el.id.len > 0 {
		if el.id in ids {
			return error('duplicate element id `${el.id}` at ${walk.path()}')
		}
		ids[el.id] = true
	}
	// The first repeated key is reported where the sibling walk reaches it,
	// after any failure in the subtrees of the siblings before it.
	duplicate := element_first_duplicate_key(el.children)
	for index, child in el.children {
		if index == duplicate {
			return error('duplicate sibling key `${child.key}` at ${walk.path()}')
		}
		walk.indices << index
		walk.node(child, mut ids)!
		walk.indices.delete_last()
	}
}

struct ElementKeyRef {
	value string
}

// Short sibling lists are compared directly; only long ones build a key set.
fn element_first_duplicate_key(children []Element) int {
	if children.len < 2 { return -1 }
	if children.len <= 16 {
		for index in 1 .. children.len {
			key := children[index].key
			if key.len == 0 { continue }
			for previous in 0 .. index {
				if children[previous].key == key { return index }
			}
		}
		return -1
	}
	// Sorting the keys proves the common case, uniqueness, with one array. A
	// wrapper keeps the strings shared (appending a string copies its bytes).
	mut sorted := []ElementKeyRef{cap: children.len}
	for child in children {
		if child.key.len > 0 { sorted << ElementKeyRef{ value: child.key } }
	}
	sorted.sort(a.value < b.value)
	mut repeated := false
	for index in 1 .. sorted.len {
		if sorted[index].value == sorted[index - 1].value {
			repeated = true
			break
		}
	}
	if !repeated { return -1 }
	mut keys := map[string]bool{}
	for index, child in children {
		if child.key.len == 0 { continue }
		if child.key in keys { return index }
		keys[child.key] = true
	}
	return -1
}

// validate_element_properties checks one element's own properties, without
// its id or children. A retained property update keeps both unchanged.
fn validate_element_properties(el Element, path string) ! {
	if config := el.overlay {
		config.validate()!
		if el.kind != .view || el.id.len == 0 {
			return error('an overlay requires a View with a stable id at ${path}')
		}
		if !backend_supports_overlays {
			return error('overlays require the desktop custom renderer at ${path}')
		}
	}
	validate_drag_element(el)!
	validate_content_padding(el)!
	if !finite_number(el.opacity) || el.opacity < 0 || el.opacity > 1 {
		return error('opacity must be finite and between zero and one at ${path}')
	}
	if config := el.motion { config.validate()! }
	if el.opacity != 1 || el.motion != none {
		if !backend_supports_motion {
			return error('opacity and motion require the desktop custom renderer at ${path}')
		}
	}
	el.authored_visual_transform().matrix(el.frame)!
	if el.authored_visual_transform() != VisualTransform{} {
		if !backend_supports_visual_transforms {
			return error('visual transforms require the custom renderer with desktop text at ${path}')
		}
	}
	if (el.focus_scope || el.focus_policy == .focusable) && el.id.len == 0 {
		return error('explicit focus targets and scopes require an id at ${path}')
	}
	if el.is_vector_canvas || el.vector_shapes.len > 0 {
		if el.kind != .view { return error('vector canvas must be a view at ${path}') }
		if el.content_size.width != 0 || el.content_size.height != 0 {
			return error('put vector canvas inside scaled content at ${path}')
		}
		validate_layout_frame(el.frame)!
		for shape in el.vector_shapes {
			if !shape.prepared { return error('vector canvas needs prepared geometry at ${path}') }
		}
	}
	el.image_asset.validate()!
	el.image_style.validate()!
	if el.image_asset != ImageAsset{} || el.image_style != ImageStyle{} {
		if el.kind !in [.image, .button] {
			return error('image assets/styles require an Image or raster Button at ${path}')
		}
		if el.image_path.starts_with('symbol:') {
			return error('symbol buttons use text_style, not raster image assets/styles at ${path}')
		}
	}
	if el.content_size.width != 0 || el.content_size.height != 0 {
		if el.kind != .view { return error('scaled content must be a view at ${path}') }
		contain_content(el.frame, el.content_size.width, el.content_size.height)!
	}
}

pub const keyboard_default = 0
pub const keyboard_decimal = 8
pub const cursor_default = ''
pub const cursor_pointing_hand = 'pointing_hand'
pub const cursor_resize_nwse = 'resize_nwse'
pub const cursor_resize_nesw = 'resize_nesw'
pub const cursor_resize_ew = 'resize_ew'
pub const cursor_resize_ns = 'resize_ns'
pub const cursor_crosshair = 'crosshair'
pub const cursor_rotate = 'rotate'

pub fn rect(x f64, y f64, width f64, height f64) Rect {
	return Rect{
		x:      x
		y:      y
		width:  width
		height: height
	}
}

fn intersect_rect(a Rect, b Rect) Rect {
	left := if a.x > b.x { a.x } else { b.x }
	top := if a.y > b.y { a.y } else { b.y }
	right_a := a.x + a.width
	right_b := b.x + b.width
	bottom_a := a.y + a.height
	bottom_b := b.y + b.height
	right := if right_a < right_b { right_a } else { right_b }
	bottom := if bottom_a < bottom_b { bottom_a } else { bottom_b }
	return Rect{
		x:      left
		y:      top
		width:  if right > left { right - left } else { 0 }
		height: if bottom > top { bottom - top } else { 0 }
	}
}

pub fn screen(bg u32, children []Element) Element {
	return Element{
		kind:     .screen
		box:      BoxStyle{
			bg: bg
		}
		children: children
	}
}

pub fn view(id string, frame Rect, box_ BoxStyle, children []Element) Element {
	return Element{
		kind:     .view
		id:       id
		frame:    frame
		box:      box_
		children: children
	}
}

// clickable_view is a container that reports pointer down and up on itself,
// for a surface that is not a control but still has to answer a click — the
// body of a window that should come to the front when it is touched, say.
pub fn clickable_view(id string, frame Rect, box_ BoxStyle, children []Element) Element {
	return Element{
		kind:      .view
		id:        id
		frame:     frame
		box:       box_
		clickable: true
		children:  children
	}
}

// button_view is a container with ordinary button activation semantics. Unlike
// clickable_view, which reports raw pointer phases, it invokes its callback once
// when a press is released inside the view.
pub fn button_view(id string, frame Rect, box_ BoxStyle, children []Element) Element {
	return with_button_behavior(view(id, frame, box_, children))
}

// with_button_behavior turns a composed view into one semantic button without
// discarding its children. Attach a callback with with_event.
// as well. Other element kinds are returned unchanged.
pub fn with_button_behavior(el Element) Element {
	if el.kind != .view {
		return el
	}
	return Element{
		...el
		button_behavior:     true
		accessibility_role:  if el.accessibility_role.len > 0 {
			el.accessibility_role
		} else {
			'button'
		}
		accessibility_label: if el.accessibility_label.len > 0 {
			el.accessibility_label
		} else {
			button_behavior_label(el)
		}
	}
}

fn button_behavior_label(el Element) string {
	if el.text.trim_space().len > 0 {
		return el.text
	}
	for child in el.children {
		if !button_behavior_label_source(child) {
			continue
		}
		if child.accessibility_label.trim_space().len > 0 {
			return child.accessibility_label
		}
		child_label := button_behavior_label(child)
		if child_label.len > 0 {
			return child_label
		}
	}
	return ''
}

fn button_behavior_label_source(el Element) bool {
	if el.hidden {
		return false
	}
	return match el.kind {
		.label { true }
		.view, .image {
			!el.button_behavior && !el.clickable && !el.draggable && !el.long_press
				&& !el.swipe_left && el.menu.len == 0
		}
		else { false }
	}
}

pub fn draggable_view(id string, frame Rect, box_ BoxStyle, children []Element) Element {
	return Element{
		kind:      .view
		id:        id
		frame:     frame
		box:       box_
		draggable: true
		children:  children
	}
}

pub fn draggable_view_with_cursor(id string, frame Rect, box_ BoxStyle, cursor string, children []Element) Element {
	return Element{
		kind:      .view
		id:        id
		frame:     frame
		box:       box_
		draggable: true
		cursor:    cursor
		children:  children
	}
}

pub fn view_with_long_press(id string, frame Rect, box_ BoxStyle, children []Element) Element {
	return Element{
		kind:       .view
		id:         id
		frame:      frame
		box:        box_
		long_press: true
		children:   children
	}
}

pub fn view_with_long_press_and_swipe_left(id string, frame Rect, box_ BoxStyle, children []Element) Element {
	return Element{
		kind:       .view
		id:         id
		frame:      frame
		box:        box_
		long_press: true
		swipe_left: true
		children:   children
	}
}

pub fn scroll(id string, frame Rect, bg u32, children []Element) Element {
	return Element{
		kind:     .scroll
		id:       id
		frame:    frame
		box:      BoxStyle{
			bg: bg
		}
		children: children
	}
}

// scroll_persistent behaves like scroll but keeps a legacy, always-visible
// scroller (when the content overflows) rather than the system overlay scroller
// that fades out once scrolling stops. Suited to spreadsheet-style grids where a
// draggable scrollbar should stay on screen.
pub fn scroll_persistent(id string, frame Rect, bg u32, children []Element) Element {
	return Element{
		kind:                  .scroll
		id:                    id
		frame:                 frame
		box:                   BoxStyle{
			bg: bg
		}
		children:              children
		persistent_scrollbars: true
	}
}

// scroll_with_mode is scroll along the axes mode names: sideways for a strip of
// columns wider than its pane, or both ways for a canvas larger than its viewport.
// The content is as wide as its rightmost child reaches.
pub fn scroll_with_mode(id string, frame Rect, bg u32, mode ScrollMode, children []Element) Element {
	return Element{
		kind:        .scroll
		id:          id
		frame:       frame
		box:         BoxStyle{
			bg: bg
		}
		children:    children
		scroll_mode: mode
	}
}

// scroll_mode_offset holds a scroll position to the axes a mode scrolls. Along an axis
// the mode leaves out the position is the start: anything else would keep the content
// shifted with no way to scroll it back.
fn scroll_mode_offset(mode ScrollMode, x f64, y f64) (f64, f64) {
	return if mode == .vertical_only { 0.0 } else { x }, if mode == .horizontal_only {
		0.0
	} else {
		y
	}
}

// scroll_content_width is how far the children of a Scroll element reach to the
// right, which is the width a sideways scroll has to cover. Hidden children take
// no room.
fn scroll_content_width(children []Element) f64 {
	mut width := 0.0
	for child in children {
		if !child.layout_excluded() && child.frame.x + child.frame.width > width {
			width = child.frame.x + child.frame.width
		}
	}
	return width
}

pub fn label(id string, text string, frame Rect, style TextStyle) Element {
	return Element{
		kind:       .label
		id:         id
		text:       text
		frame:      frame
		text_style: style
	}
}

pub fn image(id string, path string, frame Rect) Element {
	return Element{
		kind:       .image
		id:         id
		image_path: path
		frame:      frame
	}
}

// rich_label uses full per-run styles; VML Run children additionally inherit
// omitted properties. Desktop custom supports shared wrapping and baselines.
pub fn rich_label(id string, runs []TextRun, frame Rect, style TextStyle) Element {
	return Element{ ...label(id, text_runs_content(runs), frame, style), text_runs: runs }
}

pub fn button(id string, title string, frame Rect, box_ BoxStyle, style TextStyle) Element {
	return Element{
		kind:       .button
		id:         id
		text:       title
		frame:      frame
		box:        box_
		text_style: style
	}
}

// with_native_style draws a button's standard bezel and interaction states
// while it has no declared fill; a declared fill still wins.
pub fn with_native_style(el Element) Element {
	return Element{
		...el
		native_style: true
	}
}

// checkbox creates the platform checkbox control. Its id is emitted when the
// user toggles it; rebuild with the updated checked value to retain that state.
pub fn checkbox(id string, title string, checked bool, frame Rect, style TextStyle) Element {
	return Element{
		kind:                .checkbox
		id:                  id
		text:                title
		checked:             checked
		frame:               frame
		box:                 BoxStyle{
			transparent: true
		}
		text_style:          style
		accessibility_role:  'checkbox'
		accessibility_label: title
		accessibility_value: if checked { 'checked' } else { 'unchecked' }
	}
}

pub fn button_with_image(id string, title string, image_name string, frame Rect, box_ BoxStyle, style TextStyle) Element {
	return Element{
		kind:       .button
		id:         id
		text:       title
		image_path: image_name
		frame:      frame
		box:        box_
		text_style: style
	}
}

// with_tooltip adds hover help without changing an element's visible text.
pub fn with_tooltip(el Element, tooltip string) Element {
	return Element{
		...el
		tooltip: tooltip
	}
}

// with_event attaches a typed callback without changing element identity.
pub fn with_event(el Element, on_event ElementCallback) Element {
	return Element{ ...el, on_event: on_event }
}

// with_secure_entry makes a text field use the platform's native password
// control while retaining the field's change and submit bindings.

pub fn button_with_long_press(id string, title string, frame Rect, box_ BoxStyle, style TextStyle) Element {
	return Element{
		kind:       .button
		id:         id
		text:       title
		frame:      frame
		box:        box_
		text_style: style
		long_press: true
	}
}

pub fn dropdown(id string, selected string, options []string, frame Rect, box_ BoxStyle, style TextStyle) Element {
	mut entries := []MenuEntry{}
	for option in options {
		entries << MenuEntry{
			id:    option
			title: option
		}
	}
	return Element{
		kind:       .dropdown
		id:         id
		text:       selected
		frame:      frame
		box:        box_
		text_style: style
		menu:       entries
	}
}

// scaled_content fits fixed logical child geometry inside a viewport without reflow.
// Custom renderer only. Navigation outside this view keeps its normal dimensions.
pub fn scaled_content(id string, viewport Rect, width f64, height f64, box_ BoxStyle, children []Element) Element {
	return Element{ ...view(id, viewport, box_, children), content_size: LayoutSize{ width: width, height: height } }
}
