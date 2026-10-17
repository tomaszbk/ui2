// vtest vflags: -d ui2_headless
module ui2

@[heap]
struct HeadlessTestModel {
mut:
	checked bool
	events  []ElementEvent
	keys    []string
}

fn open_headless_test_window(mut model HeadlessTestModel) &Window {
	mut app := new_app()
	return app.new_window(
		title:  'Headless'
		width:  320
		height: 240
		build:  fn [mut model] (mut _ Window) Element {
			name := text_input(TextInputConfig{ id: 'name', text: 'Ada', frame: rect(10, 10, 200, 24) }) or {
				panic(err)
			}
			notes := text_area(TextAreaConfig{ id: 'notes', text: 'héllo', frame: rect(10, 70, 200, 60) }) or {
				panic(err)
			}
			agree := Element{
				...checkbox('agree', 'Agree', model.checked, rect(10, 40, 200, 24), TextStyle{})
				on_event: fn [mut model] (event ElementEvent) {
					model.events << event
					model.checked = event.checked
				}
			}
			return view('root', rect(0, 0, 320, 240), BoxStyle{}, [name, agree, notes])
		}
	) or { panic(err) }
}

fn test_headless_backend_is_selected_by_its_flag() {
	assert backend_name == 'headless'
	assert backend_supports_overlays
	assert backend_supports_motion
	assert backend_supports_visual_transforms
	assert !backend_needs_host
	assert control_support(.text_area) == .supported
}

fn test_headless_window_builds_once_and_keeps_live_control_state() {
	mut model := &HeadlessTestModel{}
	mut w := open_headless_test_window(mut model)
	assert w.title == 'Headless'
	assert w.bounds() == rect(0, 0, 320, 240)
	assert w.builds == 1
	assert w.layout_error == ''
	assert w.text('name') == 'Ada'
	w.set_text('name', 'Grace')
	w.request_refresh()
	assert w.headless_frame()
	assert w.builds == 2
	// An unchanged declaration leaves the user's edit in place.
	assert w.text('name') == 'Grace'
	assert !w.headless_frame()
	w.set_text('missing', 'x')
	assert w.text('missing') == ''
}

fn test_headless_windows_keep_their_own_state() {
	mut first_model := &HeadlessTestModel{}
	mut second_model := &HeadlessTestModel{}
	mut first := open_headless_test_window(mut first_model)
	mut second := open_headless_test_window(mut second_model)
	first.set_text('name', 'Grace')
	first.focus('notes')
	assert second.text('name') == 'Ada'
	assert second.focused_id() == ''
	assert first.focused_id() == 'notes'
}

fn test_headless_keys_reach_handlers_focus_and_activation() {
	mut model := &HeadlessTestModel{}
	mut w := open_headless_test_window(mut model)
	w.on_key(fn [mut model] (mut _ Window, name string) {
		model.keys << name
	})
	assert !w.headless_key(KeyEvent{ code: .a, cmd: true })
	assert model.keys == ['cmd+a']
	w.focus('name')
	assert w.focused_id() == 'name'
	assert w.headless_key(KeyEvent{ code: .tab })
	assert w.focused_id() == 'agree'
	assert w.headless_key(KeyEvent{ code: .space })
	assert model.events.len == 1
	assert model.events[0].id == 'agree'
	assert model.events[0].checked
	assert voidptr(model.events[0].window) == voidptr(w)
	assert w.control_checked('agree')
	assert w.refresh_pending
	assert w.headless_frame()
	assert w.control_checked('agree')
	nodes := w.semantic_tree()
	assert nodes.any(it.id == 'agree' && it.state.checked)
}

fn test_headless_text_area_edits_count_utf16_units() {
	mut model := &HeadlessTestModel{}
	mut w := open_headless_test_window(mut model)
	assert w.text_area_caret('notes') == 5
	w.text_area_set_selection('notes', 1, 1)
	w.insert_text_area_text('notes', 'e🙂')
	assert w.text('notes') == 'he🙂llo'
	assert w.text_area_caret('notes') == 4
	assert w.text_area_selection_length('notes') == 0
}

fn test_headless_scroll_reveals_rects_and_reports_geometry() {
	mut app := new_app()
	mut w := app.new_window(
		title:  'Scroll'
		width:  200
		height: 100
		build:  fn (mut _ Window) Element {
			content := view('content', rect(0, 0, 200, 400), BoxStyle{}, [
				button('far', 'Far', rect(0, 300, 100, 30), BoxStyle{}, TextStyle{}),
			])
			return scroll('list', rect(0, 0, 200, 100), 0, [content])
		}
	)!
	assert w.scroll_offset('list') == 0
	w.scroll_to_rect('list', 0, 300, 100, 30)
	assert w.scroll_offset('list') == 230
	w.scroll_to_offset('list', -5)
	assert w.scroll_offset('list') == 0
	mounted := w.mounted_geometry('far') or { panic(err) }
	visual := w.visual_geometry('far') or { panic(err) }
	assert mounted == visual
	if _ := w.mounted_geometry('nowhere') {
		assert false, 'unknown elements have no geometry'
	}
}

fn test_headless_dialogs_and_menus_show_nothing() {
	assert !message_box_supported()
	assert message_box(MessageBoxConfig{ buttons: .yes_no }) == message_box_default_result(.yes_no)
	assert !file_dialog_supported()
	assert file_dialog(FileDialogConfig{}) == []string{}
	assert !menu_bar_supported()
	mut app := new_app()
	mut w := app.new_window(
		title:  'Quit'
		width:  10
		height: 10
		build:  fn (mut _ Window) Element {
			return view('root', rect(0, 0, 10, 10), BoxStyle{}, [])
		}
	)!
	assert app.windows().len == 1
	w.quit()
	assert w.quit_requested
	assert app.windows().len == 0
}
