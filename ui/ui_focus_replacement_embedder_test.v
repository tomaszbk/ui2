// vtest vflags: -d ui2_embedder
// vfmt off
@[has_globals]
module ui2

$if macos && ui2_embedder ? && !ui2_headless ? {
	import gg
	import macos

	#include "@VMODROOT/tests/embedder/native_darwin.h"
	fn C.ui2_fixture_preedit(window voidptr, value &char) bool
	fn C.ui2_fixture_commit(window voidptr, value &char) bool

	__global replacement_kind = Kind.text_field
	__global replacement_text = 'declared ñ'
	__global replacement_events = []ElementEvent{}
	__global replacement_after_build = fn () {}
	__global replacement_task_pending bool

	fn replacement_event(event ElementEvent) { replacement_events << event }

	fn build_replacement_screen(mut w Window) Element {
		if replacement_task_pending {
			replacement_task_pending = false
			// A posted task runs after the host has completed this frame, including
			// state pruning and synchronization of its NSTextInputClient snapshot.
			assert w.dispatcher().post(replacement_after_build)
		}
		control := if replacement_kind == .slider {
			slider(SliderConfig{id: 'same', value: 25, step: 5, on_event: replacement_event, frame: rect(20, 20, 200, 36)})
		} else {
			Element{
				kind: replacement_kind
				id: 'same'
				text: replacement_text
				frame: rect(20, 20, 200, 60)
				on_event: replacement_event
				menu: [MenuEntry{id: 'declared ñ', title: 'declared ñ'}, MenuEntry{id: 'local café', title: 'local café'}]
			}
		}
		return screen(0xffffff, [
			Element{kind: .view, id: 'scope', focus_scope: true, frame: rect(0, 0, 300, 220), children: [
				control,
				Element{kind: .text_area, id: 'other', text: 'other declared', frame: rect(20, 100, 220, 80)},
			]},
			Element{kind: .button, id: 'outside', text: 'outside', frame: rect(310, 20, 80, 30)},
		])
	}

	fn replacement_next_frame(mut w Window, task fn ()) {
		replacement_after_build = task
		replacement_task_pending = true
		w.request_refresh()
	}

	fn assert_replacement_editor_removed(mut w Window) {
		assert 'same' !in w.text_values
		assert 'same' !in w.text_props
		assert 'same' !in w.text_editors
		assert 'same' !in w.text_kinds
		assert 'same' !in w.active_fields
		assert 'same' !in w.editable_fields
		assert 'same' !in w.text_area_selections
		assert 'same' !in w.text_area_layouts
		assert w.dropdown_id != 'same'
	}

	fn assert_replacement_other_editor(mut w Window) {
		assert w.text('other') == 'other café ñ'
		assert w.text_area_caret('other') == 6
		assert w.text_area_selection_length('other') == 3
		assert w.text_area_selection('other') == TextAreaSelectionRange{location: 3, length: 3}
	}

	fn replacement_send_key(mut w Window, code gg.KeyCode) {
		assert embedder_event(w, &C.ui2_embedder_event{kind: 7, key_code: int(code)})
		embedder_event(w, &C.ui2_embedder_event{kind: 8, key_code: int(code)})
	}
}

fn test_mounted_text_to_control_replacement_retains_focus_scope_and_keyboard_action() {
	$if macos && ui2_embedder ? && !ui2_headless ? {
		pool := macos.autorelease_pool_new()
		defer { macos.release(pool) }
		for source in [Kind.text_field, .text_area, .dropdown] {
			for destination in [Kind.button, .slider] {
				replacement_kind = source
				replacement_text = 'declared ñ'
				replacement_events = []ElementEvent{}
				mut app := new_app()
				mut w := app.new_window(title: 'Same-id focus replacement', width: 420, height: 260, build: build_replacement_screen) or { panic(err) }
				defer { w.quit() }
				replacement_after_build = fn [mut w, source, destination] () {
					mut scheduled := false
					defer { if !scheduled { w.quit() } }
					w.set_text('same', 'local café')
					w.set_text('other', 'other café ñ')
					w.text_area_set_selection('other', 3, 3)
					assert w.enter_focus_scope('scope')
					w.focus('same')
					assert w.focused_id() == 'same'
					if source == .text_area { w.text_area_set_selection('same', 1, 3) }
					if source == .dropdown { assert w.perform_semantic_action('same', .activate) }
					replacement_next_frame(mut w, fn [mut w, source, destination] () {
						mut scheduled := false
						defer { if !scheduled { w.quit() } }
						view := macos.msg_id(w.native_handle(), 'contentView')
						if source != .dropdown {
							assert C.ui2_fixture_preedit(w.native_handle(), 'ñ'.str)
							assert macos.msg_bool(view, 'hasMarkedText')
							assert w.composition.field_id == 'same'
						} else { assert w.dropdown_id == 'same' }
						replacement_kind = destination
						replacement_next_frame(mut w, fn [mut w, source, destination] () {
							mut scheduled := false
							defer { if !scheduled { w.quit() } }
							assert w.focused_id() == 'same', '${source} -> ${destination} must retain focus after pruning'
							assert w.navigation.current == 'same'
							assert w.active_focus_scope() == 'scope'
							assert_replacement_editor_removed(mut w)
							assert_replacement_other_editor(mut w)
							assert w.composition.field_id == ''
							view := macos.msg_id(w.native_handle(), 'contentView')
							assert !macos.msg_bool(view, 'hasMarkedText')
							replacement_events = []ElementEvent{}
							replacement_send_key(mut w, if destination == .button { gg.KeyCode.space } else { gg.KeyCode.right })
							assert replacement_events.len == 1
							assert replacement_events[0].id == 'same'
							assert replacement_events[0].kind == if destination == .button { ElementEventKind.click } else { ElementEventKind.change }
							if destination == .slider { assert w.slider_value('same') == 30 }
							assert w.focused_id() == 'same'
							assert_replacement_other_editor(mut w)
							// Reintroducing the editor initializes its declaration, never the
							// obsolete local draft/selection/composition of the old editor.
							replacement_kind = source
							replacement_text = 'fresh ñ'
							replacement_next_frame(mut w, fn [mut w, source] () {
								defer { w.quit() }
								assert w.focused_id() == 'same' && w.active_focus_scope() == 'scope'
								assert w.text('same') == 'fresh ñ'
								assert w.text_kinds['same'] == source
								assert_replacement_other_editor(mut w)
								assert w.composition.field_id == ''
								if source != .dropdown {
									assert C.ui2_fixture_commit(w.native_handle(), 'é'.str)
									assert w.text('same') == 'fresh ñé'
								}
							})
							scheduled = true
						})
						scheduled = true
					})
					scheduled = true
				}
				replacement_task_pending = true
				app.run()
			}
		}
	}
}

fn test_mounted_replacement_preserves_another_editors_native_composition_and_selection() {
	$if macos && ui2_embedder ? && !ui2_headless ? {
		pool := macos.autorelease_pool_new()
		defer { macos.release(pool) }
		for destination in [Kind.button, .slider] {
			replacement_kind = .text_area
			replacement_text = 'declared ñ'
			mut app := new_app()
			mut w := app.new_window(title: 'Unrelated editor replacement', width: 420, height: 260, build: build_replacement_screen) or { panic(err) }
			defer { w.quit() }
			replacement_after_build = fn [mut w, destination] () {
				mut scheduled := false
				defer { if !scheduled { w.quit() } }
				w.set_text('same', 'local café')
				w.text_area_set_selection('same', 1, 3)
				w.set_text('other', 'other café ñ')
				w.text_area_set_selection('other', 3, 3)
				assert w.enter_focus_scope('scope')
				w.focus('other')
				replacement_next_frame(mut w, fn [mut w, destination] () {
					mut scheduled := false
					defer { if !scheduled { w.quit() } }
					assert C.ui2_fixture_preedit(w.native_handle(), 'ñ'.str)
					view := macos.msg_id(w.native_handle(), 'contentView')
					assert macos.msg_bool(view, 'hasMarkedText')
					composition := w.composition
					selection := macos.msg_range(view, 'selectedRange')
					marked := macos.msg_range(view, 'markedRange')
					selection_location := selection.location
					selection_length := selection.length
					marked_location := marked.location
					marked_length := marked.length
					replacement_kind = destination
					replacement_next_frame(mut w, fn [mut w, composition, selection_location, selection_length, marked_location, marked_length] () {
						defer { w.quit() }
						assert w.focused_id() == 'other' && w.active_focus_scope() == 'scope'
						assert_replacement_editor_removed(mut w)
						assert_replacement_other_editor(mut w)
						assert w.composition == composition
						view := macos.msg_id(w.native_handle(), 'contentView')
						assert macos.msg_bool(view, 'hasMarkedText')
						selection := macos.msg_range(view, 'selectedRange')
						marked := macos.msg_range(view, 'markedRange')
						assert selection.location == selection_location && selection.length == selection_length
						assert marked.location == marked_location && marked.length == marked_length
					})
					scheduled = true
				})
				scheduled = true
			}
			replacement_task_pending = true
			app.run()
		}
	}
}
