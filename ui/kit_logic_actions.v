// Copyright 2024 - 2026 Longbridge <https://longbridge.com>
// SPDX-License-Identifier: Apache-2.0
// The rating click rule (crates/component/src/rating.rs) and the stepping
// rules of number_input_step (step_value in crates/base/src/number_input.rs:
// step from zero when the text does not parse, clamp to the bounds, keep the
// decimals of the text, step and bound, and do nothing unless the value moves
// the way it was asked to) are adapted from GPUI Kit. The rest is new UI2
// code. See third_party/gpui-kit.
module ui2

import math
import strconv

// Pure logic of the action, choice and input controls: what a click, a key or
// an edit does to a value. Keys are the names ElementEvent.key carries
// (`left`, `home`, `5`, `backspace`); a name with a modifier (`shift+left`)
// matches nothing here. The component decides whether it is enabled before it
// asks.

// ── Toggle group ────────────────────────────────────────────────────

// toggle_group_selection_after is the selection after the item for value is
// pressed, in item order. enabled[i] tells whether values[i] can be pressed
// (a missing entry can). It returns none for a value no item has, a disabled
// item, and releasing the last pressed item when allow_empty is false.
// Selected values that name no item are dropped.
pub fn toggle_group_selection_after(values []string, enabled []bool, selected []string, value string, multiple bool, allow_empty bool) ?[]string {
	index := values.index(value)
	if index < 0 || !kit_choice_enabled(enabled, index) {
		return none
	}
	was_pressed := values[index] in selected
	mut next := []string{}
	if multiple {
		for i, item in values {
			pressed := if i == index { !was_pressed } else { item in selected }
			if pressed {
				next << item
			}
		}
	} else if !was_pressed {
		next << values[index]
	}
	if next.len == 0 && !allow_empty {
		return none
	}
	return next
}

fn kit_choice_enabled(enabled []bool, index int) bool {
	return index >= enabled.len || enabled[index]
}

fn kit_enabled_indexes(count int, enabled []bool) []int {
	mut indexes := []int{cap: count}
	for index in 0 .. count {
		if kit_choice_enabled(enabled, index) {
			indexes << index
		}
	}
	return indexes
}

// ── Radio group ─────────────────────────────────────────────────────

// radio_value_after_key moves the selection the way arrow keys move it in a
// native radio group: down/right to the next enabled option and up/left to the
// previous one, wrapping around, and home/end to the first and last. It
// returns none for other keys and when the selection would not change.
pub fn radio_value_after_key(values []string, enabled []bool, selected string, key string) ?string {
	choices := kit_enabled_indexes(values.len, enabled)
	if choices.len == 0 {
		return none
	}
	position := choices.index(values.index(selected))
	target := match key {
		'down', 'right' {
			if position < 0 { choices[0] } else { choices[(position + 1) % choices.len] }
		}
		'up', 'left' {
			if position < 0 {
				choices[choices.len - 1]
			} else {
				choices[(position + choices.len - 1) % choices.len]
			}
		}
		'home' {
			choices[0]
		}
		'end' {
			choices[choices.len - 1]
		}
		else {
			return none
		}
	}
	if values[target] == selected {
		return none
	}
	return values[target]
}

// ── Rating ──────────────────────────────────────────────────────────

// rating_max_stars bounds the work a rating does for any requested maximum.
pub const rating_max_stars = 50

// rating_value_after_click is upstream's rule: clicking a filled star sets
// the rating to the star before it, and clicking an empty star fills up to
// it. Clicking the highest filled star therefore lowers the rating by one,
// and clicking the first star of a non-empty rating clears it.
pub fn rating_value_after_click(value int, star int) int {
	return if value >= star { star - 1 } else { star }
}

// rating_value_after_key steps a rating of max stars from the keyboard:
// right/up add a star, left/down remove one, home clears and end fills, and a
// digit key sets that many stars. value is clamped to 0..max first.
pub fn rating_value_after_key(value int, max int, key string) ?int {
	if max < 1 || max > rating_max_stars {
		return none
	}
	current := math.min(math.max(value, 0), max)
	next := match key {
		'right', 'up' {
			math.min(current + 1, max)
		}
		'left', 'down' {
			math.max(current - 1, 0)
		}
		'home' {
			0
		}
		'end' {
			max
		}
		else {
			if key.len != 1 || key[0] < `0` || key[0] > `9` {
				return none
			}
			int(key[0] - `0`)
		}
	}
	if next == current || next > max {
		return none
	}
	return next
}

// ── Stepper ─────────────────────────────────────────────────────────

pub enum StepperStepState {
	completed
	current
	upcoming
}

// stepper_step_state classifies a step against the current one.
pub fn stepper_step_state(index int, current int) StepperStepState {
	return if index < current {
		.completed
	} else if index == current {
		.current
	} else {
		.upcoming
	}
}

// stepper_current clamps current to 0..count; count marks every step done.
fn stepper_current(count int, current int) int {
	return math.max(0, math.min(current, count))
}

// stepper_next_step is the first enabled step after the current one, for a
// Next button or the arrow keys. enabled has one entry per step.
pub fn stepper_next_step(enabled []bool, current int) ?int {
	for index in stepper_current(enabled.len, current) + 1 .. enabled.len {
		if enabled[index] {
			return index
		}
	}
	return none
}

// stepper_previous_step is the last enabled step before the current one.
pub fn stepper_previous_step(enabled []bool, current int) ?int {
	mut index := stepper_current(enabled.len, current) - 1
	for index >= 0 {
		if enabled[index] {
			return index
		}
		index--
	}
	return none
}

// stepper_step_after_key maps arrow keys along the stepper's orientation to
// the next or previous enabled step, and home/end to the first and last.
pub fn stepper_step_after_key(enabled []bool, current int, vertical bool, key string) ?int {
	if enabled.len == 0 {
		return none
	}
	if (!vertical && key == 'right') || (vertical && key == 'down') {
		return stepper_next_step(enabled, current)
	}
	if (!vertical && key == 'left') || (vertical && key == 'up') {
		return stepper_previous_step(enabled, current)
	}
	choices := kit_enabled_indexes(enabled.len, enabled)
	if choices.len == 0 {
		return none
	}
	target := match key {
		'home' { choices[0] }
		'end' { choices[choices.len - 1] }
		else { return none }
	}
	return if target == stepper_current(enabled.len, current) { none } else { target }
}

// ── Number input ────────────────────────────────────────────────────

pub const number_input_max_precision = 12

pub enum NumberInputStep {
	decrement
	increment
}

// number_input_validate checks a number input's range and format: a finite
// positive step, a precision of -1 (keep the decimals of the text, step and
// bounds) or 0..12, and finite bounds with min <= max.
pub fn number_input_validate(min ?f64, max ?f64, step f64, precision int) ! {
	if !math.is_finite(step) || step <= 0 {
		return error('number input step must be finite and positive')
	}
	if precision < -1 || precision > number_input_max_precision {
		return error('number input precision must be -1 or 0..${number_input_max_precision}')
	}
	if low := min {
		if !math.is_finite(low) {
			return error('number input min must be finite')
		}
		if high := max {
			if low > high {
				return error('number input min must not exceed max')
			}
		}
	}
	if high := max {
		if !math.is_finite(high) {
			return error('number input max must be finite')
		}
	}
}

// number_input_ascii folds the full-width digits, signs and decimal points an
// IME commits (and the typographic minus) into their ASCII forms.
fn number_input_ascii(r rune) rune {
	if r >= 0xff10 && r <= 0xff19 {
		return `0` + (r - 0xff10)
	}
	return match r {
		0xff0b { `+` }
		0xff0d, 0x2212 { `-` }
		0xff0e, 0x3002, 0xff61 { `.` }
		else { r }
	}
}

// number_input_sanitize is what to keep of the text the user typed: an
// optional leading sign (a minus only when the range has negative values),
// digits, and one decimal point unless precision is 0. Full-width characters
// become ASCII; everything else is dropped.
pub fn number_input_sanitize(typed string, min ?f64, precision int) string {
	allow_minus := if low := min { low < 0 } else { true }
	allow_point := precision != 0
	mut kept := []rune{cap: typed.len}
	mut has_point := false
	for raw in typed.runes() {
		r := number_input_ascii(raw)
		if r >= `0` && r <= `9` {
			kept << r
		} else if r == `.` && allow_point && !has_point {
			has_point = true
			kept << r
		} else if kept.len == 0 && (r == `+` || (r == `-` && allow_minus)) {
			kept << r
		}
	}
	return kept.string()
}

// number_input_parse reads an optional sign, digits and at most one decimal
// point, with at least one digit: `-1.5`, `.5` and `2.` parse, while ``, `-`,
// `.`, `1e3` and `1,000` do not.
pub fn number_input_parse(source string) ?f64 {
	trimmed := source.trim_space()
	if trimmed.len == 0 {
		return none
	}
	negative := trimmed[0] == `-`
	start := if negative || trimmed[0] == `+` { 1 } else { 0 }
	mut digit_count := 0
	mut has_point := false
	for ch in trimmed[start..].bytes() {
		if ch >= `0` && ch <= `9` {
			digit_count++
		} else if ch == `.` && !has_point {
			has_point = true
		} else {
			return none
		}
	}
	if digit_count == 0 {
		return none
	}
	mut body := trimmed[start..]
	if body.starts_with('.') {
		body = '0' + body
	}
	if body.ends_with('.') {
		body += '0'
	}
	magnitude := strconv.atof64(body) or { return none }
	if !math.is_finite(magnitude) {
		return none
	}
	return if negative { -magnitude } else { magnitude }
}

// number_input_fraction_digits counts the digits after the decimal point.
fn number_input_fraction_digits(source string) int {
	point := source.index('.') or { return 0 }
	return math.min(source.len - point - 1, number_input_max_precision)
}

// number_input_decimal_places is how many decimals a configured number such
// as a step of 0.25 needs: the fewest that represent it to within rounding.
fn number_input_decimal_places(value f64) int {
	mut scaled := math.abs(value)
	for places in 0 .. number_input_max_precision {
		if math.abs(scaled - math.round(scaled)) <= 1e-9 * math.max(scaled, 1) {
			return places
		}
		scaled *= 10
	}
	return number_input_max_precision
}

// number_input_plain writes a configured number with the decimals it needs,
// as an accessibility range does.
fn number_input_plain(value f64) string {
	return number_input_format(value, number_input_decimal_places(value))
}

fn number_input_pow10(places int) f64 {
	return math.pow(10, f64(places))
}

// number_input_format writes value with exactly precision decimals (clamped to
// 0..12), rounding half away from zero. Values are turned into an integer count
// of the last decimal before they are printed, so a step of 0.1 from 0.2 gives
// `0.3`, not `0.30000000000000004`.
pub fn number_input_format(value f64, precision int) string {
	if !math.is_finite(value) {
		return ''
	}
	places := math.min(math.max(precision, 0), number_input_max_precision)
	return number_input_format_scaled(math.round(value * number_input_pow10(places)),
		places, value)
}

fn number_input_format_scaled(scaled f64, places int, value f64) string {
	if math.abs(scaled) >= 9.0e15 {
		// Past the range where every integer is exact the decimals carry no
		// information; print the value itself.
		return strconv.f64_to_str_lnd1(value, places)
	}
	count := i64(scaled)
	negative := count < 0
	mut digits := (if negative { -count } else { count }).str()
	if places > 0 {
		if digits.len <= places {
			digits = '0'.repeat(places - digits.len + 1) + digits
		}
		digits = digits[..digits.len - places] + '.' + digits[digits.len - places..]
	}
	return if negative { '-' + digits } else { digits }
}

// number_input_places is the number of decimals a result is written with:
// the precision, or else (precision -1) as many as the text and the step use.
fn number_input_places(source string, step f64, precision int) int {
	if precision >= 0 {
		return precision
	}
	return math.max(number_input_fraction_digits(source.trim_space()), number_input_decimal_places(step))
}

// number_input_fit clamps value into min..max and writes it with places
// decimals. The clamping is done in counts of the last decimal, so a rounded
// value never lands outside the range: with a max of 0.25 and one decimal the
// result is 0.2, not 0.3. A value pulled onto a bound keeps the bound's own
// decimals when the precision is not fixed (-1).
fn number_input_fit(value f64, places int, min ?f64, max ?f64, precision int) string {
	mut digits := places
	mut target := value
	if low := min {
		if target < low {
			target = low
			if precision < 0 {
				digits = math.max(digits, number_input_decimal_places(low))
			}
		}
	}
	if high := max {
		if target > high {
			target = high
			if precision < 0 {
				digits = math.max(digits, number_input_decimal_places(high))
			}
		}
	}
	scale := number_input_pow10(digits)
	mut scaled := math.round(target * scale)
	if high := max {
		limit := math.floor(high * scale + 1e-7 * math.max(math.abs(high * scale), 1))
		if scaled > limit {
			scaled = limit
		}
	}
	if low := min {
		limit := math.ceil(low * scale - 1e-7 * math.max(math.abs(low * scale), 1))
		if scaled < limit {
			scaled = limit
		}
	}
	return number_input_format_scaled(scaled, digits, target)
}

// number_input_step returns the text one step up or down from text, or none
// when the step cannot move the value that way (at or past the bound in that
// direction) or the range is invalid. Empty or unparsable text steps from zero
// into the range, so the first increment of an empty field with a min of 10
// gives 10. Decimals follow number_input_places.
pub fn number_input_step(text string, min ?f64, max ?f64, step f64, precision int, direction NumberInputStep) ?string {
	number_input_validate(min, max, step, precision) or { return none }
	current := number_input_parse(text)
	delta := if direction == .increment { step } else { -step }
	next := number_input_fit((current or { 0.0 }) + delta, number_input_places(text, step,
		precision), min, max, precision)
	if was := current {
		now := number_input_parse(next) or { return none }
		moved := if direction == .increment { now > was } else { now < was }
		if !moved {
			return none
		}
	}
	return next
}

// number_input_commit is the text to keep once the user is done typing, for
// Return or before the value is used: the value parsed, clamped into range and
// written with the precision, or else with the decimals typed (or those of the
// bound it was clamped to). Empty text stays empty; text that does not parse
// gives none, leaving the component to keep or revert it.
pub fn number_input_commit(source string, min ?f64, max ?f64, step f64, precision int) ?string {
	trimmed := source.trim_space()
	if trimmed.len == 0 {
		return ''
	}
	number_input_validate(min, max, step, precision) or { return none }
	value := number_input_parse(trimmed) or { return none }
	places := if precision >= 0 { precision } else { number_input_fraction_digits(trimmed) }
	return number_input_fit(value, places, min, max, precision)
}

// number_input_in_range reports whether text parses and lies within the
// bounds, for showing a typed value as invalid before it is committed.
pub fn number_input_in_range(source string, min ?f64, max ?f64) bool {
	value := number_input_parse(source) or { return false }
	if low := min {
		if value < low {
			return false
		}
	}
	if high := max {
		if value > high {
			return false
		}
	}
	return true
}

// number_input_key_step maps the up and down arrows, without modifiers, to a
// step.
pub fn number_input_key_step(key string) ?NumberInputStep {
	if key == 'up' {
		return .increment
	}
	if key == 'down' {
		return .decrement
	}
	return none
}

// number_input_value_from_key is the text after the step a key asks for, or
// none when the key is not a step key or the step cannot move.
pub fn number_input_value_from_key(text string, min ?f64, max ?f64, step f64, precision int, key string) ?string {
	direction := number_input_key_step(key) or { return none }
	return number_input_step(text, min, max, step, precision, direction)
}

// ── One-time code input ─────────────────────────────────────────────

// otp_input_max_length bounds how many cells a code may have, so a forged or
// mistaken length cannot make a build allocate without limit.
pub const otp_input_max_length = 32

pub enum OtpInputCharset {
	digits       // 0-9; full-width digits from an IME are folded to ASCII.
	alphanumeric // ASCII letters and digits; full-width forms are folded too.
}

// OtpInputEdit is the result of an edit: the cell it was made in, the new
// code, the cell to focus next, whether the code changed, and whether every
// cell is now filled.
pub struct OtpInputEdit {
pub:
	cell     int
	code     string
	focus    int
	changed  bool
	complete bool
}

// otp_input_normalize keeps the characters a code may hold: full-width forms
// become ASCII, and anything outside the charset (spaces, dashes, punctuation
// in a pasted `123-456`) is dropped.
pub fn otp_input_normalize(source string, charset OtpInputCharset) string {
	mut kept := []rune{cap: source.len}
	for raw in source.runes() {
		r := if raw >= 0xff01 && raw <= 0xff5e { raw - 0xfee0 } else { raw }
		digit := r >= `0` && r <= `9`
		letter := (r >= `a` && r <= `z`) || (r >= `A` && r <= `Z`)
		if digit || (letter && charset == .alphanumeric) {
			kept << r
		}
	}
	return kept.string()
}

// otp_input_runes is code cut to length characters.
fn otp_input_runes(code string, length int) []rune {
	runes := code.runes()
	return if runes.len > length { runes[..math.max(length, 0)].clone() } else { runes }
}

// otp_input_cell_text is what cell index shows for code: its character, or
// nothing past the end.
pub fn otp_input_cell_text(code string, index int) string {
	runes := code.runes()
	return if index >= 0 && index < runes.len { runes[index].str() } else { '' }
}

// otp_input_focus_index is the cell that takes the next character: the first
// empty one, or the last cell of a complete code.
pub fn otp_input_focus_index(code string, length int) int {
	return math.max(math.min(otp_input_runes(code, length).len, length - 1), 0)
}

fn otp_input_result(length int, cell int, before []rune, after []rune, target int) OtpInputEdit {
	return OtpInputEdit{
		cell:     cell
		code:     after.string()
		focus:    math.max(math.min(target, length - 1), 0)
		changed:  after != before
		complete: length > 0 && after.len == length
	}
}

fn otp_input_without(code []rune, index int) []rune {
	mut rest := code.clone()
	rest.delete(index)
	return rest
}

// otp_input_edit applies what the user left in cell index of a code of length
// cells: the text of that cell's change event. The code never has gaps, so:
//
// - a character typed into a filled cell replaces that cell's character;
// - one typed into an empty cell is appended to the code;
// - several characters at once (a paste, or an autofilled code) fill cells
//   from there on, up to the length;
// - a cell left empty removes its character and the rest move up.
//
// Focus moves to the cell after the last one written.
pub fn otp_input_edit(code string, length int, charset OtpInputCharset, index int, cell_text string) OtpInputEdit {
	runes := otp_input_runes(code, length)
	unchanged := otp_input_result(length, index, runes, runes, index)
	if index < 0 || index >= length {
		return unchanged
	}
	old := if index < runes.len { runes[index].str() } else { '' }
	if cell_text == old {
		return unchanged
	}
	if cell_text.len == 0 {
		if index >= runes.len {
			return unchanged
		}
		return otp_input_result(length, index, runes, otp_input_without(runes, index), index)
	}
	// A native field appends at its caret: keep what was added around the
	// character the cell already had, or everything when it was replaced.
	added := if old.len > 0 && cell_text.starts_with(old) {
		cell_text[old.len..]
	} else if old.len > 0 && cell_text.ends_with(old) {
		cell_text[..cell_text.len - old.len]
	} else {
		cell_text
	}
	chars := otp_input_normalize(added, charset).runes()
	if chars.len == 0 {
		return unchanged
	}
	start := math.min(index, runes.len)
	mut next := runes[..start].clone()
	for ch in chars {
		if next.len >= length {
			break
		}
		next << ch
	}
	written := next.len
	for position in written .. runes.len {
		next << runes[position]
	}
	return otp_input_result(length, index, runes, next, written)
}

// otp_input_key handles the keys a single-character cell cannot handle well on
// its own, for the cell at index. Backspace removes the cell's character, or
// the last one when the cell is empty, and focuses the cell it emptied;
// forward_delete removes the cell's character; left, right, home and end move
// between the filled cells and the next empty one. It returns none for every
// other key and for a key with nothing to do, so the cell keeps what it does
// not use.
pub fn otp_input_key(code string, length int, index int, key string) ?OtpInputEdit {
	if index < 0 || index >= length {
		return none
	}
	runes := otp_input_runes(code, length)
	last := otp_input_focus_index(code, length)
	match key {
		'backspace' {
			if index < runes.len {
				return otp_input_result(length, index, runes, otp_input_without(runes, index),
					index)
			}
			if runes.len == 0 {
				return none
			}
			return otp_input_result(length, index, runes, otp_input_without(runes, runes.len - 1),
				runes.len - 1)
		}
		'forward_delete' {
			if index >= runes.len {
				return none
			}
			return otp_input_result(length, index, runes, otp_input_without(runes, index), index)
		}
		'left', 'home' {
			if index == 0 {
				return none
			}
			return otp_input_result(length, index, runes, runes, if key == 'home' {
				0
			} else {
				index - 1
			})
		}
		'right', 'end' {
			target := if key == 'end' { last } else { math.min(index + 1, last) }
			if target <= index {
				return none
			}
			return otp_input_result(length, index, runes, runes, target)
		}
		else {
			return none
		}
	}
}
