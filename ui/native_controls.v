module ui2

import os

// Helpers the native control backends (appkit/, windows/, uikit/) share. They
// read declarations only, so they compile, and are tested, with every backend.

// Placing a label's text means sizing the control it draws with to the text,
// and that control is then the wrong thing for anything measured against the
// label's declared frame: a tooltip, a context menu, a border drawn round its
// edge. Such a label is put inside a view covering the frame, which is what the
// backend holds and decorates, while the text moves within it. A label with
// none of those stays the control itself, because a view per label costs a
// third of a frame in a grid of them.
fn label_needs_container(el Element) bool {
	return el.kind == .label && (el.tooltip.len > 0 || el.menu.len > 0
		|| box_draws_border(el.box))
}

// box_rounded_border is the width of a box's border when it should follow the
// box's rounded corners: a radius and the same width on all four sides. Square
// boxes and uneven borders return 0 and keep their straight sides.
fn box_rounded_border(box BoxStyle) f64 {
	if box.radius <= 0 || box.border_left <= 0 || box.border_left != box.border_top
		|| box.border_left != box.border_right || box.border_left != box.border_bottom {
		return 0
	}
	return box.border_left
}

// native_profile_remedy names what shows a presentation the native profile
// cannot: the custom renderer.
const native_profile_remedy = 'the custom renderer (-d ui2_custom_rendering)'

// custom_renderer_hint is how a native build turns on the custom renderer,
// for the diagnostics of features only it has; other builds have no flag
// that would.
fn custom_renderer_hint() string {
	return if backend_native_controls { ' (-d ui2_custom_rendering)' } else { '' }
}

// validate_native_element is the native profile of an element (backend.v):
// presentation the operating system's controls and layer-backed boxes cannot
// show is an error naming the remedy, never left out silently. Validation
// calls it for every element when backend_native_controls is set; headless
// tooling may call it to check a tree against the native profile.
pub fn validate_native_element(el Element) ! {
	id := if el.id.len > 0 { ' (${el.id})' } else { '' }
	if el.interaction_style != InteractionStyle{} {
		return error('hover, focus, pressed and disabled styles require ${native_profile_remedy}${id}')
	}
	if _ := el.paint {
		return error('control paint requires ${native_profile_remedy}; native controls take their chrome from the OS${id}')
	}
	box := el.box
	if box.outline_width > 0 {
		return error('outlines require ${native_profile_remedy}${id}')
	}
	if box.border_pattern != .solid {
		return error('dashed borders require ${native_profile_remedy}${id}')
	}
	if box.border_left_color != none || box.border_top_color != none
		|| box.border_right_color != none || box.border_bottom_color != none {
		return error('per-side border colors require ${native_profile_remedy}${id}')
	}
	$if windows {
		// Win32 child windows paint inside their own rectangle.
		if box_has_shadow(box) {
			return error('Windows native boxes have no drop shadows; they require ${native_profile_remedy}${id}')
		}
	}
	if el.kind != .text_area {
		validate_native_text(el.text_style, id)!
	}
	validate_native_image(el)!
}

fn validate_native_text(style TextStyle, id string) ! {
	if style.letter_spacing != 0 || style.line_height != 0 || style.line_height_factor != 0
		|| style.baseline_offset != 0 || style.tabular_figures {
		return error('tracking, line height, baseline and tabular figures require ${native_profile_remedy}${id}')
	}
	if style.shadow || style.outline || style.strikethrough || style.vertical_align.len > 0
		|| style.link.len > 0 || style.background_color != 0 || style.head_indent != 0
		|| style.first_line_indent != 0 || style.hyphenation_factor != 0 {
		return error('rich text presentation requires a TextArea or ${native_profile_remedy}${id}')
	}
}

// validate_native_image checks an element against what native image views
// show.
pub fn validate_native_image(el Element) ! {
	if el.kind == .image && (el.rotation != 0 || el.clickable || el.draggable || el.long_press
		|| el.swipe_left || voidptr(el.on_event) != unsafe { nil } || el.menu.len > 0
		|| el.tooltip.len > 0 || el.cursor.len > 0) {
		return error('image rotation and visible-quad interaction require ${native_profile_remedy} (${el.id})')
	}
	$if windows {
		if el.kind == .image {
			if el.image_asset == ImageAsset{} && el.image_style == ImageStyle{ fit: .fill }
				&& el.rotation == 0 {
				return
			}
			return error('Windows native images require BMP with fit .fill, no crop/tint/DPI/rotation; use ${native_profile_remedy} (${el.id})')
		}
	}
	if el.image_asset != ImageAsset{} || el.image_style != ImageStyle{} {
		return error('image fit/source/tint/alignment and DPI assets require ${native_profile_remedy} (${el.id})')
	}
}

// appkit_insets are AppKit's control insets. Borderless NSTextField still
// reserves two points at each horizontal edge. NSAttributedString measures
// glyphs only; include the cell's existing margins so an intrinsic label does
// not truncate itself. The document library measures with them for an AppKit
// host too.
fn appkit_insets(element Element) ?LayoutPadding {
	if element.kind == .label {
		return LayoutPadding{
			left:  2
			right: 2
		}
	}
	return none
}

// font_bundle_file returns the path of a font file shipped with the
// application or with ui2 itself, or '' when no bundle directory has it. The
// Win32 backend loads the symbol font from there.
fn font_bundle_file(file_name string) string {
	for dir in font_bundle_dirs() {
		path := os.join_path(dir, file_name)
		if os.is_file(path) {
			return path
		}
	}
	return ''
}

// Windows character messages retain their originating key's scan code. A
// consumed navigation key may remain held while another key enters text.
// Scan-less synthesized/IME text does not belong to a consumed physical key.
// Only the Win32 backend calls it; it stays shared so its tests run
// everywhere.
@[markused]
fn consumed_key_character(scan_code u32, suppressed map[u32]u32) bool {
	if scan_code == 0 { return false }
	for _, consumed_scan in suppressed {
		if consumed_scan == scan_code { return true }
	}
	return false
}

// native_font_weight is the weight AppKit's systemFontOfSize:weight: and
// UIKit's take for a 100–900 weight (text_style_weight), from
// UltraLight to Black. Win32 takes the 100–900 weight itself.
fn native_font_weight(weight int) f64 {
	return match true {
		weight <= 100 { -0.8 }
		weight <= 200 { -0.6 }
		weight <= 300 { -0.4 }
		weight <= 400 { 0.0 }
		weight <= 500 { 0.23 }
		weight <= 600 { 0.3 }
		weight <= 700 { 0.4 }
		weight <= 800 { 0.56 }
		else { 0.62 }
	}
}
