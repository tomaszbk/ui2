module ui2

// Stack overlays children in declaration order. Later children paint above
// earlier children; frames remain local to the stack's padded content area.
pub struct StackChild {
pub:
	element Element
	align_x LayoutAlignment = .auto
	align_y LayoutAlignment = .auto
}

// StackRule is a StackChild without its element: the alignment a container
// retains for a child.
struct StackRule {
	align_x LayoutAlignment = .auto
	align_y LayoutAlignment = .auto
}

fn stack_rule(child StackChild) StackRule {
	return StackRule{ align_x: child.align_x, align_y: child.align_y }
}

fn (rule StackRule) stack_child() StackChild {
	return StackChild{ align_x: rule.align_x, align_y: rule.align_y }
}

// stack_rules splits children into their rules and the sizes they lay out.
fn stack_rules(children []StackChild) ([]StackRule, []Rect) {
	mut rules := []StackRule{cap: children.len}
	mut sizes := []Rect{cap: children.len}
	for index in 0 .. children.len {
		rules << stack_rule(children[index])
		sizes << children[index].element.frame
	}
	return rules, sizes
}

// A child without a rule takes the container's alignment.
fn stack_rule_at(rules []StackRule, index int) StackRule {
	return if index < rules.len { rules[index] } else { StackRule{} }
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

fn stack_validate(config StackConfig, sizes []Rect) ! {
	stack_validate_container(config)!
	for size in sizes { validate_layout_frame(size)! }
}

fn stack_validate_container(config StackConfig) ! {
	validate_layout_frame(config.frame)!
	if config.align_x == .auto || config.align_y == .auto {
		return error('stack container alignment cannot be auto')
	}
	for value in [config.padding.left, config.padding.top, config.padding.right, config.padding.bottom]! {
		if !layout_finite(value) || value < 0 {
			return error('stack padding must be finite and non-negative')
		}
	}
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
	rules, sizes := stack_rules(config.children)
	return stack_layout_frames(config, rules, sizes)
}

// stack_layout_frames places child sizes under their rules. The config's own
// children are ignored.
fn stack_layout_frames(config StackConfig, rules []StackRule, sizes []Rect) ![]Rect {
	stack_validate(config, sizes)!
	width := layout_max(0, config.frame.width - config.padding.left - config.padding.right)
	height := layout_max(0, config.frame.height - config.padding.top - config.padding.bottom)
	mut frames := []Rect{cap: sizes.len}
	for index, size in sizes {
		child := stack_rule_at(rules, index)
		align_x := if child.align_x == .auto { config.align_x } else { child.align_x }
		align_y := if child.align_y == .auto { config.align_y } else { child.align_y }
		x, w := stack_axis(config.padding.left, width, size.width, align_x)
		y, h := stack_axis(config.padding.top, height, size.height, align_y)
		frames << rect(x, y, w, h)
	}
	return frames
}

pub fn stack_preferred_size(config StackConfig) !Rect {
	_, sizes := stack_rules(config.children)
	return stack_layout_preferred_size(config, sizes)
}

fn stack_layout_preferred_size(config StackConfig, sizes []Rect) !Rect {
	stack_validate(config, sizes)!
	mut width := 0.0
	mut height := 0.0
	for size in sizes {
		width = layout_max(width, size.width)
		height = layout_max(height, size.height)
	}
	return rect(0, 0, width + config.padding.left + config.padding.right,
		height + config.padding.top + config.padding.bottom)
}

// stack places its children once and keeps their rules, without their
// elements, in the returned element's layout.
pub fn stack(config StackConfig) !Element {
	rules, sizes := stack_rules(config.children)
	frames := stack_layout_frames(config, rules, sizes)!
	mut children := []Element{cap: config.children.len}
	for index, child in config.children {
		children << Element{ ...layout_declared(child.element), frame: frames[index] }
	}
	return stack_view(config, children, rules)
}

// stack_with_rules lays out children whose rules the caller already holds,
// one per child, without wrapping each child in a StackChild.
fn stack_with_rules(config StackConfig, children []Element, rules []StackRule) !Element {
	mut sizes := []Rect{cap: children.len}
	for child in children { sizes << child.frame }
	frames := stack_layout_frames(config, rules, sizes)!
	mut laid := []Element{cap: children.len}
	for index, child in children {
		laid << Element{ ...layout_declared(child), frame: frames[index] }
	}
	return stack_view(config, laid, rules)
}

fn stack_view(config StackConfig, children []Element, rules []StackRule) Element {
	return Element{
		...view(config.id, config.frame, config.box, children)
		layout_input: config.frame
		layout:       LayoutSpec{
			kind:        .stack
			stack:       stack_layout_spec(config)
			stack_rules: rules
		}
	}
}
