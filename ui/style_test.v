// vtest vflags: -d ui2_custom_rendering
module ui2

import math

fn test_style_sparse_composition_preserves_absence_zero_black_false_and_order() ! {
	card := compose_styles([style_background(0x123456), style_padding(12), style_radius(8)])
	patch := compose_styles([card, style_background(0), style_radius(0), style_transparent(false),
		style_foreground(0), style_italic(false), style_border_left(0)])
	assert patch.box.bg? == 0
	assert patch.box.radius? == 0
	assert !patch.box.transparent?
	assert patch.box.border_left? == 0
	assert patch.box.border_top == none
	assert patch.text.foreground? == 0
	assert !patch.text.italic?
	assert patch.text.font_size == none
	assert patch.padding_left? == 12
	result := apply_style(view('card', rect(1, 2, 50, 40), BoxStyle{ border_top: 3 }, []), patch)!
	assert result.id == 'card' && result.frame == rect(1, 2, 50, 40)
	assert result.box.bg == 0 && result.box.radius == 0 && result.box.border_top == 3
	assert result.layout.stack.padding == LayoutPadding{ left: 12, top: 12, right: 12, bottom: 12 }
	assert compose_styles([style_background(0), card]).box.bg? == 0x123456
}

fn test_style_interaction_composition_uses_existing_paint_precedence() ! {
	patch := compose_styles([
		style_background(0xffffff),
		style_hover([style_background(0x111111), style_foreground(0x222222)])!,
		style_focus([style_radius(4)])!,
		style_pressed([style_background(0)])!,
		style_disabled([style_foreground(0)])!,
		style_hover([style_border_width(2)])!,
	])
	base := button('button', 'Guardar', Rect{}, BoxStyle{}, TextStyle{})
	result := apply_style(base, patch)!
	assert interaction_box(result, true, true, true).bg == 0
	assert interaction_box(result, true, true, true).radius == 4
	assert interaction_box(result, true, true, true).border_left == 2
	assert interaction_text_style(result, true, true, false).color == 0x222222
	assert interaction_text_style(Element{ ...result, enabled: false }, true, true, true).color == 0
	if _ := style_hover([style_padding(0)]) {
		assert false
	}
	if _ := style_pressed([style_font_size(0)]) {
		assert false
	}
}

fn test_style_replacement_restores_constructor_defaults_and_preserves_live_data() ! {
	mut owner := new_vml_document('style replacement')!
	owner.set_publisher(fn (_ string, _ Element) {})!
	mut patch := owner.state('style', compose_styles([style_background(0), style_radius(12),
		style_font_size(24)]))!
	mut node := owner.element(Element{
		...label('caption', 'declarado', rect(3, 4, 70, 30), TextStyle{ size: 17 })
		key:            'same'
		focused:        true
		text_selection: TextSelection{ anchor: 1, caret: 3 }
		tooltip:        'help'
	})!
	node.style(fn [mut patch] () !StylePatch { return patch.get()! })!
	node.mount()!
	assert node.element().box.bg == 0 && node.element().text_style.size == 24
	identity := node.identity()
	node.patch(fn (element Element) Element { return Element{ ...element, text: 'ñ café' } })!
	patch.set(compose_styles([style_foreground(0)]))!
	result := node.element()
	assert result.box == label('', '', Rect{}, TextStyle{}).box
	assert result.text_style.size == 17 && result.text_style.color == 0
	assert result.text == 'ñ café' && result.tooltip == 'help'
	assert result.key == 'same' && result.focused && result.text_selection == TextSelection{ anchor: 1, caret: 3 }
	assert node.identity() == identity
	owner.dispose()!
	assert owner.runtime.stats() == SignalStats{}
}

fn style_fixture_measure(_ string, style TextStyle, _ f64) !LayoutSize {
	return LayoutSize{ width: 20, height: style.size }
}

fn test_style_padding_uses_fractional_stack_geometry_and_paint_changes_reuse_layout() ! {
	leaf := label('content', 'Contenido', Rect{}, TextStyle{ size: 15 })
	base := view('card', rect(0, 0, 100, 60), BoxStyle{}, [leaf])
	styled := apply_style(base, compose_styles([style_padding(12.5), style_background(0)]))!
	mut tree := LayoutTree{}
	tree.replace(styled)!
	first := tree.resolve(LayoutConstraints{}, style_fixture_measure, LayoutEnvironment{})!
	assert first.children[0].frame == rect(12.5, 12.5, 20, 15)
	identity := tree.identity('content')?
	tree.reset_stats()
	tree.patch('card', apply_style(styled, style_background(0xffffff))!)!
	paint := tree.resolve(LayoutConstraints{}, style_fixture_measure, LayoutEnvironment{})!
	assert paint.children[0].frame == first.children[0].frame
	assert tree.identity('content')? == identity
	assert tree.stats().measure_visits == 0 && tree.stats().layout_visits == 0
	tree.patch('card', apply_style(base, style_padding(3.25))!)!
	changed := tree.resolve(LayoutConstraints{}, style_fixture_measure, LayoutEnvironment{})!
	assert changed.children[0].frame.x == 3.25 && changed.children[0].frame.y == 3.25
	assert tree.stats().layout_visits > 0
	plain := apply_style(base, StylePatch{})!
	assert plain.layout.kind == .none
}

fn test_style_native_profile_checks_explicit_supplied_zero_and_false() ! {
	validate_native_style(compose_styles([style_background(0), style_radius(0)]), .view)!
	for patch in [style_outline_width(0), style_letter_spacing(0), style_tabular_figures(false),
		style_hover([style_background(0)])!] {
		if _ := validate_native_style(patch, .view) {
			assert false, 'unsupported supplied properties need a diagnostic'
		}
	}
	for patch in [style_padding(-1), style_radius(math.inf(1)), style_font_size(-1), style_weight(99)] {
		if _ := apply_style(view('v', Rect{}, BoxStyle{}, []), patch) {
			assert false
		}
	}
}

fn test_theme_tokens_update_only_consumers_inherit_and_override_per_component() ! {
	mut owner := new_vml_document('theme')!
	owner.set_publisher(fn (_ string, _ Element) {})!
	mut child := owner.child('child')!
	mut sibling := owner.child('sibling')!
	mut accent_runs := owner.state('accent runs', 0)!
	mut surface_runs := owner.state('surface runs', 0)!
	mut accent := owner.element(view('accent', Rect{}, BoxStyle{}, []))!
	mut surface := child.element(view('surface', Rect{}, BoxStyle{}, []))!
	accent.style(fn [mut owner, mut accent_runs] () !StylePatch {
		accent_runs.set(accent_runs.peek()! + 1)!
		return style_background(owner.color_token('accent')!)
	})!
	surface.style(fn [mut child, mut surface_runs] () !StylePatch {
		surface_runs.set(surface_runs.peek()! + 1)!
		return style_background(child.color_token('surface')!)
	})!
	assert accent_runs.peek()! == 1 && surface_runs.peek()! == 1
	owner.set_theme(Theme{
		colors: {
			'accent': u32(0)
		}
	})!
	assert accent_runs.peek()! == 2 && surface_runs.peek()! == 1
	assert accent.element().box.bg == 0
	assert child.color_token('accent')! == 0 && sibling.color_token('accent')! == 0
	child.set_theme(Theme{
		colors: {
			'surface': u32(0x444444)
			'accent':  u32(0x555555)
		}
	})!
	assert surface_runs.peek()! == 2
	owner.set_theme(Theme{
		colors: {
			'accent':  u32(0x666666)
			'surface': u32(0x777777)
		}
	})!
	assert child.color_token('surface')! == 0x444444 && surface_runs.peek()! == 2
	assert sibling.color_token('surface')! == 0x777777
	child.set_theme(Theme{})!
	assert child.color_token('surface')! == 0x777777 && surface_runs.peek()! == 3
	assert child.color_token('accent')! == 0x666666
	owner.set_theme(Theme{})!
	assert child.spacing_token('medium')! == 12 && child.radius_token('large')! == 12
	owner.dispose()!
	assert owner.runtime.stats() == SignalStats{}
}

fn test_theme_values_are_owned_and_readable_from_pure_memos() ! {
	mut owner := new_vml_document('pure theme')!
	mut colors := {
		'accent': u32(0)
	}
	owner.set_theme(Theme{ colors: colors })!
	colors['accent'] = 0xff0000
	assert owner.color_token('accent')! == 0
	owner.prepare_theme_tokens(['color:accent', 'spacing:medium'])!
	mut memo := owner.computed('style', fn [mut owner] () !StylePatch {
		return compose_styles([style_background(owner.color_token('accent')!),
			style_padding(owner.spacing_token('medium')!)])
	})!
	assert memo.get()!.box.bg? == 0
	owner.set_theme(Theme{
		colors:  {
			'accent': u32(0x123456)
		}
		spacing: {
			'medium': f64(0)
		}
	})!
	assert memo.get()!.box.bg? == 0x123456 && memo.get()!.padding_left? == 0
	if _ := owner.color_token('missing') {
		assert false
	}
	if _ := owner.set_theme(Theme{
		radii: {
			'bad': f64(-1)
		}
	}) {
		assert false
	}
	owner.dispose()!
}

fn test_button_padding_changes_intrinsic_measurement_and_inner_paint_box() ! {
	base := button('button', 'Guardar', Rect{}, BoxStyle{}, TextStyle{ size: 15 })
	padded := apply_style(base, style_padding(12.5))!
	assert measure_layout_element(padded, LayoutConstraints{}, style_fixture_measure)! == LayoutSize{ width: 45, height: 40 }
	positioned := Element{ ...padded, frame: rect(7, 9, 80, 50) }
	assert button_content_rect(positioned) == rect(12.5, 12.5, 55, 25)
	zero := apply_style(base, style_padding(0))!
	assert measure_layout_element(zero, LayoutConstraints{}, style_fixture_measure)! == LayoutSize{ width: 20, height: 15 }
	assert button_content_rect(Element{ ...zero, frame: rect(0, 0, 80, 50) }) == rect(0, 0, 80, 50)
	if _ := validate_native_style(style_padding(0), .button) {
		assert false
	}
}

fn test_theme_only_allocates_requested_sources_and_rejects_orphaned_custom_token_atomically() ! {
	mut owner := new_vml_document('custom theme',
		theme: Theme{
			colors: {
				'brand': u32(0x123456)
			}
		}
	)!
	assert owner.runtime.stats().signals == 1 // application revision; theme unused
	owner.prepare_theme_tokens(['color:brand'])!
	assert owner.runtime.stats().signals == 2
	mut child := owner.child('child')!
	assert owner.runtime.stats().signals == 2
	child.prepare_theme_tokens(['color:brand'])!
	assert child.color_token('brand')! == 0x123456
	if _ := owner.set_theme(Theme{}) {
		assert false
	}
	assert owner.color_token('brand')! == 0x123456
	assert child.color_token('brand')! == 0x123456
	assert owner.theme.colors['brand'] == 0x123456
	child.set_theme(Theme{
		colors: {
			'brand': u32(0)
		}
	})!
	assert child.color_token('brand')! == 0
	child.set_theme(Theme{})!
	assert child.color_token('brand')! == 0x123456
	owner.dispose()!
	assert owner.runtime.stats() == SignalStats{}
}

fn test_progress_bar_style_refines_fill_and_track_for_structural_updates() ! {
	patch := compose_styles([style_background(0), style_foreground(0x123456), style_radius(0)])
	initial := progress_bar(style_progress_bar(ProgressBarConfig{ frame: rect(0, 0, 100, 10), value: 20 }, patch)!)
	assert initial.box.bg == 0 && initial.box.radius == 0
	assert initial.children[0].box.bg == 0x123456 && initial.children[0].box.radius == 0
	changed := progress_bar(style_progress_bar(ProgressBarConfig{ frame: rect(0, 0, 100, 10), value: 75 }, patch)!)
	assert changed.children[0].frame.width == 75
	assert changed.box == initial.box && changed.children[0].box == initial.children[0].box
}

fn test_progress_styled_constructor_retains_unstyled_track_defaults_for_replacement() ! {
	mut owner := new_vml_document('progress defaults')!
	owner.set_publisher(fn (_ string, _ Element) {})!
	mut patch := owner.state('style', compose_styles([style_background(0), style_radius(0)]))!
	initial_config := style_progress_bar(ProgressBarConfig{ id: 'progress', frame: rect(0, 0, 100, 10), value: 20 }, patch.get()!)!
	mut node := owner.element(progress_bar(initial_config))!
	node.style(fn [mut patch] () !StylePatch { return patch.get()! })!
	assert node.element().box.bg == 0 && node.element().box.radius == 0
	patch.set(StylePatch{})!
	assert node.element().box.bg == 0xe2e8f0
	assert node.element().box.radius == 4
	owner.dispose()!
}

fn test_tree_style_targets_owned_row_typography_without_replacing_part_colors() ! {
	config := TreeViewConfig{
		text_style:            TextStyle{ color: 0x111111, size: 14 }
		selected_text_style:   TextStyle{ color: 0x222222, size: 14, bold: true }
		disclosure_text_style: TextStyle{ color: 0x333333, size: 14 }
	}
	styled := style_tree_view(config, compose_styles([style_foreground(0), style_font_size(22),
		style_italic(true)]))!
	assert styled.text_style.color == 0
	assert styled.text_style.size == 22 && styled.text_style.italic
	assert styled.selected_text_style.color == 0x222222 && styled.selected_text_style.size == 22
	assert styled.disclosure_text_style.color == 0x333333 && styled.disclosure_text_style.size == 22
	assert style_tree_view(config, StylePatch{})! == config
}

fn test_native_style_masks_follow_actual_appkit_control_capabilities() ! {
	$if macos {
		validate_native_style(compose_styles([style_foreground(0), style_font_size(15),
			style_weight(700)]), .label)!
		validate_native_style(compose_styles([style_background(0), style_foreground(0),
			style_weight(700)]), .button)!
		for patch in [style_background(0), style_radius(0), style_transparent(false)] {
			if _ := validate_native_style(patch, .label) {
				assert false
			}
		}
		for patch in [style_weight(700), style_italic(false), style_font_family(''),
			style_padding_left(0)] {
			if _ := validate_native_style(patch, .text_field) {
				assert false
			}
		}
		if _ := validate_native_style(style_foreground(0), .dropdown) {
			assert false
		}
		if _ := validate_native_style(style_text_align(.center), .button) {
			assert false
		}
		if _ := validate_native_style(style_background(0), .image) {
			assert false
		}
		if _ := validate_native_style(style_border_width(0), .screen) {
			assert false
		}
	}
}

fn test_style_text_enum_and_empty_string_composition_preserves_typed_values() ! {
	patch := compose_styles([style_text_align(.right), style_text_valign(.top),
		style_font_family('Inter'), style_text_align(.left), style_font_family('')])
	assert patch.text.text_align? == .left
	assert patch.text.text_valign? == .top
	assert patch.text.font_family? == ''
	text := apply_text_style(TextStyle{ align: .center, font_family: 'Serif' }, patch)!
	assert text.align == .left && text.valign == .top && text.font_family == ''
}
