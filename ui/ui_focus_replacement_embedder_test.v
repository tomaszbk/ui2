// vtest vflags: -d ui2_custom_rendering -d ui2_embedder
// vfmt off
@[has_globals]
module ui2

$if macos && ui2_custom_rendering ? && ui2_embedder ? && !ui2_headless ? {
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

	fn build_replacement_screen() Element {
		if replacement_task_pending {
			replacement_task_pending = false
			// A posted task runs after the host has completed this frame, including
			// state pruning and synchronization of its NSTextInputClient snapshot.
			assert ui_dispatcher().post(replacement_after_build)
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

	fn replacement_next_frame(task fn ()) {
		replacement_after_build = task
		replacement_task_pending = true
		refresh()
	}

	fn assert_replacement_editor_removed() {
		assert 'same' !in g_text_values
		assert 'same' !in g_text_props
		assert 'same' !in g_text_editors
		assert 'same' !in g_text_kinds
		assert 'same' !in g_active_fields
		assert 'same' !in g_gg_app.editable_fields
		assert 'same' !in portable_text_area_selections
		assert 'same' !in g_text_area_layouts
		assert g_open_dropdown != 'same'
	}

	fn assert_replacement_other_editor() {
		assert text('other') == 'other café ñ'
		assert text_area_caret('other') == 6
		assert text_area_selection_length('other') == 3
		assert portable_text_area_selection('other') == TextAreaSelectionRange{location: 3, length: 3}
	}

	fn replacement_send_key(code gg.KeyCode) {
		assert embedder_event(g_gg_app, &C.ui2_embedder_event{kind: 7, key_code: int(code)})
		embedder_event(g_gg_app, &C.ui2_embedder_event{kind: 8, key_code: int(code)})
	}
}

fn test_mounted_text_to_control_replacement_retains_focus_scope_and_keyboard_action() {
	$if macos && ui2_custom_rendering ? && ui2_embedder ? && !ui2_headless ? {
		pool := macos.autorelease_pool_new()
		defer { macos.release(pool) }
		for source in [Kind.text_field, .text_area, .dropdown] {
			for destination in [Kind.button, .slider] {
				replacement_kind = source
				replacement_text = 'declared ñ'
				replacement_events = []ElementEvent{}
				window := open_window('Same-id focus replacement', 420, 260, build_replacement_screen) or { panic(err) }
				defer { window.close() }
				replacement_after_build = fn [window, source, destination] () {
					mut scheduled := false
					defer { if !scheduled { window.close() } }
					set_text('same', 'local café')
					set_text('other', 'other café ñ')
					text_area_set_selection('other', 3, 3)
					assert enter_focus_scope('scope')
					focus('same')
					assert focused_id() == 'same'
					if source == .text_area { text_area_set_selection('same', 1, 3) }
					if source == .dropdown { assert perform_semantic_action('same', .activate) }
					replacement_next_frame(fn [window, source, destination] () {
						mut scheduled := false
						defer { if !scheduled { window.close() } }
						view := macos.msg_id(window.native_handle(), 'contentView')
						if source != .dropdown {
							assert C.ui2_fixture_preedit(window.native_handle(), 'ñ'.str)
							assert macos.msg_bool(view, 'hasMarkedText')
							assert g_gg_app.composition.field_id == 'same'
						} else { assert g_open_dropdown == 'same' }
						replacement_kind = destination
						replacement_next_frame(fn [window, source, destination] () {
							mut scheduled := false
							defer { if !scheduled { window.close() } }
							assert focused_id() == 'same', '${source} -> ${destination} must retain focus after pruning'
							assert g_focus_navigation.current == 'same'
							assert active_focus_scope() == 'scope'
							assert_replacement_editor_removed()
							assert_replacement_other_editor()
							assert g_gg_app.composition.field_id == ''
							view := macos.msg_id(window.native_handle(), 'contentView')
							assert !macos.msg_bool(view, 'hasMarkedText')
							replacement_events = []ElementEvent{}
							replacement_send_key(if destination == .button { gg.KeyCode.space } else { gg.KeyCode.right })
							assert replacement_events.len == 1
							assert replacement_events[0].id == 'same'
							assert replacement_events[0].kind == if destination == .button { ElementEventKind.tap } else { ElementEventKind.change }
							if destination == .slider { assert slider_value('same') == 30 }
							assert focused_id() == 'same'
							assert_replacement_other_editor()
							// Reintroducing the editor initializes its declaration, never the
							// obsolete local draft/selection/composition of the old editor.
							replacement_kind = source
							replacement_text = 'fresh ñ'
							replacement_next_frame(fn [window, source] () {
								defer { window.close() }
								assert focused_id() == 'same' && active_focus_scope() == 'scope'
								assert text('same') == 'fresh ñ'
								assert g_text_kinds['same'] == source
								assert_replacement_other_editor()
								assert g_gg_app.composition.field_id == ''
								if source != .dropdown {
									assert C.ui2_fixture_commit(window.native_handle(), 'é'.str)
									assert text('same') == 'fresh ñé'
								}
							})
							scheduled = true
						})
						scheduled = true
					})
					scheduled = true
				}
				replacement_task_pending = true
				run_windows()
			}
		}
	}
}

fn test_mounted_replacement_preserves_another_editors_native_composition_and_selection() {
	$if macos && ui2_custom_rendering ? && ui2_embedder ? && !ui2_headless ? {
		pool := macos.autorelease_pool_new()
		defer { macos.release(pool) }
		for destination in [Kind.button, .slider] {
			replacement_kind = .text_area
			replacement_text = 'declared ñ'
			window := open_window('Unrelated editor replacement', 420, 260, build_replacement_screen) or { panic(err) }
			defer { window.close() }
			replacement_after_build = fn [window, destination] () {
				mut scheduled := false
				defer { if !scheduled { window.close() } }
				set_text('same', 'local café')
				text_area_set_selection('same', 1, 3)
				set_text('other', 'other café ñ')
				text_area_set_selection('other', 3, 3)
				assert enter_focus_scope('scope')
				focus('other')
				replacement_next_frame(fn [window, destination] () {
					mut scheduled := false
					defer { if !scheduled { window.close() } }
					assert C.ui2_fixture_preedit(window.native_handle(), 'ñ'.str)
					view := macos.msg_id(window.native_handle(), 'contentView')
					assert macos.msg_bool(view, 'hasMarkedText')
					composition := g_gg_app.composition
					selection := macos.msg_range(view, 'selectedRange')
					marked := macos.msg_range(view, 'markedRange')
					selection_location := selection.location
					selection_length := selection.length
					marked_location := marked.location
					marked_length := marked.length
					replacement_kind = destination
					replacement_next_frame(fn [window, composition, selection_location, selection_length, marked_location, marked_length] () {
						defer { window.close() }
						assert focused_id() == 'other' && active_focus_scope() == 'scope'
						assert_replacement_editor_removed()
						assert_replacement_other_editor()
						assert g_gg_app.composition == composition
						view := macos.msg_id(window.native_handle(), 'contentView')
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
			run_windows()
		}
	}
}
