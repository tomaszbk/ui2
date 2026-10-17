// vfmt off
// The headless backend (backend.v): the contract with in-memory state and no
// window, selected by -d ui2_headless on every OS. run builds the first frame
// and returns. Tests then drive it through the public API and the headless_*
// functions below: headless_frame rebuilds after a refresh request,
// headless_key delivers a key press, and headless_state exposes the counters
// and live control values.
@[has_globals]
module ui2

$if !(android || ios || linux || macos || windows) && !ui2_headless ? && !ui2_document_library ? {
	$compile_error('ui2 has no backend for this target OS; build with -d ui2_headless')
}

$if ui2_headless ? && !ui2_document_library ? {
	import math

	pub const backend_name = 'headless'
	pub const backend_supports_overlays = true
	pub const backend_supports_motion = true
	pub const backend_supports_visual_transforms = true
	pub const backend_embedder = false
	pub const backend_needs_host = false

	// HeadlessControl is the live state of one mounted control with an id. As on
	// the custom renderer, a declared value replaces the live one only when the
	// declaration changes, so user edits survive unrelated rebuilds.
	pub struct HeadlessControl {
	pub mut:
		kind             Kind
		mounted          bool
		text             string
		declared_text    string
		value            f64
		declared_value   f64
		spec             SliderSpec
		checked          bool
		declared_checked bool
		group            string
		allow_no_selection bool
		caret            int
		selection_length int
	}

	@[heap]
	pub struct HeadlessState {
	pub mut:
		title      string
		viewport   Rect = Rect{ width: 800, height: 600 }
		min_width  int
		min_height int
		safe_area_top f64
		quit_requested bool
		// Counters tests can assert on.
		builds            int
		refresh_requests  int
		element_refreshes int
		refresh_pending   bool
		// Live control state and scroll offsets by element id.
		controls  map[string]HeadlessControl
		scroll_y  map[string]f64
		scroll_x  map[string]f64
		// The last declaration and its resolved, overlay-projected tree.
		declared Element
		root     Element
		layout_error string
	mut:
		build             BuildFn    = unsafe { nil }
		key_handler       KeyFn      = unsafe { nil }
		key_event_handler KeyEventFn = unsafe { nil }
		drop_handler      DropFn     = unsafe { nil }
		key_consumed      bool
		text_key_consumed bool
		rendering         bool
		layout_tree &LayoutTree    = &LayoutTree{}
		overlays    &OverlayTree   = &OverlayTree{}
		navigation  &FocusManager  = &FocusManager{}
		environment LayoutEnvironment
		revision    u64
	}

	__global g_headless = &HeadlessState{}

	// headless_state is the in-memory window tests read and adjust, for example
	// the viewport before run or the counters after an interaction.
	pub fn headless_state() &HeadlessState { return g_headless }

	// headless_reset forgets the window, its handlers and all live state.
	pub fn headless_reset() { g_headless = &HeadlessState{} }

	// headless_frame runs the rebuild a refresh request asked for, as a window's
	// next frame would. It reports whether it built.
	pub fn headless_frame() bool {
		if !g_headless.refresh_pending { return false }
		headless_rebuild()
		return true
	}

	// headless_key delivers a key press the way a window does: to on_key_event,
	// then on_key with its normalized name, then to focus navigation and semantic
	// activation. It reports whether something handled the key.
	pub fn headless_key(event KeyEvent) bool {
		mut h := g_headless
		if voidptr(h.key_event_handler) != unsafe { nil } {
			h.key_consumed = false
			h.key_event_handler(event)
			if h.key_consumed { return true }
		}
		if voidptr(h.key_handler) != unsafe { nil } {
			mut name := event.code.name()
			if name.len > 0 {
				mut modifiers := []string{}
				if event.cmd { modifiers << 'cmd' }
				if event.ctrl { modifiers << 'ctrl' }
				if event.alt { modifiers << 'alt' }
				if event.shift { modifiers << 'shift' }
				if modifiers.len > 0 { name = modifiers.join('+') + '+' + name }
				focused := focused_text_area_id()
				if focused.len > 0 { name = 'text:${focused}:${name}' }
				h.key_consumed = false
				h.key_handler(name)
				if h.key_consumed { return true }
			}
		}
		return handle_focus_key(event, false)
	}

	// headless_drop delivers a drop on the window to the on_drop handler.
	pub fn headless_drop(event DropEvent) {
		h := g_headless
		if voidptr(h.drop_handler) != unsafe { nil } { h.drop_handler(event) }
	}

	pub fn run(build BuildFn) {
		h := g_headless
		run_window_with_min_size(h.title, int(h.viewport.width), int(h.viewport.height), 0, 0, build)
	}

	pub fn run_window(title string, width int, height int, build BuildFn) {
		run_window_with_min_size(title, width, height, 0, 0, build)
	}

	fn run_window_with_min_size(title string, width int, height int, min_width int, min_height int, build BuildFn) {
		mut h := g_headless
		h.title = title
		h.viewport = rect(0, 0, width, height)
		h.min_width = min_width
		h.min_height = min_height
		h.build = build
		h.quit_requested = false
		set_window_wake(backend_invalidate)
		publish_menu_context(title, unsafe { nil })
		install_declared_menus()
		headless_rebuild()
	}

	pub fn quit() { g_headless.quit_requested = true }

	pub fn bounds() Rect { return g_headless.viewport }

	pub fn safe_area_top() f64 { return g_headless.safe_area_top }

	// headless_rebuild builds and renders now. A rebuild asked for while one
	// builds waits for the next headless_frame.
	fn headless_rebuild() {
		mut h := g_headless
		if voidptr(h.build) == unsafe { nil } { return }
		if h.rendering {
			h.refresh_pending = true
			return
		}
		h.rendering = true
		h.refresh_pending = false
		run_due_timers_now()
		declared := h.build()
		h.builds++
		headless_render(declared)
		h.rendering = false
	}

	// request_refresh schedules a rebuild for the next headless_frame.
	pub fn request_refresh() {
		mut h := g_headless
		h.refresh_requests++
		h.refresh_pending = true
	}

	pub fn refresh_element(id string, element Element) {
		mut h := g_headless
		h.element_refreshes++
		h.layout_tree.patch(id, element) or {
			h.layout_error = err.msg()
			return
		}
		headless_mount_layout()
	}

	fn refresh_compiled_element(id string, _node &CompiledVmlNode, element Element) { refresh_compiled_by_id(id, element) }

	fn begin_compiled_snapshot() {}

	fn end_compiled_snapshot() {}

	fn backend_invalidate(_reason RenderReason) { request_refresh() }

	pub fn layout_stats() LayoutStats { return g_headless.layout_tree.stats() }

	pub fn invalidate_layout_environment(environment LayoutEnvironment) {
		mut h := g_headless
		h.environment = environment
		if h.layout_tree.root.len > 0 { headless_mount_layout() }
	}

	fn headless_render(declared Element) {
		mut h := g_headless
		h.declared = declared
		h.layout_tree.replace(declared) or {
			h.layout_error = err.msg()
			return
		}
		headless_mount_layout()
	}

	fn headless_mount_layout() {
		mut h := g_headless
		resolved := h.layout_tree.resolve(LayoutConstraints{}, measure_layout_text, h.environment) or {
			h.layout_error = err.msg()
			return
		}
		mut offsets := map[string]f64{}
		mut offsets_x := map[string]f64{}
		headless_focus_offsets(resolved, presentation_root_path(resolved), mut offsets, mut offsets_x)
		h.revision++
		mut overlays := h.overlays
		overlays.offsets_x = offsets_x.clone()
		overlays.measure = measure_layout_text
		overlays.environment = h.environment
		projected := overlays.resolve(resolved, offsets, h.viewport, h.revision) or {
			h.layout_error = err.msg()
			return
		}
		h.layout_error = ''
		h.root = projected
		for _, mut control in h.controls {
			control.mounted = false
		}
		headless_mount_controls(projected)
		mut manager := h.navigation
		manager.set_root(projected)
		sync_focus_navigation()
	}

	fn headless_mount_controls(el Element) {
		if el.id.len > 0 && el.kind in [.text_field, .text_area, .dropdown, .slider, .checkbox, .switch_control, .toggle_button] {
			mut h := g_headless
			previous := h.controls[el.id] or { HeadlessControl{ kind: el.kind, text: el.text, declared_text: el.text, value: el.value, declared_value: el.value, checked: el.checked, declared_checked: el.checked, caret: text_area_utf16_length(el.text) } }
			mut control := HeadlessControl{ ...previous, kind: el.kind, mounted: true, group: el.toggle_group(), allow_no_selection: el.toggle_allow_no_selection() }
			if previous.kind != el.kind || el.text != previous.declared_text {
				control.text = el.text
				control.caret = text_area_utf16_length(el.text)
				control.selection_length = 0
			}
			control.declared_text = el.text
			if el.kind == .slider {
				control.spec = slider_spec(el)
				if previous.kind != el.kind || el.value != previous.declared_value { control.value = el.value }
				control.value = slider_clamped_value(control.value, control.spec.min, control.spec.max)
				control.declared_value = el.value
			}
			if previous.kind != el.kind || el.checked != previous.declared_checked { control.checked = el.checked }
			control.declared_checked = el.checked
			h.controls[el.id] = control
			if el.kind == .toggle_button && control.checked { headless_release_toggle_group(el.id) }
		}
		for child in el.children { headless_mount_controls(child) }
	}

	fn headless_control(id string, kinds []Kind) ?HeadlessControl {
		control := g_headless.controls[id] or { return none }
		if !control.mounted || control.kind !in kinds { return none }
		return control
	}

	fn headless_focus_offsets(el Element, path string, mut offsets map[string]f64, mut offsets_x map[string]f64) {
		if el.kind == .scroll {
			x, y := scroll_mode_offset(el.scroll_mode, g_headless.scroll_x[el.id] or { 0 }, g_headless.scroll_y[el.id] or { 0 })
			offsets[path] = y
			offsets_x[path] = x
		}
		for i, child in el.children {
			headless_focus_offsets(child, reconciliation_child_key(path, i, child), mut offsets, mut offsets_x)
		}
	}

	// Events from semantic actions reach the element's callback; the model it
	// changes is built on the next headless_frame.
	fn headless_emit(el Element, event ElementEvent) {
		if voidptr(el.on_event) == unsafe { nil } { return }
		el.on_event(event)
		request_refresh()
	}

	pub fn on_key(handler KeyFn) { g_headless.key_handler = handler }

	pub fn on_key_event(handler KeyEventFn) { g_headless.key_event_handler = handler }

	pub fn consume_key() { g_headless.key_consumed = true }

	pub fn consume_text_key() { g_headless.text_key_consumed = true }

	pub fn on_drop(handler DropFn) { g_headless.drop_handler = handler }

	fn backend_input_dispatch() AlwaysValidDispatch { return AlwaysValidDispatch{} }

	fn backend_own_activation(_code KeyCode) {}

	pub fn text(id string) string {
		control := g_headless.controls[id] or { return '' }
		return control.text.clone()
	}

	pub fn set_text(id string, value string) {
		mut control := headless_control(id, [.text_field, .text_area, .dropdown]) or { return }
		control.text = value.clone()
		control.caret = text_area_utf16_length(value)
		control.selection_length = 0
		g_headless.controls[id] = control
	}

	pub fn slider_value(id string) f64 {
		control := g_headless.controls[id] or { return 0 }
		return control.value
	}

	pub fn set_slider_value(id string, value f64) {
		mut control := headless_control(id, [.slider]) or { return }
		control.value = slider_clamped_value(value, control.spec.min, control.spec.max)
		g_headless.controls[id] = control
	}

	pub fn switch_active(id string) bool {
		control := g_headless.controls[id] or { return false }
		return control.kind == .switch_control && control.checked
	}

	pub fn set_switch_active(id string, active bool) {
		mut control := headless_control(id, [.switch_control]) or { return }
		control.checked = active
		g_headless.controls[id] = control
	}

	pub fn toggle_button_pressed(id string) bool {
		control := g_headless.controls[id] or { return false }
		return control.kind == .toggle_button && control.checked
	}

	pub fn set_toggle_button_pressed(id string, pressed bool) {
		mut control := headless_control(id, [.toggle_button]) or { return }
		if pressed { headless_release_toggle_group(id) }
		control.checked = pressed
		g_headless.controls[id] = control
	}

	pub fn toggle_button_group_members(id string) []string {
		control := headless_control(id, [.toggle_button]) or { return [] }
		if control.group.len == 0 { return [id] }
		mut members := []string{}
		for member, other in g_headless.controls {
			if other.mounted && other.kind == .toggle_button && other.group == control.group { members << member }
		}
		return members
	}

	fn headless_release_toggle_group(id string) {
		mut h := g_headless
		group := (h.controls[id] or { return }).group
		if group.len == 0 { return }
		for member, mut other in h.controls {
			if member != id && other.kind == .toggle_button && other.group == group {
				other.checked = false
			}
		}
	}

	pub fn control_checked(id string) bool {
		control := headless_control(id, [.checkbox, .switch_control, .toggle_button]) or { return false }
		return control.checked
	}

	pub fn set_control_checked(id string, value bool) {
		control := headless_control(id, [.checkbox, .switch_control, .toggle_button]) or { return }
		match control.kind {
			.toggle_button { set_toggle_button_pressed(id, value) }
			else { g_headless.controls[id] = HeadlessControl{ ...control, checked: value } }
		}
	}

	// Barcode scanning needs a camera; the scan is cancelled at once.
	pub fn start_barcode_scan(on_result ScanCallback) {
		if voidptr(on_result) != unsafe { nil } { on_result(ScanResult{ kind: .cancelled }) }
	}

	pub fn focused_text_area_id() string {
		id := focused_id()
		control := headless_control(id, [.text_area]) or { return '' }
		return if control.mounted { id } else { '' }
	}

	// insert_text_area_text replaces the selection, or inserts at the caret, and
	// leaves the caret after the inserted text.
	pub fn insert_text_area_text(id string, value string) {
		mut control := headless_control(id, [.text_area]) or { return }
		control.text, control.caret = text_area_replace_selection(control.text, TextAreaSelectionRange{ location: control.caret, length: control.selection_length }, value)
		control.selection_length = 0
		g_headless.controls[id] = control
	}

	pub fn text_area_caret(id string) int {
		control := headless_control(id, [.text_area]) or { return 0 }
		return control.caret
	}

	pub fn text_area_selection_length(id string) int {
		control := headless_control(id, [.text_area]) or { return 0 }
		return control.selection_length
	}

	pub fn text_area_set_caret(id string, pos int) { text_area_set_selection(id, pos, 0) }

	pub fn text_area_set_selection(id string, location int, length int) {
		mut control := headless_control(id, [.text_area]) or { return }
		selection := clamped_text_area_selection(control.text, location, length)
		control.caret = selection.location
		control.selection_length = selection.length
		g_headless.controls[id] = control
	}

	pub fn scroll_offset(id string) f64 { return g_headless.scroll_y[id] or { 0 } }

	pub fn scroll_horizontal_offset(id string) f64 { return g_headless.scroll_x[id] or { 0 } }

	// Offsets are kept for Scrolls that are not mounted yet, which open there.
	pub fn scroll_to_offset(id string, offset f64) {
		if id.len == 0 { return }
		g_headless.scroll_y[id] = math.max(0.0, offset)
		sync_focus_navigation()
	}

	pub fn scroll_to_horizontal_offset(id string, offset f64) {
		if id.len == 0 { return }
		g_headless.scroll_x[id] = math.max(0.0, offset)
		sync_focus_navigation()
	}

	// scroll_to_rect scrolls the least distance that shows the rect, as the
	// windowed backends do.
	pub fn scroll_to_rect(id string, x f64, y f64, width f64, height f64) {
		node := g_headless.navigation.node(id) or { return }
		if node.el.kind != .scroll { return }
		viewport := node.el.frame
		current_y := scroll_offset(id)
		current_x := scroll_horizontal_offset(id)
		g_headless.scroll_y[id] = math.max(0.0, headless_reveal(current_y, viewport.height, y, height))
		g_headless.scroll_x[id] = math.max(0.0, headless_reveal(current_x, viewport.width, x, width))
		sync_focus_navigation()
	}

	fn headless_reveal(offset f64, extent f64, start f64, length f64) f64 {
		if start < offset { return start }
		if start + length > offset + extent { return start + length - extent }
		return offset
	}

	pub fn focus(id string) {
		sync_focus_navigation()
		mut manager := g_headless.navigation
		manager.set_focus(id)
	}

	pub fn focused_id() string { return g_headless.navigation.current }

	pub fn dismiss_keyboard() {
		mut manager := g_headless.navigation
		manager.current = ''
	}

	fn focus_manager() &FocusManager { return g_headless.navigation }

	fn sync_focus_navigation() {
		mut manager := g_headless.navigation
		mut offsets := map[string]f64{}
		mut offsets_x := map[string]f64{}
		headless_focus_offsets(manager.root, presentation_root_path(manager.root), mut offsets, mut offsets_x)
		manager.update_mounted_axes(manager.root, offsets, offsets_x, bounds(), ContentTransform{})
	}

	fn live_semantic_nodes(nodes []SemanticNode) []SemanticNode {
		mut result := []SemanticNode{cap: nodes.len}
		for node in nodes {
			control := headless_control(node.id, [.text_field, .text_area, .dropdown, .slider, .checkbox, .switch_control, .toggle_button]) or {
				result << node
				continue
			}
			focus_node := g_headless.navigation.node(node.id) or {
				result << node
				continue
			}
			el := focus_node.el
			mut value := node.value
			mut checked := node.state.checked
			if el.kind in [.text_field, .text_area, .dropdown] && !el.secure && el.accessibility_value.len == 0 {
				value = control.text.clone()
			}
			if el.kind == .slider && el.accessibility_value.len == 0 { value = control.value.str() }
			if el.kind in [.checkbox, .switch_control, .toggle_button] {
				checked = control.checked
				if el.accessibility_value.len == 0 { value = if checked { 'checked' } else { 'unchecked' } }
			}
			result << SemanticNode{
				...node
				value: value
				state: SemanticState{
					...node.state
					checked:  checked
					selected: el.kind == .toggle_button && checked
				}
			}
		}
		return result
	}

	fn activate_semantic_control(id string, action SemanticAction) bool {
		manager := g_headless.navigation
		node := manager.node(id) or { return false }
		if node.hidden || !node.enabled || !manager.in_scope(node) { return false }
		el := node.el
		if action in [.increment, .decrement] && el.kind == .slider {
			before := slider_value(id)
			value := semantic_slider_step(before, slider_spec(el), action)
			set_slider_value(id, value)
			if value != before { headless_emit(el, ElementEvent{ kind: .change, id: id, value: value }) }
			return true
		}
		if action != .activate || !semantic_activatable(el) { return false }
		match el.kind {
			.checkbox {
				checked := !control_checked(id)
				set_control_checked(id, checked)
				headless_emit(el, ElementEvent{ kind: .change, id: id, checked: checked })
			}
			.switch_control {
				active := !switch_active(id)
				set_switch_active(id, active)
				headless_emit(el, ElementEvent{ kind: .change, id: id, checked: active })
			}
			.toggle_button {
				previous := toggle_button_pressed(id)
				pressed := if el.toggle_group().len > 0 && previous && !el.toggle_allow_no_selection() { true } else { !previous }
				set_toggle_button_pressed(id, pressed)
				headless_emit(el, ElementEvent{ kind: .change, id: id, checked: pressed })
			}
			.dropdown { focus(id) }
			else { headless_emit(el, ElementEvent{ kind: .click, id: id }) }
		}
		return true
	}

	pub fn control_support(_kind Kind) BackendSupport { return .supported }

	pub fn set_visual_transform(id string, transform VisualTransform) ! {
		if id.len == 0 { return error('visual transform updates require an element id') }
		mut h := g_headless
		root, found := replace_visual_transform(h.declared, id, transform)!
		if !found { return error('unknown element `${id}`') }
		h.declared = root
		if h.layout_tree.root.len > 0 {
			h.layout_tree.set_transform(id, transform)!
			headless_mount_layout()
		}
	}

	pub fn mounted_geometry(id string) !VisualGeometry {
		sync_focus_navigation()
		node := g_headless.navigation.node(id) or { return error('element `${id}` has no mounted geometry') }
		if node.hidden { return error('element `${id}` is hidden') }
		return VisualGeometry{
			frame:            node.local_frame
			transform:        node.transform
			parent_transform: node.parent_transform
			clip:             node.clip
		}
	}

	// Nothing is painted, so the presented geometry is the mounted one.
	pub fn visual_geometry(id string) !VisualGeometry { return mounted_geometry(id) }

	pub fn drag_active() bool { return false }

	pub fn cancel_drag() {}

	pub fn image_resource_stats() ImageResourceStats { return ImageResourceStats{} }

	fn backend_measure_text(text string, style TextStyle, max_width f64) !LayoutSize {
		return layout_measure_cpu_text(text, style, max_width)
	}

	fn backend_measure_element_text(element Element, content string, max_width f64) !LayoutSize {
		return measure_layout_text(content, element.text_style, max_width)
	}

	fn backend_control_insets(_element Element) ?LayoutPadding { return none }

	fn backend_layout_environment(environment LayoutEnvironment) LayoutEnvironment { return environment }

	// Menus are kept by menu.v; there is no bar or status area to show them.
	fn backend_menu_bar_supported() bool { return false }

	fn backend_tray_supported() bool { return false }

	fn backend_set_menu_bar(_menus []Menu) {}

	fn backend_set_tray(_cfg TrayConfig) {}

	fn backend_remove_tray() {}

	// No operating system dialog is shown: pickers return no paths and message
	// boxes their dismissal result.
	fn backend_file_dialog(_cfg FileDialogConfig) []string { return [] }

	fn backend_file_dialog_supported() bool { return false }

	fn backend_message_box(cfg MessageBoxConfig) MessageBoxResult { return message_box_default_result(cfg.buttons) }

	fn backend_message_box_supported() bool { return false }
}
