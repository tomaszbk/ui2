// vtest vflags: -d ui2_headless
module ui2

@[heap]
struct ElementKeysLog {
mut:
	events []string
	keys   []string
}

fn (mut log ElementKeysLog) callback() ElementCallback {
	return fn [mut log] (event ElementEvent) {
		if event.kind == .key_down {
			log.events << '${event.id}:${event.key}:${event.target}'
		}
	}
}

fn open_element_keys_window(mut log ElementKeysLog) &Window {
	mut app := new_app()
	mut w := app.new_window(
		title:  'Keys'
		width:  320
		height: 240
		build:  fn [mut log] (mut _ Window) Element {
			name := text_input(TextInputConfig{ id: 'name', frame: rect(10, 40, 200, 24) }) or {
				panic(err)
			}
			amount := text_input(TextInputConfig{ id: 'amount', frame: rect(10, 70, 200, 24) }) or {
				panic(err)
			}
			group := Element{
				...view('group', rect(0, 0, 320, 120), BoxStyle{}, [
					button('first', 'First', rect(10, 10, 80, 24), BoxStyle{}, TextStyle{}),
					button('second', 'Second', rect(100, 10, 80, 24), BoxStyle{}, TextStyle{}),
					name,
					Element{
						...amount
						keys:     ['up', 'down']
						on_event: log.callback()
					},
				])
				keys:     ['left', 'right', 'shift+tab', 'enter']
				on_event: log.callback()
			}
			inert := Element{
				...button('inert', 'Inert', rect(10, 130, 80, 24), BoxStyle{}, TextStyle{})
				keys: ['left']
			}
			return view('root', rect(0, 0, 320, 240), BoxStyle{}, [group, inert])
		}
	) or { panic(err) }
	w.on_key(fn [mut log] (mut _ Window, name string) {
		log.keys << name
	})
	return w
}

fn test_key_event_names_follow_the_on_key_spelling() {
	assert key_event_name(KeyEvent{ code: .a }) == 'a'
	assert key_event_name(KeyEvent{ code: .tab, shift: true }) == 'shift+tab'
	assert key_event_name(KeyEvent{ code: .s, cmd: true, ctrl: true, alt: true, shift: true }) == 'cmd+ctrl+alt+shift+s'
	assert key_event_name(KeyEvent{ code: .space }) == 'space'
	assert key_event_name(KeyEvent{ code: .kp_enter }) == 'enter'
	assert key_event_name(KeyEvent{ code: .delete }) == 'forward_delete'
	assert key_event_name(KeyEvent{ code: .page_down }) == 'page_down'
	assert key_event_name(KeyEvent{ code: .f5 }) == 'f5'
	assert key_event_name(KeyEvent{ code: .left_bracket }) == '['
	assert key_event_name(KeyEvent{ code: .left_shift, shift: true }) == ''
	assert key_event_name(KeyEvent{ code: .invalid }) == ''
}

fn test_a_focused_descendant_routes_declared_keys_to_its_ancestor() {
	mut log := &ElementKeysLog{}
	mut w := open_element_keys_window(mut log)
	w.focus('first')
	assert w.headless_key(KeyEvent{ code: .right })
	assert log.events == ['group:right:first']
	// The element takes the key before the application's handlers and focus
	// navigation, which would otherwise move focus.
	assert log.keys == []
	assert w.focused_id() == 'first'
	assert w.headless_key(KeyEvent{ code: .tab, shift: true })
	assert log.events.last() == 'group:shift+tab:first'
	assert w.focused_id() == 'first'
	// An undeclared key goes on to on_key and then to focus navigation.
	assert w.headless_key(KeyEvent{ code: .tab })
	assert log.keys == ['tab']
	assert w.focused_id() == 'second'
	assert log.events.len == 2
}

fn test_repeated_activation_keys_are_claimed_once() {
	mut log := &ElementKeysLog{}
	mut w := open_element_keys_window(mut log)
	w.focus('second')
	assert w.element_key(KeyEvent{ code: .enter }, false)
	assert w.element_key(KeyEvent{ code: .enter }, true)
	assert w.element_key(KeyEvent{ code: .left }, true)
	assert log.events == ['group:enter:second', 'group:left:second']
}

fn test_text_fields_keep_their_caret_keys() {
	mut log := &ElementKeysLog{}
	mut w := open_element_keys_window(mut log)
	w.focus('name')
	assert !w.element_key(KeyEvent{ code: .left }, false)
	assert log.events == []
	// A field that declares a key takes it itself.
	w.focus('amount')
	assert w.element_key(KeyEvent{ code: .up }, false)
	assert !w.element_key(KeyEvent{ code: .right }, false)
	assert log.events == ['amount:up:amount']
}

fn test_elements_without_a_callback_or_focus_take_no_keys() {
	mut log := &ElementKeysLog{}
	mut w := open_element_keys_window(mut log)
	w.focus('inert')
	assert !w.element_key(KeyEvent{ code: .left }, false)
	w.dismiss_keyboard()
	assert !w.element_key(KeyEvent{ code: .left }, false)
	assert log.events == []
}
