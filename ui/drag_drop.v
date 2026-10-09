module ui2

import math

// Applications implement this interface with their own value types. A target
// uses `if offer.payload is MyPayload` to narrow the data without string routing.
pub interface DragPayload {
	drag_type() string
}

pub struct DragText {
pub:
	text string
}

pub fn (payload DragText) drag_type() string {
	return 'text'
}

pub enum DragOperation {
	none
	copy
	move
	link
}

pub enum DragCancelReason {
	none
	invalid_target
	cancelled
	escape
	focus_lost
	source_removed
}

// Acceptance is a pure query. Return one of the offered operations or .none.
pub type DragAccept = fn (DragOffer) DragOperation

pub struct DragOffer {
pub:
	payload   DragPayload = DragText{}
	allowed   []DragOperation
	source_id string
	target_id string
	window_x  f64
	window_y  f64
	// Composition coordinates (the same space as ElementEvent.x/y).
	source_x f64
	source_y f64
	target_x f64
	target_y f64
}

pub struct DragEvent {
pub:
	offer     DragOffer
	operation DragOperation
	reason    DragCancelReason
}

// The preview is a window overlay, clipped to the window, never a hit target.
// Its dimensions/offset are source-composition units, projected by the shared
// ContentTransform captured at drag start. Device DPI is applied by DrawContext.
pub struct DragPreview {
pub:
	text       string
	image_path string
	image_asset ImageAsset
	image_style ImageStyle
	width      f64       = 120
	height     f64       = 40
	offset_x   f64       = 12
	offset_y   f64       = 12
	box        BoxStyle  = BoxStyle{ bg: 0x334155, radius: 6 }
	text_style TextStyle = TextStyle{ color: 0xffffff, size: 14 }
}

pub struct DragSource {
pub:
	payload DragPayload     = DragText{}
	allowed []DragOperation = [.move]
	// Distance in window-logical units, independent of content scale and DPI.
	threshold f64 = 6
	preview   DragPreview
}

pub struct DropTarget {
pub:
	accept DragAccept = unsafe { nil }
}

pub fn with_drag_source(el Element, source DragSource) Element {
	return Element{ ...el, drag_source: source }
}

pub fn with_drop_target(el Element, target DropTarget) Element {
	return Element{ ...el, drop_target: target }
}

fn validate_drag_element(el Element) ! {
	if el.drag_source == none && el.drop_target == none { return }
	if el.kind !in [.view, .image] {
		return error('drag sources and drop targets must be View or Image elements')
	}
	if voidptr(el.on_event) == unsafe { nil } {
		return error('drag sources and drop targets require on_event')
	}
	if el.draggable || el.long_press || el.swipe_left || (el.drag_source != none && el.clickable) {
		return error('drag-drop owns its gesture; raw clickable/draggable/long_press/swipe_left cannot share it')
	}
	if source := el.drag_source {
		if source.allowed.len == 0 || DragOperation.none in source.allowed {
			return error('drag source must offer copy, move or link')
		}
		if source.threshold < 0 || math.is_nan(source.threshold) || math.is_inf(source.threshold, 0) {
			return error('drag threshold must be finite and nonnegative')
		}
		preview := source.preview
		preview.image_asset.validate()!
		preview.image_style.validate()!
		for value in [preview.width, preview.height, preview.offset_x, preview.offset_y] {
			if math.is_nan(value) || math.is_inf(value, 0) {
				return error('drag preview geometry must be finite')
			}
		}
		if preview.width <= 0 || preview.height <= 0 {
			return error('drag preview dimensions must be positive')
		}
	}
	if target := el.drop_target {
		if voidptr(target.accept) == unsafe { nil } {
			return error('drop target requires an acceptance query')
		}
	}
	$if !( android || linux || ( ( macos || windows ) && ui2_custom_rendering ?) ) && !ui2_headless ? {
		return error('drag-drop requires the custom renderer')
	}
}

// cancel_drag is safe when idle. Native profiles reject drag declarations.
$if !( ( android || linux || ( ( macos || windows ) && ui2_custom_rendering ?) ) && !ui2_headless ?) {
	pub fn cancel_drag() {}
	pub fn drag_active() bool { return false }
}

fn drag_preview_transform(source ContentTransform, window_x f64, window_y f64) ContentTransform {
	origin := source.project(rect(0, 0, 0, 0))
	return ContentTransform{ x: window_x - origin.x, y: window_y - origin.y }.compose(source)
}
