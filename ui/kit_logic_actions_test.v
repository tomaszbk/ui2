// SPDX-License-Identifier: Apache-2.0
// Includes rating click-rule and number-input stepping cases adapted from GPUI
// Kit (Longbridge, copyright 2024 - 2026); the other tests are new. See
// third_party/gpui-kit.
module ui2

import math

// ── Toggle group ────────────────────────────────────────────────────

const kit_toggle_values = ['bold', 'italic', 'code', 'strike']
const kit_toggle_enabled = [true, true, false, true]

fn kit_toggle_after(selected []string, value string, multiple bool, allow_empty bool) []string {
	return toggle_group_selection_after(kit_toggle_values, kit_toggle_enabled, selected, value,
		multiple, allow_empty) or { ['none'] }
}

fn test_toggle_group_multiple_selection() {
	selected := ['italic', 'stale']
	// Selections come back in item order and drop values that name no item.
	assert kit_toggle_after(selected, 'bold', true, true) == ['bold', 'italic']
	assert kit_toggle_after(selected, 'italic', true, true) == []string{}
	assert kit_toggle_after(selected, 'italic', true, false) == ['none']
	for value in ['code', 'stale', 'Bold', ''] {
		assert kit_toggle_after(selected, value, true, true) == ['none']
	}
}

fn test_toggle_group_single_selection() {
	selected := ['italic', 'stale']
	assert kit_toggle_after(selected, 'bold', false, true) == ['bold']
	assert kit_toggle_after(selected, 'italic', false, true) == []string{}
	assert kit_toggle_after(selected, 'italic', false, false) == ['none']
	assert kit_toggle_after(selected, 'strike', false, false) == ['strike']
}

// ── Radio group ─────────────────────────────────────────────────────

const kit_radio_values = ['card', 'PayPal', 'bank', 'cash']
const kit_radio_enabled = [true, true, false, true]

fn kit_radio_key(selected string, key string) string {
	return radio_value_after_key(kit_radio_values, kit_radio_enabled, selected, key) or { 'none' }
}

fn test_radio_keys_skip_disabled_options_and_wrap() {
	assert kit_radio_key('card', 'down') == 'PayPal'
	assert kit_radio_key('card', 'up') == 'cash'
	assert kit_radio_key('card', 'end') == 'cash'
	assert kit_radio_key('card', 'home') == 'none'
	assert kit_radio_key('card', 'enter') == 'none'
	assert kit_radio_key('card', 'shift+down') == 'none'
	assert kit_radio_key('PayPal', 'right') == 'cash'
	assert kit_radio_key('cash', 'down') == 'card'
	assert kit_radio_key('', 'down') == 'card'
	assert kit_radio_key('', 'left') == 'cash'
	assert (radio_value_after_key(kit_radio_values, [false, false, false, false], 'card',
		'down') or { 'none' }) == 'none'
}

// ── Rating ──────────────────────────────────────────────────────────

fn test_rating_click_rule_matches_upstream() {
	assert rating_value_after_click(0, 1) == 1
	assert rating_value_after_click(3, 5) == 5
	assert rating_value_after_click(3, 3) == 2
	assert rating_value_after_click(3, 1) == 0
	assert rating_value_after_click(1, 1) == 0
	assert rating_value_after_click(5, 2) == 1
}

fn test_rating_keyboard_steps() {
	assert (rating_value_after_key(3, 5, 'right') or { -1 }) == 4
	assert (rating_value_after_key(3, 5, 'down') or { -1 }) == 2
	assert (rating_value_after_key(3, 5, 'home') or { -1 }) == 0
	assert (rating_value_after_key(3, 5, 'end') or { -1 }) == 5
	assert (rating_value_after_key(3, 5, '1') or { -1 }) == 1
	assert (rating_value_after_key(3, 5, '3') or { -1 }) == -1
	assert (rating_value_after_key(3, 5, '9') or { -1 }) == -1
	assert (rating_value_after_key(3, 5, 'space') or { -1 }) == -1
	assert (rating_value_after_key(5, 5, 'up') or { -1 }) == -1
	// Out-of-range values are clamped before the key applies.
	assert (rating_value_after_key(40, 5, 'left') or { -1 }) == 4
	assert (rating_value_after_key(3, 0, 'right') or { -1 }) == -1
	assert (rating_value_after_key(3, rating_max_stars + 1, 'right') or { -1 }) == -1
}

// ── Stepper ─────────────────────────────────────────────────────────

const kit_stepper_enabled = [true, true, false, true]

fn test_stepper_states() {
	assert stepper_step_state(0, 1) == .completed
	assert stepper_step_state(1, 1) == .current
	assert stepper_step_state(2, 1) == .upcoming
}

fn test_stepper_navigation() {
	// Next and previous skip the inactive step.
	assert (stepper_next_step(kit_stepper_enabled, 1) or { -1 }) == 3
	assert (stepper_previous_step(kit_stepper_enabled, 1) or { -1 }) == 0
	assert (stepper_previous_step(kit_stepper_enabled, 0) or { -1 }) == -1
	assert (stepper_next_step(kit_stepper_enabled, 3) or { -1 }) == -1
	assert (stepper_previous_step(kit_stepper_enabled, 4) or { -1 }) == 3
	assert (stepper_step_after_key(kit_stepper_enabled, 1, false, 'right') or { -1 }) == 3
	assert (stepper_step_after_key(kit_stepper_enabled, 1, false, 'left') or { -1 }) == 0
	assert (stepper_step_after_key(kit_stepper_enabled, 1, false, 'down') or { -1 }) == -1
	assert (stepper_step_after_key(kit_stepper_enabled, 1, false, 'end') or { -1 }) == 3
	assert (stepper_step_after_key(kit_stepper_enabled, 0, false, 'home') or { -1 }) == -1
	assert (stepper_step_after_key(kit_stepper_enabled, 1, true, 'down') or { -1 }) == 3
	assert (stepper_step_after_key(kit_stepper_enabled, 1, true, 'up') or { -1 }) == 0
	assert (stepper_step_after_key([]bool{}, 0, false, 'right') or { -1 }) == -1
}

// ── Number input ────────────────────────────────────────────────────

fn kit_step(text string, min ?f64, max ?f64, step f64, precision int, direction NumberInputStep) string {
	return number_input_step(text, min, max, step, precision, direction) or { 'none' }
}

fn test_number_input_parse_accepts_signed_decimals_only() {
	assert number_input_parse('42') or { 0 } == 42
	assert number_input_parse(' -1.5 ') or { 0 } == -1.5
	assert number_input_parse('.5') or { 0 } == 0.5
	assert number_input_parse('2.') or { 0 } == 2
	assert number_input_parse('+7') or { 0 } == 7
	for bad in ['', '-', '.', '+.', '1e3', '1,000', '1.2.3', '--1', 'abc', '١٢'] {
		if value := number_input_parse(bad) {
			assert false, '`${bad}` parsed as ${value}'
		}
	}
}

fn test_number_input_format_avoids_float_noise() {
	assert number_input_format(0.1 + 0.2, 1) == '0.3'
	assert number_input_format(-0.04, 1) == '0.0'
	assert number_input_format(-2.5, 0) == '-3'
	assert number_input_format(0.05, 2) == '0.05'
	assert number_input_format(12, 3) == '12.000'
	assert number_input_format(math.nan(), 2) == ''
	assert number_input_format(3, -4) == '3'
	assert number_input_format(1.0, 99).len == '1.'.len + number_input_max_precision
	assert number_input_plain(0.25) == '0.25'
	assert number_input_plain(10) == '10'
}

fn test_number_input_sanitize_keeps_a_number() {
	assert number_input_sanitize('12a3', none, -1) == '123'
	assert number_input_sanitize('-1.2.3', none, -1) == '-1.23'
	assert number_input_sanitize('1-2', none, -1) == '12'
	assert number_input_sanitize('１２３．５', none, -1) == '123.5'
	assert number_input_sanitize('－４', none, -1) == '-4'
	assert number_input_sanitize('+5', none, -1) == '+5'
	assert number_input_sanitize('1,000 ', none, -1) == '1000'
	assert number_input_sanitize('-5', 0, -1) == '5'
	assert number_input_sanitize('3.75', none, 0) == '375'
}

fn test_number_input_step_keeps_decimals_and_direction() {
	assert kit_step('1', none, none, 1, -1, .increment) == '2'
	assert kit_step('-2', none, none, 1, -1, .increment) == '-1'
	assert kit_step('', none, none, 1, -1, .increment) == '1'
	assert kit_step('', none, none, 1, -1, .decrement) == '-1'
	assert kit_step('-', none, none, 1, -1, .increment) == '1'
	assert kit_step('1.25', none, none, 1, -1, .increment) == '2.25'
	assert kit_step('0.2', none, none, 0.1, -1, .increment) == '0.3'
	assert kit_step('0.3', none, none, 0.1, -1, .decrement) == '0.2'
	assert kit_step('4', none, none, 0.25, 2, .increment) == '4.25'
}

fn test_number_input_step_respects_bounds() {
	assert kit_step('99.5', 10, 100, 1, -1, .increment) == '100.0'
	assert kit_step('100', 10, 100, 1, -1, .increment) == 'none'
	assert kit_step('10', 10, 100, 1, -1, .decrement) == 'none'
	// A value outside the range only steps back toward it.
	assert kit_step('5', 10, 100, 1, -1, .decrement) == 'none'
	assert kit_step('5', 10, 100, 1, -1, .increment) == '10'
	assert kit_step('1000', 10, 100, 1, -1, .increment) == 'none'
	assert kit_step('1000', 10, 100, 1, -1, .decrement) == '100'
	// An empty field steps into the range from zero.
	assert kit_step('', 10, 100, 1, -1, .decrement) == '10'
	assert kit_step('1', 0.25, none, 1, -1, .decrement) == '0.25'
	// Fixed precision never rounds a bound outside the range.
	assert kit_step('0', none, 0.25, 1, 1, .increment) == '0.2'
	// An invalid range never steps.
	assert kit_step('1', none, none, 0, -1, .increment) == 'none'
	assert kit_step('1', 5, 1, 1, -1, .increment) == 'none'
}

fn test_number_input_validate() {
	number_input_validate(none, none, 1, -1) or { panic(err) }
	number_input_validate(1, 5, 0.5, 2) or { panic(err) }
	for step in [0.0, -1, math.inf(1)] {
		if _ := number_input_validate(none, none, step, -1) {
			assert false, 'step ${step} accepted'
		}
	}
	if _ := number_input_validate(5, 1, 1, -1) {
		assert false, 'min above max accepted'
	}
	if _ := number_input_validate(math.nan(), none, 1, -1) {
		assert false, 'NaN min accepted'
	}
	if _ := number_input_validate(none, none, 1, 13) {
		assert false, 'precision 13 accepted'
	}
}

fn test_number_input_in_range() {
	assert number_input_in_range('1', 1, 99)
	assert number_input_in_range('99.0', 1, 99)
	assert !number_input_in_range('150', 1, 99)
	assert !number_input_in_range('0.5', 1, 99)
	assert !number_input_in_range('', 1, 99)
	assert !number_input_in_range('-', 1, 99)
	assert number_input_in_range('-1', none, none)
}

fn test_number_input_commit_parses_clamps_and_formats() {
	commit := fn (source string, precision int) string {
		return number_input_commit(source, 1, 99, 1, precision) or { 'none' }
	}
	assert commit(' ', -1) == ''
	assert commit('007', -1) == '7'
	assert commit('250', -1) == '99'
	assert commit('0.5', -1) == '1.0'
	assert commit('2.', -1) == '2'
	assert commit('-', -1) == 'none'
	assert commit('3.456', 2) == '3.46'
	assert commit('5', 2) == '5.00'
}

fn test_number_input_keys() {
	assert number_input_key_step('up') or { NumberInputStep.decrement } == .increment
	assert number_input_key_step('down') or { NumberInputStep.increment } == .decrement
	assert number_input_key_step('shift+up') == none
	assert number_input_key_step('left') == none
	assert number_input_value_from_key('5', none, 5, 1, -1, 'up') == none
	assert number_input_value_from_key('5', none, 5, 1, -1, 'down') or { '' } == '4'
}

// ── One-time code input ─────────────────────────────────────────────

fn kit_otp_edit(code string, index int, text string) OtpInputEdit {
	return otp_input_edit(code, 6, .digits, index, text)
}

fn kit_otp_key(code string, index int, key string) ?OtpInputEdit {
	return otp_input_key(code, 6, index, key)
}

fn test_otp_input_normalize_by_charset() {
	assert otp_input_normalize('12 34-56', .digits) == '123456'
	assert otp_input_normalize('１２３', .digits) == '123'
	assert otp_input_normalize('ab12', .digits) == '12'
	assert otp_input_normalize('ab-12_Ｃ', .alphanumeric) == 'ab12C'
	assert otp_input_normalize('é٣', .alphanumeric) == ''
}

fn test_otp_input_typing_appends_and_moves_focus() {
	first := kit_otp_edit('', 0, '1')
	assert first.code == '1'
	assert first.focus == 1
	assert first.changed
	assert !first.complete
	// Typing into a later empty cell still fills the first empty one.
	skipped := kit_otp_edit('12', 5, '3')
	assert skipped.code == '123'
	assert skipped.focus == 3
	// Typing in a filled cell replaces its character, whichever side the caret was on.
	after := kit_otp_edit('123', 1, '27')
	assert after.code == '173'
	assert after.focus == 2
	before := kit_otp_edit('123', 1, '72')
	assert before.code == '173'
	// The same character again keeps the code and still advances.
	same := kit_otp_edit('123', 1, '22')
	assert same.code == '123'
	assert !same.changed
	assert same.focus == 2
	last := kit_otp_edit('12345', 5, '6')
	assert last.complete
	assert last.focus == 5
	assert otp_input_cell_text(last.code, 5) == '6'
	assert otp_input_cell_text(last.code, 6) == ''
	assert otp_input_focus_index('123', 6) == 3
	assert otp_input_focus_index('1234567', 6) == 5
}

fn test_otp_input_paste_fills_cells_and_rejects_other_characters() {
	pasted := kit_otp_edit('', 0, '123-456')
	assert pasted.code == '123456'
	assert pasted.complete
	assert pasted.focus == 5
	overflow := kit_otp_edit('12', 2, '3456789')
	assert overflow.code == '123456'
	middle := kit_otp_edit('123456', 2, '9')
	assert middle.code == '129456'
	assert middle.focus == 3
	rejected := kit_otp_edit('12', 2, 'x')
	assert rejected.code == '12'
	assert !rejected.changed
	assert rejected.focus == 2
	letters := otp_input_edit('A', 6, .alphanumeric, 1, 'b')
	assert letters.code == 'Ab'
	outside := kit_otp_edit('12', 6, '3')
	assert !outside.changed
}

fn test_otp_input_clearing_a_cell_closes_the_gap() {
	cleared := kit_otp_edit('123456', 2, '')
	assert cleared.code == '12456'
	assert cleared.focus == 2
	assert !cleared.complete
	nothing := kit_otp_edit('12', 4, '')
	assert !nothing.changed
}

fn test_otp_input_keys() {
	// In the empty cell after the code, Backspace removes the last character.
	back := kit_otp_key('123', 3, 'backspace') or { panic('ignored') }
	assert back.code == '12'
	assert back.focus == 2
	// In a filled cell it removes that character and stays.
	own := kit_otp_key('123456', 5, 'backspace') or { panic('ignored') }
	assert own.code == '12345'
	assert own.focus == 5
	assert kit_otp_key('', 0, 'backspace') == none
	delete := kit_otp_key('123', 0, 'forward_delete') or { panic('ignored') }
	assert delete.code == '23'
	assert kit_otp_key('123', 3, 'forward_delete') == none
	left := kit_otp_key('123', 2, 'left') or { panic('ignored') }
	assert left.focus == 1
	assert !left.changed
	assert kit_otp_key('123', 0, 'left') == none
	right := kit_otp_key('123', 2, 'right') or { panic('ignored') }
	assert right.focus == 3
	// Right stops at the first empty cell.
	assert kit_otp_key('123', 3, 'right') == none
	end := kit_otp_key('123', 0, 'end') or { panic('ignored') }
	assert end.focus == 3
	home := kit_otp_key('123', 3, 'home') or { panic('ignored') }
	assert home.focus == 0
	// Shortcuts such as Cmd+V, shifted arrows and other keys are left to the field.
	assert kit_otp_key('123', 3, 'cmd+v') == none
	assert kit_otp_key('123', 2, 'shift+left') == none
	assert kit_otp_key('123', 3, '4') == none
	assert kit_otp_key('123', 6, 'backspace') == none
}
