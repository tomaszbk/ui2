module ui2

import math

fn choice_assert_inside(el Element) {
	component_validate_frame(el.frame) or { panic(err) }
	for child in el.children {
		assert child.frame.x >= -1e-9 && child.frame.y >= -1e-9
		assert child.frame.x + child.frame.width <= el.frame.width + 1e-9
		assert child.frame.y + child.frame.height <= el.frame.height + 1e-9
		choice_assert_inside(child)
	}
}

// choice_buttons collects the elements that answer a click, in tree order.
fn choice_buttons(el Element) []Element {
	mut found := []Element{}
	if el.button_behavior {
		found << el
	}
	for child in el.children {
		found << choice_buttons(child)
	}
	return found
}

@[heap]
struct ChoiceLog {
mut:
	events []string
}

fn choice_has_callback(el Element) bool {
	return voidptr(el.on_event) != unsafe { nil }
}

// choice_click delivers a click to el's callback the way the renderer would,
// and fails the test when el has none.
fn choice_click(el Element) {
	assert choice_has_callback(el), 'no callback on ${el.id}'
	el.on_event(ElementEvent{
		kind: .click
		id:   el.id
	})
}

fn choice_labels(el Element) []string {
	mut found := []string{}
	if el.kind == .label {
		found << el.text
	}
	for child in el.children {
		found << choice_labels(child)
	}
	return found
}

// ── Shared helpers ──────────────────────────────────────────────────

fn test_choice_colors_mix_contrast_and_legibility() {
	assert choice_mix(0x000000, 0xffffff, 0) == 0x000000
	assert choice_mix(0x000000, 0xffffff, 1) == 0xffffff
	assert choice_mix(0x000000, 0xffffff, 0.5) == 0x808080
	assert choice_mix(0x102030, 0x102030, 0.3) == 0x102030
	assert choice_mix(0x000000, 0xffffff, 7) == 0xffffff
	assert math.abs(choice_contrast(0x000000, 0xffffff) - 21) < 0.01
	assert math.abs(choice_contrast(0x777777, 0x777777) - 1) < 1e-9
	light := component_theme(false)
	dark := component_theme(true)
	// The warning yellow is a fill; as text on white it must be darkened.
	assert choice_contrast(light.warning, light.background) < 4.5
	assert choice_contrast(choice_legible(light.warning, light.background, light.foreground),
		light.background) >= 4.5
	assert choice_legible(dark.primary, dark.background, dark.foreground) == dark.primary
	for theme in [light, dark] {
		assert choice_contrast(choice_pressed(theme), theme.background) > 1.1
	}
}

fn test_choice_shape_rounds_only_the_requested_corners() {
	frame := rect(10, 20, 100, 30)
	all := choice_shape(frame, 6, 0x123456, .all, false)
	assert all.len == 1
	assert all[0].box.radius == 6
	assert all[0].box.bg == 0x123456
	start := choice_shape(frame, 6, 0x123456, .start, false)
	assert start.len == 2
	assert start[1].frame == rect(60, 20, 50, 30)
	assert start[1].box.radius == 0
	end := choice_shape(frame, 6, 0x123456, .end, false)
	assert end[1].frame == rect(10, 20, 50, 30)
	top := choice_shape(frame, 6, 0x123456, .start, true)
	assert top[1].frame == rect(10, 35, 100, 15)
	bottom := choice_shape(frame, 6, 0x123456, .end, true)
	assert bottom[1].frame == rect(10, 20, 100, 15)
	square := choice_shape(frame, 6, 0x123456, .none, false)
	assert square.len == 1 && square[0].box.radius == 0
	clamped := choice_shape(rect(0, 0, 40, 8), 30, 0, .all, false)
	assert clamped[0].box.radius == 4
	assert choice_shape(rect(0, 0, 0, 8), 4, 0, .all, false).len == 0
	ring := choice_ring(frame, 6, 0x111111, 0x222222, .all, false)
	assert ring.len == 2
	assert ring[1].frame == rect(11, 21, 98, 28)
	assert ring[1].box.radius == 5
}

fn test_choice_pack_keeps_natural_sizes_until_it_must_scale() {
	sizes, gap := choice_pack([10.0, 20], 100, 4, false)
	assert sizes == [10.0, 20] && gap == 4
	squeezed, _ := choice_pack([60.0, 60], 100, 4, false)
	assert math.abs(squeezed[0] + squeezed[1] + 4 - 100) < 1e-9
	filled, _ := choice_pack([10.0, 30], 84, 4, true)
	assert math.abs(filled[0] - 20) < 1e-9 && math.abs(filled[1] - 60) < 1e-9
	tiny, tiny_gap := choice_pack([10.0, 10, 10], 2, 8, false)
	assert tiny_gap * 2 <= 1 + 1e-9
	assert tiny.all(it >= 0)
	empty, _ := choice_pack([]f64{}, 50, 4, true)
	assert empty.len == 0
}

fn test_choice_values_default_to_labels_and_must_be_unique() {
	assert choice_value('', 'Light') == 'Light'
	assert choice_value('light', 'Light') == 'light'
	choice_validate_values(['a', 'b'], 'test') or { panic(err) }
	for values in [['a', 'a'], ['a', ''], [' ']] {
		if _ := choice_validate_values(values, 'test') {
			assert false, 'invalid values accepted: ${values}'
		}
	}
	// Values are hex-encoded into element ids, so any string makes a valid id
	// and no value's id can collide with another's.
	assert button_group_item_id('g', 'b:c') == 'g:component:item:623a63'
	assert radio_group_item_id('g', 'a') == 'g:component:option:61'
	values := ['a', 'b:c', '日本', 'b', ':c']
	ids := values.map(toggle_group_item_id('g', it))
	for i, id in ids {
		assert ids.index(id) == i
		component_validate_id(id) or { panic(err) }
	}
}

// ── Button variants, styled button, button group ────────────────────

fn test_button_variant_colors_follow_upstream_roles() {
	theme := component_theme(false)
	secondary := button_variant_colors(theme, .secondary, false, false, true)
	assert secondary.fill == theme.muted
	assert secondary.border == theme.border
	assert secondary.foreground == theme.foreground
	primary := button_variant_colors(theme, .primary, false, false, true)
	assert primary.fill == theme.primary
	assert primary.foreground == theme.primary_foreground
	// Attached solid buttons need a visible line between them.
	assert primary.divider != primary.fill
	outline := button_variant_colors(theme, .warning, true, false, true)
	assert outline.fill == theme.background
	assert outline.border == theme.warning
	assert choice_contrast(outline.foreground, outline.fill) >= 4.5
	selected := button_variant_colors(theme, .primary, false, true, true)
	assert selected.fill != primary.fill
	ghost := button_variant_colors(theme, .ghost, false, false, true)
	assert !ghost.filled && !ghost.bordered
	assert button_variant_colors(theme, .ghost, false, true, true).filled
	inactive := button_variant_colors(theme, .danger, false, false, false)
	assert inactive.foreground == choice_disabled_text(theme)
	assert inactive.fill != theme.danger
	for variant in [ButtonVariant.secondary, .primary, .danger, .success, .warning] {
		for outlined in [false, true] {
			colors := button_variant_colors(theme, variant, outlined, false, true)
			assert colors.filled && colors.bordered
		}
	}
}

fn test_styled_button_is_a_composite_button_with_its_own_callback() {
	mut log := &ChoiceLog{}
	el := styled_button(
		id:       'save'
		label:    'Save'
		frame:    rect(0, 0, 100, 32)
		variant:  .primary
		on_event: fn [mut log] (event ElementEvent) {
			log.events << '${event.kind}:${event.id}'
		}
	) or { panic(err) }
	assert el.kind == .view && el.button_behavior
	choice_click(el)
	// Only clicks are forwarded.
	el.on_event(ElementEvent{ kind: .pointer_down, id: 'save' })
	assert log.events == ['click:save']
	assert el.accessibility_role == 'button'
	assert el.accessibility_label == 'Save'
	assert choice_labels(el) == ['Save']
	outlined := styled_button(
		id:      'add'
		icon:    'plus'
		label:   'Add'
		frame:   rect(0, 0, 100, 32)
		outline: true
		enabled: false
	) or { panic(err) }
	assert !choice_has_callback(outlined)
	assert !outlined.enabled
	images := outlined.children.filter(it.kind == .image)
	assert images.len == 1 && images[0].image_path == 'symbol:plus'
	icon_only := styled_button(id: 'x', icon: 'xmark', accessibility_label: 'Close') or {
		panic(err)
	}
	assert icon_only.accessibility_label == 'Close'
	if _ := styled_button(label: 'No id') {
		assert false, 'styled button accepted without identity'
	}
	assert styled_button_width('', '', .medium) == component_metrics(.medium).height
	assert styled_button_width('Longer label', '', .medium) > styled_button_width('Short', '',
		.medium)
	assert styled_button_width('Save', 'plus', .medium) > styled_button_width('Save', '', .medium)
}

fn choice_button_group() ButtonGroupConfig {
	return ButtonGroupConfig{
		id:    'view'
		frame: rect(10, 10, 300, 32)
		items: [ButtonGroupItem{
			label: 'List'
		}, ButtonGroupItem{
			value:    'grid'
			label:    'Grid'
			selected: true
		}, ButtonGroupItem{
			value:   'table'
			label:   'Table'
			enabled: false
		}]
	}
}

fn test_button_group_identity_and_callbacks() {
	mut log := &ChoiceLog{}
	base := choice_button_group()
	mut items := base.items.clone()
	items[1] = ButtonGroupItem{
		...items[1]
		on_event: fn [mut log] (event ElementEvent) {
			log.events << 'item:${event.id}'
		}
	}
	config := ButtonGroupConfig{
		...base
		items:    items
		on_click: fn [mut log] (value string) {
			log.events << 'group:${value}'
		}
	}
	el := button_group(config) or { panic(err) }
	buttons := choice_buttons(el)
	assert buttons.len == 3
	assert buttons[0].id == button_group_item_id('view', 'List')
	assert buttons[0].key == 'item:List'
	assert buttons[1].accessibility_value == 'selected'
	assert !buttons[2].enabled
	assert el.accessibility_role == 'group'
	choice_click(buttons[0])
	// The item's own callback hears the click before the group's.
	choice_click(buttons[1])
	assert log.events == ['group:List', 'item:${buttons[1].id}', 'group:grid']
	// A disabled button takes no clicks, and a group nobody listens to has no
	// callbacks at all.
	assert !choice_has_callback(buttons[2])
	assert !choice_buttons(button_group(base) or { panic(err) }).any(choice_has_callback(it))
	inactive := ButtonGroupConfig{
		...config
		enabled: false
	}
	inactive_buttons := choice_buttons(button_group(inactive) or { panic(err) })
	assert inactive_buttons.all(!it.enabled && !choice_has_callback(it))
	if _ := button_group(ButtonGroupConfig{
		...config
		items: [ButtonGroupItem{
			label: 'A'
		}, ButtonGroupItem{
			label: 'A'
		}]
	})
	{
		assert false, 'duplicate button values accepted'
	}
	if _ := button_group(ButtonGroupConfig{ items: config.items }) {
		assert false, 'button group accepted without identity'
	}
}

fn test_button_group_segments_touch_and_share_a_border() {
	config := choice_button_group()
	el := button_group(config) or { panic(err) }
	buttons := choice_buttons(el)
	for i in 1 .. buttons.len {
		previous := buttons[i - 1].frame
		assert math.abs(previous.x + previous.width - buttons[i].frame.x) < 1e-9
		assert buttons[i].frame.y == buttons[0].frame.y
	}
	// Packed at their natural widths, from the start.
	assert buttons[0].frame.x == 0
	last := buttons[buttons.len - 1].frame
	assert last.x + last.width < config.frame.width
	// The border lies under the segments, every outer corner rounded.
	assert el.children[0].box.bg == config.theme.border
	assert el.children[0].box.radius == component_metrics(.medium).radius
	filled := button_group(ButtonGroupConfig{
		...config
		fill: true
	}) or { panic(err) }
	filled_last := choice_buttons(filled).last().frame
	assert math.abs(filled_last.x + filled_last.width - config.frame.width) < 1e-9
	// Solid buttons get divider lines; ghost buttons have neither border nor lines.
	primary := button_group(ButtonGroupConfig{
		...config
		variant: .primary
	}) or { panic(err) }
	divider := button_variant_colors(config.theme, .primary, false, false, true).divider
	assert primary.children.filter(it.box.bg == divider && !it.button_behavior).len == 2
	ghost := button_group(ButtonGroupConfig{
		...config
		variant: .ghost
	}) or { panic(err) }
	assert ghost.children.all(it.button_behavior)
	vertical := button_group(ButtonGroupConfig{
		...config
		frame:       rect(0, 0, 120, 200)
		orientation: .vertical
	}) or { panic(err) }
	stacked := choice_buttons(vertical)
	assert stacked[1].frame.y == stacked[0].frame.y + stacked[0].frame.height
	assert stacked.all(it.frame.x == 0 && it.frame.width == stacked[0].frame.width)
}

// ── Toggle and toggle group ─────────────────────────────────────────

@[heap]
struct ChoiceFlags {
mut:
	values []bool
}

fn test_toggle_is_controlled_by_its_callback() {
	mut flags := &ChoiceFlags{}
	config := ToggleConfig{
		id:        'bold'
		label:     'Bold'
		frame:     rect(0, 0, 80, 32)
		pressed:   true
		on_change: fn [mut flags] (pressed bool) {
			flags.values << pressed
		}
	}
	el := toggle(config) or { panic(err) }
	assert el.kind == .view && el.button_behavior
	assert el.accessibility_value == 'pressed'
	choice_click(el)
	released := ToggleConfig{
		...config
		pressed: false
	}
	released_el := toggle(released) or { panic(err) }
	assert released_el.accessibility_value == 'released'
	choice_click(released_el)
	// A click asks for the opposite of the state the toggle was built with.
	assert flags.values == [false, true]
	inactive := ToggleConfig{
		...config
		enabled: false
	}
	inactive_el := toggle(inactive) or { panic(err) }
	assert !inactive_el.enabled
	assert !choice_has_callback(inactive_el)
	if _ := toggle(label: 'No id') {
		assert false, 'toggle accepted without identity'
	}
	// Ghost toggles are bare until pressed; outline ones always have a ring.
	bare := toggle(ToggleConfig{ ...released }) or { panic(err) }
	assert bare.children.filter(it.kind == .view).len == 0
	ringed := toggle(ToggleConfig{
		...released
		variant: .outline
	}) or { panic(err) }
	assert ringed.children.filter(it.kind == .view).len == 2
}

fn choice_toggle_group() ToggleGroupConfig {
	return ToggleGroupConfig{
		id:       'marks'
		frame:    rect(0, 0, 400, 32)
		selected: ['italic', 'stale']
		items:    [ToggleItem{
			value: 'bold'
			label: 'Bold'
		}, ToggleItem{
			value: 'italic'
			label: 'Italic'
		}, ToggleItem{
			value:   'code'
			label:   'Code'
			enabled: false
		}, ToggleItem{
			value: 'strike'
			icon:  'minus'
		}]
	}
}

fn test_toggle_group_multiple_selection() {
	config := choice_toggle_group()
	el := toggle_group(config) or { panic(err) }
	buttons := choice_buttons(el)
	assert buttons.len == 4
	assert buttons.map(it.accessibility_value) == ['released', 'pressed', 'released', 'released']
	assert !buttons[2].enabled
	assert buttons[3].accessibility_label == ''
	assert buttons[1].id == toggle_group_item_id('marks', 'italic')
	// Selections come back in item order and drop values that name no item.
	assert (toggle_group_selection_after(config, 'bold') or { []string{} }) == ['bold', 'italic']
	assert (toggle_group_selection_after(config, 'italic') or { ['none'] }) == []string{}
	strict := ToggleGroupConfig{
		...config
		allow_empty: false
	}
	assert (toggle_group_selection_after(strict, 'italic') or { ['none'] }) == ['none']
	for value in ['code', 'stale', 'Bold', ''] {
		assert (toggle_group_selection_after(config, value) or { ['none'] }) == ['none']
	}
	inactive := ToggleGroupConfig{
		...config
		enabled: false
	}
	assert (toggle_group_selection_after(inactive, 'bold') or { ['none'] }) == ['none']
	// Clicks report the same selections to on_change.
	mut log := &ChoiceLog{}
	listened := ToggleGroupConfig{
		...config
		on_change: fn [mut log] (selected []string) {
			log.events << selected.join(',')
		}
	}
	clickable := choice_buttons(toggle_group(listened) or { panic(err) })
	choice_click(clickable[0])
	choice_click(clickable[1])
	assert !choice_has_callback(clickable[2])
	assert log.events == ['bold,italic', '']
	strict_buttons := choice_buttons(toggle_group(ToggleGroupConfig{
		...listened
		allow_empty: false
	}) or { panic(err) })
	choice_click(strict_buttons[1])
	assert log.events.len == 2
	assert !choice_buttons(toggle_group(inactive) or { panic(err) }).any(choice_has_callback(it))
}

fn test_toggle_group_single_selection() {
	config := ToggleGroupConfig{
		...choice_toggle_group()
		multiple: false
	}
	assert (toggle_group_selection_after(config, 'bold') or { []string{} }) == ['bold']
	assert (toggle_group_selection_after(config, 'italic') or { ['none'] }) == []string{}
	strict := ToggleGroupConfig{
		...config
		allow_empty: false
	}
	assert (toggle_group_selection_after(strict, 'italic') or { ['none'] }) == ['none']
	assert (toggle_group_selection_after(strict, 'strike') or { []string{} }) == ['strike']
}

fn test_toggle_group_layout_apart_and_segmented() {
	config := choice_toggle_group()
	apart := choice_buttons(toggle_group(config) or { panic(err) })
	gap := component_metrics(.medium).gap
	assert math.abs(apart[1].frame.x - (apart[0].frame.x + apart[0].frame.width + gap)) < 1e-9
	// An icon-only item is a square.
	assert apart[3].frame.width == component_metrics(.medium).height
	outline := toggle_group(ToggleGroupConfig{
		...config
		segmented: true
		variant:   .outline
	}) or { panic(err) }
	joined := choice_buttons(outline)
	assert math.abs(joined[1].frame.x - (joined[0].frame.x + joined[0].frame.width)) < 1e-9
	assert outline.children[0].box.bg == config.theme.border
	ghost := toggle_group(ToggleGroupConfig{
		...config
		segmented: true
	}) or { panic(err) }
	assert ghost.children.all(it.button_behavior)
	if _ := toggle_group(ToggleGroupConfig{
		...config
		items: [ToggleItem{
			label: 'Same'
		}, ToggleItem{
			value: 'Same'
		}]
	})
	{
		assert false, 'duplicate toggle values accepted'
	}
}

// ── Radio ───────────────────────────────────────────────────────────

fn choice_radio_group() RadioGroupConfig {
	return RadioGroupConfig{
		id:       'pay'
		frame:    rect(0, 0, 300, 200)
		selected: 'card'
		options:  [
			RadioOption{
				value:       'card'
				label:       'Card'
				description: 'Visa or Mastercard'
			},
			RadioOption{
				label: 'PayPal'
			},
			RadioOption{
				value:   'bank'
				label:   'Bank'
				enabled: false
			},
			RadioOption{
				value: 'cash'
				label: 'Cash'
			},
		]
	}
}

fn test_radio_group_renders_options_as_radios() {
	config := choice_radio_group()
	el := radio_group(config) or { panic(err) }
	assert el.accessibility_role == 'radiogroup'
	assert el.accessibility_value == 'Card'
	buttons := choice_buttons(el)
	assert buttons.len == 4
	assert buttons.all(it.accessibility_role == 'radio')
	assert buttons.map(it.accessibility_value) == ['checked', 'unchecked', 'unchecked', 'unchecked']
	assert buttons[1].id == radio_group_item_id('pay', 'PayPal')
	assert buttons[1].key == 'option:PayPal'
	assert !buttons[2].enabled
	assert choice_labels(buttons[0]) == ['Card', 'Visa or Mastercard']
	// The checked indicator carries the inner dot.
	assert buttons[0].children[0].children.len == 3
	assert buttons[1].children[0].children.len == 2
	if _ := radio_group(RadioGroupConfig{
		...config
		options: [RadioOption{
			label: 'A'
		}, RadioOption{
			value: 'A'
		}]
	})
	{
		assert false, 'duplicate radio values accepted'
	}
	if _ := radio_group(RadioGroupConfig{ options: config.options }) {
		assert false, 'radio group accepted without identity'
	}
}

fn test_radio_group_callbacks_and_keys() {
	mut log := &ChoiceLog{}
	config := RadioGroupConfig{
		...choice_radio_group()
		on_change: fn [mut log] (value string) {
			log.events << value
		}
	}
	buttons := choice_buttons(radio_group(config) or { panic(err) })
	// The selected option and the disabled one take no clicks.
	assert !choice_has_callback(buttons[0])
	assert !choice_has_callback(buttons[2])
	choice_click(buttons[1])
	choice_click(buttons[3])
	assert log.events == ['PayPal', 'cash']
	inactive := RadioGroupConfig{
		...config
		enabled: false
	}
	assert !choice_buttons(radio_group(inactive) or { panic(err) }).any(choice_has_callback(it))
	assert (radio_group_value_after_key(config, .down) or { '' }) == 'PayPal'
	assert (radio_group_value_after_key(config, .up) or { '' }) == 'cash'
	assert (radio_group_value_after_key(config, .end) or { '' }) == 'cash'
	assert (radio_group_value_after_key(config, .home) or { 'none' }) == 'none'
	assert (radio_group_value_after_key(config, .enter) or { 'none' }) == 'none'
	// Disabled options are skipped and the selection wraps around.
	on_paypal := RadioGroupConfig{
		...config
		selected: 'PayPal'
	}
	assert (radio_group_value_after_key(on_paypal, .right) or { '' }) == 'cash'
	on_cash := RadioGroupConfig{
		...config
		selected: 'cash'
	}
	assert (radio_group_value_after_key(on_cash, .down) or { '' }) == 'card'
	unset := RadioGroupConfig{
		...config
		selected: ''
	}
	assert (radio_group_value_after_key(unset, .down) or { '' }) == 'card'
	assert (radio_group_value_after_key(unset, .left) or { '' }) == 'cash'
	assert (radio_group_value_after_key(inactive, .down) or { 'none' }) == 'none'
}

fn test_radio_group_layout_vertical_horizontal_and_squeezed() {
	config := choice_radio_group()
	frames, lines := radio_group_frames(config)
	assert lines == [1, 0, 0, 0]
	assert frames[0].height > frames[1].height
	for i in 1 .. frames.len {
		assert frames[i].y == frames[i - 1].y + frames[i - 1].height
		assert frames[i].width == config.frame.width
	}
	options := []RadioOption{len: 11, init: RadioOption{
		label: index.str()
	}}
	row := RadioGroupConfig{
		id:          'score'
		frame:       rect(0, 0, 200, 100)
		orientation: .horizontal
		options:     options
	}
	row_frames, _ := radio_group_frames(row)
	assert row_frames[0].y == 0 && row_frames[1].x > 0
	assert row_frames.last().y > 0
	assert row_frames.all(it.x + it.width <= 200 + 1e-9)
	squeezed := RadioGroupConfig{
		...config
		frame: rect(0, 0, 300, 40)
	}
	squeezed_frames, _ := radio_group_frames(squeezed)
	last := squeezed_frames.last()
	assert last.y + last.height <= 40 + 1e-9
	choice_assert_inside(radio_group(squeezed) or { panic(err) })
}

fn test_single_radio_only_ever_checks_itself() {
	config := RadioConfig{
		id:          'terms'
		label:       'Accept'
		description: 'Required to continue'
		frame:       rect(0, 0, 200, 48)
	}
	mut flags := &ChoiceFlags{}
	listened := RadioConfig{
		...config
		on_change: fn [mut flags] (checked bool) {
			flags.values << checked
		}
	}
	el := radio(listened) or { panic(err) }
	assert el.accessibility_role == 'radio'
	assert el.accessibility_value == 'unchecked'
	choice_click(el)
	assert flags.values == [true]
	checked := radio(RadioConfig{ ...listened, checked: true }) or { panic(err) }
	assert !choice_has_callback(checked)
	disabled := radio(RadioConfig{ ...listened, enabled: false }) or { panic(err) }
	assert !choice_has_callback(disabled)
	assert !choice_has_callback(radio(config) or { panic(err) })
	if _ := radio(label: 'No id') {
		assert false, 'radio accepted without identity'
	}
}

// ── Rating ──────────────────────────────────────────────────────────

fn test_rating_click_rule_matches_upstream() {
	assert rating_value_after_click(0, 1) == 1
	assert rating_value_after_click(3, 5) == 5
	assert rating_value_after_click(3, 3) == 2
	assert rating_value_after_click(3, 1) == 0
	assert rating_value_after_click(1, 1) == 0
	assert rating_value_after_click(5, 2) == 1
}

@[heap]
struct ChoiceNumbers {
mut:
	values []int
}

fn test_rating_callbacks_follow_the_click_rule_and_skip_inert_ratings() {
	mut log := &ChoiceNumbers{}
	config := RatingConfig{
		id:        'stars'
		value:     3
		frame:     rect(0, 0, 200, 32)
		on_change: fn [mut log] (value int) {
			log.values << value
		}
	}
	stars := choice_buttons(rating(config) or { panic(err) })
	choice_click(stars[4])
	choice_click(stars[2])
	assert log.values == [5, 2]
	for inert in [RatingConfig{
		...config
		readonly: true
	}, RatingConfig{
		...config
		enabled: false
	}] {
		assert choice_buttons(rating(inert) or { panic(err) }).len == 0
		assert (rating_value_after_key(inert, .right) or { -1 }) == -1
	}
	// Out-of-range values are clamped before the rule applies.
	high := RatingConfig{
		...config
		value: 40
	}
	choice_click(choice_buttons(rating(high) or { panic(err) })[4])
	assert log.values == [5, 2, 4]
}

fn test_rating_rendering_and_validation() {
	config := RatingConfig{
		id:    'stars'
		value: 7
		frame: rect(0, 0, 200, 32)
	}
	el := rating(config) or { panic(err) }
	assert el.children.len == 5
	buttons := choice_buttons(el)
	assert buttons.len == 5
	assert buttons.all(it.accessibility_value == 'filled')
	assert buttons[0].accessibility_label == '1 star'
	assert buttons[1].id == rating_star_id('stars', 2)
	assert el.accessibility_value == '5 of 5 stars'
	for i in 1 .. 5 {
		assert el.children[i].frame.x == el.children[i - 1].frame.x + el.children[i - 1].frame.width
	}
	readonly := rating(value: -2, readonly: true, frame: rect(0, 0, 100, 20)) or { panic(err) }
	assert choice_buttons(readonly).len == 0
	assert readonly.accessibility_role == 'img'
	assert readonly.accessibility_value == '0 of 5 stars'
	inactive := rating(value: 2, enabled: false) or { panic(err) }
	assert choice_buttons(inactive).len == 0
	for max in [0, -1, rating_max_stars + 1] {
		if _ := rating(id: 'r', max: max) {
			assert false, 'rating accepted max ${max}'
		}
	}
	if _ := rating(value: 1) {
		assert false, 'interactive rating accepted without identity'
	}
	assert rating_width(10, .large) > rating_width(5, .large)
	assert rating_width(5, .small) < rating_width(5, .large)
}

fn test_rating_keyboard_steps() {
	config := RatingConfig{
		id:    'stars'
		value: 3
	}
	assert (rating_value_after_key(config, .right) or { -1 }) == 4
	assert (rating_value_after_key(config, .down) or { -1 }) == 2
	assert (rating_value_after_key(config, .home) or { -1 }) == 0
	assert (rating_value_after_key(config, .end) or { -1 }) == 5
	assert (rating_value_after_key(config, ._1) or { -1 }) == 1
	assert (rating_value_after_key(config, ._3) or { -1 }) == -1
	assert (rating_value_after_key(config, ._9) or { -1 }) == -1
	assert (rating_value_after_key(config, .space) or { -1 }) == -1
	full := RatingConfig{
		...config
		value: 5
	}
	assert (rating_value_after_key(full, .up) or { -1 }) == -1
}

// ── Stepper ─────────────────────────────────────────────────────────

fn choice_stepper() StepperConfig {
	return StepperConfig{
		id:      'wizard'
		frame:   rect(0, 0, 600, 80)
		current: 1
		items:   [
			StepperItem{
				title:       'Account'
				description: 'Your details'
			},
			StepperItem{
				title: 'Shipping'
			},
			StepperItem{
				title:   'Billing'
				enabled: false
			},
			StepperItem{
				title: 'Review'
				icon:  'eye'
			},
		]
	}
}

fn test_stepper_states_and_rendering() {
	assert stepper_step_state(0, 1) == .completed
	assert stepper_step_state(1, 1) == .current
	assert stepper_step_state(2, 1) == .upcoming
	config := choice_stepper()
	el := stepper(config) or { panic(err) }
	assert el.accessibility_role == 'list'
	assert el.accessibility_value == 'Step 2 of 4'
	steps := choice_buttons(el)
	assert steps.len == 4
	assert steps.map(it.accessibility_value) == ['completed', 'current', 'upcoming', 'upcoming']
	assert steps[0].id == stepper_step_id('wizard', 0)
	assert steps[1].accessibility_label == 'Step 2 of 4: Shipping'
	assert !steps[2].enabled
	// A completed step shows a check, the others their number or icon.
	assert '✓' in choice_labels(steps[0])
	assert '2' in choice_labels(steps[1])
	icons := steps[3].children[0].children.filter(it.kind == .image)
	assert icons.len == 1 && icons[0].image_path == 'symbol:eye'
	// Three connectors come first; the one already passed takes the primary color.
	connectors := el.children.filter(!it.button_behavior)
	assert connectors.len == 3
	assert connectors[0].box.bg == config.theme.primary
	assert connectors[1].box.bg == config.theme.border
	// The last step only takes the width its text needs.
	assert steps[3].frame.width < steps[0].frame.width
	assert math.abs(steps[3].frame.x + steps[3].frame.width - config.frame.width) < 1e-9
	done := stepper(StepperConfig{
		...config
		current: 99
	}) or { panic(err) }
	assert done.accessibility_value == 'complete'
	assert choice_buttons(done).all(it.accessibility_value == 'completed')
}

fn test_stepper_text_center_vertical_and_display_only() {
	config := choice_stepper()
	centered := stepper(StepperConfig{
		...config
		text_center: true
	}) or { panic(err) }
	steps := choice_buttons(centered)
	assert steps.all(it.frame.width == config.frame.width / 4)
	indicator := steps[0].children[0].frame
	assert math.abs(indicator.x + indicator.width / 2 - steps[0].frame.width / 2) < 1e-9
	vertical := stepper(StepperConfig{
		...config
		frame:       rect(0, 0, 240, 300)
		orientation: .vertical
	}) or { panic(err) }
	rows := choice_buttons(vertical)
	for i in 1 .. rows.len {
		assert rows[i].frame.y == rows[i - 1].frame.y + rows[i - 1].frame.height
	}
	assert math.abs(rows.last().frame.y + rows.last().frame.height - 300) < 1e-9
	display := stepper(StepperConfig{
		...config
		id:        ''
		clickable: false
	}) or { panic(err) }
	assert choice_buttons(display).len == 0
	assert display.children.filter(it.accessibility_role == 'listitem').len == 4
	if _ := stepper(StepperConfig{ ...config, id: '' }) {
		assert false, 'clickable stepper accepted without identity'
	}
}

fn test_stepper_callbacks_and_navigation() {
	mut log := &ChoiceNumbers{}
	config := StepperConfig{
		...choice_stepper()
		on_change: fn [mut log] (step int) {
			log.values << step
		}
	}
	steps := choice_buttons(stepper(config) or { panic(err) })
	choice_click(steps[0])
	choice_click(steps[3])
	assert log.values == [0, 3]
	// The current step and the disabled one take no clicks.
	assert !choice_has_callback(steps[1])
	assert !choice_has_callback(steps[2])
	inactive := stepper(StepperConfig{ ...config, enabled: false }) or { panic(err) }
	assert !choice_buttons(inactive).any(choice_has_callback(it))
	display := stepper(StepperConfig{ ...config, clickable: false }) or { panic(err) }
	assert choice_buttons(display).len == 0
	// Next and previous skip the inactive step.
	assert (stepper_next_step(config) or { -1 }) == 3
	assert (stepper_previous_step(config) or { -1 }) == 0
	first := StepperConfig{
		...config
		current: 0
	}
	assert (stepper_previous_step(first) or { -1 }) == -1
	last := StepperConfig{
		...config
		current: 3
	}
	assert (stepper_next_step(last) or { -1 }) == -1
	assert (stepper_previous_step(StepperConfig{ ...config, current: 4 }) or { -1 }) == 3
	assert (stepper_step_after_key(config, .right) or { -1 }) == 3
	assert (stepper_step_after_key(config, .left) or { -1 }) == 0
	assert (stepper_step_after_key(config, .down) or { -1 }) == -1
	assert (stepper_step_after_key(config, .end) or { -1 }) == 3
	assert (stepper_step_after_key(first, .home) or { -1 }) == -1
	vertical := StepperConfig{
		...config
		orientation: .vertical
	}
	assert (stepper_step_after_key(vertical, .down) or { -1 }) == 3
	assert (stepper_step_after_key(vertical, .up) or { -1 }) == 0
	assert (stepper_next_step(StepperConfig{ ...config, enabled: false }) or { -1 }) == -1
}

// ── Geometry under any frame ────────────────────────────────────────

fn test_choice_geometry_stays_inside_tiny_and_large_frames() {
	for extent in [0.0, 0.5, 1.0, 8.0, 32.0, 200.0, 900.0] {
		frame := rect(10, 20, extent, extent / 2)
		group := choice_button_group()
		toggles := choice_toggle_group()
		radios := choice_radio_group()
		steps := choice_stepper()
		mut elements := [
			styled_button(id: 'b', label: 'Save', icon: 'plus', frame: frame, outline: true) or {
				panic(err)
			},
			button_group(ButtonGroupConfig{ ...group, frame: frame }) or { panic(err) },
			button_group(ButtonGroupConfig{ ...group, frame: frame, orientation: .vertical }) or {
				panic(err)
			},
			toggle(id: 't', label: 'Bold', icon: 'textformat', frame: frame, variant: .outline) or {
				panic(err)
			},
			toggle_group(ToggleGroupConfig{ ...toggles, frame: frame }) or { panic(err) },
			toggle_group(ToggleGroupConfig{ ...toggles, frame: frame, segmented: true }) or {
				panic(err)
			},
			radio(id: 'r', label: 'Accept', description: 'Long description text', frame: frame) or {
				panic(err)
			},
			radio_group(RadioGroupConfig{ ...radios, frame: frame }) or { panic(err) },
			radio_group(RadioGroupConfig{ ...radios, frame: frame, orientation: .horizontal }) or {
				panic(err)
			},
			rating(id: 'stars', value: 3, max: 10, frame: frame) or { panic(err) },
			stepper(StepperConfig{ ...steps, frame: frame }) or { panic(err) },
			stepper(StepperConfig{ ...steps, frame: frame, text_center: true }) or { panic(err) },
			stepper(StepperConfig{ ...steps, frame: frame, orientation: .vertical }) or {
				panic(err)
			},
		]
		elements << radio_group(RadioGroupConfig{
			...radios
			frame:   frame
			options: []RadioOption{}
		}) or { panic(err) }
		elements << stepper(StepperConfig{
			...steps
			frame: frame
			items: []StepperItem{}
		}) or { panic(err) }
		for el in elements {
			choice_assert_inside(el)
		}
	}
	for frame in [rect(0, 0, -1, 10), rect(0, math.nan(), 10, 10)] {
		if _ := toggle(id: 't', frame: frame) {
			assert false, 'invalid frame accepted'
		}
		if _ := stepper(id: 's', frame: frame) {
			assert false, 'invalid frame accepted'
		}
	}
}
