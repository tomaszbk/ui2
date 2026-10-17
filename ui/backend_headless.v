// vfmt off
// The headless backend (backend.v): the contract with in-memory windows,
// selected by -d ui2_headless on every OS. A window builds its first frame as
// it opens, and App.run returns at once. Tests then drive a window through
// its public methods and the headless_* methods below: headless_frame
// rebuilds after a refresh request, headless_key delivers a key press, and
// the window's public fields expose the counters and live control values.
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

	// Window is a window kept in memory: its declaration, resolved tree and
	// live control state. The fields under `pub mut` are what tests read and
	// adjust, for example the viewport or the counters after an interaction.
	@[heap]
	pub struct Window {
	pub mut:
		title      string
		viewport   Rect = Rect{ width: 800, height: 600 }
		min_width  int
		min_height int
		safe_area f64
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
		app               &App       = unsafe { nil }
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
		close_hooks []fn ()
		menus       MenuDeclarations
		timers      &TimerRuntime = &TimerRuntime{}
		// The modifier keys key_modifiers reports where the OS has none.
		event_modifiers KeyModifiers
	}

	fn (mut app App) open_backend_window(config WindowConfig) !&Window {
		mut w := &Window{
			app: app
			title: config.title
			viewport: rect(0, 0, config.width, config.height)
			min_width: config.min_width
			min_height: config.min_height
			build: config.build
		}
		w.install_declared_menus()
		w.headless_rebuild()
		return w
	}

	fn (mut app App) run_backend() {}

	fn (mut w Window) on_close(hook fn ()) { w.close_hooks << hook }

	// headless_frame runs the rebuild a refresh request asked for, as a window's
	// next frame would. It reports whether it built.
	pub fn (mut w Window) headless_frame() bool {
		if !w.refresh_pending { return false }
		w.headless_rebuild()
		return true
	}

	// headless_key delivers a key press the way a window does: to the focused
	// element keys, to on_key_event, then on_key with its normalized name, then
	// to focus navigation and semantic activation. It reports whether something handled the key.
	pub fn (mut w Window) headless_key(event KeyEvent) bool {
		key := KeyEvent{ ...event, window: w }
		if w.element_key(key, false) { return true }
		if voidptr(w.key_event_handler) != unsafe { nil } {
			w.key_consumed = false
			w.key_event_handler(key)
			if w.key_consumed { return true }
		}
		if voidptr(w.key_handler) != unsafe { nil } {
			mut name := key.code.name()
			if name.len > 0 {
				mut modifiers := []string{}
				if key.cmd { modifiers << 'cmd' }
				if key.ctrl { modifiers << 'ctrl' }
				if key.alt { modifiers << 'alt' }
				if key.shift { modifiers << 'shift' }
				if modifiers.len > 0 { name = modifiers.join('+') + '+' + name }
				focused := w.focused_text_area_id()
				if focused.len > 0 { name = 'text:${focused}:${name}' }
				w.key_consumed = false
				w.key_handler(mut w, name)
				if w.key_consumed { return true }
			}
		}
		return w.handle_focus_key(key, false)
	}

	// headless_drop delivers a drop on the window to the on_drop handler.
	pub fn (mut w Window) headless_drop(event DropEvent) {
		if voidptr(w.drop_handler) != unsafe { nil } { w.drop_handler(DropEvent{ ...event, window: w }) }
	}

	// quit closes the window as a host would: its close hooks run once, and
	// its app forgets it. Its state stays readable.
	pub fn (mut w Window) quit() {
		if w.quit_requested { return }
		w.quit_requested = true
		hooks := w.close_hooks.clone()
		w.close_hooks.clear()
		for hook in hooks { hook() }
		if w.app != unsafe { nil } {
			mut app := w.app
			app.forget_window(w)
		}
	}

	pub fn (mut w Window) bounds() Rect { return w.viewport }

	pub fn (mut w Window) safe_area_top() f64 { return w.safe_area }

	// headless_rebuild builds and renders now. A rebuild asked for while one
	// builds waits for the next headless_frame.
	fn (mut w Window) headless_rebuild() {
		if voidptr(w.build) == unsafe { nil } { return }
		if w.rendering {
			w.refresh_pending = true
			return
		}
		w.rendering = true
		w.refresh_pending = false
		w.run_due_timers()
		declared := w.build(mut w)
		w.builds++
		w.headless_render(declared)
		w.rendering = false
	}

	// request_refresh schedules a rebuild for the next headless_frame.
	pub fn (mut w Window) request_refresh() {
		w.refresh_requests++
		w.refresh_pending = true
	}

	pub fn (mut w Window) refresh_element(id string, element Element) {
		w.element_refreshes++
		w.layout_tree.patch(id, element) or {
			w.layout_error = err.msg()
			return
		}
		w.headless_mount_layout()
	}

	fn (mut w Window) refresh_compiled_element(id string, _node &CompiledVmlNode, element Element) { w.refresh_compiled_by_id(id, element) }

	fn (mut w Window) begin_compiled_snapshot() {}

	fn (mut w Window) end_compiled_snapshot() {}

	fn (mut w Window) backend_invalidate(_reason RenderReason) { w.request_refresh() }

	pub fn (mut w Window) layout_stats() LayoutStats { return w.layout_tree.stats() }

	pub fn (mut w Window) invalidate_layout_environment(environment LayoutEnvironment) {
		w.environment = environment
		if w.layout_tree.root.len > 0 { w.headless_mount_layout() }
	}

	fn (mut w Window) headless_render(declared Element) {
		w.declared = declared
		w.layout_tree.replace(declared) or {
			w.layout_error = err.msg()
			return
		}
		w.headless_mount_layout()
	}

	fn (mut w Window) headless_mount_layout() {
		resolved := w.layout_tree.resolve(LayoutConstraints{}, measure_layout_text, w.environment) or {
			w.layout_error = err.msg()
			return
		}
		mut offsets := map[string]f64{}
		mut offsets_x := map[string]f64{}
		w.headless_focus_offsets(resolved, presentation_root_path(resolved), mut offsets, mut offsets_x)
		w.revision++
		mut overlays := w.overlays
		overlays.offsets_x = offsets_x.clone()
		overlays.measure = measure_layout_text
		overlays.environment = w.environment
		projected := overlays.resolve(resolved, offsets, w.viewport, w.revision) or {
			w.layout_error = err.msg()
			return
		}
		w.layout_error = ''
		w.root = projected
		for _, mut control in w.controls {
			control.mounted = false
		}
		w.headless_mount_controls(projected)
		mut manager := w.navigation
		manager.set_root(projected)
		w.sync_focus_navigation()
	}

	fn (mut w Window) headless_mount_controls(el Element) {
		if el.id.len > 0 && el.kind in [.text_field, .text_area, .dropdown, .slider, .checkbox, .switch_control, .toggle_button] {
			previous := w.controls[el.id] or { HeadlessControl{ kind: el.kind, text: el.text, declared_text: el.text, value: el.value, declared_value: el.value, checked: el.checked, declared_checked: el.checked, caret: text_area_utf16_length(el.text) } }
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
			w.controls[el.id] = control
			if el.kind == .toggle_button && control.checked { w.headless_release_toggle_group(el.id) }
		}
		for child in el.children { w.headless_mount_controls(child) }
	}

	fn (mut w Window) headless_control(id string, kinds []Kind) ?HeadlessControl {
		control := w.controls[id] or { return none }
		if !control.mounted || control.kind !in kinds { return none }
		return control
	}

	fn (mut w Window) headless_focus_offsets(el Element, path string, mut offsets map[string]f64, mut offsets_x map[string]f64) {
		if el.kind == .scroll {
			x, y := scroll_mode_offset(el.scroll_mode, w.scroll_x[el.id] or { 0 }, w.scroll_y[el.id] or { 0 })
			offsets[path] = y
			offsets_x[path] = x
		}
		for i, child in el.children {
			w.headless_focus_offsets(child, reconciliation_child_key(path, i, child), mut offsets, mut offsets_x)
		}
	}

	// Events from semantic actions reach the element's callback; the model it
	// changes is built on the next headless_frame.
	fn (mut w Window) headless_emit(el Element, event ElementEvent) {
		if voidptr(el.on_event) == unsafe { nil } { return }
		el.on_event(ElementEvent{ ...event, window: w })
		w.request_refresh()
	}

	pub fn (mut w Window) on_key(handler KeyFn) { w.key_handler = handler }

	pub fn (mut w Window) on_key_event(handler KeyEventFn) { w.key_event_handler = handler }

	pub fn (mut w Window) consume_key() { w.key_consumed = true }

	pub fn (mut w Window) consume_text_key() { w.text_key_consumed = true }

	pub fn (mut w Window) on_drop(handler DropFn) { w.drop_handler = handler }

	fn (mut w Window) backend_input_dispatch() AlwaysValidDispatch { return AlwaysValidDispatch{} }

	fn (mut w Window) backend_own_activation(_code KeyCode) {}

	pub fn (mut w Window) text(id string) string {
		control := w.controls[id] or { return '' }
		return control.text.clone()
	}

	pub fn (mut w Window) set_text(id string, value string) {
		mut control := w.headless_control(id, [.text_field, .text_area, .dropdown]) or { return }
		control.text = value.clone()
		control.caret = text_area_utf16_length(value)
		control.selection_length = 0
		w.controls[id] = control
	}

	pub fn (mut w Window) slider_value(id string) f64 {
		control := w.controls[id] or { return 0 }
		return control.value
	}

	pub fn (mut w Window) set_slider_value(id string, value f64) {
		mut control := w.headless_control(id, [.slider]) or { return }
		control.value = slider_clamped_value(value, control.spec.min, control.spec.max)
		w.controls[id] = control
	}

	pub fn (mut w Window) switch_active(id string) bool {
		control := w.controls[id] or { return false }
		return control.kind == .switch_control && control.checked
	}

	pub fn (mut w Window) set_switch_active(id string, active bool) {
		mut control := w.headless_control(id, [.switch_control]) or { return }
		control.checked = active
		w.controls[id] = control
	}

	pub fn (mut w Window) toggle_button_pressed(id string) bool {
		control := w.controls[id] or { return false }
		return control.kind == .toggle_button && control.checked
	}

	pub fn (mut w Window) set_toggle_button_pressed(id string, pressed bool) {
		mut control := w.headless_control(id, [.toggle_button]) or { return }
		if pressed { w.headless_release_toggle_group(id) }
		control.checked = pressed
		w.controls[id] = control
	}

	pub fn (mut w Window) toggle_button_group_members(id string) []string {
		control := w.headless_control(id, [.toggle_button]) or { return [] }
		if control.group.len == 0 { return [id] }
		mut members := []string{}
		for member, other in w.controls {
			if other.mounted && other.kind == .toggle_button && other.group == control.group { members << member }
		}
		return members
	}

	fn (mut w Window) headless_release_toggle_group(id string) {
		group := (w.controls[id] or { return }).group
		if group.len == 0 { return }
		for member, mut other in w.controls {
			if member != id && other.kind == .toggle_button && other.group == group {
				other.checked = false
			}
		}
	}

	pub fn (mut w Window) control_checked(id string) bool {
		control := w.headless_control(id, [.checkbox, .switch_control, .toggle_button]) or { return false }
		return control.checked
	}

	pub fn (mut w Window) set_control_checked(id string, value bool) {
		control := w.headless_control(id, [.checkbox, .switch_control, .toggle_button]) or { return }
		match control.kind {
			.toggle_button { w.set_toggle_button_pressed(id, value) }
			else { w.controls[id] = HeadlessControl{ ...control, checked: value } }
		}
	}

	// Barcode scanning needs a camera; the scan is cancelled at once.
	pub fn start_barcode_scan(on_result ScanCallback) {
		if voidptr(on_result) != unsafe { nil } { on_result(ScanResult{ kind: .cancelled }) }
	}

	pub fn (mut w Window) focused_text_area_id() string {
		id := w.focused_id()
		control := w.headless_control(id, [.text_area]) or { return '' }
		return if control.mounted { id } else { '' }
	}

	// insert_text_area_text replaces the selection, or inserts at the caret, and
	// leaves the caret after the inserted text.
	pub fn (mut w Window) insert_text_area_text(id string, value string) {
		mut control := w.headless_control(id, [.text_area]) or { return }
		control.text, control.caret = text_area_replace_selection(control.text, TextAreaSelectionRange{ location: control.caret, length: control.selection_length }, value)
		control.selection_length = 0
		w.controls[id] = control
	}

	pub fn (mut w Window) text_area_caret(id string) int {
		control := w.headless_control(id, [.text_area]) or { return 0 }
		return control.caret
	}

	pub fn (mut w Window) text_area_selection_length(id string) int {
		control := w.headless_control(id, [.text_area]) or { return 0 }
		return control.selection_length
	}

	pub fn (mut w Window) text_area_set_caret(id string, pos int) { w.text_area_set_selection(id, pos, 0) }

	pub fn (mut w Window) text_area_set_selection(id string, location int, length int) {
		mut control := w.headless_control(id, [.text_area]) or { return }
		selection := clamped_text_area_selection(control.text, location, length)
		control.caret = selection.location
		control.selection_length = selection.length
		w.controls[id] = control
	}

	pub fn (mut w Window) scroll_offset(id string) f64 { return w.scroll_y[id] or { 0 } }

	pub fn (mut w Window) scroll_horizontal_offset(id string) f64 { return w.scroll_x[id] or { 0 } }

	// Offsets are kept for Scrolls that are not mounted yet, which open there.
	pub fn (mut w Window) scroll_to_offset(id string, offset f64) {
		if id.len == 0 { return }
		w.scroll_y[id] = math.max(0.0, offset)
		w.sync_focus_navigation()
	}

	pub fn (mut w Window) scroll_to_horizontal_offset(id string, offset f64) {
		if id.len == 0 { return }
		w.scroll_x[id] = math.max(0.0, offset)
		w.sync_focus_navigation()
	}

	// scroll_to_rect scrolls the least distance that shows the rect, as the
	// windowed backends do.
	pub fn (mut w Window) scroll_to_rect(id string, x f64, y f64, width f64, height f64) {
		node := w.navigation.node(id) or { return }
		if node.el.kind != .scroll { return }
		viewport := node.el.frame
		current_y := w.scroll_offset(id)
		current_x := w.scroll_horizontal_offset(id)
		w.scroll_y[id] = math.max(0.0, headless_reveal(current_y, viewport.height, y, height))
		w.scroll_x[id] = math.max(0.0, headless_reveal(current_x, viewport.width, x, width))
		w.sync_focus_navigation()
	}

	fn headless_reveal(offset f64, extent f64, start f64, length f64) f64 {
		if start < offset { return start }
		if start + length > offset + extent { return start + length - extent }
		return offset
	}

	pub fn (mut w Window) focus(id string) {
		w.sync_focus_navigation()
		mut manager := w.navigation
		manager.set_focus(id)
	}

	pub fn (mut w Window) focused_id() string { return w.navigation.current }

	pub fn (mut w Window) dismiss_keyboard() {
		mut manager := w.navigation
		manager.current = ''
	}

	fn (mut w Window) focus_manager() &FocusManager { return w.navigation }

	fn (mut w Window) sync_focus_navigation() {
		mut manager := w.navigation
		mut offsets := map[string]f64{}
		mut offsets_x := map[string]f64{}
		w.headless_focus_offsets(manager.root, presentation_root_path(manager.root), mut offsets, mut offsets_x)
		manager.update_mounted_axes(manager.root, offsets, offsets_x, w.bounds(), ContentTransform{})
	}

	fn (mut w Window) live_semantic_nodes(nodes []SemanticNode) []SemanticNode {
		mut result := []SemanticNode{cap: nodes.len}
		for node in nodes {
			control := w.headless_control(node.id, [.text_field, .text_area, .dropdown, .slider, .checkbox, .switch_control, .toggle_button]) or {
				result << node
				continue
			}
			focus_node := w.navigation.node(node.id) or {
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

	fn (mut w Window) activate_semantic_control(id string, action SemanticAction) bool {
		manager := w.navigation
		node := manager.node(id) or { return false }
		if node.hidden || !node.enabled || !manager.in_scope(node) { return false }
		el := node.el
		if action in [.increment, .decrement] && el.kind == .slider {
			before := w.slider_value(id)
			value := semantic_slider_step(before, slider_spec(el), action)
			w.set_slider_value(id, value)
			if value != before { w.headless_emit(el, ElementEvent{ kind: .change, id: id, value: value }) }
			return true
		}
		if action != .activate || !semantic_activatable(el) { return false }
		match el.kind {
			.checkbox {
				checked := !w.control_checked(id)
				w.set_control_checked(id, checked)
				w.headless_emit(el, ElementEvent{ kind: .change, id: id, checked: checked })
			}
			.switch_control {
				active := !w.switch_active(id)
				w.set_switch_active(id, active)
				w.headless_emit(el, ElementEvent{ kind: .change, id: id, checked: active })
			}
			.toggle_button {
				previous := w.toggle_button_pressed(id)
				pressed := if el.toggle_group().len > 0 && previous && !el.toggle_allow_no_selection() { true } else { !previous }
				w.set_toggle_button_pressed(id, pressed)
				w.headless_emit(el, ElementEvent{ kind: .change, id: id, checked: pressed })
			}
			.dropdown { w.focus(id) }
			else { w.headless_emit(el, ElementEvent{ kind: .click, id: id }) }
		}
		return true
	}

	pub fn control_support(_kind Kind) BackendSupport { return .supported }

	pub fn (mut w Window) set_visual_transform(id string, transform VisualTransform) ! {
		if id.len == 0 { return error('visual transform updates require an element id') }
		root, found := replace_visual_transform(w.declared, id, transform)!
		if !found { return error('unknown element `${id}`') }
		w.declared = root
		if w.layout_tree.root.len > 0 {
			w.layout_tree.set_transform(id, transform)!
			w.headless_mount_layout()
		}
	}

	pub fn (mut w Window) mounted_geometry(id string) !VisualGeometry {
		w.sync_focus_navigation()
		node := w.navigation.node(id) or { return error('element `${id}` has no mounted geometry') }
		if node.hidden { return error('element `${id}` is hidden') }
		return VisualGeometry{
			frame:            node.local_frame
			transform:        node.transform
			parent_transform: node.parent_transform
			clip:             node.clip
		}
	}

	// Nothing is painted, so the presented geometry is the mounted one.
	pub fn (mut w Window) visual_geometry(id string) !VisualGeometry { return w.mounted_geometry(id) }

	pub fn (mut w Window) drag_active() bool { return false }

	pub fn (mut w Window) cancel_drag() {}

	pub fn (mut w Window) image_resource_stats() ImageResourceStats { return ImageResourceStats{} }

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

	fn (mut w Window) backend_set_menu_bar(_menus []Menu) {}

	fn (mut w Window) backend_set_tray(_cfg TrayConfig) {}

	fn (mut w Window) backend_remove_tray() {}

	// The window is in memory, so the host has no native one to change.
	fn (w &Window) backend_native_window() voidptr { return unsafe { nil } }

	// No operating system dialog is shown: pickers return no paths and message
	// boxes their dismissal result.
	fn backend_file_dialog(_cfg FileDialogConfig) []string { return [] }

	fn backend_file_dialog_supported() bool { return false }

	fn backend_message_box(cfg MessageBoxConfig) MessageBoxResult { return message_box_default_result(cfg.buttons) }

	fn backend_message_box_supported() bool { return false }
}
