module ui2

// StylePatch is a sparse value. An absent property preserves the preceding
// value; explicit zero, false and black are ordinary overrides.
pub struct StyleTextPatch {
pub:
	foreground         ?u32
	text_background    ?u32
	font_size          ?f64
	font_family        ?string
	weight             ?int
	letter_spacing     ?f64
	line_height        ?f64
	line_height_factor ?f64
	baseline_offset    ?f64
	tabular_figures    ?bool
	italic             ?bool
	underline          ?bool
	strikethrough      ?bool
	shadow             ?bool
	text_outline       ?bool
	vertical_align     ?string
	link               ?string
	text_align         ?Align
	text_valign        ?VAlign
	head_indent        ?f64
	first_line_indent  ?f64
	hyphenation_factor ?f64
	lines              ?int
}

pub struct StylePatch {
pub:
	box            BoxStylePatch
	text           StyleTextPatch
	hover          BoxStylePatch
	focus          BoxStylePatch
	pressed        BoxStylePatch
	disabled       BoxStylePatch
	hover_text     TextStylePatch
	focus_text     TextStylePatch
	pressed_text   TextStylePatch
	disabled_text  TextStylePatch
	padding_left   ?f64
	padding_top    ?f64
	padding_right  ?f64
	padding_bottom ?f64
}

fn merge_style_fields[T](base T, patch T) T {
	mut result := base
	$for field in T.fields {
		if value := patch.$(field.name) {
			unsafe { result.$(field.name) = value }
		}
	}
	return result
}

// Composition is left to right. Nested named styles have already been composed
// into the same value type, so they require no tree traversal or special rule.
pub fn compose_styles(patches []StylePatch) StylePatch {
	mut result := StylePatch{}
	for patch in patches {
		result = StylePatch{
			...result
			box:            merge_style_fields(result.box, patch.box)
			text:           merge_style_fields(result.text, patch.text)
			hover:          merge_style_fields(result.hover, patch.hover)
			focus:          merge_style_fields(result.focus, patch.focus)
			pressed:        merge_style_fields(result.pressed, patch.pressed)
			disabled:       merge_style_fields(result.disabled, patch.disabled)
			hover_text:     merge_style_fields(result.hover_text, patch.hover_text)
			focus_text:     merge_style_fields(result.focus_text, patch.focus_text)
			pressed_text:   merge_style_fields(result.pressed_text, patch.pressed_text)
			disabled_text:  merge_style_fields(result.disabled_text, patch.disabled_text)
			padding_left:   if value := patch.padding_left {
				?f64(value)
			} else {
				result.padding_left
			}
			padding_top:    if value := patch.padding_top {
				?f64(value)
			} else {
				result.padding_top
			}
			padding_right:  if value := patch.padding_right {
				?f64(value)
			} else {
				result.padding_right
			}
			padding_bottom: if value := patch.padding_bottom {
				?f64(value)
			} else {
				result.padding_bottom
			}
		}
	}
	return result
}

pub fn apply_text_style(base TextStyle, patch StylePatch) !TextStyle {
	validate_style_patch(patch)!
	return TextStyle{
		...base
		color:              patch.text.foreground or { base.color }
		background_color:   patch.text.text_background or { base.background_color }
		size:               patch.text.font_size or { base.size }
		font_family:        patch.text.font_family or { base.font_family }
		weight:             patch.text.weight or { base.weight }
		bold:               if weight := patch.text.weight { weight >= 700 } else { base.bold }
		letter_spacing:     patch.text.letter_spacing or { base.letter_spacing }
		line_height:        patch.text.line_height or { base.line_height }
		line_height_factor: patch.text.line_height_factor or { base.line_height_factor }
		baseline_offset:    patch.text.baseline_offset or { base.baseline_offset }
		tabular_figures:    patch.text.tabular_figures or { base.tabular_figures }
		italic:             patch.text.italic or { base.italic }
		underline:          patch.text.underline or { base.underline }
		strikethrough:      patch.text.strikethrough or { base.strikethrough }
		shadow:             patch.text.shadow or { base.shadow }
		outline:            patch.text.text_outline or { base.outline }
		vertical_align:     patch.text.vertical_align or { base.vertical_align }
		link:               patch.text.link or { base.link }
		align:              patch.text.text_align or { base.align }
		valign:             patch.text.text_valign or { base.valign }
		head_indent:        patch.text.head_indent or { base.head_indent }
		first_line_indent:  patch.text.first_line_indent or { base.first_line_indent }
		hyphenation_factor: patch.text.hyphenation_factor or { base.hyphenation_factor }
		lines:              patch.text.lines or { base.lines }
	}
}

pub fn style_background(value u32) StylePatch {
	return StylePatch{ box: BoxStylePatch{ bg: value, transparent: false } }
}

pub fn style_radius(value f64) StylePatch {
	return StylePatch{ box: BoxStylePatch{ radius: value } }
}

pub fn style_transparent(value bool) StylePatch {
	return StylePatch{ box: BoxStylePatch{ transparent: value } }
}

pub fn style_border_color(value u32) StylePatch {
	return StylePatch{ box: BoxStylePatch{ border_color: value } }
}

pub fn style_border_left(value f64) StylePatch {
	return StylePatch{ box: BoxStylePatch{ border_left: value } }
}

pub fn style_border_top(value f64) StylePatch {
	return StylePatch{ box: BoxStylePatch{ border_top: value } }
}

pub fn style_border_right(value f64) StylePatch {
	return StylePatch{ box: BoxStylePatch{ border_right: value } }
}

pub fn style_border_bottom(value f64) StylePatch {
	return StylePatch{ box: BoxStylePatch{ border_bottom: value } }
}

pub fn style_border_left_color(value u32) StylePatch {
	return StylePatch{ box: BoxStylePatch{ border_left_color: value } }
}

pub fn style_border_top_color(value u32) StylePatch {
	return StylePatch{ box: BoxStylePatch{ border_top_color: value } }
}

pub fn style_border_right_color(value u32) StylePatch {
	return StylePatch{ box: BoxStylePatch{ border_right_color: value } }
}

pub fn style_border_bottom_color(value u32) StylePatch {
	return StylePatch{ box: BoxStylePatch{ border_bottom_color: value } }
}

pub fn style_border_pattern(value BorderPattern) StylePatch {
	return StylePatch{ box: BoxStylePatch{ border_pattern: value } }
}

pub fn style_dash_length(value f64) StylePatch {
	return StylePatch{ box: BoxStylePatch{ dash_length: value } }
}

pub fn style_dash_gap(value f64) StylePatch {
	return StylePatch{ box: BoxStylePatch{ dash_gap: value } }
}

pub fn style_outline_color(value u32) StylePatch {
	return StylePatch{ box: BoxStylePatch{ outline_color: value } }
}

pub fn style_outline_width(value f64) StylePatch {
	return StylePatch{ box: BoxStylePatch{ outline_width: value } }
}

pub fn style_outline_offset(value f64) StylePatch {
	return StylePatch{ box: BoxStylePatch{ outline_offset: value } }
}

pub fn style_foreground(value u32) StylePatch {
	return StylePatch{ text: StyleTextPatch{ foreground: value } }
}

pub fn style_text_background(value u32) StylePatch {
	return StylePatch{ text: StyleTextPatch{ text_background: value } }
}

pub fn style_font_size(value f64) StylePatch {
	return StylePatch{ text: StyleTextPatch{ font_size: value } }
}

pub fn style_font_family(value string) StylePatch {
	return StylePatch{ text: StyleTextPatch{ font_family: value } }
}

pub fn style_weight(value int) StylePatch {
	return StylePatch{ text: StyleTextPatch{ weight: value } }
}

pub fn style_letter_spacing(value f64) StylePatch {
	return StylePatch{ text: StyleTextPatch{ letter_spacing: value } }
}

pub fn style_line_height(value f64) StylePatch {
	return StylePatch{ text: StyleTextPatch{ line_height: value } }
}

pub fn style_line_height_factor(value f64) StylePatch {
	return StylePatch{ text: StyleTextPatch{ line_height_factor: value } }
}

pub fn style_baseline_offset(value f64) StylePatch {
	return StylePatch{ text: StyleTextPatch{ baseline_offset: value } }
}

pub fn style_tabular_figures(value bool) StylePatch {
	return StylePatch{ text: StyleTextPatch{ tabular_figures: value } }
}

pub fn style_italic(value bool) StylePatch {
	return StylePatch{ text: StyleTextPatch{ italic: value } }
}

pub fn style_underline(value bool) StylePatch {
	return StylePatch{ text: StyleTextPatch{ underline: value } }
}

pub fn style_strikethrough(value bool) StylePatch {
	return StylePatch{ text: StyleTextPatch{ strikethrough: value } }
}

pub fn style_shadow(value bool) StylePatch {
	return StylePatch{ text: StyleTextPatch{ shadow: value } }
}

pub fn style_text_outline(value bool) StylePatch {
	return StylePatch{ text: StyleTextPatch{ text_outline: value } }
}

pub fn style_vertical_align(value string) StylePatch {
	return StylePatch{ text: StyleTextPatch{ vertical_align: value } }
}

pub fn style_link(value string) StylePatch {
	return StylePatch{ text: StyleTextPatch{ link: value } }
}

pub fn style_text_align(value Align) StylePatch {
	return StylePatch{ text: StyleTextPatch{ text_align: value } }
}

pub fn style_text_valign(value VAlign) StylePatch {
	return StylePatch{ text: StyleTextPatch{ text_valign: value } }
}

pub fn style_head_indent(value f64) StylePatch {
	return StylePatch{ text: StyleTextPatch{ head_indent: value } }
}

pub fn style_first_line_indent(value f64) StylePatch {
	return StylePatch{ text: StyleTextPatch{ first_line_indent: value } }
}

pub fn style_hyphenation_factor(value f64) StylePatch {
	return StylePatch{ text: StyleTextPatch{ hyphenation_factor: value } }
}

pub fn style_lines(value int) StylePatch {
	return StylePatch{ text: StyleTextPatch{ lines: value } }
}

pub fn style_padding_left(value f64) StylePatch {
	return StylePatch{ padding_left: value }
}

pub fn style_padding_top(value f64) StylePatch {
	return StylePatch{ padding_top: value }
}

pub fn style_padding_right(value f64) StylePatch {
	return StylePatch{ padding_right: value }
}

pub fn style_padding_bottom(value f64) StylePatch {
	return StylePatch{ padding_bottom: value }
}

pub fn style_padding(value f64) StylePatch {
	return StylePatch{ padding_left: value, padding_top: value, padding_right: value, padding_bottom: value }
}

pub fn style_border_width(value f64) StylePatch {
	return StylePatch{ box: BoxStylePatch{ border_left: value, border_top: value, border_right: value, border_bottom: value } }
}

pub fn style_hover(patches []StylePatch) !StylePatch {
	patch := compose_styles(patches)
	if StylePatch{ ...patch, box: BoxStylePatch{}, text: StyleTextPatch{} } != StylePatch{}
		|| StyleTextPatch{ ...patch.text, foreground: none } != StyleTextPatch{} {
		return error('hover style only accepts box presentation and foreground')
	}
	validate_style_patch(patch)!
	return StylePatch{ hover: patch.box, hover_text: TextStylePatch{ color: patch.text.foreground } }
}

pub fn style_focus(patches []StylePatch) !StylePatch {
	patch := compose_styles(patches)
	if StylePatch{ ...patch, box: BoxStylePatch{}, text: StyleTextPatch{} } != StylePatch{}
		|| StyleTextPatch{ ...patch.text, foreground: none } != StyleTextPatch{} {
		return error('focus style only accepts box presentation and foreground')
	}
	validate_style_patch(patch)!
	return StylePatch{ focus: patch.box, focus_text: TextStylePatch{ color: patch.text.foreground } }
}

pub fn style_pressed(patches []StylePatch) !StylePatch {
	patch := compose_styles(patches)
	if StylePatch{ ...patch, box: BoxStylePatch{}, text: StyleTextPatch{} } != StylePatch{}
		|| StyleTextPatch{ ...patch.text, foreground: none } != StyleTextPatch{} {
		return error('pressed style only accepts box presentation and foreground')
	}
	validate_style_patch(patch)!
	return StylePatch{ pressed: patch.box, pressed_text: TextStylePatch{ color: patch.text.foreground } }
}

pub fn style_disabled(patches []StylePatch) !StylePatch {
	patch := compose_styles(patches)
	if StylePatch{ ...patch, box: BoxStylePatch{}, text: StyleTextPatch{} } != StylePatch{}
		|| StyleTextPatch{ ...patch.text, foreground: none } != StyleTextPatch{} {
		return error('disabled style only accepts box presentation and foreground')
	}
	validate_style_patch(patch)!
	return StylePatch{ disabled: patch.box, disabled_text: TextStylePatch{ color: patch.text.foreground } }
}
