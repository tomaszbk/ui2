module ui2

// Absolute preserves explicitly authored parent-local child geometry. It is
// useful for canvases, game HUDs and the visual designer's free positioning.
pub struct AbsoluteConfig {
pub:
	id       string
	frame    Rect
	box      BoxStyle
	children []Element
}

pub fn absolute_frames(config AbsoluteConfig) ![]Rect {
	validate_layout_frame(config.frame)!
	mut frames := []Rect{cap: config.children.len}
	for child in config.children {
		validate_layout_frame(child.frame)!
		frames << child.frame
	}
	return frames
}

pub fn absolute(config AbsoluteConfig) !Element {
	absolute_frames(config)!
	return Element{
		...view(config.id, config.frame, config.box, config.children)
		layout_input: config.frame
		layout:       LayoutSpec{ kind: .absolute }
	}
}

// Natural content extent includes positioned children, exposing overflowing
// content to a Scroll parent without changing explicit viewport dimensions.
pub fn absolute_preferred_size(config AbsoluteConfig) !Rect {
	absolute_frames(config)!
	mut width := 0.0
	mut height := 0.0
	for child in config.children {
		right := child.frame.x + child.frame.width
		bottom := child.frame.y + child.frame.height
		if !layout_finite(right) || !layout_finite(bottom) {
			return error('absolute content extent must be finite')
		}
		width = layout_max(width, right)
		height = layout_max(height, bottom)
	}
	return rect(0, 0, width, height)
}
