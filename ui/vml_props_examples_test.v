// vtest vflags: -d vml_props -d vml_fixtures
module ui2

// vml: ../examples/switch/switch.vml
// vml: ../examples/message/message.vml
// vml: fixtures/text_typography_0.vml
// vml: fixtures/compiled_overlay_surface.vml

// Golden equivalence of hand-written props with example documents used
// verbatim: switch, message, typography runs and an overlay surface.

struct PropsSwitchDemo {
pub mut:
	enabled bool = true
}

fn props_switch_compiled(mut app PropsSwitchDemo, frame Rect) Element {
	return switch_vml_framed(mut app, frame)
}

fn props_switch_tree(mut app PropsSwitchDemo, frame Rect) PNode {
	card_width := if frame.width - 32 < 288 { frame.width - 32 } else { 288.0 }
	return pn(ScreenProps{ style: style_list([style_background(0xF1F5F9)]) },
		id:       'root'
		children: [
			pn(AbsoluteProps{ style: style_list([style_transparent(true)]) },
				children: [
					pn(ViewProps{
						x:      (frame.width - card_width) / 2
						y:      16
						width:  card_width
						height: 128
						style:  style_list([style_background(0xFFFFFF), style_radius(10)])
					},
						id:       'card'
						children: [
							pn(AbsoluteProps{ style: style_list([style_transparent(true)]) },
								children: [
									pn(LabelProps{
										text:   if app.enabled { 'Enabled' } else { 'Disabled' }
										x:      16
										y:      14
										width:  card_width - 32
										height: 34
										style:  style_list([
											style_foreground(if app.enabled {
												u32(0x166534)
											} else {
												u32(0x991B1B)
											}),
											style_font_size(20),
											style_weight(700),
										])
									}, id: 'state'),
									pn(LabelProps{
										text:   'Feature enabled'
										x:      16
										y:      62
										width:  card_width - 96
										height: 42
										style:  style_list([
											style_foreground(0x111827),
											style_font_size(15),
										])
									}),
									pn(SwitchProps{
										active:       app.enabled
										x:            card_width - 76
										y:            67
										width:        60
										height:       32
										active_color: 0x16A34A
										on_change:    fn [mut app] (e ElementEvent) {
											app.enabled = e.checked
										}
									}, id: 'switch_control', bind: true),
								]
							),
						]
					),
				]
			),
		]
	)
}

fn test_props_switch_example_matches_compiled_vml() {
	for enabled in [true, false] {
		for frame in [rect(0, 0, 320, 160), rect(0, 0, 250, 160)] {
			mut compiled_app := PropsSwitchDemo{
				enabled: enabled
			}
			mut props_app := PropsSwitchDemo{
				enabled: enabled
			}
			compiled := props_switch_compiled(mut compiled_app, frame)
			built := props_document(props_switch_tree(mut props_app, frame), frame)!
			assert_props_equal('switch', compiled, built)
		}
	}
}

struct PropsMessageDemo {
pub mut:
	visible bool
	answer  string = 'No answer yet.'
	log     []string
}

pub fn (mut app PropsMessageDemo) show_message() {
	app.visible = true
}

pub fn (mut app PropsMessageDemo) close_message() {
	app.visible = false
}

pub fn (mut app PropsMessageDemo) show_native_message() {
	app.log << 'native'
}

pub fn (mut app PropsMessageDemo) ask_native_question() {
	app.log << 'question'
}

fn props_message_compiled(mut app PropsMessageDemo, frame Rect) Element {
	return message_vml_framed(mut app, frame)
}

fn props_message_button(mut app PropsMessageDemo, id string, text string, y f64, frame Rect, action fn (mut PropsMessageDemo)) PNode {
	return pn(ButtonProps{
		text:     text
		on_click: fn [mut app, action] (e ElementEvent) {
			action(mut app)
		}
		native:   true
		x:        16
		y:        y
		width:    frame.width - 64
		height:   36
	}, id: id)
}

fn props_message_tree(mut app PropsMessageDemo, frame Rect) PNode {
	transparent := style_list([style_transparent(true)])
	return pn(ScreenProps{ style: style_list([style_background(0xF1F5F9)]) },
		id:       'root'
		children: [
			pn(AbsoluteProps{ style: transparent },
				children: [
					pn(ViewProps{
						x:      16
						y:      16
						width:  frame.width - 32
						height: frame.height - 32
						style:  style_list([style_background(0xFFFFFF), style_radius(10)])
					},
						children: [
							pn(AbsoluteProps{ style: transparent },
								children: [
									pn(LabelProps{
										text:   'Message'
										x:      16
										y:      14
										width:  frame.width - 64
										height: 28
										style:  style_list([
											style_foreground(0x111827),
											style_font_size(18),
											style_weight(700),
										])
									}),
									pn(LabelProps{
										text:   'Native alerts block; the drawn one does not.'
										x:      16
										y:      50
										width:  frame.width - 64
										height: 22
										style:  style_list([
											style_foreground(0x64748B),
											style_font_size(13),
										])
									}),
									props_message_button(mut app, 'show_native_message', 'Show native message', 92, frame, fn (mut app PropsMessageDemo) {
										app.show_native_message()
									}),
									props_message_button(mut app, 'ask_native_question', 'Ask a native question', 136, frame, fn (mut app PropsMessageDemo) {
										app.ask_native_question()
									}),
									props_message_button(mut app, 'show_message', 'Show drawn message', 180, frame, fn (mut app PropsMessageDemo) {
										app.show_message()
									}),
									pn(LabelProps{
										text:   app.answer
										x:      16
										y:      228
										width:  frame.width - 64
										height: 22
										style:  style_list([
											style_foreground(0x475569),
											style_font_size(13),
										])
									}, id: 'answer'),
								]
							),
						]
					),
					pn(MessageBoxProps{
						hidden:       !app.visible
						title:        'Hello World'
						text:         'This message came from the ui example.'
						dialog_width: 360
					},
						id:       'overlay'
						children: [
							pn(ButtonProps{
								text:     'OK'
								on_click: fn [mut app] (e ElementEvent) {
									app.close_message()
								}
							}, id: 'close_message'),
						]
					),
				]
			),
		]
	)
}

fn test_props_message_example_matches_compiled_vml() {
	frame := rect(0, 0, 420, 320)
	for visible in [false, true] {
		mut compiled_app := PropsMessageDemo{
			visible: visible
		}
		mut props_app := PropsMessageDemo{
			visible: visible
		}
		compiled := props_message_compiled(mut compiled_app, frame)
		built := props_document(props_message_tree(mut props_app, frame), frame)!
		assert_props_equal('message', compiled, built)
	}
}

struct PropsTypographyApp {
pub mut:
	content  string = 'one two three four five six seven'
	run_size f64    = 24
}

fn props_typography_compiled(mut app PropsTypographyApp, frame Rect) Element {
	return text_typography_0_vml_framed(mut app, frame)
}

fn test_props_typography_runs_match_compiled_vml() {
	frame := rect(0, 0, 200, 320)
	mut compiled_app := PropsTypographyApp{}
	mut props_app := PropsTypographyApp{}
	compiled := props_typography_compiled(mut compiled_app, frame)
	built := props_document(pn(ScreenProps{},
		children: [
			pn(FlexProps{ orientation: .vertical, width: 120, height: 300 },
				children: [
					pn(LabelProps{ width: 120, style: style_list([style_lines(10), style_font_size(16)]) },
						children: [
							pn(RunProps{
								text:  props_app.content
								style: style_list([style_font_size(props_app.run_size)])
							}),
						]
					),
				]
			),
		]
	), frame)!
	assert_props_equal('typography', compiled, built)
}

@[heap]
struct PropsOverlayModel {
pub mut:
	open           bool = true
	hidden         bool
	count          int = 3
	context_open   bool
	tip_open       bool
	point          ?OverlayPoint = OverlayPoint{
		x: 12
		y: 18
	}
	dismiss_reason OverlayDismissReason
}

pub fn (mut app PropsOverlayModel) increment() {
	app.count++
}

pub fn (mut app PropsOverlayModel) dismiss(reason OverlayDismissReason) {
	app.dismiss_reason = reason
	app.open = false
}

pub fn (mut app PropsOverlayModel) open_context(x f64, y f64) {
	app.point = OverlayPoint{
		x: x
		y: y
	}
	app.context_open = true
}

pub fn (mut app PropsOverlayModel) dismiss_context() {
	app.context_open = false
}

pub fn (mut app PropsOverlayModel) show_tip() {
	app.tip_open = true
}

pub fn (mut app PropsOverlayModel) hide_tip() {
	app.tip_open = false
}

fn props_overlay_surface_compiled(mut app PropsOverlayModel) Element {
	return compiled_overlay_surface_vml_framed(mut app, rect(0, 0, 500, 400))
}

fn props_overlay_surface_tree(mut app PropsOverlayModel) PNode {
	return pn(ViewProps{ width: 500, height: 400 },
		id:       'document'
		children: [
			pn(ButtonProps{ width: 80, height: 30, text: 'Open' }, id: 'anchor'),
			pn(DialogProps{
				width:      320
				height:     180
				open:       app.open
				hidden:     app.hidden
				on_dismiss: fn [mut app] (e ElementEvent) {
					app.dismiss(e.dismiss_reason)
				}
			},
				id:       'dialog'
				children: [
					pn(ColumnProps{},
						children: [
							pn(TextInputProps{ text: 'Local draft', width: 240, height: 30 },
								id: 'draft'
							),
							pn(ButtonProps{
								text:     'Count'
								width:    100
								height:   30
								on_click: fn [mut app] (e ElementEvent) {
									app.increment()
								}
							}, id: 'counter'),
							pn(LabelProps{ text: app.count, width: 100, height: 30 }, id: 'count'),
						]
					),
				]
			),
			pn(ContextMenuProps{
				width:      160
				height:     100
				anchor:     'anchor'
				point:      app.point
				open:       app.context_open
				on_open:    fn [mut app] (e ElementEvent) {
					app.open_context(e.x, e.y)
				}
				on_dismiss: fn [mut app] (e ElementEvent) {
					app.dismiss_context()
				}
			},
				id:       'context'
				children: [
					pn(ButtonProps{ text: 'Action', width: 140, height: 30 }, id: 'context_action'),
				]
			),
			pn(TooltipProps{
				width:         120
				height:        40
				anchor:        'anchor'
				open:          app.tip_open
				on_open:       fn [mut app] (e ElementEvent) {
					app.show_tip()
				}
				on_dismiss:    fn [mut app] (e ElementEvent) {
					app.hide_tip()
				}
				tooltip_delay: 0.25
			},
				id:       'help'
				children: [
					pn(LabelProps{ text: 'Help' }),
				]
			),
		]
	)
}

fn test_props_overlay_surface_matches_compiled_vml() {
	frame := rect(0, 0, 500, 400)
	mut compiled_app := &PropsOverlayModel{}
	mut props_app := &PropsOverlayModel{}
	compiled := props_overlay_surface_compiled(mut compiled_app)
	built := props_document(props_overlay_surface_tree(mut props_app), frame)!
	assert_props_equal('overlay surface', compiled, built)
	for el in [compiled, built] {
		context := el.children[2]
		config := context.overlay or { panic('missing context overlay') }
		config.on_open(ElementEvent{ kind: .open, x: 40, y: 50 })
		dialog := el.children[1]
		dialog_config := dialog.overlay or { panic('missing dialog overlay') }
		dialog_config.on_dismiss(ElementEvent{ kind: .dismiss, dismiss_reason: .selection })
	}
	point := compiled_app.point or { panic('missing point') }
	assert point.x == 40 && compiled_app.context_open && !compiled_app.open
	assert '${compiled_app.point}' == '${props_app.point}'
	assert compiled_app.context_open == props_app.context_open
	assert compiled_app.dismiss_reason == props_app.dismiss_reason
}
