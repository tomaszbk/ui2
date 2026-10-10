// ui2 profiles: custom (custom font family)
module main

import math
import ui2

const calculate_width = 600
const calculate_height = 360

struct ArithmeticParser {
	input string
mut:
	pos int
}

fn (mut parser ArithmeticParser) skip_spaces() {
	for parser.pos < parser.input.len && parser.input[parser.pos].is_space() {
		parser.pos++
	}
}

fn (mut parser ArithmeticParser) parse_expression() !f64 {
	mut value := parser.parse_term()!
	for {
		parser.skip_spaces()
		if parser.pos >= parser.input.len || parser.input[parser.pos] !in [`+`, `-`] {
			break
		}
		op := parser.input[parser.pos]
		parser.pos++
		right := parser.parse_term()!
		value = if op == `+` { value + right } else { value - right }
	}
	return value
}

fn (mut parser ArithmeticParser) parse_term() !f64 {
	mut value := parser.parse_factor()!
	for {
		parser.skip_spaces()
		if parser.pos >= parser.input.len || parser.input[parser.pos] !in [`*`, `/`] {
			break
		}
		op := parser.input[parser.pos]
		parser.pos++
		right := parser.parse_factor()!
		if op == `/` && right == 0 {
			return error('division by zero')
		}
		value = if op == `*` { value * right } else { value / right }
	}
	return value
}

fn (mut parser ArithmeticParser) parse_factor() !f64 {
	parser.skip_spaces()
	if parser.pos >= parser.input.len {
		return error('expected a number')
	}
	if parser.input[parser.pos] in [`+`, `-`] {
		op := parser.input[parser.pos]
		parser.pos++
		value := parser.parse_factor()!
		return if op == `-` { -value } else { value }
	}
	if parser.input[parser.pos] == `(` {
		parser.pos++
		value := parser.parse_expression()!
		parser.skip_spaces()
		if parser.pos >= parser.input.len || parser.input[parser.pos] != `)` {
			return error('missing closing parenthesis')
		}
		parser.pos++
		return value
	}
	start := parser.pos
	mut decimal := false
	for parser.pos < parser.input.len {
		character := parser.input[parser.pos]
		if character.is_digit() {
			parser.pos++
			continue
		}
		if character == `.` && !decimal {
			decimal = true
			parser.pos++
			continue
		}
		break
	}
	if parser.pos == start || parser.input[start..parser.pos] == '.' {
		return error('expected a number at position ${start + 1}')
	}
	return parser.input[start..parser.pos].f64()
}

fn calculate_expression(input string) !f64 {
	mut parser := ArithmeticParser{ input: input }
	value := parser.parse_expression()!
	parser.skip_spaces()
	if parser.pos != input.len {
		return error('unexpected `${input[parser.pos]}` at position ${parser.pos + 1}')
	}
	if !math.is_finite(value) {
		return error('result is not finite')
	}
	return value
}

fn format_calculation(value f64) string {
	if math.trunc(value).eq_epsilon(value) {
		return i64(math.round(value)).str()
	}
	return '${value:.10f}'.trim_right('0').trim_right('.')
}

pub struct CalculateDemo {
pub mut:
	expression string = '((23.3 + 10) / 4) - 3'
	result     string = '5.325'
	status     string = 'Expression ready.'
	has_error  bool
}

pub fn (mut app CalculateDemo) evaluate() {
	value := calculate_expression(app.expression) or {
		app.result = 'Error'
		app.status = err.msg()
		app.has_error = true
		return
	}
	app.result = format_calculation(value)
	app.status = 'Calculated successfully.'
	app.has_error = false
}

pub fn (mut app CalculateDemo) load_example(index int) {
	app.expression = match index {
		1 { '3 + 22 / 2' }
		2 { '(22 + (13 - 5) * 4) / 2 + 10' }
		else { '((23.3 + 10) / 4) - 3' }
	}
	app.evaluate()
}

fn main() {
	mut app := CalculateDemo{}
	ui2.run_compiled_vml[CalculateDemo](
		build:  build_calculate
		model:  &app
		title:  'Calculate'
		width:  calculate_width
		height: calculate_height
	) or {
		panic(err)
	}
}

fn build_calculate(mut app CalculateDemo) ui2.Element {
	return $vml('calculate.vml')
}

fn calculate_tree(mut app CalculateDemo, frame ui2.Rect) ui2.Element {
	return $vml('calculate.vml', frame)
}
