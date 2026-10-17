module ui2

import math

struct DialogsTestCounter {
mut:
	count int
}

@[heap]
struct DialogsTestLog {
mut:
	events  []DialogEvent
	choices []AlertDialogChoice
	sizes   []f64
}

fn dialogs_test_field(id string, frame Rect) Element {
	return text_input(id: id, frame: frame) or { panic(err) }
}

fn dialogs_test_has_callback(el Element) bool {
	return voidptr(el.on_event) != unsafe { nil }
}

fn dialogs_test_click(el Element) {
	assert dialogs_test_has_callback(el), 'no callback on ${el.id}'
	el.on_event(ElementEvent{
		kind: .click
		id:   el.id
	})
}

// dialogs_test_dismiss delivers an overlay dismissal the way the window's
// overlay layer does.
fn dialogs_test_dismiss(el Element, reason OverlayDismissReason) {
	overlay := el.overlay or { panic('${el.id} is not an overlay') }
	assert voidptr(overlay.on_dismiss) != unsafe { nil }, 'no on_dismiss on ${el.id}'
	overlay.on_dismiss(ElementEvent{
		kind:           .dismiss
		id:             el.id
		dismiss_reason: reason
	})
}

fn dialogs_test_listened(config DialogConfig, mut log DialogsTestLog) Element {
	return modal_dialog(DialogConfig{
		...config
		on_dialog: fn [mut log] (event DialogEvent) {
			log.events << event
		}
	}) or { panic(err) }
}

fn dialogs_test_keyed(el Element, key string) ?Element {
	for child in el.children {
		if child.key == key {
			return child
		}
	}
	return none
}

fn dialogs_test_find(el Element, id string) ?Element {
	if el.id == id {
		return el
	}
	for child in el.children {
		if found := dialogs_test_find(child, id) {
			return found
		}
	}
	return none
}

fn dialogs_test_rect_inside(inner Rect, outer Rect) bool {
	return inner.x >= -1e-9 && inner.y >= -1e-9 && inner.x + inner.width <= outer.width + 1e-9
		&& inner.y + inner.height <= outer.height + 1e-9
}

// dialogs_test_assert_local_geometry checks that every child lies inside its
// parent, except the content of a scroll element, which may be taller.
fn dialogs_test_assert_local_geometry(el Element) {
	component_validate_frame(el.frame) or { panic(err) }
	if el.kind == .scroll {
		return
	}
	for child in el.children {
		assert dialogs_test_rect_inside(child.frame, el.frame), '${child.id} ${child.frame} outside ${el.id} ${el.frame}'
		dialogs_test_assert_local_geometry(child)
	}
}

fn dialogs_test_profile(open bool) DialogConfig {
	return DialogConfig{
		id:          'profile'
		frame:       rect(0, 0, 1000, 800)
		open:        open
		title:       'Edit profile'
		description: 'Make changes to your profile here.'
		children:    [
			dialogs_test_field('name', rect(0, 0, 200, 32)),
			dialogs_test_field('email', rect(0, 44, 200, 32)),
		]
		buttons:     [
			DialogButton{
				id:   'cancel'
				text: 'Cancel'
				role: .cancel
			},
			DialogButton{
				id:      'later'
				text:    'Later'
				enabled: false
			},
			DialogButton{
				id:   'save'
				text: 'Save changes'
				role: .confirm
			},
		]
	}
}

fn test_dialog_layout_centers_a_default_width_dialog() {
	cfg := dialogs_test_profile(true)
	geom := dialog_layout(cfg) or { panic(err) }
	assert geom.surface.width == 448
	assert geom.surface.x == (1000 - 448) / 2
	assert math.abs(geom.surface.y + geom.surface.height / 2 - 400) < 1e-9
	assert geom.content_width == 448 - 32
	assert dialog_body_width(cfg) == geom.content_width
	assert geom.content_height == 76
	assert !geom.scrolls
	// The body is as tall as its content plus the blank space a scroll keeps below it.
	assert geom.body.height == geom.content_height + dialog_scroll_inset
	// Header, body and footer follow one another inside the surface.
	assert geom.title.y == 16
	assert geom.description.y > geom.title.y + geom.title.height - 1e-9
	assert geom.body.y > geom.description.y + geom.description.height
	assert geom.footer.y >= geom.body.y + geom.body.height
	assert geom.footer.y + geom.footer.height + 16 == geom.surface.height
	// Buttons are packed to the right in the order given.
	assert geom.buttons.len == 3
	assert geom.buttons[0].x < geom.buttons[1].x
	assert geom.buttons[1].x < geom.buttons[2].x
	last := geom.buttons[2]
	assert math.abs(last.x + last.width - (448 - 16)) < 1e-9
	// The title stops short of the close button.
	assert geom.title.x + geom.title.width <= geom.close_button.x
	assert geom.close_button.x + geom.close_button.width < geom.surface.width
}

fn test_dialog_layout_presets_custom_width_and_fixed_height() {
	base := dialogs_test_profile(true)
	small := dialog_layout(DialogConfig{ ...base, width: .small }) or { panic(err) }
	large := dialog_layout(DialogConfig{ ...base, width: .large }) or { panic(err) }
	full := dialog_layout(DialogConfig{ ...base, width: .full }) or { panic(err) }
	custom := dialog_layout(DialogConfig{ ...base, custom_width: 500, width: .small }) or {
		panic(err)
	}
	assert small.surface.width == 360
	assert large.surface.width == 640
	assert full.surface.width == 1000 - 32
	assert custom.surface.width == 500
	fixed := dialog_layout(DialogConfig{ ...base, height: 500 }) or { panic(err) }
	assert fixed.surface.height == 500
	assert fixed.body.height > fixed.content_height
	assert !fixed.scrolls
	centered := dialog_layout(DialogConfig{ ...base, footer_align: .center }) or { panic(err) }
	first := centered.buttons[0]
	end := centered.buttons[2]
	assert math.abs((first.x - 16) - (448 - 16 - end.x - end.width)) < 1e-9
	stretched := dialog_layout(DialogConfig{ ...base, footer_align: .stretch }) or { panic(err) }
	assert stretched.buttons[0].width == stretched.buttons[2].width
	assert stretched.buttons[0].x == 16
}

fn test_dialog_stays_inside_a_small_window_and_scrolls_its_body() {
	cfg := DialogConfig{
		...dialogs_test_profile(true)
		frame:          rect(0, 0, 400, 300)
		custom_width:   800
		content_height: 1000
	}
	geom := dialog_layout(cfg) or { panic(err) }
	assert geom.surface.x == dialog_window_margin
	assert geom.surface.width == 400 - 2 * dialog_window_margin
	assert geom.surface.y == dialog_window_margin
	assert geom.surface.height == 300 - 2 * dialog_window_margin
	assert geom.scrolls
	assert geom.body.height < geom.content_height
	// The footer stays visible at the bottom of the surface, a little apart from
	// the content the body cuts off.
	assert geom.footer.y + geom.footer.height + 16 == geom.surface.height
	assert geom.footer.y - (geom.body.y + geom.body.height) == 8
	el := modal_dialog(cfg) or { panic(err) }
	body := dialogs_test_find(el, 'profile:component:body') or { panic('no body') }
	assert body.kind == .scroll
	assert body.children[0].frame.height == 1000
	dialogs_test_assert_local_geometry(el)
}

fn test_dialog_wraps_long_titles_and_descriptions() {
	short := dialog_layout(dialogs_test_profile(true)) or { panic(err) }
	assert short.title_lines == 1
	assert short.description_lines == 1
	long := dialog_layout(DialogConfig{
		...dialogs_test_profile(true)
		description: 'This action cannot be undone. This will permanently delete your account and remove your data from our servers.'
	}) or { panic(err) }
	assert long.description_lines >= 2
	assert long.description.height == f64(long.description_lines) * font_line_height(14) +
		dialog_wrap_slack
	assert long.surface.height > short.surface.height
	el := modal_dialog(DialogConfig{ ...dialogs_test_profile(true), description: 'one\ntwo\nthree' }) or {
		panic(err)
	}
	description := dialogs_test_find(el, 'profile:component:description') or { panic('none') }
	assert description.text_style.lines == 3
	assert description.text_style.valign == .top
}

fn test_dialog_wrap_estimate() {
	assert dialog_wrap_width('iiii', 10) < dialog_wrap_width('nnnn', 10)
	assert dialog_wrap_width('nnnn', 10) < dialog_wrap_width('MMMM', 10)
	assert dialog_wrap_width('中文', 10) == 20
	assert dialog_line_count('', 14, false, 100) == 0
	assert dialog_line_count('word', 14, false, 0) == 1
	assert dialog_line_count('a\nb', 14, false, 1000) == 2
	assert dialog_line_count('a few words', 16, true, 1000) == 1
	assert dialog_text_height(0, 14) == 0
	assert dialog_text_height(1, 14) == font_line_height(14)
	assert dialog_text_height(2, 14) == 2 * font_line_height(14) + dialog_wrap_slack
	$if macos {
		// AppKit and the custom renderer both draw this on two lines; the estimate
		// used to make it three and leave a blank line under it.
		geom := alert_dialog_layout(AlertDialogConfig{
			...dialogs_test_alert()
			description: 'This permanently deletes the project and everything in it. This action cannot be undone.'
		}) or { panic(err) }
		assert geom.description_lines == 2
	}
}

fn test_dialog_is_a_retained_overlay() {
	el := modal_dialog(dialogs_test_profile(true)) or { panic(err) }
	assert el.id == dialog_surface_id('profile')
	assert el.accessibility_role == 'dialog'
	assert el.accessibility_label == 'Edit profile'
	assert !el.hidden
	// The overlay layer centers the surface and lays the backdrop under it.
	overlay := el.overlay or { panic('not an overlay') }
	assert overlay.kind == .dialog && overlay.open
	assert overlay.dismiss_on_escape && overlay.dismiss_on_outside
	geom := dialog_layout(dialogs_test_profile(true)) or { panic(err) }
	assert el.frame == rect(0, 0, geom.surface.width, geom.surface.height)
	assert el.box.bg == ComponentTheme{}.background
	assert el.focus_scope
	validate_element_tree(screen(0xffffff, [el])) or { panic(err) }
	close := dialogs_test_find(el, 'profile:component:close') or { panic('no close button') }
	assert close.button_behavior
	assert close.accessibility_label == 'Close'
	assert close.children[0].image_path == 'symbol:xmark'
	assert symbol_known('xmark')
	save := dialogs_test_find(el, dialog_button_id('profile', 'save')) or { panic('no save') }
	assert save.text == 'Save changes'
	assert save.box.bg == ComponentTheme{}.primary
	assert save.enabled
	later := dialogs_test_find(el, dialog_button_id('profile', 'later')) or { panic('no later') }
	assert !later.enabled
	assert later.box.bg == ComponentTheme{}.background
	name := dialogs_test_find(el, 'name') or { panic('no body child') }
	assert name.frame == rect(0, 0, 200, 32)
	// A closed dialog stays in the tree, hidden, so its fields keep their state.
	closed := modal_dialog(dialogs_test_profile(false)) or { panic(err) }
	assert closed.hidden
	assert !(closed.overlay or { panic('not an overlay') }).open
	assert dialogs_test_find(closed, 'name') != none
	disabled := modal_dialog(DialogConfig{ ...dialogs_test_profile(true), enabled: false }) or {
		panic(err)
	}
	assert !(dialogs_test_find(disabled, dialog_button_id('profile', 'save')) or {
		panic('no save')
	}).enabled
	assert !(dialogs_test_find(disabled, 'profile:component:close') or { panic('none') }).enabled
}

fn test_dialog_backdrops() {
	solid := modal_dialog(DialogConfig{ ...dialogs_test_profile(true), backdrop: .solid }) or {
		panic(err)
	}
	solid_overlay := solid.overlay or { panic('not an overlay') }
	assert solid_overlay.backdrop.bg == dialog_backdrop_color(ComponentTheme{})
	assert solid_overlay.backdrop_opacity == 1
	assert dialog_backdrop_color(ComponentTheme{}) == 0x8c8c8c
	assert dialog_backdrop_color(component_theme(true)) < 0x172033
	dim := modal_dialog(dialogs_test_profile(true)) or { panic(err) }
	dim_overlay := dim.overlay or { panic('not an overlay') }
	assert dim_overlay.backdrop.bg == 0x000000
	assert dim_overlay.backdrop_opacity == 0.4
	assert dialog_scrim_opacity(component_theme(true)) == 0.6
	clear := modal_dialog(DialogConfig{ ...dialogs_test_profile(true), backdrop: .clear }) or {
		panic(err)
	}
	assert (clear.overlay or { panic('not an overlay') }).backdrop_opacity == 0
	pinned := modal_dialog(DialogConfig{ ...dialogs_test_profile(true), close_on_backdrop: false }) or {
		panic(err)
	}
	assert !(pinned.overlay or { panic('not an overlay') }).dismiss_on_outside
	// Without a backdrop the dialog is a popover at its place, so the rest of
	// the window keeps working.
	free := modal_dialog(DialogConfig{ ...dialogs_test_profile(true), backdrop: .none }) or {
		panic(err)
	}
	geom := dialog_layout(dialogs_test_profile(true)) or { panic(err) }
	free_overlay := free.overlay or { panic('not an overlay') }
	assert free_overlay.kind == .popover
	assert !free_overlay.dismiss_on_outside
	point := free_overlay.point or { panic('no point') }
	assert point.x == geom.surface.x && point.y == geom.surface.y
	assert free.frame == rect(0, 0, geom.surface.width, geom.surface.height)
}

fn test_dialog_callbacks_report_each_request() {
	cfg := dialogs_test_profile(true)
	mut log := &DialogsTestLog{}
	el := dialogs_test_listened(cfg, mut log)
	dialogs_test_click(dialogs_test_find(el, 'profile:component:close') or { panic('no close') })
	dialogs_test_click(dialogs_test_find(el, dialog_button_id('profile', 'save')) or {
		panic('no save')
	})
	dialogs_test_click(dialogs_test_find(el, dialog_button_id('profile', 'cancel')) or {
		panic('no cancel')
	})
	dialogs_test_dismiss(el, .outside_pointer)
	dialogs_test_dismiss(el, .escape)
	dialogs_test_dismiss(el, .selection)
	assert log.events == [DialogEvent{
		reason: .close_button
	}, DialogEvent{
		reason: .confirm
		button: 'save'
	}, DialogEvent{
		reason: .cancel
		button: 'cancel'
	}, DialogEvent{
		reason: .backdrop
	}, DialogEvent{
		reason: .escape
	}]
	assert log.events[0].dismisses()
	assert !log.events[1].dismisses()
	assert log.events[2].dismisses()
	// A disabled button takes no clicks.
	later := dialogs_test_find(el, dialog_button_id('profile', 'later')) or { panic('no later') }
	assert !dialogs_test_has_callback(later)
	// Nothing answers while the dialog is closed or disabled.
	for rejected in [DialogConfig{
		...cfg
		open: false
	}, DialogConfig{
		...cfg
		enabled: false
	}] {
		quiet := dialogs_test_listened(rejected, mut log)
		close := dialogs_test_find(quiet, 'profile:component:close') or { panic('no close') }
		assert !dialogs_test_has_callback(close)
		assert voidptr((quiet.overlay or { panic('not an overlay') }).on_dismiss) == unsafe { nil }
	}
	log.events.clear()
	no_close := dialogs_test_listened(DialogConfig{
		...cfg
		close_button:      false
		close_on_backdrop: false
		close_on_escape:   false
	}, mut log)
	assert dialogs_test_find(no_close, 'profile:component:close') == none
	dialogs_test_dismiss(no_close, .outside_pointer)
	dialogs_test_dismiss(no_close, .escape)
	free := dialogs_test_listened(DialogConfig{
		...cfg
		backdrop: .none
	}, mut log)
	dialogs_test_dismiss(free, .outside_pointer)
	assert log.events.len == 0
}

fn test_dialog_key_event_reads_escape_and_enter() {
	cfg := dialogs_test_profile(true)
	escape := dialog_key_event(cfg, KeyEvent{ code: .escape }) or { panic('escape') }
	assert escape.reason == .escape && escape.dismisses()
	enter := dialog_key_event(cfg, KeyEvent{ code: .enter }) or { panic('enter') }
	assert enter == DialogEvent{
		reason: .confirm
		button: 'save'
	}
	keypad := dialog_key_event(cfg, KeyEvent{ code: .kp_enter }) or { panic('keypad enter') }
	assert keypad.button == 'save'
	none_event := DialogEvent{
		button: 'none'
	}
	for event in [KeyEvent{
		code: .escape
		cmd:  true
	}, KeyEvent{
		code:  .enter
		shift: true
	}, KeyEvent{
		code: .a
	}] {
		assert (dialog_key_event(cfg, event) or { none_event }) == none_event
	}
	assert (dialog_key_event(DialogConfig{ ...cfg, close_on_escape: false }, KeyEvent{
		code: .escape
	}) or { none_event }) == none_event
	assert (dialog_key_event(DialogConfig{ ...cfg, confirm_on_enter: false }, KeyEvent{
		code: .enter
	}) or { none_event }) == none_event
	assert (dialog_key_event(DialogConfig{ ...cfg, open: false }, KeyEvent{ code: .escape }) or {
		none_event
	}) == none_event
	// A disabled confirm button is skipped; with none left Enter does nothing.
	only_cancel := DialogConfig{
		...cfg
		buttons: [cfg.buttons[0], DialogButton{
			id:      'save'
			text:    'Save'
			role:    .confirm
			enabled: false
		}]
	}
	assert (dialog_key_event(only_cancel, KeyEvent{ code: .enter }) or { none_event }) == none_event
}

fn test_dialog_validation() {
	if _ := modal_dialog(DialogConfig{ frame: rect(0, 0, 100, 100) }) {
		assert false, 'dialog accepted without identity'
	}
	base := dialogs_test_profile(true)
	for bad in [DialogConfig{
		...base
		frame: rect(0, 0, math.nan(), 10)
	}, DialogConfig{
		...base
		custom_width: -1
	}, DialogConfig{
		...base
		height: math.inf(1)
	}, DialogConfig{
		...base
		content_height: -2
	}, DialogConfig{
		...base
		buttons: [DialogButton{
			id: 'a'
		}, DialogButton{
			id: 'a'
		}]
	}, DialogConfig{
		...base
		buttons: [DialogButton{
			id: ' '
		}]
	}, DialogConfig{
		...base
		children: [label('profile:component:title', '', Rect{}, TextStyle{})]
	}] {
		if _ := modal_dialog(bad) {
			assert false, 'invalid dialog accepted'
		}
	}
}

fn test_dialog_tiny_frames_keep_geometry_inside() {
	for extent in [0.0, 1.0, 20.0, 60.0, 120.0, 300.0] {
		frame := rect(0, 0, extent, extent * 0.75)
		cfg := DialogConfig{
			...dialogs_test_profile(true)
			frame: frame
			icon:  'info.circle'
		}
		dialogs_test_assert_local_geometry(modal_dialog(cfg) or { panic(err) })
		alert_el := alert_dialog(
			id:          'alert'
			frame:       frame
			open:        true
			title:       'Delete?'
			description: 'Cannot be undone.'
			icon:        'trash'
		) or { panic(err) }
		dialogs_test_assert_local_geometry(alert_el)
		for side in [SheetSide.left, .right, .top, .bottom] {
			sheet_el := sheet(
				id:         'sheet'
				frame:      frame
				open:       true
				side:       side
				title:      'Settings'
				resizable:  true
				margin_top: 10
				children:   [label('', 'x', rect(0, 0, 100, 20), TextStyle{})]
				buttons:    [DialogButton{
					id:   'ok'
					text: 'OK'
				}]
			) or { panic(err) }
			dialogs_test_assert_local_geometry(sheet_el)
		}
	}
}

fn test_dialog_animate_drops_the_surface_into_place() {
	motion := dialog_motion()
	assert motion.enter.opacity == 0
	assert motion.enter.transform.translate_y == -dialog_entrance_travel
	assert motion.enter_transition.duration == dialog_entrance_duration
	motion.validate() or { panic(err) }
	still := modal_dialog(dialogs_test_profile(true)) or { panic(err) }
	assert still.motion == none
	animated := modal_dialog(DialogConfig{ ...dialogs_test_profile(true), animate: true }) or {
		panic(err)
	}
	entrance := animated.motion or { panic('no motion') }
	assert entrance.enter.transform.translate_y == -dialog_entrance_travel
	alert := alert_dialog(AlertDialogConfig{ ...dialogs_test_alert(), animate: true }) or {
		panic(err)
	}
	assert alert.motion != none
}

fn dialogs_test_alert() AlertDialogConfig {
	return AlertDialogConfig{
		id:           'delete'
		frame:        rect(0, 0, 800, 600)
		open:         true
		title:        'Delete project?'
		description:  'This permanently deletes the project and its history.'
		icon:         'trash'
		confirm_text: 'Delete'
		destructive:  true
	}
}

fn test_alert_dialog_defaults_and_destructive_variant() {
	cfg := dialogs_test_alert()
	el := alert_dialog(cfg) or { panic(err) }
	assert el.accessibility_role == 'alertdialog'
	assert el.accessibility_label == 'Delete project?'
	// No close button, and the backdrop does not dismiss.
	assert (dialogs_test_find(el, 'delete:component:close') or { Element{} }).id == ''
	assert !(el.overlay or { panic('not an overlay') }).dismiss_on_outside
	confirm_el := dialogs_test_find(el, dialog_button_id('delete', 'confirm')) or {
		panic('no confirm')
	}
	cancel_el := dialogs_test_find(el, dialog_button_id('delete', 'cancel')) or {
		panic('no cancel')
	}
	assert confirm_el.text == 'Delete'
	assert confirm_el.box.bg == ComponentTheme{}.danger
	assert confirm_el.accessibility_value == 'default'
	assert cancel_el.text == 'Cancel'
	assert cancel_el.accessibility_value == ''
	// Cancel comes first and the pair is centered.
	geom := alert_dialog_layout(cfg) or { panic(err) }
	assert geom.surface.width == 420
	assert geom.buttons[0].x < geom.buttons[1].x
	left_gap := geom.buttons[0].x - 16
	right_gap := 420 - 16 - geom.buttons[1].x - geom.buttons[1].width
	assert math.abs(left_gap - right_gap) < 1e-9
	icon := dialogs_test_keyed(el, 'icon') or { panic('no icon') }
	assert icon.image_path == 'symbol:trash'
	assert icon.text_style.color == ComponentTheme{}.danger
	plain := alert_dialog(AlertDialogConfig{
		...cfg
		destructive: false
		icon_tone:   ComponentTone.primary
	}) or { panic(err) }
	assert (dialogs_test_keyed(plain, 'icon') or { panic('no icon') }).text_style.color == ComponentTheme{}.primary
	assert (dialogs_test_find(plain, dialog_button_id('delete', 'confirm')) or {
		panic('no confirm')
	}).box.bg == ComponentTheme{}.primary
	single := alert_dialog(AlertDialogConfig{ ...cfg, show_cancel: false }) or { panic(err) }
	assert (dialogs_test_find(single, dialog_button_id('delete', 'cancel')) or {
		Element{}
	}).id == ''
}

fn dialogs_test_alert_listened(config AlertDialogConfig, mut log DialogsTestLog) Element {
	return alert_dialog(AlertDialogConfig{
		...config
		on_choice: fn [mut log] (choice AlertDialogChoice) {
			log.choices << choice
		}
	}) or { panic(err) }
}

fn test_alert_dialog_choices() {
	cfg := dialogs_test_alert()
	mut log := &DialogsTestLog{}
	el := dialogs_test_alert_listened(cfg, mut log)
	dialogs_test_click(dialogs_test_find(el, dialog_button_id('delete', 'confirm')) or {
		panic('no confirm')
	})
	dialogs_test_click(dialogs_test_find(el, dialog_button_id('delete', 'cancel')) or {
		panic('no cancel')
	})
	// Escape cancels; the backdrop does not dismiss an alert unless asked.
	dialogs_test_dismiss(el, .outside_pointer)
	dialogs_test_dismiss(el, .escape)
	assert log.choices == [AlertDialogChoice.confirm, .cancel, .cancel]
	log.choices.clear()
	closable := dialogs_test_alert_listened(AlertDialogConfig{
		...cfg
		close_on_backdrop: true
		close_button:      true
	}, mut log)
	dialogs_test_dismiss(closable, .outside_pointer)
	dialogs_test_click(dialogs_test_find(closable, 'delete:component:close') or {
		panic('no close')
	})
	assert log.choices == [AlertDialogChoice.cancel, .cancel]
	disabled := dialogs_test_alert_listened(AlertDialogConfig{ ...cfg, enabled: false }, mut log)
	assert !dialogs_test_has_callback(dialogs_test_find(disabled, dialog_button_id('delete',
		'confirm')) or { panic('no confirm') })
	assert (alert_dialog_key_choice(cfg, KeyEvent{ code: .escape }) or { panic('escape') }) == .cancel
	assert (alert_dialog_key_choice(cfg, KeyEvent{ code: .enter }) or { panic('enter') }) == .confirm
	careful := AlertDialogConfig{
		...cfg
		default_choice: .cancel
	}
	assert (alert_dialog_key_choice(careful, KeyEvent{ code: .enter }) or { panic('enter') }) == .cancel
	marked := alert_dialog(careful) or { panic(err) }
	assert (dialogs_test_find(marked, dialog_button_id('delete', 'cancel')) or {
		panic('no cancel')
	}).accessibility_value == 'default'
	// With the Cancel button hidden, Enter can only confirm.
	assert (alert_dialog_key_choice(AlertDialogConfig{ ...careful, show_cancel: false }, KeyEvent{
		code: .enter
	}) or { panic('enter') }) == .confirm
	assert (alert_dialog_key_choice(AlertDialogConfig{ ...cfg, close_on_escape: false }, KeyEvent{
		code: .escape
	}) or { AlertDialogChoice.confirm }) == .confirm
	assert (alert_dialog_key_choice(AlertDialogConfig{ ...cfg, open: false }, KeyEvent{
		code: .enter
	}) or { AlertDialogChoice.cancel }) == .cancel
}

fn dialogs_test_sheet(side SheetSide) SheetConfig {
	return SheetConfig{
		id:          'sheet'
		frame:       rect(0, 0, 900, 600)
		open:        true
		side:        side
		title:       'Settings'
		description: 'Adjust the workspace.'
		children:    [dialogs_test_field('display', rect(0, 0, 200, 32))]
		buttons:     [DialogButton{
			id:   'apply'
			text: 'Apply'
			role: .confirm
		}]
	}
}

fn test_sheet_layout_places_the_panel_on_each_side() {
	right := sheet_layout(dialogs_test_sheet(.right)) or { panic(err) }
	assert right.surface == rect(550, 0, 350, 600)
	assert right.offscreen == rect(900, 0, 350, 600)
	left := sheet_layout(dialogs_test_sheet(.left)) or { panic(err) }
	assert left.surface == rect(0, 0, 350, 600)
	assert left.offscreen == rect(-350, 0, 350, 600)
	top := sheet_layout(SheetConfig{ ...dialogs_test_sheet(.top), panel_size: 240, margin_top: 30 }) or {
		panic(err)
	}
	assert top.surface == rect(0, 30, 900, 240)
	assert top.offscreen == rect(0, -210, 900, 240)
	bottom := sheet_layout(SheetConfig{ ...dialogs_test_sheet(.bottom), panel_size: 240, margin_top: 30 }) or {
		panic(err)
	}
	assert bottom.surface == rect(0, 360, 900, 240)
	assert bottom.offscreen == rect(0, 600, 900, 240)
	// The body fills the panel between the header and the bottom footer.
	assert right.footer.y + right.footer.height + 16 == 600
	assert right.body.y + right.body.height == right.footer.y
	assert right.content_width == 350 - 32
	assert !right.scrolls
	wide := sheet_layout(SheetConfig{ ...dialogs_test_sheet(.left), panel_size: 5000 }) or {
		panic(err)
	}
	assert wide.surface.width == 900
	tall := sheet_layout(SheetConfig{ ...dialogs_test_sheet(.right), content_height: 2000 }) or {
		panic(err)
	}
	assert tall.scrolls
}

fn test_sheet_element_structure() {
	el := sheet(dialogs_test_sheet(.right)) or { panic(err) }
	assert el.accessibility_role == 'dialog'
	assert el.frame == rect(0, 0, 900, 600)
	assert el.children[0].id == 'sheet:component:backdrop'
	assert el.children[0].kind == .button
	panel_el := el.children[1]
	assert panel_el.id == sheet_panel_id('sheet')
	assert panel_el.frame == rect(550, 0, 350, 600)
	assert panel_el.box.border_left == 1 && panel_el.box.border_right == 0
	// A transparent button under the content keeps clicks off the backdrop.
	assert panel_el.children[0].kind == .button
	assert panel_el.children[0].box.transparent
	close := dialogs_test_find(el, 'sheet:component:close') or { panic('no close') }
	assert close.children[0].image_path == 'symbol:xmark'
	assert (dialogs_test_find(el, 'display') or { panic('no body child') }).frame == rect(0, 0,
		200, 32)
	closed := sheet(SheetConfig{ ...dialogs_test_sheet(.right), open: false }) or { panic(err) }
	assert closed.hidden
	free := sheet(SheetConfig{ ...dialogs_test_sheet(.right), backdrop: .none }) or { panic(err) }
	assert free.children.len == 1
	solid := sheet(SheetConfig{ ...dialogs_test_sheet(.top), backdrop: .solid }) or { panic(err) }
	assert solid.children[0].box.bg == dialog_backdrop_color(ComponentTheme{})
	assert solid.children[1].box.border_bottom == 1
	handle := sheet(SheetConfig{ ...dialogs_test_sheet(.left), resizable: true }) or { panic(err) }
	grip := dialogs_test_find(handle, 'sheet:component:resize') or { panic('no handle') }
	assert grip.draggable
	assert grip.cursor == cursor_resize_ew
	assert grip.frame == rect(344, 0, 6, 600)
	if _ := sheet(SheetConfig{ ...dialogs_test_sheet(.left), panel_size: -1 }) {
		assert false, 'negative sheet size accepted'
	}
	if _ := sheet(SheetConfig{ ...dialogs_test_sheet(.left), id: '' }) {
		assert false, 'sheet accepted without identity'
	}
}

fn dialogs_test_drag(kind ElementEventKind, x f64, y f64) ElementEvent {
	return ElementEvent{
		kind: kind
		id:   'sheet:component:resize'
		x:    x
		y:    y
	}
}

fn test_sheet_callbacks_and_resize() {
	cfg := dialogs_test_sheet(.right)
	mut log := &DialogsTestLog{}
	el := sheet(SheetConfig{
		...cfg
		on_dialog: fn [mut log] (event DialogEvent) {
			log.events << event
		}
	}) or { panic(err) }
	dialogs_test_click(el.children[0])
	dialogs_test_click(dialogs_test_find(el, 'sheet:component:close') or { panic('no close') })
	dialogs_test_click(dialogs_test_find(el, dialog_button_id('sheet', 'apply')) or {
		panic('no apply')
	})
	assert log.events.map(it.reason) == [DialogReason.backdrop, .close_button, .confirm]
	assert log.events[2].button == 'apply'
	// The surface under the content only keeps clicks off the backdrop.
	surface := dialogs_test_find(el, 'sheet:component:surface') or { panic('no surface') }
	assert !dialogs_test_has_callback(surface)
	pinned := sheet(SheetConfig{
		...cfg
		close_on_backdrop: false
		on_dialog:         fn [mut log] (event DialogEvent) {
			log.events << event
		}
	}) or { panic(err) }
	assert !dialogs_test_has_callback(pinned.children[0])
	assert (sheet_key_event(cfg, KeyEvent{ code: .escape }) or { panic('escape') }).reason == .escape
	// Enter only confirms in a sheet that asks for it.
	assert (sheet_key_event(cfg, KeyEvent{ code: .enter }) or {
		DialogEvent{
			button: 'none'
		}
	}).button == 'none'
	assert (sheet_key_event(SheetConfig{ ...cfg, confirm_on_enter: true }, KeyEvent{
		code: .enter
	}) or { panic('enter') }).button == 'apply'
	resizable := SheetConfig{
		...cfg
		resizable: true
	}
	assert (sheet_size_from_pointer(resizable, dialogs_test_drag(.pointer_drag, 500, 40)) or {
		panic('drag')
	}) == 400
	assert (sheet_size_from_pointer(resizable, dialogs_test_drag(.pointer_drag, 880, 40)) or {
		panic('drag')
	}) == 160
	assert (sheet_size_from_pointer(resizable, dialogs_test_drag(.pointer_up, -50, 40)) or {
		panic('drag')
	}) == 900
	left := SheetConfig{
		...resizable
		side: .left
	}
	assert (sheet_size_from_pointer(left, dialogs_test_drag(.pointer_drag, 420, 40)) or {
		panic('drag')
	}) == 420
	bottom := SheetConfig{
		...resizable
		side: .bottom
	}
	assert (sheet_size_from_pointer(bottom, dialogs_test_drag(.pointer_drag, 10, 350)) or {
		panic('drag')
	}) == 250
	top := SheetConfig{
		...resizable
		side:       .top
		margin_top: 20
	}
	assert (sheet_size_from_pointer(top, dialogs_test_drag(.pointer_drag, 10, 320)) or {
		panic('drag')
	}) == 300
	for event in [dialogs_test_drag(.pointer_enter, 1, 2), dialogs_test_drag(.click, 1, 2),
		dialogs_test_drag(.pointer_drag, math.nan(), 2)] {
		assert (sheet_size_from_pointer(resizable, event) or { -1.0 }) == -1.0, '${event.kind}'
	}
	// The handle reports the sizes a drag asks for.
	handle := sheet(SheetConfig{
		...resizable
		on_resize: fn [mut log] (size f64) {
			log.sizes << size
		}
	}) or { panic(err) }
	grip := dialogs_test_find(handle, 'sheet:component:resize') or { panic('no handle') }
	grip.on_event(dialogs_test_drag(.pointer_down, 500, 40))
	grip.on_event(dialogs_test_drag(.pointer_drag, 880, 40))
	grip.on_event(dialogs_test_drag(.pointer_enter, 600, 40))
	assert log.sizes == [400.0, 160]
	assert (sheet_size_from_pointer(cfg, dialogs_test_drag(.pointer_drag, 500, 40)) or {
		-1.0
	}) == -1.0
}

fn test_sheet_animations_slide_from_the_edge_and_back() {
	reset_widget_animations()
	cfg := dialogs_test_sheet(.right)
	panel_id := sheet_panel_id('sheet')
	opening := sheet_open_animation(cfg) or { panic(err) }
	start_widget_animation_at(panel_id, opening, 1_000, false)
	root := screen(0xffffff, [sheet(cfg) or { panic(err) }])
	first := dialogs_test_find(apply_widget_animations_at(root, 1_000), panel_id) or {
		panic('no panel')
	}
	assert first.frame.x == 900
	middle := dialogs_test_find(apply_widget_animations_at(root, 1_100), panel_id) or {
		panic('no panel')
	}
	assert middle.frame.x > 550 && middle.frame.x < 900
	last := dialogs_test_find(apply_widget_animations_at(root, 1_300), panel_id) or {
		panic('no panel')
	}
	assert last.frame.x == 550
	assert animation_info(panel_id).status == .idle
	vertical := sheet_open_animation(SheetConfig{ ...cfg, side: .bottom }) or { panic(err) }
	assert vertical.animated_properties() == ['y']

	mut closed := &DialogsTestCounter{}
	closing := sheet_close_animation(cfg, fn [mut closed] () {
		closed.count++
	}) or { panic(err) }
	start_widget_animation_at(panel_id, closing, 2_000, false)
	apply_widget_animations_at(root, 2_000)
	assert closed.count == 0
	out := dialogs_test_find(apply_widget_animations_at(root, 2_300), panel_id) or {
		panic('no panel')
	}
	assert out.frame.x == 900
	assert closed.count == 1
	assert animation_info(panel_id).status == .idle
}

fn test_focus_trap_next_cycles_and_wraps() {
	ids := ['name', 'email', 'bio']
	assert focus_trap_next(ids, 'name', false) == 'email'
	assert focus_trap_next(ids, 'bio', false) == 'name'
	assert focus_trap_next(ids, 'name', true) == 'bio'
	assert focus_trap_next(ids, 'email', true) == 'name'
	assert focus_trap_next(ids, '', false) == 'name'
	assert focus_trap_next(ids, 'page-search', true) == 'bio'
	assert focus_trap_next(['only'], 'only', false) == 'only'
	assert focus_trap_next([]string{}, 'name', false) == ''
	assert focus_trap_next(['', ''], '', false) == ''
	// Empty and repeated ids are skipped.
	assert focus_trap_next(['a', '', 'a', 'b'], 'a', false) == 'b'
	assert focus_trap_next(['a', '', 'a', 'b'], 'b', false) == 'a'
}

fn test_focus_trap_key_directions() {
	assert (focus_trap_direction(KeyEvent{ code: .tab }) or { panic('tab') }) == false
	assert (focus_trap_direction(KeyEvent{ code: .tab, shift: true }) or { panic('shift tab') }) == true
	for event in [KeyEvent{
		code: .tab
		ctrl: true
	}, KeyEvent{
		code: .tab
		cmd:  true
	}, KeyEvent{
		code: .tab
		alt:  true
	}, KeyEvent{
		code: .enter
	}] {
		assert (focus_trap_direction(event) or { true }) == true
		assert (focus_trap_direction(event) or { false }) == false
	}
	assert (focus_trap_key_direction('tab') or { panic('tab') }) == false
	assert (focus_trap_key_direction('shift+tab') or { panic('shift+tab') }) == true
	assert (focus_trap_key_direction('ctrl+tab') or { true }) == true
	assert (focus_trap_key_direction('ctrl+tab') or { false }) == false
}

fn test_focus_traps_modal_nested_and_conditional() {
	dialog_trap := FocusTrap{
		ids: ['name', 'email']
	}
	assert (dialog_trap.first() or { '' }) == 'name'
	assert (dialog_trap.next('page', false) or { '' }) == 'name'
	assert (dialog_trap.next('email', false) or { '' }) == 'name'
	inline := FocusTrap{
		ids:   ['a', 'b']
		modal: false
	}
	assert (inline.next('page', false) or { 'none' }) == 'none'
	assert (inline.next('a', true) or { 'none' }) == 'b'
	off := FocusTrap{
		ids:     ['a']
		enabled: false
	}
	assert (off.next('a', false) or { 'none' }) == 'none'
	assert (off.first() or { 'none' }) == 'none'
	assert !off.contains('a')
	assert (FocusTrap{}.first() or { 'none' }) == 'none'
	outer := FocusTrap{
		ids: ['outer-1', 'inner-1', 'inner-2', 'outer-2']
	}
	inner := FocusTrap{
		ids:   ['inner-1', 'inner-2']
		modal: false
	}
	traps := [outer, inner]
	// Inside the nested trap, focus stays inside it.
	assert (focus_trap_target(traps, 'inner-2', false) or { '' }) == 'inner-1'
	// Elsewhere in the outer trap, the outer order applies.
	assert (focus_trap_target(traps, 'outer-2', false) or { '' }) == 'outer-1'
	// Outside every trap, the last modal one pulls focus in.
	assert (focus_trap_target(traps, 'page', true) or { '' }) == 'outer-2'
	assert (focus_trap_target([inner], 'page', false) or { 'none' }) == 'none'
	assert (focus_trap_target([]FocusTrap{}, 'page', false) or { 'none' }) == 'none'
	// A sheet opened over a dialog: the top one wins.
	sheet_trap := FocusTrap{
		ids: ['display']
	}
	assert (focus_trap_target([dialog_trap, sheet_trap], 'name', false) or { '' }) == 'email'
	assert (focus_trap_target([dialog_trap, sheet_trap], 'page', false) or { '' }) == 'display'
}

fn test_focus_trap_ids_collect_text_inputs_in_tree_order() {
	children := [
		label('caption', 'Name', rect(0, 0, 100, 20), TextStyle{}),
		dialogs_test_field('name', rect(0, 20, 100, 32)),
		view('group', rect(0, 60, 200, 100), BoxStyle{}, [
			text_area(id: 'bio', frame: rect(0, 0, 200, 60)) or { panic(err) },
			Element{
				...dialogs_test_field('hidden', Rect{})
				hidden: true
			},
			Element{
				...dialogs_test_field('disabled', Rect{})
				enabled: false
			},
			dialogs_test_field('', Rect{}),
		]),
		Element{
			...view('collapsed', Rect{}, BoxStyle{}, [
				dialogs_test_field('inside-hidden', Rect{}),
			])
			hidden: true
		},
		dialogs_test_field('email', rect(0, 170, 100, 32)),
	]
	assert focus_trap_ids(children) == ['name', 'bio', 'email']
	assert focus_trap_ids(dialogs_test_profile(true).children) == ['name', 'email']
}
