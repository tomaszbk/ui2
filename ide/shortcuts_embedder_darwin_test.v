// vtest vflags: -d ui2_custom_rendering -d ui2_embedder
// vfmt off
@[has_globals]
module main

import ui2

$if macos && ui2_custom_rendering ? && ui2_embedder ? && !ui2_headless ? {
	import macos

	#include "@VMODROOT/ide/shortcuts_embedder_darwin_test.h"
	#include "@VMODROOT/tests/embedder/native_darwin.h"
	fn C.ui2_ide_shortcut_key_event(window voidptr, event_type u64, code u16, characters voidptr, modifiers u64, timestamp f64) voidptr
	fn C.ui2_ide_shortcut_character(window voidptr, character u32)
	fn C.ui2_fixture_preedit(window voidptr, value &char) bool

	__global ide_shortcut_keys = []string{}
	__global ide_shortcut_timestamp f64
	__global ide_shortcut_after_build = fn () {}
	__global ide_shortcut_task_pending bool

	fn ide_shortcut_observer(key string) {
		ide_shortcut_keys << key
		handle_ide_key(key)
	}

	fn build_ide_shortcut_screen() ui2.Element {
		if ide_shortcut_task_pending {
			ide_shortcut_task_pending = false
			// Posted tasks drain on the next host callback, after this frame
			// mounts the actual IDE controls and synchronizes native text input.
			assert ui2.ui_dispatcher().post(ide_shortcut_after_build)
		}
		return build_ide_screen()
	}

	fn ide_shortcut_fixture(source bool) ui2.CustomWindow {
		mut state := unsafe { ide_state }
		unsafe { *state = new_ide_app('.') }
		state.snap_to_grid = false
		state.add_component('button', 32, 40)
		state.selected_id = 0
		if source { state.active_tab = 'source' }
		window := ui2.open_window('IDE shortcut fixture', ide_width, ide_height, build_ide_shortcut_screen) or { panic(err) }
		assert window.update(fn () {
			ui2.on_key(ide_shortcut_observer)
			ui2.set_menu_bar([]ui2.Menu{})
		})
		return window
	}

	fn send_ide_shortcut(window ui2.CustomWindow, code u16, characters string, modifiers u64) {
		native := window.native_handle()
		assert native != unsafe { nil }
		view := macos.msg_id(native, 'contentView')
		// Real NSEvents enter the host's keyDown/keyUp route. These fixtures do
		// not claim physical OS input or an actual configured input method.
		for event_type in [u64(10), u64(11)] {
			ide_shortcut_timestamp += 1
			event := C.ui2_ide_shortcut_key_event(native, event_type, code, macos.nsstring(characters), modifiers, ide_shortcut_timestamp)
			assert event != unsafe { nil }
			macos.msg_void1(view, if event_type == 10 { 'keyDown:' } else { 'keyUp:' }, event)
		}
	}

	fn select_ide_shortcut_navigator() {
		node := ui2.semantic_node('tree_1') or { panic('actual IDE navigator was not mounted') }
		assert node.role == 'button'
		ui2.focus('tree_1')
		assert ui2.perform_semantic_action('tree_1', .activate)
		assert ui2.focused_id() == 'tree_1'
		assert ide_state.selected_id == 1
	}
}

fn test_mounted_ide_navigator_focus_preserves_backspace_and_delete_commands() {
	$if macos && ui2_custom_rendering ? && ui2_embedder ? && !ui2_headless ? {
		pool := macos.autorelease_pool_new()
		defer { macos.release(pool) }
		previous := *ide_state
		defer { unsafe { *ide_state = previous } }
		for code in [u16(0x33), u16(0x75)] {
			window := ide_shortcut_fixture(false)
			defer { window.close() }
			ide_shortcut_after_build = fn [window, code] () {
				defer { window.close() }
				select_ide_shortcut_navigator()
				ide_shortcut_keys = []string{}
				send_ide_shortcut(window, code, '\u007f', 0)
				assert ide_state.components.len == 0, 'focused navigator must delete the selected component'
				assert ide_shortcut_keys == [if code == 0x33 { 'backspace' } else { 'forward_delete' }]
			}
			ide_shortcut_task_pending = true
			ui2.run_windows()
		}
	}
}

fn test_mounted_ide_control_focus_consumes_nudge_undo_and_redo_once() {
	$if macos && ui2_custom_rendering ? && ui2_embedder ? && !ui2_headless ? {
		pool := macos.autorelease_pool_new()
		defer { macos.release(pool) }
		previous := *ide_state
		defer { unsafe { *ide_state = previous } }
		window := ide_shortcut_fixture(false)
		defer { window.close() }
		ide_shortcut_after_build = fn [window] () {
			defer { window.close() }
			select_ide_shortcut_navigator()
			ide_shortcut_keys = []string{}
			undo_count := ide_state.undo_stack.len
			send_ide_shortcut(window, 0x7c, '\uf703', 0)
			assert ide_state.components[0].x == 33
			assert ide_state.components[0].y == 40
			assert ide_state.undo_stack.len == undo_count + 1
			assert ide_shortcut_keys == ['right']
			assert ui2.focused_id() == 'tree_1'
			// Another legitimate button focus leaves commands with the designer.
			ui2.focus('tab_designer')
			send_ide_shortcut(window, 0x7d, '\uf701', 0x20000)
			assert ide_state.components[0].x == 33
			assert ide_state.components[0].y == 48
			assert ide_state.undo_stack.len == undo_count + 2
			assert ide_shortcut_keys == ['right', 'shift+down']
			assert ui2.focused_id() == 'tab_designer'
			send_ide_shortcut(window, 0x06, 'z', 0x100000)
			assert ide_state.components[0].y == 40
			assert ide_state.undo_stack.len == undo_count + 1
			assert ide_state.redo_stack.len == 1
			send_ide_shortcut(window, 0x06, 'z', 0x120000)
			assert ide_state.components[0].y == 48
			assert ide_state.undo_stack.len == undo_count + 2
			assert ide_state.redo_stack.len == 0
		}
		ide_shortcut_task_pending = true
		ui2.run_windows()
	}
}

fn test_mounted_ide_editor_focus_preserves_draft_selection_and_composition() {
	$if macos && ui2_custom_rendering ? && ui2_embedder ? && !ui2_headless ? {
		pool := macos.autorelease_pool_new()
		defer { macos.release(pool) }
		previous := *ide_state
		defer { unsafe { *ide_state = previous } }
		for editor_id in ['project_path', 'source_editor'] {
			window := ide_shortcut_fixture(editor_id == 'source_editor')
			defer { window.close() }
			ide_shortcut_after_build = fn [window, editor_id] () {
				node := ui2.semantic_node(editor_id) or { panic('actual IDE editor was not mounted') }
				assert node.role == 'textbox'
				ui2.set_text(editor_id, 'café ñ draft')
				ui2.focus(editor_id)
				ui2.set_menu_bar([]ui2.Menu{})
				ide_shortcut_after_build = fn [window, editor_id] () {
					defer { window.close() }
					view := macos.msg_id(window.native_handle(), 'contentView')
					C.ui2_ide_shortcut_character(window.native_handle(), `é`)
					draft := 'café ñ drafté'
					assert ui2.text(editor_id) == draft
					// Ordinary CHAR fallback must also synchronize the actual host's
					// NSTextInputClient snapshot before returning to Cocoa.
					assert macos.utf8_string(macos.msg_id(view, 'textSnapshot')) == draft
					// Shift+Left must edit selection rather than nudge the component.
					send_ide_shortcut(window, 0x7b, '\uf702', 0x20000)
					selection := macos.msg_range(view, 'selectedRange')
					assert selection.length == 1
					before := ide_state.snapshot()
					assert ui2.text(editor_id) == draft
					for key in ['backspace', 'forward_delete', 'left', 'right', 'up', 'down',
						'shift+left', 'shift+right', 'shift+up', 'shift+down', 'cmd+z', 'cmd+shift+z'] {
						handle_ide_key(key)
					}
					assert ui2.text(editor_id) == draft
					assert ui2.focused_id() == editor_id
					assert ide_state.snapshot() == before
					assert macos.msg_range(view, 'selectedRange') == selection
					assert C.ui2_fixture_preedit(window.native_handle(), 'ñ'.str)
					assert macos.msg_bool(view, 'hasMarkedText')
					marked := macos.msg_range(view, 'markedRange')
					composing_selection := macos.msg_range(view, 'selectedRange')
					for key in ['backspace', 'forward_delete', 'left', 'shift+right', 'cmd+z', 'cmd+shift+z'] {
						handle_ide_key(key)
					}
					assert ui2.text(editor_id) == draft
					assert ide_state.snapshot() == before
					assert macos.msg_bool(view, 'hasMarkedText')
					assert macos.msg_range(view, 'markedRange') == marked
					assert macos.msg_range(view, 'selectedRange') == composing_selection
				}
				ide_shortcut_task_pending = true
				ui2.refresh()
			}
			ide_shortcut_task_pending = true
			ui2.run_windows()
		}
	}
}
