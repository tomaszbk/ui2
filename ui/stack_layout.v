module ui2

// Stack overlays children in declaration order. Later children paint above
// earlier children; frames remain local to the stack's padded content area.
pub struct StackChild {
pub:
	element Element
	align_x LayoutAlignment = .auto
	align_y LayoutAlignment = .auto
}

pub struct StackConfig {
pub:
	id       string
	frame    Rect
	box      BoxStyle
	padding  LayoutPadding
	align_x  LayoutAlignment = .start
	align_y  LayoutAlignment = .start
	children []StackChild
}

fn stack_validate(config StackConfig) ! {
	validate_layout_frame(config.frame)!
	if config.align_x == .auto || config.align_y == .auto {
		return error('stack container alignment cannot be auto')
	}
	for value in [config.padding.left, config.padding.top, config.padding.right, config.padding.bottom] {
		if !layout_finite(value) || value < 0 {
			return error('stack padding must be finite and non-negative')
		}
	}
	for child in config.children { validate_layout_frame(child.element.frame)! }
}

fn stack_axis(start f64, available f64, preferred f64, alignment LayoutAlignment) (f64, f64) {
	size := if alignment == .stretch { available } else { preferred }
	position := match alignment {
		.center { start + (available - size) / 2 }
		.end { start + available - size }
		else { start }
	}
	return position, size
}

pub fn stack_frames(config StackConfig) ![]Rect {
	stack_validate(config)!
	width := layout_max(0, config.frame.width - config.padding.left - config.padding.right)
	height := layout_max(0, config.frame.height - config.padding.top - config.padding.bottom)
	mut frames := []Rect{cap: config.children.len}
	for child in config.children {
		align_x := if child.align_x == .auto { config.align_x } else { child.align_x }
		align_y := if child.align_y == .auto { config.align_y } else { child.align_y }
		x, w := stack_axis(config.padding.left, width, child.element.frame.width, align_x)
		y, h := stack_axis(config.padding.top, height, child.element.frame.height, align_y)
		frames << rect(x, y, w, h)
	}
	return frames
}

pub fn stack_preferred_size(config StackConfig) !Rect {
	stack_validate(config)!
	mut width := 0.0
	mut height := 0.0
	for child in config.children {
		width = layout_max(width, child.element.frame.width)
		height = layout_max(height, child.element.frame.height)
	}
	return rect(0, 0, width + config.padding.left + config.padding.right,
		height + config.padding.top + config.padding.bottom)
}

pub fn stack(config StackConfig) !Element {
	frames := stack_frames(config)!
	mut children := []Element{cap: config.children.len}
	for index, child in config.children {
		children << Element{ ...child.element, frame: frames[index] }
	}
	return view(config.id, config.frame, config.box, children)
}
