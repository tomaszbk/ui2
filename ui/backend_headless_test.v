// vtest vflags: -d ui2_headless
module ui2

@[heap]
struct HeadlessTestModel {
mut:
	checked bool
	events  []ElementEvent
	keys    []string
}

fn open_headless_test_window(mut model HeadlessTestModel) {
	headless_reset()
	run_window('Headless', 320, 240, fn [mut model] () Element {
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
	})
}

fn test_headless_backend_is_selected_by_its_flag() {
	assert backend_name == 'headless'
	assert backend_supports_overlays
	assert backend_supports_motion
	assert backend_supports_visual_transforms
	assert backend_supports_vector_canvas
	assert backend_supports_drag_drop
	assert !backend_needs_host
	assert control_support(.text_area) == .supported
}

fn test_headless_window_builds_once_and_keeps_live_control_state() {
	mut model := &HeadlessTestModel{}
	open_headless_test_window(mut model)
	state := headless_state()
	assert state.title == 'Headless'
	assert bounds() == rect(0, 0, 320, 240)
	assert state.builds == 1
	assert state.layout_error == ''
	assert text('name') == 'Ada'
	set_text('name', 'Grace')
	request_refresh()
	assert headless_frame()
	assert state.builds == 2
	// An unchanged declaration leaves the user's edit in place.
	assert text('name') == 'Grace'
	assert !headless_frame()
	set_text('missing', 'x')
	assert text('missing') == ''
}

fn test_headless_keys_reach_handlers_focus_and_activation() {
	mut model := &HeadlessTestModel{}
	open_headless_test_window(mut model)
	on_key(fn [mut model] (name string) {
		model.keys << name
	})
	assert !headless_key(KeyEvent{ code: .a, cmd: true })
	assert model.keys == ['cmd+a']
	focus('name')
	assert focused_id() == 'name'
	assert headless_key(KeyEvent{ code: .tab })
	assert focused_id() == 'agree'
	assert headless_key(KeyEvent{ code: .space })
	assert model.events.len == 1
	assert model.events[0].id == 'agree'
	assert model.events[0].checked
	assert control_checked('agree')
	assert headless_state().refresh_pending
	assert headless_frame()
	assert control_checked('agree')
	nodes := semantic_tree()
	assert nodes.any(it.id == 'agree' && it.state.checked)
}

fn test_headless_text_area_edits_count_utf16_units() {
	mut model := &HeadlessTestModel{}
	open_headless_test_window(mut model)
	assert text_area_caret('notes') == 5
	text_area_set_selection('notes', 1, 1)
	insert_text_area_text('notes', 'e🙂')
	assert text('notes') == 'he🙂llo'
	assert text_area_caret('notes') == 4
	assert text_area_selection_length('notes') == 0
}

fn test_headless_scroll_reveals_rects_and_reports_geometry() {
	headless_reset()
	run_window('Scroll', 200, 100, fn () Element {
		content := view('content', rect(0, 0, 200, 400), BoxStyle{}, [
			button('far', 'Far', rect(0, 300, 100, 30), BoxStyle{}, TextStyle{}),
		])
		return scroll('list', rect(0, 0, 200, 100), 0, [content])
	})
	assert scroll_offset('list') == 0
	scroll_to_rect('list', 0, 300, 100, 30)
	assert scroll_offset('list') == 230
	scroll_to_offset('list', -5)
	assert scroll_offset('list') == 0
	mounted := mounted_geometry('far') or { panic(err) }
	visual := visual_geometry('far') or { panic(err) }
	assert mounted == visual
	if _ := mounted_geometry('nowhere') {
		assert false, 'unknown elements have no geometry'
	}
}

fn test_headless_dialogs_and_menus_show_nothing() {
	headless_reset()
	assert !message_box_supported()
	assert message_box(MessageBoxConfig{ buttons: .yes_no }) == message_box_default_result(.yes_no)
	assert !file_dialog_supported()
	assert file_dialog(FileDialogConfig{}) == []string{}
	assert !menu_bar_supported()
	run_window('Quit', 10, 10, fn () Element {
		return view('root', rect(0, 0, 10, 10), BoxStyle{}, [])
	})
	quit()
	assert headless_state().quit_requested
}
