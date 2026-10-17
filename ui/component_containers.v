module ui2

import math

pub struct InlineAlertConfig {
pub:
	id          string
	frame       Rect
	title       string
	description string
	// on_dismiss receives the close button's click. Without it the alert has
	// no close button.
	on_dismiss ElementCallback = unsafe { nil }
	enabled    bool            = true
	tone       ComponentTone   = .primary
	size       ComponentSize   = .medium
	theme      ComponentTheme
}

// inline_alert is a message drawn in the layout. It is not the OS dialog that
// alert() shows, nor a global toast manager.
pub fn inline_alert(config InlineAlertConfig) !Element {
	component_validate_frame(config.frame)!
	dismissible := voidptr(config.on_dismiss) != unsafe { nil }
	if dismissible {
		component_validate_id(config.id)!
	}
	metrics := component_metrics(config.size)
	accent, _ := config.theme.colors(config.tone)
	inner := component_inset(component_local(config.frame), metrics.padding)!
	close_width := if dismissible {
		math.min(metrics.height, inner.width)
	} else {
		0.0
	}
	width := inner.width - close_width
	title_height := if config.title.len > 0 { math.min(metrics.height, inner.height) } else { 0.0 }
	mut children := []Element{}
	if config.title.len > 0 {
		children << component_text(config.title, rect(inner.x, inner.y, width, title_height),
			config.theme.foreground, metrics.font_size, true)
	}
	if config.description.len > 0 {
		children << label('', config.description, rect(inner.x, inner.y + title_height, width,
			inner.height - title_height), TextStyle{
			color:  config.theme.muted_foreground
			size:   metrics.font_size
			valign: .top
			lines:  0
		})
	}
	if dismissible {
		children << Element{
			...button(component_part_id(config.id, 'dismiss'), '×', rect(inner.x + width, inner.y,
				close_width, math.min(metrics.height, inner.height)), BoxStyle{ transparent: true }, TextStyle{
				color: config.theme.foreground
				size:  metrics.font_size
				align: .center
			})
			on_event:            component_forward_click(config.on_dismiss)
			enabled:             config.enabled
			accessibility_label: 'Dismiss ${config.title}'
		}
	}
	return component_finish(Element{
		...view(config.id, config.frame, component_box(config.theme.background, accent,
			metrics.radius), children)
		accessibility_role:  'alert'
		accessibility_label: (config.title + ' ' + config.description).trim_space()
	})
}

pub struct EmptyStateConfig {
pub:
	id          string
	frame       Rect
	title       string
	description string
	action_text string
	// on_action receives the action button's click. Without it the empty state
	// has no action button.
	on_action ElementCallback = unsafe { nil }
	enabled   bool            = true
	size      ComponentSize   = .medium
	theme     ComponentTheme
}

pub fn empty_state(config EmptyStateConfig) !Element {
	component_validate_frame(config.frame)!
	has_action := voidptr(config.on_action) != unsafe { nil }
	if has_action {
		component_validate_id(config.id)!
	}
	metrics := component_metrics(config.size)
	inner := component_inset(component_local(config.frame), metrics.padding)!
	action_height := if has_action {
		math.min(metrics.height, inner.height)
	} else {
		0.0
	}
	title_height := math.min(metrics.height, inner.height - action_height)
	mut children := [label('', config.title, rect(inner.x, inner.y, inner.width, title_height), TextStyle{
		color: config.theme.foreground
		size:  metrics.font_size
		bold:  true
		align: .center
	})]
	children << label('', config.description, rect(inner.x, inner.y + title_height, inner.width,
		inner.height - title_height - action_height), TextStyle{
		color: config.theme.muted_foreground
		size:  metrics.font_size
		align: .center
		lines: 0
	})
	if has_action {
		children << Element{
			...button(component_part_id(config.id, 'action'), config.action_text,
				rect(inner.x, inner.y + inner.height - action_height, inner.width, action_height),
				BoxStyle{ bg: config.theme.primary, radius: metrics.radius }, TextStyle{
					color: config.theme.primary_foreground
					size:  metrics.font_size
					align: .center
				})
			on_event:            component_forward_click(config.on_action)
			enabled:             config.enabled
			accessibility_label: config.action_text
		}
	}
	return component_finish(view(config.id, config.frame, BoxStyle{ transparent: true }, children))
}

pub struct GroupBoxConfig {
pub:
	id       string
	frame    Rect
	title    string
	children []Element // Positioned relative to the padded body, below the title.
	size     ComponentSize = .medium
	theme    ComponentTheme
}

pub fn group_box(config GroupBoxConfig) !Element {
	component_validate_frame(config.frame)!
	metrics := component_metrics(config.size)
	inner := component_inset(component_local(config.frame), metrics.padding)!
	title_height := if config.title.len > 0 { math.min(metrics.height, inner.height) } else { 0.0 }
	mut children := []Element{}
	if config.title.len > 0 {
		children << component_text(config.title, rect(inner.x, inner.y, inner.width, title_height),
			config.theme.foreground, metrics.font_size, true)
	}
	children << view('', rect(inner.x, inner.y + title_height, inner.width,
		inner.height - title_height), BoxStyle{ transparent: true }, config.children)
	return component_finish(Element{
		...view(config.id, config.frame, component_box(config.theme.background, config.theme.border,
			metrics.radius), children)
		accessibility_role:  'group'
		accessibility_label: config.title
	})
}

pub struct DescriptionItem {
pub:
	term  string
	value string
}

pub struct DescriptionListConfig {
pub:
	id             string
	frame          Rect
	items          []DescriptionItem
	label_fraction f64           = 0.35
	size           ComponentSize = .medium
	theme          ComponentTheme
}

pub fn description_list(config DescriptionListConfig) !Element {
	component_validate_frame(config.frame)!
	if !component_finite(config.label_fraction) || config.label_fraction < 0
		|| config.label_fraction > 1 {
		return error('description list label fraction must be between zero and one')
	}
	metrics := component_metrics(config.size)
	mut children := []Element{}
	if config.items.len > 0 {
		row_height := config.frame.height / f64(config.items.len)
		gap := math.min(metrics.gap, config.frame.width)
		available := config.frame.width - gap
		label_width := available * config.label_fraction
		for index, item in config.items {
			y := f64(index) * row_height
			children << component_text(item.term, rect(0, y, label_width, row_height),
				config.theme.muted_foreground, metrics.font_size, false)
			children << component_text(item.value, rect(label_width + gap, y,
				available - label_width, row_height), config.theme.foreground,
				metrics.font_size, false)
		}
	}
	return component_finish(Element{
		...view(config.id, config.frame, BoxStyle{ transparent: true }, children)
		accessibility_role: 'group'
	})
}

pub struct CollapsibleConfig {
pub:
	id       string
	frame    Rect
	title    string
	open     bool
	enabled  bool = true
	children []Element // Positioned relative to the body when open.
	size     ComponentSize = .medium
	theme    ComponentTheme
	// on_toggle receives the open state a click on the header asks for: the
	// opposite of open.
	on_toggle fn (bool) = unsafe { nil }
}

fn collapsible_toggle_callback(config CollapsibleConfig) ElementCallback {
	if voidptr(config.on_toggle) == unsafe { nil } {
		return unsafe { nil }
	}
	on_toggle := config.on_toggle
	next := !config.open
	return fn [on_toggle, next] (event ElementEvent) {
		if event.kind == .click {
			on_toggle(next)
		}
	}
}

// collapsible is controlled: on_toggle receives the next open value and the
// application rebuilds with it. Closed content is not mounted and cannot
// retain focus.
pub fn collapsible(config CollapsibleConfig) !Element {
	component_validate_frame(config.frame)!
	component_validate_id(config.id)!
	metrics := component_metrics(config.size)
	header_height := math.min(metrics.height, config.frame.height)
	prefix := if config.open { '− ' } else { '+ ' }
	mut children := [Element{
		...button(component_part_id(config.id, 'trigger'), prefix + config.title,
			rect(0, 0, config.frame.width, header_height), BoxStyle{
				bg:     config.theme.muted
				radius: metrics.radius
			}, TextStyle{
				color: config.theme.foreground
				size:  metrics.font_size
			})
		on_event:            collapsible_toggle_callback(config)
		enabled:             config.enabled
		accessibility_label: config.title
		accessibility_value: if config.open { 'expanded' } else { 'collapsed' }
	}]
	if config.open {
		children << view('', rect(0, header_height, config.frame.width,
			config.frame.height - header_height), BoxStyle{ transparent: true }, config.children)
	}
	return component_finish(view(config.id, config.frame, BoxStyle{ transparent: true }, children))
}
