module ui2

fn test_preedit_preserves_committed_value_and_selection_until_commit() {
	mut editor := text_editor('A😀 old Z')
	editor.set_selection(3, 6)
	mut composition := TextComposition{}
	composition.update('field', editor, 'にほん', 2, 1, -1, 0)
	assert editor.text == 'A😀 old Z'
	assert editor.selection == TextSelection{ anchor: 3, caret: 6 }
	display := composition.display(editor)
	assert display.text == 'A😀 にほん Z'
	assert display.selection == TextSelection{ anchor: 5, caret: 6 }
	composition.update('field', editor, '日本', 2, 0, -1, 0)
	assert composition.display(editor).text == 'A😀 日本 Z'
	composition.commit(mut editor, '日本', -1, 0)
	assert editor.text == 'A😀 日本 Z'
	assert editor.selection == TextSelection{ anchor: 5, caret: 5 }
	assert composition.field_id == ''
}

fn test_utf16_replacement_after_supplementary_character() {
	assert utf16_offset_to_rune('A😀日本', 3) == 2
	assert utf16_offset_to_rune('A😀日本', 2) == 1
	assert rune_offset_to_utf16('A😀日本', 2) == 3
	mut editor := text_editor('A😀日本')
	mut composition := TextComposition{}
	composition.commit(mut editor, '語', 3, 2)
	assert editor.text == 'A😀語'
	assert editor.selection.caret == 3
}

fn test_canceled_or_retargeted_preedit_does_not_mutate_editor() {
	editor := text_editor('original')
	mut composition := TextComposition{}
	composition.update('first', editor, '仮', 1, 0, -1, 0)
	composition = TextComposition{}
	assert composition.display(editor).text == 'original'
	composition.update('second', editor, '候補', 2, 0, -1, 0)
	assert composition.start == rune_len(editor.text)
	assert editor.text == 'original'
}

fn test_explicit_utf16_range_replaces_previous_preedit_without_eating_suffix() {
	mut editor := text_editor('😀旧文 suffix')
	editor.set_selection(1, 3)
	mut composition := TextComposition{}
	composition.update('field', editor, 'にほん', 3, 0, -1, 0)
	composition.update('field', editor, '日本', 2, 0, 2, 3)
	assert composition.display(editor).text == '😀日本 suffix'
	composition.commit(mut editor, '日本語', 2, 2)
	assert editor.text == '😀日本語 suffix'
}

fn test_partial_preedit_replacement_keeps_unaffected_staged_fragments() {
	mut editor := text_editor('AB')
	editor.set_selection(1, 1)
	mut composition := TextComposition{}
	composition.update('field', editor, 'かな', 2, 0, -1, 0)
	composition.update('field', editor, 'に', 1, 0, 2, 1)
	assert composition.display(editor).text == 'AかにB'
	assert composition.mark_start == 1
	assert composition.mark_length == 1
	assert composition.display(editor).selection == TextSelection{ anchor: 3, caret: 3 }
	assert editor.text == 'AB'
	composition.update('field', editor, 'ほん', 2, 0, -1, 0)
	assert composition.display(editor).text == 'AかほんB'
	composition.commit(mut editor, '日本', -1, 0)
	assert editor.text == 'Aか日本B'
	assert editor.selection == TextSelection{ anchor: 4, caret: 4 }
	assert composition.field_id == ''
}

fn test_partial_commit_preserves_the_rest_of_preedit_and_its_suffix() {
	mut editor := text_editor('AB')
	editor.set_selection(1, 1)
	mut composition := TextComposition{}
	composition.update('field', editor, 'かな', 2, 0, -1, 0)
	composition.commit(mut editor, '😀', 2, 1)
	assert editor.text == 'Aか😀B'
	assert editor.selection == TextSelection{ anchor: 3, caret: 3 }
	assert composition.field_id == ''
}

fn test_partial_preedit_utf16_replacement_and_unmark_preserve_selection() {
	mut editor := text_editor('A😀Z')
	editor.set_selection(1, 2)
	mut composition := TextComposition{}
	composition.update('field', editor, 'か😀な', 1, 2, -1, 0)
	assert composition.display(editor).selection == TextSelection{ anchor: 2, caret: 3 }
	composition.update('field', editor, '語', 0, 1, 2, 2)
	assert composition.display(editor).text == 'Aか語なZ'
	assert composition.mark_start == 1
	assert composition.mark_length == 1
	assert composition.display(editor).selection == TextSelection{ anchor: 2, caret: 3 }
	assert editor.text == 'A😀Z'
	composition.finish(mut editor)
	assert editor.text == 'Aか語なZ'
	assert editor.selection == TextSelection{ anchor: 2, caret: 3 }
	assert composition.field_id == ''
}

fn test_preedit_replacement_expands_staged_union_outside_previous_mark() {
	mut editor := text_editor('abcdef')
	editor.set_selection(2, 4)
	mut composition := TextComposition{}
	composition.update('field', editor, '日本', 2, 0, -1, 0)
	composition.update('field', editor, '😀', 2, 0, 1, 2)
	assert composition.display(editor).text == 'a😀本ef'
	assert composition.start == 1
	assert composition.end == 4
	composition.update('field', editor, 'Z', 1, 0, 5, 1)
	assert composition.display(editor).text == 'a😀本eZ'
	assert composition.start == 1
	assert composition.end == 6
	assert composition.mark_start == 3
	assert editor.text == 'abcdef'
	composition.finish(mut editor)
	assert editor.text == 'a😀本eZ'
	assert editor.selection == TextSelection{ anchor: 5, caret: 5 }
}
