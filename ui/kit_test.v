module ui2

import math

// The kit's shared pieces: color math, part ids, icons and the tokens.

fn test_kit_colors_mix_contrast_and_legibility() {
	assert kit_mix(0x000000, 0xffffff, 0) == 0x000000
	assert kit_mix(0x000000, 0xffffff, 1) == 0xffffff
	assert kit_mix(0x000000, 0xffffff, 0.5) == 0x808080
	assert kit_mix(0x102030, 0x102030, 0.3) == 0x102030
	assert kit_mix(0x000000, 0xffffff, 7) == 0xffffff
	assert math.abs(kit_contrast(0x000000, 0xffffff) - 21) < 0.01
	assert math.abs(kit_contrast(0x777777, 0x777777) - 1) < 1e-9
	light := kit_tokens(default_theme())
	dark := kit_tokens(dark_theme())
	// The warning yellow is a fill; as text on white it must be darkened.
	assert kit_contrast(light.warning, light.surface) < 4.5
	assert kit_contrast(kit_legible(light.warning, light.surface, light.text), light.surface) >= 4.5
	assert kit_legible(dark.accent, dark.surface, dark.text) == dark.accent
}

fn test_kit_part_ids_follow_the_overlay_convention() {
	assert kit_part_id('tabs', 'trigger') == 'tabs__trigger'
	assert kit_part_id('', 'trigger') == ''
	ctx := VmlBuildContext{
		id: 'menu'
	}
	assert ctx.part_id('surface') == 'menu__surface'
	assert ctx.emitter(unsafe { nil }).id == 'menu'
}

fn test_kit_icons_map_to_portable_symbols() {
	names := icon_names()
	assert names.len == int(IconName.triangle_alert)
	mut seen := map[string]bool{}
	for name in names {
		assert name != .none
		assert symbol_known(name.symbol()), '${name}: ${name.symbol()}'
		seen[name.str()] = true
	}
	assert seen.len == names.len
	assert IconName.none.symbol() == '' && IconName.none.title() == ''
	assert IconName.eye_off.title() == 'Eye off'
	assert IconName.padlock.symbol() == 'lock'
	assert IconName.chevron_down.symbol() == 'chevron.down'
	assert icon_pixel_size(.large) == 24
}

fn test_kit_tokens_keep_the_kit_palette_and_metrics() {
	light := kit_tokens(default_theme())
	assert !light.dark
	assert light.surface == 0xffffff && light.text == 0x172033 && light.accent == 0x2563eb
	assert light.hover == kit_mix(light.surface_muted, light.text, 0.06)
	assert light.pressed == kit_mix(light.surface_muted, light.text, 0.12)
	assert light.popup_shadow() == box_shadow(0, 0.16, 24, 8)
	assert light.card_shadow() == box_shadow(0, 0.12, 16, 4)
	assert light.scrim_opacity() == 0.4
	small := light.metrics(.small)
	medium := light.metrics(.medium)
	large := light.metrics(.large)
	assert [small.height, medium.height, large.height] == [24.0, 32, 40]
	assert [small.font_size, medium.font_size, large.font_size] == [12.0, 14, 16]
	assert [small.padding_x, medium.padding_x, large.padding_x] == [9.0, 12, 18]
	assert [small.gap, medium.gap, large.gap] == [4.0, 6, 8]
	assert [small.radius, medium.radius, large.radius] == [4.0, 6, 8]
	// The vertical padding centers one line of text in the control height.
	assert medium.padding_y * 2 + font_line_height(medium.font_size) == medium.height
	fill, text := light.tone_colors(.warning)
	assert fill == 0xfbbf24 && text == 0x172033
	dark := kit_tokens(dark_theme())
	assert dark.dark
	assert dark.surface == 0x172033 && dark.text == 0xf8fafc && dark.accent == 0x93c5fd
	assert dark.hover == kit_mix(dark.surface_muted, dark.text, 0.06)
	assert dark.scrim_opacity() == 0.6
	assert dark.metrics(.medium) == medium
	// The control chrome comes from the same tokens and is shared by builds.
	paint := light.control_paint()
	assert paint.surface == light.input && paint.border == light.input_border
	assert paint.accent == light.accent && paint.placeholder == light.muted
	assert paint.radius == medium.radius && paint.chrome
	assert voidptr(light.control_paint()) == voidptr(paint)
	assert dark.control_paint().surface == 0x0f172a
	assert KitTokens{}.control_paint().surface == light.input
	// A partial theme keeps the defaults it leaves out.
	partial := kit_tokens(Theme{
		colors: {
			'accent': u32(0x123456)
		}
	})
	assert partial.accent == 0x123456 && partial.surface == 0xffffff
	assert partial.metrics(.large) == large
}

fn test_kit_tokens_follow_the_owner_chain_and_theme_changes() ! {
	mut owner := new_vml_document('kit tokens',
		theme: Theme{
			colors:  {
				'accent': u32(0x111111)
			}
			spacing: {
				'control_height_medium': f64(36)
			}
		}
	)!
	mut child := owner.child('child')!
	child.set_theme(Theme{
		colors: {
			'surface': u32(0x222222)
		}
	})!
	tokens := child.kit_tokens()
	assert tokens.accent == 0x111111 && tokens.surface == 0x222222 && tokens.dark
	assert tokens.metrics(.medium).height == 36
	assert tokens.text == 0x172033
	ctx := VmlBuildContext{
		owner: child
	}
	assert ctx.tokens() == tokens
	// Without an owner a build gets the default tokens.
	defaults := VmlBuildContext{}.tokens()
	assert defaults.accent == 0x2563eb && defaults.control_paint().surface == 0xffffff
	// A theme change drops the cached tokens of the component and its
	// descendants, and advances the revision themed widgets rebuild on.
	mut revision := child.theme_revision_signal()!
	owner.set_theme(dark_theme())!
	assert revision.peek()! == 1
	changed := child.kit_tokens()
	assert changed.accent == 0x93c5fd && changed.surface == 0x222222
	assert changed.text == 0xf8fafc
	owner.dispose()!
}

fn test_button_variant_colors_follow_the_tokens() {
	t := kit_tokens(default_theme())
	secondary := button_variant_colors(t, .secondary, false, true)
	assert secondary.fill == t.surface_muted && secondary.border == t.border
	assert secondary.filled && secondary.bordered && !secondary.underline
	assert button_variant_colors(t, .outline, false, true).fill == t.surface
	assert button_variant_colors(t, .secondary, true, true).fill == t.pressed
	ghost := button_variant_colors(t, .ghost, false, true)
	assert !ghost.filled && !ghost.bordered && ghost.hover == t.hover
	assert button_variant_colors(t, .ghost, true, true).filled
	link := button_variant_colors(t, .link, false, true)
	assert link.underline && !link.filled
	assert kit_contrast(link.foreground, t.surface) >= 4.5
	warning := button_variant_colors(t, .warning, false, true)
	assert warning.fill == t.warning && warning.foreground == t.on_warning
	assert button_variant_colors(t, .danger, true, true).fill == kit_mix(t.danger, t.text, 0.25)
	off := button_variant_colors(t, .primary, false, false)
	assert off.foreground == t.disabled_text
	assert off.fill == kit_mix(t.accent, t.surface, 0.6)
}
