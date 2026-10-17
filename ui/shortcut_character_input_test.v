@[has_globals]
module ui2

import gg

$if (android || ios || linux || macos || windows) && !ui2_headless ? {
	fn test_shortcut_character_does_not_replace_selection_and_altgr_keeps_unicode() {
		mut w := &Window{}
		root := screen(0xffffff, [Element{ kind: .text_field, id: 'draft', text: 'España café ñ' }])
		w.update_custom_focus_tree(root)
		w.sync_mounted_focus_controls(root, 'root')
		w.focus('draft')
		primary := $if macos { u32(gg.Modifier.super) } $else { u32(gg.Modifier.ctrl) }
		on_event(&gg.Event{ typ: .key_down, key_code: .a, modifiers: primary }, mut w)
		on_event(&gg.Event{ typ: .char, char_code: `a`, modifiers: primary }, mut w)
		on_event(&gg.Event{ typ: .key_up, key_code: .a, modifiers: primary }, mut w)
		assert w.text('draft') == 'España café ñ'
		assert w.text_editors['draft'].selection == TextSelection{ anchor: 0, caret: 13 }
		on_event(&gg.Event{ typ: .char, char_code: `ñ` }, mut w)
		assert w.text('draft') == 'ñ'
		on_event(&gg.Event{ typ: .char, char_code: `é`, modifiers: u32(gg.Modifier.ctrl) | u32(gg.Modifier.alt) }, mut w)
		assert w.text('draft') == 'ñé'
		on_event(&gg.Event{ typ: .char, char_code: `à`, modifiers: u32(gg.Modifier.alt) }, mut w)
		assert w.text('draft') == 'ñéà'
	}
}
