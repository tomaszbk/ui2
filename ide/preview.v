module main

import math
import ui2

fn (app &IdeApp) canvas_width() f64 {
	return if app.preview_width > 0 { app.preview_width } else { app.form_width }
}

fn (app &IdeApp) canvas_height() f64 {
	return if app.preview_height > 0 { app.preview_height } else { app.form_height }
}

fn (app &IdeApp) geometry_editable() bool {
	return app.active_tab == 'designer' && app.preview_width == 0 && app.preview_height == 0
}

fn (mut app IdeApp) require_geometry_editable() bool {
	if !app.geometry_editable() {
		app.status = 'Preview only. Choose Design size before editing the canvas.'
		return false
	}
	return true
}

fn component_frame(component DesignerComponent) ui2.Rect {
	return ui2.rect(component.x, component.y, component.width, component.height)
}

fn (mut app IdeApp) store_geometry(index int, edited DesignerComponent) {
	app.components[index].x = edited.x
	app.components[index].y = edited.y
	app.components[index].width = edited.width
	app.components[index].height = edited.height
}

fn (mut app IdeApp) reset_preview() {
	app.preview_width = 0
	app.preview_height = 0
	app.end_drag()
}

fn (mut app IdeApp) set_preview_size(width f64, height f64) {
	if math.is_nan(width) || math.is_nan(height) || math.is_inf(width, 0) || math.is_inf(height, 0) {
		return
	}
	app.end_drag()
	app.preview_width = clamp(width, 240, 3840)
	app.preview_height = clamp(height, 240, 2160)
	app.status = 'Preview ${int(app.preview_width)} x ${int(app.preview_height)}. Saved design is unchanged.'
}

fn (app &IdeApp) layout_warnings() []string {
	mut warnings := []string{}
	for component in app.components {
		if component.hidden { continue }
		if component.x < 0 || component.y < 0
			|| component.x + component.width > app.canvas_width() + 0.01
			|| component.y + component.height > app.canvas_height() + 0.01 {
			warnings << '${component.name} extends outside the preview canvas.'
		}
		if component.width <= 0 || component.height <= 0 {
			warnings << '${component.name} has no visible area at this size.'
		}
	}
	return warnings
}

fn (mut app IdeApp) set_geometry_property(field string, raw string) bool {
	index := app.find_component_index(app.selected_id)
	if index < 0 || !app.require_geometry_editable() { return false }
	number := parse_f64_property(raw) or {
		app.status = 'Enter a finite numeric value.'
		return false
	}
	mut component := app.components[index]
	before := component_frame(component)
	match field {
		'property_x' { component.x = clamp(number, 0, app.form_width - component.width) }
		'property_y' { component.y = clamp(number, 0, app.form_height - component.height) }
		'property_width' { component.width = clamp(number, 32, app.form_width - component.x) }
		'property_height' { component.height = clamp(number, 24, app.form_height - component.y) }
		else { return false }
	}
	if before == component_frame(component) { return false }
	app.checkpoint()
	app.store_geometry(index, component)
	app.changed('Updated `${component.name}` geometry.')
	return true
}

fn (mut app IdeApp) resize_design_canvas(width f64, height f64) {
	app.form_width = width
	app.form_height = height
	app.keep_components_on_form()
}

fn (mut app IdeApp) handle_preview_event(event string) bool {
	match event {
		'preview_base' { app.reset_preview() }
		'preview_phone' { app.set_preview_size(390, 844) }
		'preview_tablet' { app.set_preview_size(834, 1194) }
		'preview_desktop' { app.set_preview_size(1280, 800) }
		'preview_rotate' { app.set_preview_size(app.canvas_height(), app.canvas_width()) }
		'preview_size' {
			width := parse_f64_property(ui2.text('preview_width')) or { return true }
			height := parse_f64_property(ui2.text('preview_height')) or { return true }
			app.set_preview_size(width, height)
		}
		'preview_check' {
			warnings := app.layout_warnings()
			app.status = if warnings.len == 0 {
				'No off-canvas or empty controls at this preview size.'
			} else {
				'${warnings.len} layout warning(s). See Messages.'
			}
			app.log(app.status)
			for warning in warnings { app.log(warning) }
			app.output_open = true
		}
		'component_hidden' {
			if !app.geometry_editable() { return true }
			if app.source_modified && !app.apply_source_editor() { return true }
			index := app.find_component_index(app.selected_id)
			if index >= 0 {
				app.checkpoint()
				app.components[index].hidden = !app.components[index].hidden
				app.changed('Updated control visibility.')
			}
		}
		'inspector_layout' { app.inspector_tab = 'layout' }
		else { return false }
	}
	return true
}
