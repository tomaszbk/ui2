module ui2

import math

// Radio and radio group. Upstream draws a check in the filled indicator; this
// port draws the conventional inner dot, which reads the same at every size.

pub struct RadioOption {
pub:
	value       string // Stable key passed to on_change; defaults to label.
	label       string
	description string // Muted text under the label; wraps to at most three lines.
	enabled     bool = true
}

pub struct RadioConfig {
pub:
	id                  string
	frame               Rect
	label               string
	description         string
	checked             bool
	enabled             bool = true
	accessibility_label string // Defaults to label.
	size                ComponentSize = .medium
	theme               ComponentTheme
	// on_change is called with true when a click asks an unchecked, enabled
	// radio to become checked. A radio never asks to uncheck itself.
	on_change fn (bool) = unsafe { nil }
}

pub struct RadioGroupConfig {
pub:
	id                  string
	frame               Rect
	options             []RadioOption
	selected            string // Value of the checked option; empty checks none.
	orientation         LayoutOrientation = .vertical
	enabled             bool              = true
	accessibility_label string // Names the group for assistive technology; not drawn.
	size                ComponentSize = .medium
	theme               ComponentTheme
	// on_change receives the value of the option a click selects. Disabled
	// options and groups and the option already selected never call it.
	on_change fn (string) = unsafe { nil }
}

// RadioMetrics is the geometry shared by a radio and the options of a group.
struct RadioMetrics {
	indicator   f64 // Diameter of the circle.
	gap         f64 // Between the circle and the label.
	line        f64 // Height of the label line.
	detail_size f64 // Font size of the description.
	detail_line f64
	spacing     f64 // Added around each option to separate it from the next.
}

fn radio_metrics(metrics ComponentMetrics) RadioMetrics {
	detail_size := math.max(10.0, metrics.font_size - 1)
	return RadioMetrics{
		indicator:   metrics.font_size + 2
		gap:         metrics.gap + 2
		line:        choice_line_height(metrics.font_size)
		detail_size: detail_size
		detail_line: choice_line_height(detail_size)
		spacing:     metrics.padding
	}
}

// radio_description_lines estimates how many lines a description wraps to at
// width, capped at three. The estimate is generous, so a description is more
// likely to get a spare line than to lose one.
fn radio_description_lines(description string, width f64, rm RadioMetrics) int {
	if description.len == 0 {
		return 0
	}
	if width <= 0 {
		return 1
	}
	return int(math.min(3.0, math.ceil(choice_text_width(description, rm.detail_size) / width)))
}

// radio_content_height is how tall an option's label and description are.
fn radio_content_height(lines int, rm RadioMetrics) f64 {
	return rm.line + if lines > 0 { 2 + f64(lines) * rm.detail_line } else { 0.0 }
}

fn radio_value(checked bool) string {
	return if checked { 'checked' } else { 'unchecked' }
}

// radio_indicator is the circle: a ring under an inner fill, with a dot when
// checked. Disabled indicators fade toward the background.
fn radio_indicator(frame Rect, checked bool, enabled bool, theme ComponentTheme) Element {
	d := math.min(frame.width, frame.height)
	mut ring := if checked { theme.primary } else { theme.border }
	mut fill := if checked { theme.primary } else { theme.background }
	mut dot := theme.primary_foreground
	if !enabled {
		ring = choice_mix(ring, theme.background, 0.5)
		fill = choice_mix(fill, theme.background, 0.5)
		dot = choice_mix(dot, theme.background, 0.3)
	}
	mut children := choice_ring(rect(0, 0, d, d), d / 2, ring, fill, .all, false)
	if checked {
		inner := math.round(d * 0.4)
		children << view('', rect((d - inner) / 2, (d - inner) / 2, inner, inner), BoxStyle{
			bg:     dot
			radius: inner / 2
		}, []Element{})
	}
	return view('', frame, BoxStyle{ transparent: true }, children)
}

// radio_option_children lays out one option inside a frame of the given size:
// the circle centered on the first line, the label beside it and the
// description under the label.
fn radio_option_children(width f64, height f64, title string, description string, lines int, checked bool, enabled bool, metrics ComponentMetrics, theme ComponentTheme) []Element {
	rm := radio_metrics(metrics)
	top := rm.spacing / 2
	text_x := rm.indicator + rm.gap
	mut children := [
		radio_indicator(choice_fit(rect(0, top + (rm.line - rm.indicator) / 2, rm.indicator,
			rm.indicator), width, height), checked, enabled, theme),
		label('', title, choice_fit(rect(text_x, top, width - text_x, rm.line), width, height), TextStyle{
			color: if enabled { theme.foreground } else { choice_disabled_text(theme) }
			size:  metrics.font_size
		}),
	]
	if lines > 0 {
		children << label('', description, choice_fit(rect(text_x, top + rm.line + 2, width - text_x,
			f64(lines) * rm.detail_line), width, height), TextStyle{
			color:  if enabled { theme.muted_foreground } else { choice_disabled_text(theme) }
			size:   rm.detail_size
			valign: .top
			lines:  lines
		})
	}
	return children
}

// radio_checked_callback asks an unchecked, enabled radio to become checked.
fn radio_checked_callback(config RadioConfig) ElementCallback {
	if !config.enabled || config.checked || voidptr(config.on_change) == unsafe { nil } {
		return unsafe { nil }
	}
	on_change := config.on_change
	return fn [on_change] (event ElementEvent) {
		if event.kind == .click {
			on_change(true)
		}
	}
}

// radio is a single radio button. A radio cannot uncheck itself: on_change
// only ever receives `true`. Prefer radio_group for a set of mutually
// exclusive options.
pub fn radio(config RadioConfig) !Element {
	component_validate_frame(config.frame)!
	component_validate_id(config.id)!
	metrics := component_metrics(config.size)
	rm := radio_metrics(metrics)
	lines := radio_description_lines(config.description, config.frame.width - rm.indicator - rm.gap,
		rm)
	return component_finish(Element{
		...button_view(config.id, config.frame, BoxStyle{ transparent: true }, radio_option_children(config.frame.width,
			config.frame.height, config.label, config.description, lines, config.checked,
			config.enabled, metrics, config.theme))
		on_event:            radio_checked_callback(config)
		enabled:             config.enabled
		accessibility_role:  'radio'
		accessibility_label: if config.accessibility_label.len > 0 {
			config.accessibility_label
		} else {
			config.label
		}
		accessibility_value: radio_value(config.checked)
	})
}

// radio_group_item_id is the element id of the option for value.
pub fn radio_group_item_id(id string, value string) string {
	return component_part_id(id, choice_item_part('option:', value))
}

// radio_group_option_callback selects value unless the option is disabled or
// already selected in the group it was built from.
fn radio_group_option_callback(config RadioGroupConfig, value string, enabled bool) ElementCallback {
	if !enabled || value == config.selected || voidptr(config.on_change) == unsafe { nil } {
		return unsafe { nil }
	}
	on_change := config.on_change
	return fn [on_change, value] (event ElementEvent) {
		if event.kind == .click {
			on_change(value)
		}
	}
}

fn radio_group_values(options []RadioOption) []string {
	return options.map(choice_value(it.value, it.label))
}

// radio_group_frames places the options: one under another, or left to right
// wrapping onto new rows. Rows are squeezed to fit a frame that is too short.
// It also returns each option's description line count.
fn radio_group_frames(config RadioGroupConfig) ([]Rect, []int) {
	metrics := component_metrics(config.size)
	rm := radio_metrics(metrics)
	width := config.frame.width
	text_room := width - rm.indicator - rm.gap
	mut frames := []Rect{cap: config.options.len}
	mut lines := []int{cap: config.options.len}
	mut bottom := 0.0
	if config.orientation == .vertical {
		for option in config.options {
			count := radio_description_lines(option.description, text_room, rm)
			height := radio_content_height(count, rm) + rm.spacing
			frames << rect(0, bottom, width, height)
			lines << count
			bottom += height
		}
	} else {
		// Options keep their natural width, plus room to separate them, and wrap
		// to a new row when the next one would not fit.
		mut x := 0.0
		mut y := 0.0
		mut row_height := 0.0
		for option in config.options {
			count := if option.description.len > 0 { 1 } else { 0 }
			text_width := math.max(choice_text_width(option.label, metrics.font_size), choice_text_width(option.description,
				rm.detail_size))
			natural := math.min(width, rm.indicator + rm.gap + text_width + rm.spacing * 2)
			height := radio_content_height(count, rm) + rm.spacing
			if x > 0 && x + natural > width {
				x = 0
				y += row_height
				row_height = 0
			}
			frames << rect(x, y, natural, height)
			lines << count
			x += natural
			row_height = math.max(row_height, height)
		}
		bottom = y + row_height
	}
	if bottom > config.frame.height && bottom > 0 {
		scale := config.frame.height / bottom
		for i, frame in frames {
			frames[i] = rect(frame.x, frame.y * scale, frame.width, frame.height * scale)
		}
	}
	return frames, lines
}

// radio_group shows mutually exclusive options. It is controlled: on_change
// receives the value a click selects and the application rebuilds with it as
// `selected`.
pub fn radio_group(config RadioGroupConfig) !Element {
	component_validate_frame(config.frame)!
	component_validate_id(config.id)!
	values := radio_group_values(config.options)
	choice_validate_values(values, 'radio group')!
	metrics := component_metrics(config.size)
	frames, lines := radio_group_frames(config)
	mut children := []Element{cap: config.options.len}
	mut selected_label := ''
	for index, option in config.options {
		checked := values[index] == config.selected
		if checked {
			selected_label = option.label
		}
		enabled := config.enabled && option.enabled
		frame := frames[index]
		children << Element{
			...button_view(radio_group_item_id(config.id, values[index]), frame, BoxStyle{ transparent: true }, radio_option_children(frame.width,
				frame.height, option.label, option.description, lines[index], checked,
				enabled, metrics, config.theme))
			key:                 'option:' + values[index]
			on_event:            radio_group_option_callback(config, values[index], enabled)
			enabled:             enabled
			accessibility_role:  'radio'
			accessibility_label: option.label
			accessibility_value: radio_value(checked)
		}
	}
	return component_finish(Element{
		...view(config.id, config.frame, BoxStyle{ transparent: true }, children)
		accessibility_role:  'radiogroup'
		accessibility_label: config.accessibility_label
		accessibility_value: selected_label
	})
}

// radio_group_value_after_key moves the selection the way arrow keys move it
// in a native radio group: down/right to the next enabled option and up/left
// to the previous one, wrapping around, and home/end to the first and last.
// Call it from on_key_event while the application treats the group as focused.
pub fn radio_group_value_after_key(config RadioGroupConfig, code KeyCode) ?string {
	if !config.enabled {
		return none
	}
	values := radio_group_values(config.options)
	enabled := []int{len: values.len, init: index}.filter(config.options[it].enabled)
	if enabled.len == 0 {
		return none
	}
	position := enabled.index(values.index(config.selected))
	target := match code {
		.down, .right {
			if position < 0 { enabled[0] } else { enabled[(position + 1) % enabled.len] }
		}
		.up, .left {
			if position < 0 {
				enabled[enabled.len - 1]
			} else {
				enabled[(position + enabled.len - 1) % enabled.len]
			}
		}
		.home {
			enabled[0]
		}
		.end {
			enabled[enabled.len - 1]
		}
		else {
			return none
		}
	}
	if values[target] == config.selected {
		return none
	}
	return values[target]
}
