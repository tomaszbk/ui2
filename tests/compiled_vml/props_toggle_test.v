module main

// vml: ../../examples/toggle_button/toggle_button.vml

import ui2

// A styled ToggleButton's compiled pressed face spreads a call result, which V
// accepts only outside module ui2, so its props equivalence is checked here
// against the toggle_button example: ToggleButtonProps built and styled the
// way the retained runtime does must give the same element.

pub struct PropsToggleDemo {
pub mut:
	bold   bool = true
	italic bool
}

fn props_toggle_tree(mut app PropsToggleDemo) ui2.Element {
	return toggle_button_vml_framed(mut app, ui2.rect(0, 0, 340, 200))
}

fn props_toggle_find(el ui2.Element, id string) ?ui2.Element {
	if el.id == id {
		return el
	}
	for child in el.children {
		if found := props_toggle_find(child, id) {
			return found
		}
	}
	return none
}

fn props_toggle_fields(el ui2.Element) string {
	return '${el.kind}|${el.text}|${el.checked}|${el.toggle_group()}|${el.toggle_allow_no_selection()}|${el.native_style}|${el.enabled}|${el.accessibility_role}|${el.accessibility_label}|${el.accessibility_value}\n${el.box}\n${el.text_style}\n${el.toggle_down_box()}\n${el.toggle_down_text_style()}\n${el.interaction_style}'
}

fn test_styled_toggle_button_props_match_compiled_vml() {
	mut app := PropsToggleDemo{}
	tree := props_toggle_tree(mut app)
	style := ui2.compose_styles([ui2.style_background(0xE2E8F0), ui2.style_foreground(0x1E293B),
		ui2.style_radius(7)])
	for id, title in {
		'bold':   'Bold'
		'italic': 'Italic'
	} {
		compiled := props_toggle_find(tree, id) or { panic('missing ${id}') }
		props := ui2.ToggleButtonProps{
			text:               title
			pressed:            if id == 'bold' { app.bold } else { app.italic }
			group:              'formatting'
			allow_no_selection: false
			down_background:    0x1D4ED8
			down_color:         0xFFFFFF
			style:              style
		}
		built := ui2.vml_build_element(props, ui2.VmlBuildContext{
			id:    id
			frame: compiled.frame
		})!
		styled := ui2.apply_style(built, style)!
		assert props_toggle_fields(styled) == props_toggle_fields(compiled)
		assert compiled.toggle_down_text_style().color == 0xFFFFFF
		assert compiled.toggle_down_box().bg == 0x1D4ED8
	}
}
