module ui2

import math

// VML props types are the widget table behind VML tags. Tag `Slider` builds
// from `SliderProps`; every authored property is a field of that struct, so V
// checks names, types and enum spellings. `build` lowers a props value through
// the existing ui2 constructors. The shared rules (common Element fields,
// MenuItem parts, child layout, placement and events) live here.

// DisplayText is the value of a VML `text` property: a string, or a number
// formatted with V's str(), exactly as vml_display_text formats it.
pub type DisplayText = string | int | i64 | f64

pub fn (text DisplayText) str() string {
	return match text {
		string { text }
		int { text.str() }
		i64 { text.str() }
		f64 { text.str() }
	}
}

// TextKeyboard names the VML keyboard spellings; the values are the
// keyboard_default and keyboard_decimal constants.
pub enum TextKeyboard {
	default = 0
	decimal = 8
}

// VmlPlacement is how a parent offers a frame to a child: allocated, or
// measured with omitted axes starting at zero.
pub enum VmlPlacement {
	normal
	preferred
	width_preferred
	inherited_preferred
	allocated
}

// VmlRun is a Run part. Its parent composes its own style before the run's,
// so the patch is kept until the parent builds the TextRun.
pub struct VmlRun {
pub:
	text  string
	style StylePatch
}

// VmlPart is a child that is not an element: rich-text runs, dropdown options
// (MenuEntry), menu rows (MenuItem), menus, message box actions, and the typed
// records composite parents read from their children. Part tags defined
// outside ui2 give their parent a VmlRecordPart.
pub type VmlPart = AccordionItem
	| ManagedScreen
	| Menu
	| MenuEntry
	| MenuItem
	| MessageBoxAction
	| TabbedPanelTab
	| TreeViewNode
	| VmlRecordPart
	| VmlRun

// VmlPartRecord is any record a part tag defined outside ui2 gives its parent.
pub interface VmlPartRecord {}

// VmlRecordPart carries such a record. The parent reads the records of its
// own type with `ctx.records[T]()`.
pub struct VmlRecordPart {
pub:
	record VmlPartRecord
}

// Capability markers. They are method-only interfaces, checked with
// `$if P is VmlContainer` by generic code.
//
// VmlContainer accepts element children.
pub interface VmlContainer {
	vml_container()
}

// VmlPositioner lets children author x and y (Absolute).
pub interface VmlPositioner {
	vml_positioner()
}

// VmlCustomRenderer requires the custom renderer (ScaledContent, overlays, Run).
pub interface VmlCustomRenderer {
	vml_custom_renderer()
}

// VmlPartProps is implemented by props that become a VmlPart of their parent.
pub interface VmlPartProps {
	part(ctx VmlBuildContext) !VmlPart
}

// VmlLayoutItem holds the attached child-layout properties. A Flex, Grid or
// Stack parent reads them from its children; other parents ignore them. The
// defaults equal FlexChild, GridSpan and StackChild.
pub struct VmlLayoutItem {
pub mut:
	flex_basis   f64 = -1
	flex_grow    f64
	flex_shrink  f64 = 1
	min_width    f64
	min_height   f64
	max_width    f64 = -1
	max_height   f64 = -1
	align_self   LayoutAlignment = .auto
	column_span  int             = 1
	row_span     int             = 1
	align_self_x LayoutAlignment = .auto
	align_self_y LayoutAlignment = .auto
}

pub fn (item VmlLayoutItem) flex_child(element Element) FlexChild {
	return FlexChild{
		element:        element
		basis:          item.flex_basis
		grow:           item.flex_grow
		shrink:         item.flex_shrink
		minimum_width:  item.min_width
		minimum_height: item.min_height
		maximum_width:  item.max_width
		maximum_height: item.max_height
		align_self:     item.align_self
	}
}

pub fn (item VmlLayoutItem) grid_span() GridSpan {
	return GridSpan{
		column_span: item.column_span
		row_span:    item.row_span
	}
}

pub fn (item VmlLayoutItem) stack_child(element Element) StackChild {
	return StackChild{
		element: element
		align_x: item.align_self_x
		align_y: item.align_self_y
	}
}

// VmlBuildContext is what a parent and the runtime give a props value to build.
pub struct VmlBuildContext {
pub:
	// id is the authored id, or the generated control identity the runtime
	// assigns to bound, referenced and overlay nodes. The owning component
	// namespaces it when the element is retained.
	id  string
	key string
	// frame is the runtime frame: authored x/y/width/height resolved against
	// the parent's offered input.
	frame Rect
	// children are the projected child elements in declaration order and
	// child_layouts their attached layout properties (same indexes).
	children      []Element
	child_layouts []VmlLayoutItem
	// parts are the non-element children in declaration order.
	parts []VmlPart
	// owner resolves local id references (overlay anchors).
	owner &CompiledVmlComponent = unsafe { nil }
}

pub fn (ctx VmlBuildContext) child_layout(index int) VmlLayoutItem {
	return if index < ctx.child_layouts.len { ctx.child_layouts[index] } else { VmlLayoutItem{} }
}

// resolve_id maps a local id reference to the public id of the element in the
// owner's namespace. Empty references stay empty, and an id that is already a
// public control id (a value read from state, a ref or an event) is kept, so
// it is never namespaced twice.
pub fn (ctx VmlBuildContext) resolve_id(id string) string {
	if id.len == 0 || ctx.owner == unsafe { nil } || vml_is_control_id(id) { return id }
	return ctx.owner.control_id(id)
}

// vml_is_control_id reports whether id has the form control_id gives a
// component-local id: `vml:<namespace>:<hex of the local id>`.
fn vml_is_control_id(id string) bool {
	if !id.starts_with('vml:') { return false }
	colon := id.last_index_u8(`:`)
	if colon < 5 || colon == id.len - 1 || (id.len - colon - 1) % 2 != 0 {
		return false
	}
	for i in colon + 1 .. id.len {
		c := id[i]
		if !((c >= `0` && c <= `9`) || (c >= `a` && c <= `f`)) { return false }
	}
	return true
}

// records are the part records of type T, in declaration order.
pub fn (ctx VmlBuildContext) records[T]() []T {
	mut result := []T{}
	for part in ctx.parts {
		if part is VmlRecordPart {
			record := part.record
			if record is T {
				result << record
			}
		}
	}
	return result
}

pub fn (ctx VmlBuildContext) runs() []VmlRun {
	mut runs := []VmlRun{}
	for part in ctx.parts {
		if part is VmlRun { runs << part }
	}
	return runs
}

// options are the Option parts of a Dropdown or Spinner.
pub fn (ctx VmlBuildContext) options() []MenuEntry {
	mut entries := []MenuEntry{}
	for part in ctx.parts {
		if part is MenuEntry { entries << part }
	}
	return entries
}

// menu_items are the MenuItem parts; a nested Menu is a submenu row.
pub fn (ctx VmlBuildContext) menu_items() []MenuItem {
	mut items := []MenuItem{}
	for part in ctx.parts {
		match part {
			MenuItem {
				items << part
			}
			Menu {
				items << MenuItem{
					title: part.title
					items: part.items
				}
			}
			else {}
		}
	}
	return items
}

pub fn (ctx VmlBuildContext) menus() []Menu {
	mut result := []Menu{}
	for part in ctx.parts {
		if part is Menu { result << part }
	}
	return result
}

pub fn (ctx VmlBuildContext) message_actions() []MessageBoxAction {
	mut actions := []MessageBoxAction{}
	for part in ctx.parts {
		if part is MessageBoxAction { actions << part }
	}
	return actions
}

// text_runs composes each Run with its parent's style first, like inherited
// typography: omitted run properties follow the parent's style.
pub fn (ctx VmlBuildContext) text_runs(parent_style StylePatch) ![]TextRun {
	mut runs := []TextRun{}
	for run in ctx.runs() {
		runs << TextRun{
			text:  run.text
			style: apply_text_style(TextStyle{}, compose_styles([parent_style, run.style]))!
		}
	}
	return runs
}

// CommonProps are the properties every element tag accepts. Optional fields
// are applied to the built element only when authored; their names equal the
// Element fields they set, except `native` (Element.native_style).
pub struct CommonProps {
	VmlLayoutItem
pub mut:
	// Authored geometry; omitted axes follow the parent's placement.
	x      ?f64
	y      ?f64
	width  ?f64
	height ?f64
	// style refines the built element (a self-styled widget also consumes it
	// in build). An empty patch is not applied.
	style               StylePatch
	button_behavior     ?bool
	secure              ?bool
	clickable           ?bool
	draggable           ?bool
	long_press          ?bool
	swipe_left          ?bool
	rotation            ?f64
	opacity             ?f64
	motion              ?MotionConfig
	translate_x         ?f64
	translate_y         ?f64
	scale_x             ?f64
	scale_y             ?f64
	origin_x            ?f64
	origin_y            ?f64
	cursor              ?string
	tooltip             ?string
	hidden              ?bool
	enabled             ?bool
	accessibility_role  ?string
	accessibility_label ?string
	accessibility_value ?string
	native              ?bool
	autocorrect         ?bool
	// Events dispatched by ElementEvent.kind.
	on_click        ElementCallback = unsafe { nil }
	on_change       ElementCallback = unsafe { nil }
	on_scroll       ElementCallback = unsafe { nil }
	on_open         ElementCallback = unsafe { nil }
	on_dismiss      ElementCallback = unsafe { nil }
	on_pointer_down ElementCallback = unsafe { nil }
	on_pointer_drag ElementCallback = unsafe { nil }
	on_pointer_up   ElementCallback = unsafe { nil }
	on_long_press   ElementCallback = unsafe { nil }
	on_swipe_left   ElementCallback = unsafe { nil }
	on_link         ElementCallback = unsafe { nil }
}

pub fn (p CommonProps) common_props() CommonProps {
	return p
}

// vml_structure is how the runtime reconciles the widget's element; widgets
// whose constructor manufactures or reads its children override it.
pub fn (p CommonProps) vml_structure() VmlStructure {
	return .plain
}

// control_id_required reports whether the element needs a public id even when
// none is authored (overlays are addressed by id).
pub fn (p CommonProps) control_id_required() bool {
	return false
}

pub fn (p CommonProps) layout_item() VmlLayoutItem {
	return p.VmlLayoutItem
}

// validate rejects values the compiled document would reject before its
// first frame. Widgets with their own ranges add to it.
pub fn (p CommonProps) validate() ! {
	if value := p.opacity {
		if !math.is_finite(value) || value < 0 || value > 1 {
			return error('opacity must be finite and between zero and one')
		}
	}
	if value := p.scale_x {
		if !math.is_finite(value) || value == 0 {
			return error('`scale_x` must be finite and nonzero')
		}
	}
	if value := p.scale_y {
		if !math.is_finite(value) || value == 0 {
			return error('`scale_y` must be finite and nonzero')
		}
	}
	if p.column_span <= 0 { return error('`column_span` must be positive') }
	if p.row_span <= 0 { return error('`row_span` must be positive') }
}

// project applies the authored common properties and MenuItem parts to a
// built element. Widgets that wrap their element afterwards (overlays) or
// derive a common field (TextInput) override it.
pub fn (p CommonProps) project(el Element, ctx VmlBuildContext) !Element {
	return p.project_common(el, ctx)
}

pub fn (p CommonProps) project_common(el Element, ctx VmlBuildContext) Element {
	items := ctx.menu_items()
	return Element{
		...el
		menu:                if items.len > 0 {
			items.map(MenuEntry{ id: it.id, on_select: it.on_select, title: it.title })
		} else {
			el.menu
		}
		button_behavior:     p.button_behavior or { el.button_behavior }
		secure:              p.secure or { el.secure }
		clickable:           p.clickable or { el.clickable }
		draggable:           p.draggable or { el.draggable }
		long_press:          p.long_press or { el.long_press }
		swipe_left:          p.swipe_left or { el.swipe_left }
		rotation:            p.rotation or { el.rotation }
		opacity:             p.opacity or { el.opacity }
		motion:              if motion := p.motion { ?MotionConfig(motion) } else { el.motion }
		translate_x:         p.translate_x or { el.translate_x }
		translate_y:         p.translate_y or { el.translate_y }
		scale_x:             p.scale_x or { el.scale_x }
		scale_y:             p.scale_y or { el.scale_y }
		origin_x:            p.origin_x or { el.origin_x }
		origin_y:            p.origin_y or { el.origin_y }
		cursor:              p.cursor or { el.cursor }
		tooltip:             p.tooltip or { el.tooltip }
		hidden:              p.hidden or { el.hidden }
		enabled:             p.enabled or { el.enabled }
		accessibility_role:  p.accessibility_role or { el.accessibility_role }
		accessibility_label: p.accessibility_label or { el.accessibility_label }
		accessibility_value: p.accessibility_value or { el.accessibility_value }
		native_style:        p.native or { el.native_style }
		autocorrect:         p.autocorrect or { el.autocorrect }
	}
}

// apply_event lets a widget update its own value from the event it emitted,
// before bindings write back and handlers run. Most props have no value.
pub fn (mut p CommonProps) apply_event(event ElementEvent) {
	_ = event
}

// child_placement is the placement a generic container offers its children:
// allocated, unless the container itself is being measured.
pub fn (p CommonProps) child_placement(placement VmlPlacement) VmlPlacement {
	return if placement in [.preferred, .width_preferred, .inherited_preferred] {
		VmlPlacement.inherited_preferred
	} else {
		VmlPlacement.normal
	}
}

// child_input is the logical frame a container offers each child.
pub fn (p CommonProps) child_input(frame Rect, child_count int) !Rect {
	_ = child_count
	return rect(0, 0, frame.width, frame.height)
}

// resolve_frame resolves authored geometry against the offered input. A
// measured placement starts omitted dimensions at zero.
pub fn (p CommonProps) resolve_frame(input Rect, placement VmlPlacement) Rect {
	if placement == .allocated { return input }
	preferred := placement in [.preferred, .width_preferred]
	width := if placement == .width_preferred {
		input.width
	} else {
		p.width or { if preferred { 0.0 } else { input.width } }
	}
	height := p.height or { if preferred { 0.0 } else { input.height } }
	return rect(p.x or { input.x }, p.y or { input.y }, width, height)
}

// element_callback dispatches the common events of a built element; it is nil
// when no handler is set.
pub fn (p CommonProps) element_callback() ElementCallback {
	return p.event_handlers().callback()
}

fn (p CommonProps) event_handlers() VmlEventHandlers {
	return VmlEventHandlers{
		on_click:        p.on_click
		on_change:       p.on_change
		on_scroll:       p.on_scroll
		on_open:         p.on_open
		on_dismiss:      p.on_dismiss
		on_pointer_down: p.on_pointer_down
		on_pointer_drag: p.on_pointer_drag
		on_pointer_up:   p.on_pointer_up
		on_long_press:   p.on_long_press
		on_swipe_left:   p.on_swipe_left
		on_link:         p.on_link
	}
}

struct VmlEventHandlers {
	on_click        ElementCallback = unsafe { nil }
	on_active       ElementCallback = unsafe { nil }
	on_change       ElementCallback = unsafe { nil }
	on_submit       ElementCallback = unsafe { nil }
	on_scroll       ElementCallback = unsafe { nil }
	on_open         ElementCallback = unsafe { nil }
	on_dismiss      ElementCallback = unsafe { nil }
	on_pointer_down ElementCallback = unsafe { nil }
	on_pointer_drag ElementCallback = unsafe { nil }
	on_pointer_up   ElementCallback = unsafe { nil }
	on_long_press   ElementCallback = unsafe { nil }
	on_swipe_left   ElementCallback = unsafe { nil }
	on_link         ElementCallback = unsafe { nil }
}

fn (h VmlEventHandlers) empty() bool {
	return h.on_click == unsafe { nil } && h.on_active == unsafe { nil }
		&& h.on_change == unsafe { nil } && h.on_submit == unsafe { nil }
		&& h.on_scroll == unsafe { nil } && h.on_open == unsafe { nil }
		&& h.on_dismiss == unsafe { nil } && h.on_pointer_down == unsafe { nil }
		&& h.on_pointer_drag == unsafe { nil } && h.on_pointer_up == unsafe { nil }
		&& h.on_long_press == unsafe { nil } && h.on_swipe_left == unsafe { nil }
		&& h.on_link == unsafe { nil }
}

fn vml_dispatch(callback ElementCallback, event ElementEvent) {
	if callback != unsafe { nil } { callback(event) }
}

// A change runs on_active (Switch) before on_change.
fn (h VmlEventHandlers) callback() ElementCallback {
	if h.empty() { return unsafe { nil } }
	return fn [h] (event ElementEvent) {
		match event.kind {
			.click {
				vml_dispatch(h.on_click, event)
			}
			.change {
				vml_dispatch(h.on_active, event)
				vml_dispatch(h.on_change, event)
			}
			.submit {
				vml_dispatch(h.on_submit, event)
			}
			.scroll {
				vml_dispatch(h.on_scroll, event)
			}
			.open {
				vml_dispatch(h.on_open, event)
			}
			.dismiss {
				vml_dispatch(h.on_dismiss, event)
			}
			.pointer_down {
				vml_dispatch(h.on_pointer_down, event)
			}
			.pointer_drag {
				vml_dispatch(h.on_pointer_drag, event)
			}
			.pointer_up {
				vml_dispatch(h.on_pointer_up, event)
			}
			.long_press {
				vml_dispatch(h.on_long_press, event)
			}
			.swipe_left {
				vml_dispatch(h.on_swipe_left, event)
			}
			.link {
				vml_dispatch(h.on_link, event)
			}
			else {}
		}
	}
}

// vml_build_element validates and builds a props value into the declaration a
// retained node owns: the widget's element with its authored common
// properties. The runtime applies `style` to the retained node afterwards.
pub fn vml_build_element[P](props P, ctx VmlBuildContext) !Element {
	props.validate()!
	return props.project(props.build(ctx)!, ctx)!
}

// vml_keyed gives a built element the context's reconciliation key.
fn vml_keyed(el Element, ctx VmlBuildContext) Element {
	return Element{
		...el
		key: ctx.key
	}
}

// vml_handled also attaches the element's event dispatch.
fn vml_handled(el Element, ctx VmlBuildContext, on_event ElementCallback) Element {
	return Element{
		...el
		on_event: on_event
		key:      ctx.key
	}
}
