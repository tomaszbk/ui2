module main

import os
import time
import ui2

const default_iterations = 1_000
const default_rows = 5

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

fn benchmark_model(rows int) Calculator {
	mut keys := []Key{cap: rows * 4}
	for row in 0 .. rows {
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
	rows := if os.args.len > 2 { os.args[2].int() } else { default_rows }
	if iterations <= 0 || rows <= 0 {
		eprintln('usage: ${os.args[0]} [positive iteration count] [positive row count]')
		exit(1)
	}
	mut app := benchmark_model(rows)
	frame := ui2.rect(0, 0, 800, 600)
	first_before := ui2.gc_allocation_snapshot() or { panic(err) }
	_ = consume_and_dispose(build_compiled(mut app, frame))
	first := ui2.gc_allocation_snapshot() or { panic(err) }
	first_delta := first.delta_since(first_before)
	mut checksum := 0
	mut watch := time.new_stopwatch()
	before := ui2.gc_allocation_snapshot() or { panic(err) }
	for _ in 0 .. iterations {
		checksum += consume_and_dispose(build_compiled(mut app, frame))
	}
	after := ui2.gc_allocation_snapshot() or { panic(err) }
	elapsed := watch.elapsed()
	delta := after.delta_since(before)
	println('iterations: ${iterations}')
	println('keys:       ${app.keys.len}')
	println('first build/dispose: ${first_delta.allocated_bytes} bytes; ${first_delta.collections} GC collections')
	println('compiled build/dispose: ${f64(elapsed) / f64(time.millisecond):.3f} ms')
	println('per build:    ${f64(elapsed) / f64(time.microsecond) / iterations:.3f} us')
	println('bytes:        ${delta.allocated_bytes}')
	println('bytes/build:  ${f64(delta.allocated_bytes) / iterations:.1f}')
	println('GC collections: ${delta.collections}')
	println('checksum:     ${checksum}')
}
