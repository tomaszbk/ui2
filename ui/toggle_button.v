module ui2

pub struct ToggleButtonConfig {
pub:
	id                 string
	on_event           ElementCallback = unsafe { nil }
	title              string
	frame              Rect
	pressed            bool
	group              string
	allow_no_selection bool = true
	box                BoxStyle
	down_box           BoxStyle = BoxStyle{ bg: 0x2563eb, radius: 6 }
	text_style         TextStyle
	down_text_style    TextStyle = TextStyle{ color: 0xffffff }
	native_style       bool
}

// ToggleSpec is what only a toggle button declares: its exclusive group and
// its pressed presentation. Elements share it by reference.
pub struct ToggleSpec {
pub:
	group              string
	allow_no_selection bool = true
	down_box           BoxStyle
	down_text_style    TextStyle
}

// An element without a toggle spec reads the defaults below.
pub fn (el &Element) toggle_group() string {
	return if spec := el.toggle { spec.group } else { '' }
}

pub fn (el &Element) toggle_allow_no_selection() bool {
	return if spec := el.toggle { spec.allow_no_selection } else { true }
}

// toggle_selection reads the selection rule of a possibly absent spec.
fn toggle_selection(toggle ?&ToggleSpec) (string, bool) {
	spec := toggle or { return '', true }
	return spec.group, spec.allow_no_selection
}

pub fn (el &Element) toggle_down_box() BoxStyle {
	return if spec := el.toggle { spec.down_box } else { BoxStyle{} }
}

pub fn (el &Element) toggle_down_text_style() TextStyle {
	return if spec := el.toggle { spec.down_text_style } else { TextStyle{} }
}

pub fn (el Element) with_toggle_down_box(box BoxStyle) Element {
	spec := el.toggle or { &ToggleSpec{} }
	return Element{ ...el, toggle: &ToggleSpec{ ...spec, down_box: box } }
}

pub fn (el Element) with_toggle_down_text_style(style TextStyle) Element {
	spec := el.toggle or { &ToggleSpec{} }
	return Element{ ...el, toggle: &ToggleSpec{ ...spec, down_text_style: style } }
}

// toggle_button creates a button that retains an explicit pressed/released
// state across rebuilds. Its action fires after the backend has toggled the
// live state, so toggle_button_pressed can be read from the callback. Controls
// sharing a non-empty group are mutually exclusive; allow_no_selection controls
// whether pressing the selected member can release it.
pub fn toggle_button(config ToggleButtonConfig) Element {
	return Element{
		kind:                .toggle_button
		id:                  config.id
		on_event:            config.on_event
		text:                config.title
		frame:               config.frame
		box:                 config.box
		text_style:          config.text_style
		checked:             config.pressed
		toggle:              &ToggleSpec{
			group:              config.group
			allow_no_selection: config.allow_no_selection
			down_box:           config.down_box
			down_text_style:    config.down_text_style
		}
		native_style:        config.native_style
		accessibility_role:  'button'
		accessibility_label: config.title
		accessibility_value: if config.pressed { 'pressed' } else { 'released' }
	}
}
