module ui2

// Native presentation is an explicit profile. Check supplied properties,
// including zero and false, rather than only comparing the resulting values.
pub fn validate_native_style(patch StylePatch, kind Kind) ! {
	if patch.hover != BoxStylePatch{} || patch.focus != BoxStylePatch{}
		|| patch.pressed != BoxStylePatch{} || patch.disabled != BoxStylePatch{}
		|| patch.hover_text != TextStylePatch{} || patch.focus_text != TextStylePatch{}
		|| patch.pressed_text != TextStylePatch{} || patch.disabled_text != TextStylePatch{} {
		return error('interaction styles require the custom renderer')
	}
	if patch.box.border_pattern != none || patch.box.dash_length != none
		|| patch.box.dash_gap != none || patch.box.outline_color != none
		|| patch.box.outline_width != none || patch.box.outline_offset != none {
		return error('border patterns and outlines require the custom renderer')
	}
	if weight := patch.text.weight {
		if weight != 0 && weight != 400 && weight != 700 {
			return error('native typography weight supports 0, 400 and 700; other weights require the custom renderer')
		}
	}
	if patch.text.letter_spacing != none
		|| patch.text.line_height != none || patch.text.line_height_factor != none
		|| patch.text.baseline_offset != none || patch.text.tabular_figures != none {
		return error('tracking, line height, baseline and tabular figures require the custom renderer')
	}
	if kind !in [.text_area] && (patch.text.text_background != none
		|| patch.text.strikethrough != none || patch.text.shadow != none
		|| patch.text.text_outline != none || patch.text.vertical_align != none
		|| patch.text.link != none || patch.text.head_indent != none
		|| patch.text.first_line_indent != none || patch.text.hyphenation_factor != none) {
		return error('rich text presentation requires TextArea or the custom renderer')
	}
	$if macos {
		if patch.text.font_family != none && kind != .text_area {
			return error('native macOS font_family requires TextArea or the custom renderer')
		}
		if kind == .label && (patch.box.bg != none || patch.box.radius != none || patch.box.transparent != none) {
			return error('native macOS Label box fill and radius require the custom renderer')
		}
		if kind == .text_field {
			if style_has_padding(patch) || patch.text.italic != none || patch.text.underline != none
				|| patch.text.text_align != none || patch.text.text_valign != none || patch.text.lines != none {
				return error('native macOS TextInput insets, italic, underline and text alignment require the custom renderer')
			}
			if weight := patch.text.weight {
				if weight != 0 && weight != 400 {
					return error('native macOS TextInput weight requires the custom renderer')
				}
			}
			if patch.box.radius != none {
				return error('native macOS TextInput radius requires the custom renderer')
			}
		}
		if kind in [.dropdown, .checkbox] && (patch.box.bg != none || patch.box.radius != none
			|| patch.text.foreground != none || patch.text.underline != none
			|| patch.text.text_align != none || patch.text.text_valign != none || patch.text.lines != none) {
			return error('native macOS ${kind} colors, radius and text alignment require the custom renderer')
		}
		if kind == .checkbox && patch.box.transparent != none {
			return error('native macOS Checkbox transparency requires the custom renderer')
		}
		if kind in [.screen, .scroll, .image] && patch.box.radius != none {
			return error('native macOS ${kind} radius requires the custom renderer')
		}
		if kind == .text_area && patch.text.text_valign != none {
			return error('native macOS TextArea vertical alignment requires the custom renderer')
		}
		if kind in [.button, .toggle_button] && (patch.text.text_align != none
			|| patch.text.text_valign != none) {
			return error('native macOS button text alignment requires the custom renderer')
		}
		if kind == .image && (patch.box.bg != none || patch.box.transparent != none) {
			return error('native macOS Image fill requires the custom renderer')
		}
		if kind == .screen && (patch.box.border_color != none || patch.box.border_left != none
			|| patch.box.border_top != none || patch.box.border_right != none || patch.box.border_bottom != none) {
			return error('native macOS Window borders require the custom renderer')
		}
	}
	if kind in [.button, .toggle_button] && style_has_padding(patch) {
		return error('button content padding requires the custom renderer')
	}
	if kind in [.slider, .switch_control] && patch != StylePatch{} {
		return error('slider and switch presentation requires the custom renderer')
	}
}

fn validate_style_box(box BoxStylePatch) ! {
	if value := box.radius {
		if !layout_finite(value) || value < 0 {
			return error('style radius must be finite and non-negative')
		}
	}
	if value := box.border_left {
		if !layout_finite(value) || value < 0 {
			return error('style border_left must be finite and non-negative')
		}
	}
	if value := box.border_top {
		if !layout_finite(value) || value < 0 {
			return error('style border_top must be finite and non-negative')
		}
	}
	if value := box.border_right {
		if !layout_finite(value) || value < 0 {
			return error('style border_right must be finite and non-negative')
		}
	}
	if value := box.border_bottom {
		if !layout_finite(value) || value < 0 {
			return error('style border_bottom must be finite and non-negative')
		}
	}
	if value := box.dash_length {
		if !layout_finite(value) || value < 0 {
			return error('style dash_length must be finite and non-negative')
		}
	}
	if value := box.dash_gap {
		if !layout_finite(value) || value < 0 {
			return error('style dash_gap must be finite and non-negative')
		}
	}
	if value := box.outline_width {
		if !layout_finite(value) || value < 0 {
			return error('style outline_width must be finite and non-negative')
		}
	}
	if value := box.outline_offset {
		if !layout_finite(value) || value < 0 {
			return error('style outline_offset must be finite and non-negative')
		}
	}
}

fn validate_style_patch(patch StylePatch) ! {
	validate_style_box(patch.box)!
	validate_style_box(patch.hover)!
	validate_style_box(patch.focus)!
	validate_style_box(patch.pressed)!
	validate_style_box(patch.disabled)!
	if value := patch.text.font_size {
		if !layout_finite(value) { return error('style font_size must be finite') }
	}
	if value := patch.text.letter_spacing {
		if !layout_finite(value) { return error('style letter_spacing must be finite') }
	}
	if value := patch.text.line_height {
		if !layout_finite(value) { return error('style line_height must be finite') }
	}
	if value := patch.text.line_height_factor {
		if !layout_finite(value) { return error('style line_height_factor must be finite') }
	}
	if value := patch.text.baseline_offset {
		if !layout_finite(value) { return error('style baseline_offset must be finite') }
	}
	if value := patch.text.head_indent {
		if !layout_finite(value) { return error('style head_indent must be finite') }
	}
	if value := patch.text.first_line_indent {
		if !layout_finite(value) { return error('style first_line_indent must be finite') }
	}
	if value := patch.text.hyphenation_factor {
		if !layout_finite(value) { return error('style hyphenation_factor must be finite') }
	}
	if value := patch.padding_left {
		if !layout_finite(value) || value < 0 {
			return error('style padding_left must be finite and non-negative')
		}
	}
	if value := patch.padding_top {
		if !layout_finite(value) || value < 0 {
			return error('style padding_top must be finite and non-negative')
		}
	}
	if value := patch.padding_right {
		if !layout_finite(value) || value < 0 {
			return error('style padding_right must be finite and non-negative')
		}
	}
	if value := patch.padding_bottom {
		if !layout_finite(value) || value < 0 {
			return error('style padding_bottom must be finite and non-negative')
		}
	}
	if value := patch.text.font_size {
		if value < 0 { return error('style font_size cannot be negative') }
	}
	if value := patch.text.weight {
		if value != 0 && (value < 100 || value > 900) {
			return error('style weight must be zero or between 100 and 900')
		}
	}
	if value := patch.text.lines {
		if value < 0 { return error('style lines cannot be negative') }
	}
}

fn style_layout_padding(base LayoutPadding, patch StylePatch) LayoutPadding {
	return LayoutPadding{
		left:   patch.padding_left or { base.left }
		top:    patch.padding_top or { base.top }
		right:  patch.padding_right or { base.right }
		bottom: patch.padding_bottom or { base.bottom }
	}
}

fn style_has_padding(patch StylePatch) bool {
	return patch.padding_left != none || patch.padding_top != none
		|| patch.padding_right != none || patch.padding_bottom != none
}

fn apply_style_padding(el Element, patch StylePatch) !Element {
	if !style_has_padding(patch) { return el }
	mut layout := el.layout
	match layout.kind {
		.flex {
			layout = LayoutSpec{
				...layout
				flex: FlexConfig{
					...layout.flex
					padding: style_layout_padding(layout.flex.padding, patch)
				}
			}
		}
		.grid {
			p := layout.grid.padding
			padding := style_layout_padding(LayoutPadding{ left: p.left, top: p.top, right: p.right, bottom: p.bottom }, patch)
			layout = LayoutSpec{
				...layout
				grid: GridConfig{
					...layout.grid
					padding: GridPadding{ left: padding.left, top: padding.top, right: padding.right, bottom: padding.bottom }
				}
			}
		}
		.stack {
			layout = LayoutSpec{
				...layout
				stack: StackConfig{
					...layout.stack
					padding: style_layout_padding(layout.stack.padding, patch)
				}
			}
		}
		.none {
			if el.kind in [.button, .toggle_button] {
				padding := style_layout_padding(layout_measure_control_insets(el), patch)
				return Element{ ...el, content_padding: padding }
			}
			if el.kind == .text_field {
				if patch.padding_top != none || patch.padding_right != none || patch.padding_bottom != none {
					return error('TextInput currently supports padding_left only')
				}
				return Element{ ...el, padding_left: patch.padding_left or { el.padding_left } }
			}
			if el.kind != .view { return error('padding requires a View or layout container') }
			layout = LayoutSpec{
				kind:  .stack
				stack: StackConfig{
					padding: style_layout_padding(LayoutPadding{}, patch)
				}
			}
		}
		.absolute {
			return error('Absolute positions children explicitly and does not accept padding')
		}
	}
	return Element{ ...el, layout: layout }
}

// Apply a sparse refinement to an Element value. Stateful declarations use
// node.style(), which restores omitted properties from their unstyled baseline.
pub fn apply_style(el Element, patch StylePatch) !Element {
	validate_style_patch(patch)!
	if backend_native_controls {
		validate_native_style(patch, el.kind)!
	}
	interaction := InteractionStyle{
		hover:         merge_style_fields(el.interaction_style.hover, patch.hover)
		focus:         merge_style_fields(el.interaction_style.focus, patch.focus)
		pressed:       merge_style_fields(el.interaction_style.pressed, patch.pressed)
		disabled:      merge_style_fields(el.interaction_style.disabled, patch.disabled)
		hover_text:    merge_style_fields(el.interaction_style.hover_text, patch.hover_text)
		focus_text:    merge_style_fields(el.interaction_style.focus_text, patch.focus_text)
		pressed_text:  merge_style_fields(el.interaction_style.pressed_text, patch.pressed_text)
		disabled_text: merge_style_fields(el.interaction_style.disabled_text, patch.disabled_text)
	}
	mut result := Element{
		...el
		box:               apply_box_patch(el.box, patch.box)
		text_style:        apply_text_style(el.text_style, patch)!
		interaction_style: interaction
	}
	if el.kind == .slider {
		result = Element{
			...result
			slider_style: SliderStyle{
				...el.slider_style
				track_color:       patch.box.bg or { el.slider_style.track_color }
				value_track_color: patch.text.foreground or { el.slider_style.value_track_color }
			}
		}
	}
	if el.kind == .switch_control {
		result = Element{
			...result
			switch_style: SwitchStyle{
				...el.switch_style
				inactive_track_color: patch.box.bg or { el.switch_style.inactive_track_color }
				active_track_color:   patch.text.foreground or { el.switch_style.active_track_color }
			}
		}
	}
	return apply_style_padding(result, patch)
}

fn reset_style_layout(current LayoutSpec, base LayoutSpec) LayoutSpec {
	if current.kind != base.kind { return base }
	return match current.kind {
		.flex {
			LayoutSpec{ ...current, flex: FlexConfig{ ...current.flex, padding: base.flex.padding } }
		}
		.grid {
			LayoutSpec{ ...current, grid: GridConfig{ ...current.grid, padding: base.grid.padding } }
		}
		.stack {
			LayoutSpec{ ...current, stack: StackConfig{ ...current.stack, padding: base.stack.padding } }
		}
		else { current }
	}
}

// Register once per retained node. Replacing a style is authoritative: dropping
// a field restores the original constructor default rather than the previous
// theme's value. Non-presentation data always comes from the live declaration.
pub fn (mut node CompiledVmlNode) style(compute fn () !StylePatch) ! {
	if compute == unsafe { nil } { return error('compiled VML style callback is nil') }
	source := node.source_element()
	base := Element{ ...source, box: source.style_default_box or { source.box } }
	node.effect('style', fn [base, compute] (element Element) !Element {
		patch := compute()!
		unstyled := Element{
			...element
			box:               base.box
			text_style:        base.text_style
			interaction_style: base.interaction_style
			layout:            reset_style_layout(element.layout, base.layout)
			padding_left:      base.padding_left
			content_padding:   base.content_padding
			slider_style:      base.slider_style
			switch_style:      base.switch_style
		}
		return apply_style(unstyled, patch)!
	})!
}

fn validate_content_padding(el Element) ! {
	if padding := el.content_padding {
		if el.kind !in [.button, .toggle_button] {
			return error('content padding requires a button')
		}
		for value in [padding.left, padding.top, padding.right, padding.bottom]! {
			if !layout_finite(value) || value < 0 {
				return error('button content padding must be finite and non-negative')
			}
		}
		if backend_native_controls {
			return error('button content padding requires the custom renderer')
		}
	}
}

// Painting and independent geometry fixtures share the same inner content box.
// Hit testing continues to use the complete authored button frame.
fn button_content_rect(el Element) Rect {
	if padding := el.content_padding {
		return rect(padding.left, padding.top,
			layout_max(0, el.frame.width - padding.left - padding.right),
			layout_max(0, el.frame.height - padding.top - padding.bottom))
	}
	return rect(0, 0, el.frame.width, el.frame.height)
}

// Composite widgets refine their constructor inputs through the same sparse
// value. Progress foreground belongs to its retained fill, and radius shapes
// both the track and fill; ordinary root decoration still uses apply_style.
pub fn style_progress_bar(config ProgressBarConfig, patch StylePatch) !ProgressBarConfig {
	validate_style_patch(patch)!
	return ProgressBarConfig{
		...config
		style_default_box: config.style_default_box or { BoxStyle{ bg: config.background, radius: config.radius } }
		background:        patch.box.bg or { config.background }
		color:             patch.text.foreground or { config.color }
		radius:            patch.box.radius or { config.radius }
	}
}

// Tree text belongs to the widget's generated rows, not its authored content.
// Generic foreground refines normal rows; the selected/disclosure colors remain
// their independently configured parts while sharing typography refinements.
pub fn style_tree_view(config TreeViewConfig, patch StylePatch) !TreeViewConfig {
	validate_style_patch(patch)!
	typography := StylePatch{ text: StyleTextPatch{ ...patch.text, foreground: none } }
	return TreeViewConfig{
		...config
		text_style:            apply_text_style(config.text_style, patch)!
		selected_text_style:   apply_text_style(config.selected_text_style, typography)!
		disclosure_text_style: apply_text_style(config.disclosure_text_style, typography)!
	}
}
