module ui2

// The native profile (backend.v, native_controls.v) is plain validation, so
// it is tested with every backend, not only where the operating system's
// controls run.

fn native_profile_rejects(name string, el Element) {
	validate_native_element(el) or {
		assert err.msg().contains('-d ui2_custom_rendering'), '${name}: ${err.msg()}'
		return
	}
	assert false, '${name} must be a diagnostic in the native profile'
}

fn test_native_profile_names_the_custom_renderer_for_what_os_controls_cannot_show() {
	plain := view('box', rect(0, 0, 40, 20), BoxStyle{}, [])
	native_profile_rejects('hover', with_interaction_style(plain, InteractionStyle{
		hover: BoxStylePatch{
			bg: 0x123456
		}
	}))
	native_profile_rejects('focus ring', with_interaction_style(plain, InteractionStyle{
		focus: BoxStylePatch{
			outline_width: 2
		}
	}))
	native_profile_rejects('control paint', Element{
		...with_native_style(button('save', 'Save', Rect{}, BoxStyle{}, TextStyle{}))
		paint: &ControlPaint{}
	})
	native_profile_rejects('outline', view('box', Rect{}, BoxStyle{ outline_width: 1 }, []))
	native_profile_rejects('dashed border', view('box', Rect{}, BoxStyle{
		border_pattern: .dashed
		border_left:    1
	}, []))
	native_profile_rejects('per-side color', view('box', Rect{}, BoxStyle{
		border_left:       1
		border_left_color: 0xff0000
	}, []))
	native_profile_rejects('tracking', label('caption', 'Text', Rect{}, TextStyle{
		letter_spacing: 1
	}))
	native_profile_rejects('strikethrough label', label('caption', 'Text', Rect{}, TextStyle{
		strikethrough: true
	}))
}

fn test_native_profile_accepts_layer_backed_boxes_and_os_controls() ! {
	validate_native_element(view('card', rect(0, 0, 200, 80), BoxStyle{
		bg:            0xf8fafc
		radius:        8
		border_color:  0xcbd5e1
		border_left:   1
		border_top:    1
		border_right:  1
		border_bottom: 1
	}, []))!
	validate_native_element(label('caption', 'Caption', Rect{}, TextStyle{
		size:   18
		weight: 600
		italic: true
	}))!
	validate_native_element(with_native_style(button('save', 'Save', Rect{}, BoxStyle{},
		TextStyle{})))!
	// A text area shows rich text itself.
	validate_native_element(Element{
		kind:       .text_area
		id:         'notes'
		text_style: TextStyle{
			strikethrough: true
		}
	})!
}

fn test_native_style_profile_checks_explicit_supplied_zero_and_false() ! {
	validate_native_style(compose_styles([style_background(0), style_radius(0)]), .view)!
	for patch in [style_outline_width(0), style_letter_spacing(0), style_tabular_figures(false),
		style_hover([style_background(0)])!] {
		if _ := validate_native_style(patch, .view) {
			assert false, 'unsupported supplied properties need a diagnostic'
		}
	}
	if _ := validate_native_style(style_padding(0), .button) {
		assert false, 'button content padding needs a diagnostic'
	}
}

fn test_kit_button_is_the_platform_push_button_in_native_mode() ! {
	tokens := kit_tokens(Theme{})
	for variant in [ButtonVariant.primary, .secondary, .ghost, .link, .danger] {
		el := kit_native_button(tokens, 'save', Rect{}, ButtonProps{
			text:    'Save'
			variant: variant
		}, [])!
		assert el.kind == .button
		assert el.native_style
		assert el.text == 'Save'
		assert el.accessibility_label == 'Save'
		assert el.interaction_style == InteractionStyle{}
		validate_native_element(el)!
	}
	disabled := kit_native_button(tokens, 'save', Rect{}, ButtonProps{
		CommonProps: CommonProps{
			enabled: false
		}
		text:        'Save'
	}, [])!
	assert !disabled.enabled
	for name, props in {
		'icon':     ButtonProps{
			text: 'Save'
			icon: .close
		}
		'loading':  ButtonProps{
			text:    'Save'
			loading: true
		}
		'selected': ButtonProps{
			text:     'Save'
			selected: true
		}
	} {
		kit_native_button(tokens, 'save', Rect{}, props, []) or {
			assert err.msg().contains('-d ui2_custom_rendering'), name
			continue
		}
		assert false, 'a native Button cannot show ${name}'
	}
	kit_native_button(tokens, 'save', Rect{}, ButtonProps{ text: 'Save' }, [
		label('', 'child', Rect{}, TextStyle{}),
	]) or {
		assert err.msg().contains('-d ui2_custom_rendering')
		return
	}
	assert false, 'a native Button cannot show children'
}
