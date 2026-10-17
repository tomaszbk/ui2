@[has_globals]
module ui2

import gg

$if (android || ios || linux || macos || windows) && !ui2_headless ? {
	fn test_shortcut_character_does_not_replace_selection_and_altgr_keeps_unicode() {
		previous_app := g_gg_app
		previous_build := g_build_screen
		previous := activate_custom_window_state(new_custom_window_state())
		defer { activate_custom_window_state(previous); g_gg_app = previous_app; g_build_screen = previous_build }
		g_build_screen = unsafe { nil }
		mut app := &GgApp{}
		g_gg_app = app
		root := screen(0xffffff, [Element{kind: .text_field, id: 'draft', text: 'España café ñ'}])
		update_custom_focus_tree(root)
		sync_mounted_focus_controls(root, 'root')
		focus('draft')
		primary := $if macos { u32(gg.Modifier.super) } $else { u32(gg.Modifier.ctrl) }
		on_event(&gg.Event{typ: .key_down, key_code: .a, modifiers: primary}, app)
		on_event(&gg.Event{typ: .char, char_code: `a`, modifiers: primary}, app)
		on_event(&gg.Event{typ: .key_up, key_code: .a, modifiers: primary}, app)
		assert text('draft') == 'España café ñ'
		assert g_text_editors['draft'].selection == TextSelection{anchor: 0, caret: 13}
		on_event(&gg.Event{typ: .char, char_code: `ñ`}, app)
		assert text('draft') == 'ñ'
		on_event(&gg.Event{typ: .char, char_code: `é`, modifiers: u32(gg.Modifier.ctrl) | u32(gg.Modifier.alt)}, app)
		assert text('draft') == 'ñé'
		on_event(&gg.Event{typ: .char, char_code: `à`, modifiers: u32(gg.Modifier.alt)}, app)
		assert text('draft') == 'ñéà'
	}
}
