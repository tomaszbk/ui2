module main

import math
import os
import strconv
import ui2

const default_form_width = 760.0
const default_form_height = 520.0
const designer_grid_size = 8.0

pub struct DesignerComponent {
pub mut:
	id            int
	kind          string
	name          string
	text          string
	x             f64
	y             f64
	width         f64
	height        f64
	background    u32
	color         u32 = 0x172033
	font_size     f64 = 14
	checked       bool
	event_handler string
	hidden        bool
}

struct IdeSnapshot {
	components      []DesignerComponent
	selected_id     int
	next_id         int
	form_name       string
	form_width      f64
	form_height     f64
	form_background u32
}

@[heap]
pub struct IdeApp {
pub mut:
	preview_width   f64
	preview_height  f64
	components      []DesignerComponent
	selected_id     int
	next_id         int    = 1
	form_name       string = 'Form1'
	form_width      f64    = default_form_width
	form_height     f64    = default_form_height
	form_background u32    = 0xf8fafc
	project_root    string
	file_path       string
	path_input      string
	active_tab      string = 'designer'
	inspector_tab   string = 'properties'
	armed_kind      string
	source_text     string
	source_modified bool
	source_only     bool
	dirty           bool
	show_grid       bool   = true
	snap_to_grid    bool   = true
	output_open     bool   = true
	status          string = 'Choose a component, then click the form to place it.'
	messages        string
mut:
	preview_build      DesignerPreviewBuild = unsafe { nil }
	preview_node       &ui2.CompiledVmlNode = unsafe { nil }
	preview_libraries  []DesignerPreviewLibrary
	undo_stack         []IdeSnapshot
	redo_stack         []IdeSnapshot
	drag_component_id  int = -1
	drag_mode          string
	drag_grab_x        f64
	drag_grab_y        f64
	drag_checkpointed  bool
	palette_drag_kind  string
	palette_drag_x     f64
	palette_drag_y     f64
	palette_drag_moved bool
}

fn new_ide_app(root string) IdeApp {
	real_root := os.real_path(root)
	mut app := IdeApp{
		project_root: real_root
		path_input:   os.join_path(real_root, 'form.vml')
	}
	app.sync_source()
	app.log('Ready. The form is 760 x 520 logical pixels.')
	return app
}

fn (app &IdeApp) snapshot() IdeSnapshot {
	return IdeSnapshot{
		components:      app.components.clone()
		selected_id:     app.selected_id
		next_id:         app.next_id
		form_name:       app.form_name
		form_width:      app.form_width
		form_height:     app.form_height
		form_background: app.form_background
	}
}

fn (mut app IdeApp) restore(snapshot IdeSnapshot) {
	app.components = snapshot.components.clone()
	app.selected_id = snapshot.selected_id
	app.next_id = snapshot.next_id
	app.reset_preview()
	app.form_name = snapshot.form_name
	app.form_width = snapshot.form_width
	app.form_height = snapshot.form_height
	app.form_background = snapshot.form_background
	app.sync_source()
	app.dirty = true
}

fn (mut app IdeApp) checkpoint() {
	app.undo_stack << app.snapshot()
	if app.undo_stack.len > 100 {
		app.undo_stack.delete(0)
	}
	app.redo_stack = []IdeSnapshot{}
}

fn (mut app IdeApp) undo() {
	if app.undo_stack.len == 0 {
		app.status = 'Nothing to undo.'
		return
	}
	app.redo_stack << app.snapshot()
	previous := app.undo_stack.last()
	app.undo_stack.delete_last()
	app.restore(previous)
	app.status = 'Undid the last designer change.'
	app.log(app.status)
}

fn (mut app IdeApp) redo() {
	if app.redo_stack.len == 0 {
		app.status = 'Nothing to redo.'
		return
	}
	app.undo_stack << app.snapshot()
	next := app.redo_stack.last()
	app.redo_stack.delete_last()
	app.restore(next)
	app.status = 'Redid the designer change.'
	app.log(app.status)
}

fn (mut app IdeApp) log(message string) {
	line := '> ${message}'
	app.messages = if app.messages.len == 0 { line } else { '${app.messages}\n${line}' }
	lines := app.messages.split_into_lines()
	if lines.len > 80 {
		app.messages = lines[lines.len - 80..].join('\n')
	}
}

fn component_title(kind string) string {
	return match kind {
		'label' { 'Label' }
		'button' { 'Button' }
		'text_field' { 'Text field' }
		'text_area' { 'Text area' }
		'checkbox' { 'Checkbox' }
		'dropdown' { 'Dropdown' }
		'view' { 'View' }
		'image' { 'Image' }
		else { kind }
	}
}

fn component_tag(kind string) string {
	return match kind {
		'label' { 'Label' }
		'button' { 'Button' }
		'text_field' { 'TextInput' }
		'text_area' { 'TextArea' }
		'checkbox' { 'Checkbox' }
		'dropdown' { 'Dropdown' }
		'view' { 'View' }
		'image' { 'Image' }
		else { '' }
	}
}

fn tag_component_kind(tag string) string {
	return match tag {
		'Label' { 'label' }
		'Button' { 'button' }
		'TextInput' { 'text_field' }
		'TextArea' { 'text_area' }
		'Checkbox' { 'checkbox' }
		'Dropdown' { 'dropdown' }
		'View' { 'view' }
		'Image' { 'image' }
		else { '' }
	}
}

fn component_default_size(kind string) (f64, f64) {
	return match kind {
		'label' { 120.0, 26.0 }
		'button' { 112.0, 36.0 }
		'text_field' { 190.0, 36.0 }
		'text_area' { 240.0, 108.0 }
		'checkbox' { 150.0, 30.0 }
		'dropdown' { 170.0, 36.0 }
		'view' { 160.0, 100.0 }
		'image' { 120.0, 100.0 }
		else { 120.0, 36.0 }
	}
}

fn component_default_background(kind string) u32 {
	return match kind {
		'button' { u32(0x2563eb) }
		'text_field', 'text_area', 'dropdown' { u32(0xffffff) }
		'view' { u32(0xdbeafe) }
		'image' { u32(0xe2e8f0) }
		else { u32(0xffffff) }
	}
}

fn component_default_text(kind string, ordinal int) string {
	return match kind {
		'label' { 'Label ${ordinal}' }
		'button' { 'Button ${ordinal}' }
		'text_field' { 'Text field ${ordinal}' }
		'text_area' { 'Text area ${ordinal}' }
		'checkbox' { 'Checkbox ${ordinal}' }
		'dropdown' { 'Option 1' }
		'view' { '' }
		'image' { '' }
		else { component_title(kind) }
	}
}

fn component_name_prefix(kind string) string {
	return match kind {
		'text_field' { 'text_field' }
		'text_area' { 'text_area' }
		else { kind }
	}
}

fn (app &IdeApp) component_ordinal(kind string) int {
	mut count := 1
	for component in app.components {
		if component.kind == kind {
			count++
		}
	}
	return count
}

fn (app &IdeApp) find_component_index(id int) int {
	for index, component in app.components {
		if component.id == id {
			return index
		}
	}
	return -1
}

fn (app &IdeApp) selected_component() ?DesignerComponent {
	index := app.find_component_index(app.selected_id)
	if index < 0 {
		return none
	}
	return app.components[index]
}

fn (app &IdeApp) inspector_property_ids() []string {
	if app.inspector_tab == 'layout' {
		return []string{}
	}
	if app.inspector_tab == 'events' {
		return if app.selected_id > 0 { ['property_event'] } else { []string{} }
	}
	if app.selected_id == 0 {
		return [
			'form_property_name',
			'form_property_width',
			'form_property_height',
			'form_property_background',
		]
	}
	return [
		'property_name',
		'property_text',
		'property_x',
		'property_y',
		'property_width',
		'property_height',
		'property_background',
		'property_color',
		'property_font_size',
	]
}

fn (app &IdeApp) adjacent_inspector_property_id(current string, reverse bool) ?string {
	ids := app.inspector_property_ids()
	current_index := ids.index(current)
	if current_index < 0 || ids.len == 0 {
		return none
	}
	next_index := if reverse {
		if current_index == 0 { ids.len - 1 } else { current_index - 1 }
	} else {
		(current_index + 1) % ids.len
	}
	return ids[next_index]
}

fn (app &IdeApp) unique_component_name(kind string) string {
	prefix := component_name_prefix(kind)
	mut ordinal := 1
	for {
		candidate := '${prefix}${ordinal}'
		mut used := false
		for component in app.components {
			if component.name == candidate {
				used = true
				break
			}
		}
		if !used {
			return candidate
		}
		ordinal++
	}
	return '${prefix}${app.next_id}'
}

fn clamp(value f64, low f64, high f64) f64 {
	if high < low {
		return low
	}
	if value < low {
		return low
	}
	return if value > high { high } else { value }
}

fn snap_value(value f64, enabled bool) f64 {
	if !enabled {
		return value
	}
	return math.round(value / designer_grid_size) * designer_grid_size
}

fn snap_clamped(value f64, low f64, high f64, enabled bool) f64 {
	return clamp(snap_value(clamp(value, low, high), enabled), low, high)
}

fn (mut app IdeApp) add_component(kind string, x f64, y f64) int {
	if !app.require_geometry_editable() {
		return -1
	}
	if component_tag(kind).len == 0 {
		return -1
	}
	app.checkpoint()
	width, height := component_default_size(kind)
	ordinal := app.component_ordinal(kind)
	id := app.next_id
	app.next_id++
	component := DesignerComponent{
		id:         id
		kind:       kind
		name:       app.unique_component_name(kind)
		text:       component_default_text(kind, ordinal)
		x:          snap_clamped(x, 0, app.form_width - width, app.snap_to_grid)
		y:          snap_clamped(y, 0, app.form_height - height, app.snap_to_grid)
		width:      width
		height:     height
		background: component_default_background(kind)
		color:      if kind == 'button' { u32(0xffffff) } else { u32(0x172033) }
	}
	app.components << component
	app.selected_id = id
	app.armed_kind = ''
	app.changed('${component_title(kind)} `${component.name}` added.')
	return id
}

fn (mut app IdeApp) duplicate_selected() {
	if !app.require_geometry_editable() {
		return
	}
	index := app.find_component_index(app.selected_id)
	if index < 0 {
		app.status = 'Select a component to duplicate.'
		return
	}
	app.checkpoint()
	original := app.components[index]
	id := app.next_id
	app.next_id++
	duplicate := DesignerComponent{
		...original
		id:   id
		name: app.unique_component_name(original.kind)
		x:    snap_clamped(original.x + 16, 0, app.form_width - original.width, app.snap_to_grid)
		y:    snap_clamped(original.y + 16, 0, app.form_height - original.height, app.snap_to_grid)
	}
	app.components << duplicate
	app.selected_id = id
	app.changed('Duplicated `${original.name}` as `${duplicate.name}`.')
}

fn (mut app IdeApp) delete_selected() {
	index := app.find_component_index(app.selected_id)
	if index < 0 {
		app.status = 'Select a component to delete.'
		return
	}
	app.checkpoint()
	name := app.components[index].name
	app.components.delete(index)
	app.selected_id = 0
	app.changed('Deleted `${name}`.')
}

fn (mut app IdeApp) reorder_selected(to_front bool) {
	index := app.find_component_index(app.selected_id)
	if index < 0 {
		return
	}
	if (to_front && index == app.components.len - 1) || (!to_front && index == 0) {
		return
	}
	app.checkpoint()
	component := app.components[index]
	app.components.delete(index)
	if to_front {
		app.components << component
	} else {
		app.components.insert(0, component)
	}
	app.changed(if to_front {
		'Brought `${component.name}` to front.'
	} else {
		'Sent `${component.name}` to back.'
	})
}

fn (mut app IdeApp) begin_drag(id int, mode string, local_x f64, local_y f64) {
	index := app.find_component_index(id)
	if index < 0 {
		return
	}
	app.selected_id = id
	if !app.require_geometry_editable() { return }
	component := app.components[index]
	app.drag_component_id = id
	app.drag_mode = mode
	app.drag_grab_x = local_x - component.x
	app.drag_grab_y = local_y - component.y
	app.drag_checkpointed = false
	app.status = if mode == 'resize' {
		'Resizing `${component.name}`.'
	} else {
		'Moving `${component.name}`.'
	}
}

fn (mut app IdeApp) drag_to(local_x f64, local_y f64) {
	index := app.find_component_index(app.drag_component_id)
	if index < 0 {
		return
	}
	if !app.drag_checkpointed {
		app.checkpoint()
		app.drag_checkpointed = true
	}
	if !app.require_geometry_editable() { return }
	mut component := app.components[index]
	if app.drag_mode == 'resize' {
		component.width = snap_clamped(local_x - component.x, 32, app.canvas_width() - component.x, app.snap_to_grid)
		component.height = snap_clamped(local_y - component.y, 24, app.canvas_height() - component.y, app.snap_to_grid)
	} else {
		component.x = snap_clamped(local_x - app.drag_grab_x, 0, app.canvas_width() - component.width, app.snap_to_grid)
		component.y = snap_clamped(local_y - app.drag_grab_y, 0, app.canvas_height() - component.height, app.snap_to_grid)
	}
	app.store_geometry(index, component)
	app.dirty = true
	app.sync_source()
}

fn (mut app IdeApp) end_drag() {
	if app.drag_checkpointed {
		component := app.selected_component() or { return }
		app.status = '${component.name}: ${int(component.x)}, ${int(component.y)}, ${int(component.width)} x ${int(component.height)}.'
		app.log(app.status)
	}
	app.drag_component_id = -1
	app.drag_mode = ''
	app.drag_checkpointed = false
}

fn (mut app IdeApp) nudge_selected(dx f64, dy f64) {
	index := app.find_component_index(app.selected_id)
	if index < 0 {
		return
	}
	if !app.require_geometry_editable() { return }
	app.checkpoint()
	if !app.require_geometry_editable() { return }
	mut component := app.components[index]
	component.x = clamp(component.x + dx, 0, app.canvas_width() - component.width)
	component.y = clamp(component.y + dy, 0, app.canvas_height() - component.height)
	app.store_geometry(index, component)
	app.changed('${component.name}: ${int(component.x)}, ${int(component.y)}.')
}

fn valid_identifier(value string) bool {
	if value.len == 0 {
		return false
	}
	for index, c in value.bytes() {
		if !((c >= `a` && c <= `z`) || (c >= `A` && c <= `Z`) || c == `_` || (index > 0 && c >= `0` && c <= `9`)) {
			return false
		}
	}
	return true
}

fn parse_f64_property(raw string) ?f64 {
	trimmed := raw.trim_space()
	if trimmed.len == 0 {
		return none
	}
	value := strconv.atof64(trimmed) or { return none }
	if math.is_nan(value) || math.is_inf(value, 0) { return none }
	return value
}

fn parse_color_property(raw string) ?u32 {
	trimmed := raw.trim_space()
	if trimmed.len != 7 || !trimmed.starts_with('#') {
		return none
	}
	for c in trimmed[1..].bytes() {
		if !((c >= `0` && c <= `9`) || (c >= `a` && c <= `f`) || (c >= `A` && c <= `F`)) {
			return none
		}
	}
	return u32(strconv.parse_uint(trimmed[1..], 16, 32) or { return none })
}

fn color_hex(color u32) string {
	return '#${color:06X}'
}

fn (app &IdeApp) component_name_available(name string, except_id int) bool {
	for component in app.components {
		if component.id != except_id && component.name == name {
			return false
		}
	}
	return true
}

fn (mut app IdeApp) set_component_text_property(field string, value string) bool {
	if field in ['property_x', 'property_y', 'property_width', 'property_height'] {
		return app.set_geometry_property(field, value)
	}
	index := app.find_component_index(app.selected_id)
	if index < 0 {
		return false
	}
	mut component := app.components[index]
	match field {
		'property_name' {
			if !valid_identifier(value) {
				app.status = 'Name must be a V/VML identifier.'
				return false
			}
			if !app.component_name_available(value, component.id) {
				app.status = '`${value}` is already used on this form.'
				return false
			}
			if component.name == value {
				return false
			}
			app.checkpoint()
			component.name = value
		}
		'property_text' {
			if component.text == value {
				return false
			}
			app.checkpoint()
			component.text = value
		}
		'property_event' {
			if value.len > 0 && !valid_identifier(value) {
				app.status = 'Event names must be V/VML identifiers.'
				return false
			}
			if component.event_handler == value {
				return false
			}
			app.checkpoint()
			component.event_handler = value
		}
		'property_font_size' {
			number := parse_f64_property(value) or {
				app.status = 'Enter a finite numeric value.'
				return false
			}
			app.checkpoint()
			component.font_size = clamp(number, 8, 72)
		}
		'property_background', 'property_color' {
			color := parse_color_property(value) or {
				app.status = 'Colors use #RRGGBB.'
				return false
			}
			app.checkpoint()
			if field == 'property_background' {
				component.background = color
			} else {
				component.color = color
			}
		}
		else {
			return false
		}
	}
	app.components[index] = component
	app.changed('Updated `${component.name}`.')
	return true
}

fn (mut app IdeApp) toggle_selected_checked() {
	index := app.find_component_index(app.selected_id)
	if index < 0 || app.components[index].kind != 'checkbox' {
		return
	}
	app.checkpoint()
	app.components[index].checked = !app.components[index].checked
	app.changed('Updated `${app.components[index].name}`.')
}

fn (mut app IdeApp) set_form_property(field string, value string) bool {
	match field {
		'form_property_name' {
			if !valid_identifier(value) {
				app.status = 'Form name must be a V/VML identifier.'
				return false
			}
			if app.form_name == value {
				return false
			}
			app.checkpoint()
			app.form_name = value
		}
		'form_property_width', 'form_property_height' {
			number := parse_f64_property(value) or {
				app.status = 'Enter a numeric form size.'
				return false
			}
			app.checkpoint()
			if field == 'form_property_width' {
				app.resize_design_canvas(clamp(number, 320, 1920), app.form_height)
			} else {
				app.resize_design_canvas(app.form_width, clamp(number, 240, 1200))
			}
		}
		'form_property_background' {
			color := parse_color_property(value) or {
				app.status = 'Colors use #RRGGBB.'
				return false
			}
			if app.form_background == color {
				return false
			}
			app.checkpoint()
			app.form_background = color
		}
		else {
			return false
		}
	}
	app.changed('Updated form properties.')
	return true
}

fn (mut app IdeApp) keep_components_on_form() {
	for index, item in app.components {
		mut component := item
		component.width = clamp(component.width, 32, app.form_width)
		component.height = clamp(component.height, 24, app.form_height)
		component.x = clamp(component.x, 0, app.form_width - component.width)
		component.y = clamp(component.y, 0, app.form_height - component.height)
		app.components[index] = component
	}
}

fn (mut app IdeApp) changed(message string) {
	app.dirty = true
	app.sync_source()
	app.status = message
	app.log(message)
}

fn vml_escape(value string) string {
	return value.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n').replace('\t', '\\t')
}

fn component_vml(component DesignerComponent) string {
	tag := component_tag(component.kind)
	mut properties := [
		'id: "${component.name}"',
		'x: ${component.x:g}',
		'y: ${component.y:g}',
		'width: ${component.width:g}',
		'height: ${component.height:g}',
	]
	if component.hidden { properties << 'hidden: true' }
	match component.kind {
		'label' {
			properties << 'text: "${vml_escape(component.text)}"'
			properties << 'color: ${color_hex(component.color)}'
			properties << 'font_size: ${component.font_size:g}'
		}
		'button' {
			properties << 'text: "${vml_escape(component.text)}"'
			properties << 'background: ${color_hex(component.background)}'
			properties << 'color: ${color_hex(component.color)}'
			properties << 'font_size: ${component.font_size:g}'
			properties << 'corner_radius: 6'
		}
		'text_field' {
			properties << 'placeholder: "${vml_escape(component.text)}"'
			properties << 'background: ${color_hex(component.background)}'
			properties << 'color: ${color_hex(component.color)}'
			properties << 'font_size: ${component.font_size:g}'
			properties << 'corner_radius: 5'
		}
		'text_area' {
			properties << 'text: "${vml_escape(component.text)}"'
			properties << 'background: ${color_hex(component.background)}'
			properties << 'color: ${color_hex(component.color)}'
			properties << 'font_size: ${component.font_size:g}'
			properties << 'corner_radius: 5'
		}
		'checkbox' {
			properties << 'text: "${vml_escape(component.text)}"'
			properties << 'checked: ${component.checked}'
			properties << 'color: ${color_hex(component.color)}'
			properties << 'font_size: ${component.font_size:g}'
		}
		'dropdown' {
			properties << 'text: "${vml_escape(component.text)}"'
			properties << 'background: ${color_hex(component.background)}'
			properties << 'color: ${color_hex(component.color)}'
			properties << 'font_size: ${component.font_size:g}'
		}
		'view' {
			properties << 'background: ${color_hex(component.background)}'
			properties << 'corner_radius: 4'
		}
		'image' {
			if component.text.len > 0 {
				properties << 'source: "${vml_escape(component.text)}"'
			}
		}
		else {}
	}
	if component.event_handler.len > 0 {
		event_property := if component.kind in ['text_field', 'text_area', 'dropdown'] {
			'on_change'
		} else {
			'on_tap'
		}
		properties << '${event_property}: ${component.event_handler}'
		if component.kind in ['label', 'view', 'image'] {
			properties << 'clickable: true'
		}
	}
	attributes := properties.join(', ')
	if component.kind == 'dropdown' {
		return '    ${tag}(${attributes}) {\n        Option(text: "Option 1")\n        Option(text: "Option 2")\n        Option(text: "Option 3")\n    }'
	}
	return '    ${tag}(${attributes})'
}

fn generate_vml(app &IdeApp) string {
	mut lines := [
		'// Generated by the ui2 visual IDE.',
		'Screen(id: "${app.form_name}", width: ${app.form_width:g}, height: ${app.form_height:g}, background: ${color_hex(app.form_background)}) {',
		'    Absolute {',
	]
	for component in app.components {
		lines << component_vml(component).split_into_lines().map('    ' + it).join('\n')
	}
	lines << '    }'
	lines << '}'
	return lines.join('\n') + '\n'
}

fn (mut app IdeApp) sync_source() {
	app.source_text = generate_vml(app)
	app.source_modified = false
	app.source_only = false
}

fn node_number(node &DesignerNode, key string, fallback f64) !f64 {
	raw := node.prop(key)
	if raw.len == 0 {
		return fallback
	}
	return parse_f64_property(raw) or { return error('`${key}` on `${node.id}` must be a plain finite number') }
}

fn node_color(node &DesignerNode, key string, fallback u32) !u32 {
	raw := node.prop(key)
	if raw.len == 0 {
		return fallback
	}
	return parse_color_property(raw) or { return error('`${key}` on `${node.id}` must use #RRGGBB') }
}

fn component_from_node(node &DesignerNode, id int) !DesignerComponent {
	kind := tag_component_kind(node.tag)
	if kind.len == 0 {
		return error('unsupported designer component `${node.tag}`')
	}
	default_width, default_height := component_default_size(kind)
	name := if node.id.len > 0 { node.id } else { '${component_name_prefix(kind)}${id}' }
	if !valid_identifier(name) {
		return error('`${name}` is not a valid component id')
	}
	for child in node.children {
		if node.tag != 'Dropdown' || child.tag != 'Option' {
			return error('nested `${child.tag}` inside `${name}` is not editable by the visual designer')
		}
	}
	mut text := node.prop('text')
	if kind == 'text_field' {
		text = node.prop_or('placeholder', text)
	} else if kind == 'image' {
		text = node.prop_or('source', node.prop('path'))
	}
	if node_number(node, 'width', default_width)! < 0 || node_number(node, 'height', default_height)! < 0 {
		return error('designer control dimensions must be non-negative')
	}
	return DesignerComponent{
		hidden:        node.prop_bool('hidden')
		id:            id
		kind:          kind
		name:          name
		text:          text
		x:             node_number(node, 'x', 0)!
		y:             node_number(node, 'y', 0)!
		width:         node_number(node, 'width', default_width)!
		height:        node_number(node, 'height', default_height)!
		background:    node_color(node, 'background', component_default_background(kind))!
		color:         node_color(node, 'color', if kind == 'button' {
			u32(0xffffff)
		} else {
			u32(0x172033)
		})!
		font_size:     node_number(node, 'font_size', 14)!
		checked:       node.prop_bool('checked')
		event_handler: if kind in ['text_field', 'text_area', 'dropdown'] {
			node.prop('on_change')
		} else {
			node.prop('on_tap')
		}
	}
}

fn document_from_vml(source string) !IdeSnapshot {
	root := designer_document(source)!
	if root.tag != 'Screen' {
		return error('the designer expects a Screen root')
	}
	mut components := []DesignerComponent{}
	mut names := map[string]bool{}
	content := root.children.filter(it.tag != 'MenuItem' && it.tag != 'Option')
	if content.len != 1 || content[0].tag != 'Absolute' {
		return error('the designer expects one Absolute canvas inside Screen')
	}
	for child in content[0].children {
		if child.tag in ['MenuItem', 'Option'] {
			continue
		}
		kind := tag_component_kind(child.tag)
		if kind.len == 0 {
			return error('`${child.tag}` is not yet editable by the visual designer')
		}
		component := component_from_node(child, components.len + 1)!
		if component.name in names {
			return error('duplicate component id `${component.name}`')
		}
		names[component.name] = true
		components << component
	}
	form_name := root.prop_or('id', 'Form1')
	if !valid_identifier(form_name) {
		return error('`${form_name}` is not a valid form id')
	}
	width := node_number(root, 'width', default_form_width)!
	height := node_number(root, 'height', default_form_height)!
	if width <= 0 || height <= 0 {
		return error('form dimensions must be positive')
	}
	return IdeSnapshot{
		components:      components
		selected_id:     0
		next_id:         components.len + 1
		form_name:       form_name
		form_width:      width
		form_height:     height
		form_background: node_color(root, 'background', 0xf8fafc)!
	}
}

fn (mut app IdeApp) apply_source(source string) ! {
	document := document_from_vml(source)!
	app.checkpoint()
	app.restore(document)
	app.reset_preview()
	app.source_text = generate_vml(app)
	app.source_modified = false
	app.source_only = false
	app.active_tab = 'designer'
	app.inspector_tab = 'properties'
	app.status = 'Source applied to the visual designer.'
	app.log(app.status)
}

fn resolve_vml_path(raw_path string, root string) !string {
	trimmed := raw_path.trim_space()
	if trimmed.len == 0 {
		return error('enter a .vml file path')
	}
	mut path := if os.is_abs_path(trimmed) { trimmed } else { os.join_path(root, trimmed) }
	if os.is_dir(path) {
		mut names := os.ls(path)!
		names.sort()
		for name in names {
			if os.file_ext(name).to_lower() == '.vml' {
				return os.real_path(os.join_path(path, name))
			}
		}
		return error('no .vml files found in `${path}`')
	}
	if os.file_ext(path).len == 0 {
		path += '.vml'
	}
	return os.real_path(path)
}

fn (mut app IdeApp) open_document(raw_path string) ! {
	path := resolve_vml_path(raw_path, app.project_root)!
	source := os.read_file(path)!
	if document := document_from_vml(source) {
		app.restore(document)
		app.source_only = false
	} else {
		app.components.clear()
		app.selected_id = 0
		app.source_only = true
		app.active_tab = 'source'
		app.log('Opened in source mode: ${err}')
	}
	app.reset_preview()
	app.file_path = path
	app.path_input = path
	app.project_root = os.dir(path)
	app.source_text = source
	app.source_modified = false
	app.undo_stack = []IdeSnapshot{}
	app.redo_stack = []IdeSnapshot{}
	app.dirty = false
	app.status = 'Opened ${os.file_name(path)}.'
	app.log(app.status)
}

fn (mut app IdeApp) save_document() !string {
	path := resolve_vml_path(app.path_input, app.project_root)!
	if app.file_path.len == 0 && os.exists(path) {
		return error('`${path}` already exists; open it first or choose another path')
	}
	os.mkdir_all(os.dir(path))!
	if app.source_modified { app.source_only = true }
	if !app.source_only && !app.source_modified { app.sync_source() }
	os.write_file(path, app.source_text)!
	app.file_path = path
	app.path_input = path
	app.project_root = os.dir(path)
	app.source_modified = false
	app.dirty = false
	app.status = 'Saved ${os.file_name(path)}.'
	app.log(app.status)
	return path
}

fn companion_main_source(app &IdeApp, vml_name string) string {
	mut actions := []string{}
	for component in app.components {
		if component.event_handler.len > 0 && component.event_handler !in actions {
			actions << component.event_handler
		}
	}
	mut handlers := ''
	mut connections := ''
	for action in actions {
		handlers += "fn handle_${action}(event ui2.ElementEvent) { println('Action ${vml_escape(action)}: \${event.kind} on \${event.id}') }\n\n"
		connections += '\t${action} := handle_${action}\n'
	}
	return "module main\n\nimport ui2\n\npub struct FormApp {}\n\n${handlers}fn build_form(mut app FormApp) ui2.Element {\n${connections}\treturn \$vml('${vml_escape(vml_name)}')\n}\n\nfn main() {\n\tui2.run_compiled_vml[FormApp](\n\t\tmodel: &FormApp{}\n\t\tbuild: build_form\n\t\ttitle: '${vml_escape(app.form_name)}'\n\t\twidth: ${int(app.form_width)}\n\t\theight: ${int(app.form_height)}\n\t) or { panic(err) }\n}\n"
}

fn (mut app IdeApp) generate_companion(overwrite bool) !string {
	vml_path := if app.file_path.len > 0 { app.file_path } else { app.save_document()! }
	main_path := os.join_path(os.dir(vml_path), 'main.v')
	if os.exists(main_path) && !overwrite {
		return error('`${main_path}` already exists; it was left unchanged')
	}
	os.write_file(main_path, companion_main_source(app, os.file_name(vml_path)))!
	app.status = 'Generated ${main_path}.'
	app.log(app.status)
	return main_path
}

fn (mut app IdeApp) new_document() {
	app.reset_preview()
	app.components = []DesignerComponent{}
	app.selected_id = 0
	app.next_id = 1
	app.form_name = 'Form1'
	app.form_width = default_form_width
	app.form_height = default_form_height
	app.form_background = 0xf8fafc
	app.file_path = ''
	app.path_input = os.join_path(app.project_root, 'form.vml')
	app.active_tab = 'designer'
	app.armed_kind = ''
	app.source_modified = false
	app.undo_stack = []IdeSnapshot{}
	app.redo_stack = []IdeSnapshot{}
	app.dirty = false
	app.sync_source()
	app.status = 'New Form1 created.'
	app.log(app.status)
}
