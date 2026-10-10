module main

import os
import time
import ui2

const default_iterations = 1_000

struct Key {
pub:
	text   string
	role   string
	row    int
	column int
}

pub struct Calculator {
pub mut:
	display string
	keys    []Key
}

fn benchmark_model() Calculator {
	mut keys := []Key{cap: 20}
	for row in 0 .. 5 {
		for column in 0 .. 4 {
			keys << Key{
				text:   '${row * 4 + column}'
				role:   if column == 3 { 'operator' } else { 'digit' }
				row:    row
				column: column
			}
		}
	}
	return Calculator{
		display: '12345'
		keys:    keys
	}
}

fn build_compiled(mut app Calculator, frame ui2.Rect) ui2.Element {
	return $vml('form.vml', frame)
}

fn consume_and_dispose(root ui2.Element) int {
	checksum := root.children[0].children.len
	if root.compiled_node != unsafe { nil } {
		root.compiled_node.dispose_document() or { panic(err) }
	}
	return checksum
}

fn main() {
	iterations := if os.args.len > 1 { os.args[1].int() } else { default_iterations }
	if iterations <= 0 {
		eprintln('usage: ${os.args[0]} [positive iteration count]')
		exit(1)
	}
	mut app := benchmark_model()
	frame := ui2.rect(0, 0, 800, 600)
	_ = consume_and_dispose(build_compiled(mut app, frame))
	mut checksum := 0
	mut watch := time.new_stopwatch()
	for _ in 0 .. iterations {
		checksum += consume_and_dispose(build_compiled(mut app, frame))
	}
	elapsed := watch.elapsed()
	println('iterations: ${iterations}')
	println('compiled build/dispose: ${f64(elapsed) / f64(time.millisecond):.3f} ms')
	println('per build:    ${f64(elapsed) / f64(time.microsecond) / iterations:.3f} us')
	println('checksum:     ${checksum}')
}
